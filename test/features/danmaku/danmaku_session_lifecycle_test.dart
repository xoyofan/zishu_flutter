import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_parser/live_parser.dart'
    show
        DanmakuConnector,
        DanmakuMessage,
        DanmakuMessageType,
        DanmakuSession,
        DanmakuSessionRequest,
        DanmakuSessionState,
        SiteCapabilities,
        SiteRegistration,
        SiteRegistry,
        buildSiteRegistry;
import 'package:zishu_flutter/src/features/danmaku/application/danmaku_session_provider.dart';
import 'package:zishu_flutter/src/features/danmaku/application/danmaku_settings_provider.dart';
import 'package:zishu_flutter/src/features/danmaku/domain/danmaku_settings.dart';

class _FakeSession implements DanmakuSession {
  final messagesController = StreamController<DanmakuMessage>.broadcast();
  final statesController = StreamController<DanmakuSessionState>.broadcast();
  int closeCount = 0;

  @override
  Stream<DanmakuMessage> get messages => messagesController.stream;

  @override
  Stream<DanmakuSessionState> get states => statesController.stream;

  void push(String text) {
    messagesController.add(
      DanmakuMessage(
        type: DanmakuMessageType.chat,
        roomId: '100',
        userName: 'tester',
        userId: 'u1',
        text: text,
      ),
    );
  }

  @override
  Future<void> close() async {
    closeCount += 1;
    await messagesController.close();
    await statesController.close();
  }
}

class _FakeConnector implements DanmakuConnector {
  _FakeConnector({this.supported = true});

  final bool supported;
  final requests = <DanmakuSessionRequest>[];
  final pending = <Completer<DanmakuSession>>[];
  final sessions = <_FakeSession>[];

  @override
  SiteCapabilities get capabilities => SiteCapabilities(danmaku: supported);

  @override
  Future<DanmakuSession> connect(DanmakuSessionRequest request) {
    requests.add(request);
    final completer = Completer<DanmakuSession>();
    pending.add(completer);
    return completer.future;
  }

  _FakeSession completeNext() {
    final session = _FakeSession();
    sessions.add(session);
    pending.removeAt(0).complete(session);
    return session;
  }
}

SiteRegistry _registryFor(DanmakuConnector connector) {
  final registry = buildSiteRegistry();
  final douyu = registry['douyu']!;
  registry.register(
    SiteRegistration(
      id: douyu.id,
      name: douyu.name,
      capabilities: douyu.capabilities,
      resolver: douyu.resolver,
      browse: douyu.browse,
      search: douyu.search,
      danmaku: connector,
    ),
  );
  return registry;
}

ProviderContainer _container(_FakeConnector connector) {
  return ProviderContainer(
    overrides: [
      danmakuRegistryProvider.overrideWithValue(_registryFor(connector)),
    ],
  );
}

Future<void> _flush() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  test('切房时旧连接完成后立即关闭且不订阅旧 session', () async {
    final connector = _FakeConnector();
    final container = _container(connector);
    addTearDown(container.dispose);

    final roomA = danmakuSessionProvider((site: 'douyu', roomId: '100'));
    final subA = container.listen(roomA, (_, _) {});
    await _flush();
    expect(connector.requests.single.roomId, '100');

    subA.close();
    await _flush();
    final staleSession = connector.completeNext();
    await _flush();

    expect(staleSession.closeCount, 1);
    expect(staleSession.messagesController.hasListener, isFalse);
  });

  test('重连只保留最新 generation 的 session 且不会重复订阅', () async {
    final connector = _FakeConnector();
    final container = _container(connector);
    addTearDown(container.dispose);

    final provider = danmakuSessionProvider((site: 'douyu', roomId: '100'));
    final states = <DanmakuChatState>[];
    final sub = container.listen(
      provider,
      (_, next) => states.add(next),
      fireImmediately: true,
    );
    await _flush();
    final firstSession = connector.completeNext();
    await _flush();

    container.read(provider.notifier).reconnect();
    container.read(provider.notifier).reconnect();
    await _flush();

    expect(connector.requests, hasLength(2));
    expect(firstSession.closeCount, 1);

    final currentSession = connector.completeNext();
    await _flush();
    currentSession.push('最新会话');
    await _flush();

    expect(states.last.connection, DanmakuSessionState.connected);
    expect(states.last.messages.map((message) => message.text), ['最新会话']);
    sub.close();
  });

  test('聊天和 overlay 的两个监听共享同一个连接与消息状态', () async {
    final connector = _FakeConnector();
    final container = _container(connector);
    addTearDown(container.dispose);

    final provider = danmakuSessionProvider((site: 'douyu', roomId: '100'));
    final chatStates = <DanmakuChatState>[];
    final overlayStates = <DanmakuChatState>[];
    final chatSub = container.listen(
      provider,
      (_, next) => chatStates.add(next),
      fireImmediately: true,
    );
    final overlaySub = container.listen(
      provider,
      (_, next) => overlayStates.add(next),
      fireImmediately: true,
    );
    await _flush();

    expect(connector.requests, hasLength(1));
    final session = connector.completeNext();
    await _flush();
    session.push('共享消息');
    await _flush();

    expect(chatStates.last.messages.single.text, '共享消息');
    expect(overlayStates.last.messages.single.text, '共享消息');
    chatSub.close();
    overlaySub.close();
  });

  test('不支持弹幕的平台不建立连接并返回明确空态', () async {
    final connector = _FakeConnector(supported: false);
    final container = _container(connector);
    addTearDown(container.dispose);

    final provider = danmakuSessionProvider((site: 'douyu', roomId: '100'));
    final states = <DanmakuChatState>[];
    final sub = container.listen(
      provider,
      (_, next) => states.add(next),
      fireImmediately: true,
    );
    await _flush();

    expect(connector.requests, isEmpty);
    expect(states.single.supported, isFalse);
    expect(states.single.connection, DanmakuSessionState.disconnected);
    sub.close();
  });

  test('弹幕设置更新立即生效并保持合法值', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final provider = danmakuSettingsProvider;
    container.read(provider);
    await container
        .read(provider.notifier)
        .setAll(
          const DanmakuSettings(
            opacity: 120,
            fontSize: 8,
            speed: 99,
            displayAreaRatio: 0.125,
          ),
        );

    expect(
      container.read(provider),
      const DanmakuSettings(
        opacity: DanmakuSettings.kOpacityMax,
        fontSize: DanmakuSettings.kFontSizeMin,
        speed: DanmakuSettings.kSpeedMax,
        displayAreaRatio: 0.25,
      ),
    );
  });
}
