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
  _FakeConnector({this.supported = true, this.failBeforeSuccess = 0});

  final bool supported;

  /// connect 总调用次数(含失败):验证「必须发起连接」与「重试次数预算」。
  int attempts = 0;

  /// 前 N 次 connect 以异常失败(模拟 douyu 对快速重连限流拒绝首连),
  /// 之后走 completer 正常发牌。测试中途可改写以放行手动刷新。
  int failBeforeSuccess;

  final requests = <DanmakuSessionRequest>[];
  final pending = <Completer<DanmakuSession>>[];
  final sessions = <_FakeSession>[];

  @override
  SiteCapabilities get capabilities => SiteCapabilities(danmaku: supported);

  @override
  Future<DanmakuSession> connect(DanmakuSessionRequest request) {
    attempts += 1;
    requests.add(request);
    if (failBeforeSuccess > 0) {
      failBeforeSuccess -= 1;
      return Future.error(StateError('handshake rejected (限流模拟)'));
    }
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

  test('切房 A→B→A:回到原房间必须重新发起连接(BUG-WIN-DANMAKU-002)', () async {
    final connector = _FakeConnector();
    final container = _container(connector);
    addTearDown(container.dispose);

    final roomA = danmakuSessionProvider((site: 'douyu', roomId: '100'));
    final roomB = danmakuSessionProvider((site: 'douyu', roomId: '200'));

    // 首次进 A:自动建连成功并收流。
    final subA1 = container.listen(roomA, (_, _) {});
    await _flush();
    expect(connector.requests.single.roomId, '100');
    final firstSession = connector.completeNext();
    await _flush();
    expect(container.read(roomA).connection, DanmakuSessionState.connected);

    // 切到 B:A 会话销毁,B 自己建立连接(路由过渡期两房并存)。
    subA1.close();
    final subB = container.listen(roomB, (_, _) {});
    await _flush();
    expect(firstSession.closeCount, 1, reason: '切房后旧会话必须被 close');
    expect(connector.requests, hasLength(2));
    connector.completeNext(); // B 的会话补全,避免悬挂 completer。
    await _flush();

    // 从 B 切回 A:必须第二次发起 connect,而不是停在「未连接」。
    final subA2 = container.listen(roomA, (_, _) {});
    await _flush();
    expect(connector.requests, hasLength(3), reason: '回房必须重新 connect');
    expect(connector.requests.last.roomId, '100');

    // 回房后的新会话正常收流(真机症状:未连接 + 暂无弹幕,点刷新才恢复)。
    final secondSession = connector.completeNext();
    await _flush();
    secondSession.push('回房消息');
    await _flush();
    expect(container.read(roomA).connection, DanmakuSessionState.connected);
    expect(container.read(roomA).messages.last.text, '回房消息');

    subA2.close();
    subB.close();
  });

  test('连接失败:直接落未连接(用户口径去掉自动重连),手动刷新可重来', () async {
    final connector = _FakeConnector(failBeforeSuccess: 1);
    final container = _container(connector);
    addTearDown(container.dispose);

    final provider = danmakuSessionProvider((site: 'douyu', roomId: '100'));
    final states = <DanmakuChatState>[];
    final sub = container.listen(
      provider,
      (_, next) => states.add(next),
      fireImmediately: true,
    );

    // 首连失败:不得自动重试,保持「未连接」等待手动刷新。
    await _flush();
    expect(connector.attempts, 1, reason: '失败后不得自动重试');
    expect(states.last.connection, DanmakuSessionState.disconnected);

    // 手动刷新:重新发起连接,本次放行成功。
    connector.failBeforeSuccess = 0;
    container.read(provider.notifier).reconnect();
    await _flush();
    expect(connector.attempts, 2);
    connector.completeNext();
    await _flush();
    expect(states.last.connection, DanmakuSessionState.connected);
    sub.close();
  });

  test('会话异常断开:直接落未连接,手动刷新可重连', () async {
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
    final first = connector.completeNext();
    await _flush();
    first.push('断开前消息');
    await _flush();
    expect(states.last.connection, DanmakuSessionState.connected);

    // 服务端掐流:states 推 disconnected(douyu 连接器自身不重连)。
    first.statesController.add(DanmakuSessionState.disconnected);
    await _flush();
    expect(connector.requests, hasLength(1), reason: '异常断开后不得自动重连');
    expect(
      states.last.connection,
      DanmakuSessionState.disconnected,
      reason: '断开后保持「未连接」等待手动刷新',
    );

    // 手动刷新:重新发起连接并恢复收流。
    container.read(provider.notifier).reconnect();
    await _flush();
    expect(connector.requests, hasLength(2));
    final second = connector.completeNext();
    await _flush();
    expect(first.closeCount, 1, reason: '重连前旧会话必须被释放');
    second.push('重连后消息');
    await _flush();
    expect(states.last.connection, DanmakuSessionState.connected);
    expect(states.last.messages.map((message) => message.text).toList(), [
      '断开前消息',
      '重连后消息',
    ], reason: '手动重连不清空历史弹幕');
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
