import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_parser/live_parser.dart';
import 'package:zishu_flutter/src/app/app_theme.dart';
import 'package:zishu_flutter/src/features/danmaku/application/danmaku_session_provider.dart';
import 'package:zishu_flutter/src/features/play/widgets/chat_badge_image.dart';
import 'package:zishu_flutter/src/features/play/widgets/play_side_panel.dart';

class _FakeSession implements DanmakuSession {
  final _messages = StreamController<DanmakuMessage>.broadcast();
  final _states = StreamController<DanmakuSessionState>.broadcast();

  @override
  Stream<DanmakuMessage> get messages => _messages.stream;

  @override
  Stream<DanmakuSessionState> get states => _states.stream;

  void emitState(DanmakuSessionState state) => _states.add(state);

  void emitMessage(DanmakuMessage message) => _messages.add(message);

  @override
  Future<void> close() async {
    await _messages.close();
    await _states.close();
  }
}

class _FakeConnector implements DanmakuConnector {
  _FakeSession? session;

  @override
  SiteCapabilities get capabilities => const SiteCapabilities(danmaku: true);

  @override
  Future<DanmakuSession> connect(DanmakuSessionRequest request) async =>
      session = _FakeSession();
}

DanmakuMessage _message({
  String site = 'bilibili',
  String user = '观众',
  String text = '你好',
  int userLevel = 0,
  String userLevelIconUrl = '',
  List<DanmakuBadge> badges = const [],
  DanmakuBadge? guard,
  List<DanmakuSegment> segments = const [],
}) => DanmakuMessage(
  type: DanmakuMessageType.chat,
  roomId: 'room-1',
  userName: user,
  userId: 'u-1',
  text: text,
  userLevel: userLevel,
  userLevelIconUrl: userLevelIconUrl,
  badges: badges,
  guard: guard,
  segments: segments,
);

Future<void> _pump(WidgetTester tester, String site, DanmakuMessage message) async {
  final connector = _FakeConnector();
  final registry = buildSiteRegistry();
  final target = registry[site]!;
  registry.register(
    SiteRegistration(
      id: target.id,
      name: target.name,
      capabilities: target.capabilities,
      resolver: target.resolver,
      browse: target.browse,
      search: target.search,
      danmaku: connector,
    ),
  );

  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(500, 1200);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [danmakuRegistryProvider.overrideWithValue(registry)],
      child: MaterialApp(
        theme: ZishuTheme.dark(),
        home: Scaffold(
          body: SizedBox(
            width: 392,
            child: PlaySidePanel(site: site, roomId: 'room-1'),
          ),
        ),
      ),
    ),
  );
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  final session = connector.session!;
  session.emitState(DanmakuSessionState.connected);
  session.emitMessage(message);
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('B站大航海按真实 guard 字段显示', (tester) async {
    await _pump(
      tester,
      'bilibili',
      _message(
        guard: const DanmakuBadge(
          name: '舰长',
          level: 3,
          color: 0xfff39c12,
          kind: 'guard',
        ),
        badges: const [
          DanmakuBadge(name: '提督骑士团', level: 12),
        ],
      ),
    );

    expect(find.text('舰长'), findsOneWidget);
    expect(find.textContaining('提督骑士团'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
  });

  testWidgets('虎牙超粉 V 使用 vFlag/vLogo 语义', (tester) async {
    await _pump(
      tester,
      'huya',
      _message(
        site: 'huya',
        badges: const [
          DanmakuBadge(
            name: '铁粉团',
            level: 13,
            vFlag: 1,
            vLogo: 'https://cdn.example/huya-v.png',
          ),
        ],
      ),
    );

    expect(find.byTooltip('超粉'), findsOneWidget);
    expect(find.text('铁粉团'), findsOneWidget);
    expect(find.text('13'), findsOneWidget);
  });

  testWidgets('SOOP 0109 表情段在聊天行显示图片', (tester) async {
    await _pump(
      tester,
      'soop',
      _message(
        site: 'soop',
        text: '你好[OGQ表情]',
        segments: const [
          DanmakuSegment.text('你好'),
          DanmakuSegment.emoji(
            text: '[OGQ表情]',
            name: 'OGQ表情',
            url: 'https://cdn.example/ogq.png',
          ),
        ],
      ),
    );

    expect(find.byKey(const Key('chat-emoji-image-OGQ表情')), findsOneWidget);
  });

  testWidgets('ChatBadgeImage 接受协议 URL 并保留本地资源回退', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChatBadgeImage(
          site: 'douyu',
          kind: ChatBadgeKind.fans,
          level: 12,
          height: 18,
          src: 'https://cdn.example/custom-fans.png',
        ),
      ),
    );

    expect(find.byType(Image), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
