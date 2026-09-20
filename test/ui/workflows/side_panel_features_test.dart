/// 侧栏功能 workflow 测试(任务卡 A8/A9/A10):关注落库、设置接线、推荐 Tab。
///
/// 覆盖三条真交互链路,全部走真实路由宿主 + 注入 FakeLivePlayer
/// (VM 下禁止初始化 media_kit);存储后端注入 InMemorySharedPreferencesAsync,
/// 与既有 play_controls_test.dart 宿主写法一致:固定次数 pump,不用 pumpAndSettle。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
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
        StreamLine,
        buildSiteRegistry;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:zishu_flutter/src/app/app_router.dart';
import 'package:zishu_flutter/src/app/app_theme.dart';
import 'package:zishu_flutter/src/features/danmaku/application/danmaku_session_provider.dart';
import 'package:zishu_flutter/src/features/danmaku/application/danmaku_settings_provider.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:zishu_flutter/src/features/danmaku/domain/danmaku_settings.dart';
import 'package:zishu_flutter/src/features/danmaku/widgets/danmaku_overlay.dart';
import 'package:zishu_flutter/src/features/follow/application/follow_provider.dart';
import 'package:zishu_flutter/src/features/follow/application/settings_provider.dart';
import 'package:zishu_flutter/src/features/play/application/play_provider.dart';
import 'package:zishu_flutter/src/features/play/widgets/play_side_panel.dart'
    show roomExternalUrl;
import 'package:zishu_flutter/src/platforms/common/playback/live_player.dart';
import 'package:zishu_flutter/src/shared/application/fixture_sources.dart';
import 'package:zishu_flutter/src/shared/application/translation/translation_coordinator.dart';
import 'package:zishu_flutter/src/shared/application/translation/translation_provider.dart';

/// 深链播放页:A8 用一个不在关注种子里的房间,避免初始即「已关注」。
const String _playLocationA8 = '/douyu/play/606118';

/// 深链播放页:A9/A10 用样例房间(与 layout/danmaku 基线同房间)。
const String _playLocation = '/douyu/play/63136';

/// 固定 pump 步长,与既有 workflow 测试一致。
const Duration _kFrame = Duration(milliseconds: 50);

/// 测试替身:替代 MediaKitLivePlayer,不触碰任何原生播放内核。
class FakeLivePlayer implements LivePlayer {
  FakeLivePlayer();

  final List<String> calls = [];

  @override
  Stream<PlayerSnapshot> get snapshots =>
      Stream<PlayerSnapshot>.value(const PlayerSnapshot());

  @override
  Widget buildVideoView({BoxFit fit = BoxFit.contain}) => const SizedBox.expand();

  @override
  Future<void> open(StreamLine line, [List<StreamLine> fallbacks = const [], bool resetRetries = true]) async => calls.add('open:${line.url}');

  @override
  Future<void> play() async => calls.add('play');

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> setVolume(double volume) async => calls.add('volume:$volume');

  @override
  Future<void> setMuted(bool muted) async => calls.add('muted:$muted');

  @override
  Future<void> toggleFullscreen() async => calls.add('fullscreen');
  @override
  Future<void> setFullscreen(bool fullscreen) async => calls.add('fullscreen:$fullscreen');

  @override
  Future<void> enterPictureInPicture({double? aspectRatio}) async => calls.add('pip:enter');

  @override
  Future<void> exitPictureInPicture() async => calls.add('pip:exit');

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  Widget wrapPipSurface(Widget child) => child;

  @override
  void dispose() => calls.add('dispose');
}

/// 测试宿主:与 WindowsApp 相同的 router/theme,补一层透明 Material。
class _TestApp extends ConsumerWidget {
  const _TestApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      theme: ZishuTheme.dark(),
      routerConfig: ref.watch(routerProvider),
      builder: (context, child) =>
          Material(type: MaterialType.transparency, child: child),
    );
  }
}

/// 记录播放器替身,便于用例断言调用序列。
late FakeLivePlayer _player;

/// 构造一条 chat 弹幕(与 danmaku_test.dart 同构)。
DanmakuMessage _chat(String userName, String text) {
  return DanmakuMessage(
    type: DanmakuMessageType.chat,
    roomId: '63136',
    userName: userName,
    userId: 'uid-$userName',
    text: text,
    rawType: 'chatmsg',
  );
}

/// 测试替身弹幕会话:由测试用 [StreamController] 完全驱动,不碰网络。
class _FakeDanmakuSession implements DanmakuSession {
  _FakeDanmakuSession();

  final messagesController = StreamController<DanmakuMessage>.broadcast();
  final statesController = StreamController<DanmakuSessionState>.broadcast();

  @override
  Stream<DanmakuMessage> get messages => messagesController.stream;

  @override
  Stream<DanmakuSessionState> get states => statesController.stream;

  /// 模拟连接建立。
  void emitConnected() => statesController.add(DanmakuSessionState.connected);

  /// 推送一条弹幕。
  void push(DanmakuMessage message) => messagesController.add(message);

  @override
  Future<void> close() async {
    await messagesController.close();
    await statesController.close();
  }
}

/// 测试替身 connector:返回受控 [_FakeDanmakuSession]。
class _FakeDanmakuConnector implements DanmakuConnector {
  _FakeDanmakuSession? session;

  @override
  SiteCapabilities get capabilities => const SiteCapabilities(danmaku: true);

  @override
  Future<DanmakuSession> connect(DanmakuSessionRequest request) async =>
      session ??= _FakeDanmakuSession();
}

/// 构造只替换斗鱼弹幕 connector 的注册表:其余(解析/浏览/搜索)沿用真实
/// 实现,保证房间解析仍走 fixture 默认链路。
SiteRegistry _buildDanmakuRegistry(DanmakuConnector connector) {
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

/// 启动宿主并深链到播放页,返回 router 与 container。
///
/// 每次调用都会重建 ProviderScope(间接触发各 provider 的持久化恢复),
/// A8 的「重建 ProviderScope 后仍在」即复用此语义。
///
/// [danmakuConnector] 可选:注入后弹幕会话由测试完全驱动(A9c 渲染设置用例)。
Future<({GoRouter router, ProviderContainer container})> _pumpPlay(
  WidgetTester tester, {
  String location = _playLocation,
  DanmakuConnector? danmakuConnector,
  List<Override> extraOverrides = const [],
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1600, 1200);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  _player = FakeLivePlayer();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        playerProvider.overrideWithValue(_player),
        if (danmakuConnector != null)
          danmakuRegistryProvider.overrideWithValue(
            _buildDanmakuRegistry(danmakuConnector),
          ),
        ...extraOverrides,
      ],
      child: const _TestApp(),
    ),
  );
  await _pumpFrames(tester, 2);

  final element = tester.element(find.byType(Navigator).first);
  final container = ProviderScope.containerOf(element);
  final router = container.read(routerProvider);
  router.go(location);
  await _pumpFrames(tester, 3);
  return (router: router, container: container);
}

/// 固定次数 pump(不用 pumpAndSettle:封面图在 VM 中不会真正加载)。
Future<void> _pumpFrames(WidgetTester tester, int times) async {
  for (var i = 0; i < times; i++) {
    await tester.pump(_kFrame);
  }
}

/// 轮询等待 settingsProvider 完成异步 _restore(hydrated)。
Future<void> _awaitSettingsHydrated(
  WidgetTester tester,
  ProviderContainer container,
) async {
  for (var attempt = 0; attempt < 10; attempt++) {
    if (container.read(settingsProvider).hydrated) return;
    await tester.pump(_kFrame);
  }
  fail('settingsProvider 未在限定帧数内完成 hydrated');
}

/// 轮询等待跟随 provider 恢复后包含指定房间 key(用于 A8 持久化证明)。
Future<void> _awaitFollowContains(
  WidgetTester tester,
  ProviderContainer container,
  String key,
) async {
  for (var attempt = 0; attempt < 10; attempt++) {
    if (container.read(followProvider).any((e) => e.key == key)) return;
    await tester.pump(_kFrame);
  }
  fail('followProvider 未在限定帧数内恢复出房间 $key');
}

/// 关注按钮子树内的标签文案(已关注 / 关注)。
Finder _followLabel(String label) => find.descendant(
      of: find.byKey(const Key('play-side-follow-btn')),
      matching: find.text(label),
    );

/// 聊天列表的 ScrollController:经锚点 play-side-chat-opacity 向下找 Scrollable
/// (聊天区非空时 Opacity 子树内恰有一个 ListView → 一个 Scrollable)。
ScrollController _chatScrollController(WidgetTester tester) {
  final scrollable = find.descendant(
    of: find.byKey(const Key('play-side-chat-opacity')),
    matching: find.byType(Scrollable),
  );
  return tester.widget<Scrollable>(scrollable.first).controller!;
}

/// 当前已构建聊天行的纯文本(「用户名：正文」),顺序自上而下。
/// ListView.builder 只构建视口内(含 cacheExtent)的行,长列表时是可见子集。
List<String> _visibleChatTexts(WidgetTester tester) => tester
    .widgetList<Text>(find.byKey(const Key('play-side-chat-message')))
    .map((t) => t.textSpan?.toPlainText() ?? '')
    .toList();

void main() {
  setUp(() {
    // 每个用例独立内存后端:被测代码与测试共享同一存储,写盘即可回读。
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData(<String, Object>{});
  });

  group('A8 关注落库', () {
    testWidgets('点关注→写盘→重建 ProviderScope 后仍在→取关移除', (tester) async {
      final play = await _pumpPlay(tester, location: _playLocationA8);
      final container = play.container;
      const roomKey = 'douyu:606118';

      // 种子里不含 606118,初始应为未关注态。
      expect(container.read(followProvider).any((e) => e.key == roomKey), isFalse);
      expect(_followLabel('关注'), findsOneWidget);

      // 点击关注按钮。
      await tester.tap(find.byKey(const Key('play-side-follow-btn')));
      await _pumpFrames(tester, 2);
      expect(_followLabel('已关注'), findsOneWidget);
      expect(container.read(followProvider).any((e) => e.key == roomKey), isTrue);

      // 写盘证明:内存后端里 zishu.follow.list 含该房间。
      final raw = await SharedPreferencesAsync().getString('zishu.follow.list');
      expect(raw, isNotNull);
      final list = jsonDecode(raw!) as List;
      expect(list.any((e) => e['roomId'] == '606118'), isTrue);

      // 重建 ProviderScope(新容器重新从存储恢复)。
      final play2 = await _pumpPlay(tester, location: _playLocationA8);
      await _awaitFollowContains(tester, play2.container, roomKey);
      expect(_followLabel('已关注'), findsOneWidget);

      // 取关:再次点击 → 移除且写盘更新。
      await tester.tap(find.byKey(const Key('play-side-follow-btn')));
      await _pumpFrames(tester, 2);
      expect(_followLabel('关注'), findsOneWidget);
      expect(
        play2.container.read(followProvider).any((e) => e.key == roomKey),
        isFalse,
      );
      final rawAfter = await SharedPreferencesAsync().getString('zishu.follow.list');
      final listAfter = jsonDecode(rawAfter!) as List;
      expect(listAfter.any((e) => e['roomId'] == '606118'), isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('关注上限 200:超出拒绝并提示', (tester) async {
      // 预置 200 条关注,再加一条应被拒绝并弹 SnackBar。
      final seed = <Map<String, Object>>[
        for (var i = 0; i < 200; i++)
          {
            'site': 'douyu',
            'roomId': 'seed$i',
            'title': '种子$i',
            'uname': '主播$i',
            'cover': '',
          },
      ];
      SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.withData(
        <String, Object>{'zishu.follow.list': jsonEncode(seed)},
      );

      final play = await _pumpPlay(tester, location: _playLocationA8);
      const roomKey = 'douyu:606118';
      // 等待从存储恢复出 200 条种子(避免种子同步返回后异步恢复未落地的竞态)。
      for (var i = 0; i < 10 && play.container.read(followProvider).length != 200; i++) {
        await _pumpFrames(tester, 1);
      }
      expect(play.container.read(followProvider).length, 200);

      await tester.tap(find.byKey(const Key('play-side-follow-btn')));
      await _pumpFrames(tester, 2);

      expect(
        play.container.read(followProvider).length,
        200,
        reason: '已达上限时不应再追加',
      );
      expect(
        find.text('关注已达上限（200）'),
        findsOneWidget,
        reason: '超出上限应给出 SnackBar 提示',
      );
      expect(
        play.container.read(followProvider).any((e) => e.key == roomKey),
        isFalse,
      );
    });
  });

  group('A9 设置接线', () {
    testWidgets('聊天开关翻转写入 zishu.settings.chatEnabled 且聊天区显示占位',
        (tester) async {
      final play = await _pumpPlay(tester);
      final container = play.container;
      await _awaitSettingsHydrated(tester, container);
      expect(container.read(settingsProvider).chatEnabled, isTrue);

      // 切到设置 tab。TabBar 切换动画约 300ms,pump 不足时页面仍在滑动,
      // 后续点击会落在滑动中的旧坐标上(实测开关点击落空)。
      await tester.tap(find.byKey(const Key('play-side-tab-settings')));
      await _pumpFrames(tester, 8);

      // 翻转聊天开关(默认开 → 关)。开关在设置 ListView 内,先滚入视口。
      await tester.ensureVisible(
        find.byKey(const Key('play-side-setting-chat')),
      );
      await tester.tap(find.byKey(const Key('play-side-setting-chat')));
      await _pumpFrames(tester, 2);

      expect(
        container.read(settingsProvider).chatEnabled,
        isFalse,
        reason: '点击设置里的聊天开关应写入 chatEnabled',
      );
      final stored = await SharedPreferencesAsync().getBool('zishu.settings.chatEnabled');
      expect(stored, isFalse);

      // 切回聊天 tab:内容区显示「聊天已关闭」占位(聊天 provider 不停,只藏 UI)。
      await tester.tap(find.byKey(const Key('play-side-tab-chat')));
      await _pumpFrames(tester, 3);
      expect(find.text('聊天已关闭'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('线路格式偏好写入 zishu.settings.preferredLineFormat',
        (tester) async {
      final play = await _pumpPlay(tester);
      final container = play.container;
      await _awaitSettingsHydrated(tester, container);

      await tester.tap(find.byKey(const Key('play-side-tab-settings')));
      await _pumpFrames(tester, 8); // 等 TabBar 切换动画落位。

      // 打开线路格式下拉并选择 HLS(下拉在设置 ListView 内,先滚入视口)。
      await tester.ensureVisible(
        find.byKey(const Key('play-side-setting-line-format')),
      );
      await tester.tap(find.byKey(const Key('play-side-setting-line-format')));
      await _pumpFrames(tester, 2);
      await tester.tap(find.text('HLS').last);
      await _pumpFrames(tester, 2);

      expect(
        container.read(settingsProvider).preferredLineFormat,
        PreferredLineFormat.hls,
      );
      final stored =
          await SharedPreferencesAsync().getString('zishu.settings.preferredLineFormat');
      expect(stored, 'hls');
      expect(tester.takeException(), isNull);
    });
  });

  group('A9b 弹幕样式入口移除(用户口径 2026-09-19:飘屏设置不放侧栏)', () {
    testWidgets('侧栏设置无「弹幕样式」入口,飘屏 overlay 与侧栏聊天均不受影响',
        (tester) async {
      final play = await _pumpPlay(tester);
      final container = play.container;
      await _awaitSettingsHydrated(tester, container);

      // 飘屏 overlay 仍挂载且默认不透明(入口移除不影响飘屏链路本身)。
      final overlay = find.byType(DanmakuOverlay);
      expect(overlay, findsOneWidget);
      expect(tester.widget<DanmakuOverlay>(overlay).opacity, closeTo(1.0, 1e-6));

      // 侧栏设置 tab:「弹幕样式 → 调整」入口不再存在;聊天组仍渲染开关,
      // 并内联 4 行滑杆(透明度/字号/间距/速度,节流默认「全量」)。
      await tester.tap(find.byKey(const Key('play-side-tab-settings')));
      await _pumpFrames(tester, 8);
      expect(find.text('弹幕样式'), findsNothing);
      expect(
        find.byKey(const Key('play-side-setting-danmaku-style')),
        findsNothing,
        reason: '飘屏弹幕设置入口应已从侧栏设置移除',
      );
      expect(find.byKey(const Key('play-side-setting-chat')), findsOneWidget);
      expect(find.text('透明度'), findsOneWidget);
      expect(find.text('字号'), findsOneWidget);
      expect(find.text('间距'), findsOneWidget);
      expect(find.text('速度'), findsOneWidget);
      expect(find.text('全量'), findsOneWidget, reason: '节流默认全量(web DEFAULT_CHAT.speedLimit = false)');
      expect(find.text('100%'), findsOneWidget, reason: '透明度滑杆默认值文案');

      // 飘屏 provider 接线保持(overlay 入参仍跟随 danmakuSettingsProvider)。
      await container.read(danmakuSettingsProvider.notifier).setOpacity(60);
      await _pumpFrames(tester, 3);
      expect(tester.widget<DanmakuOverlay>(overlay).opacity, closeTo(0.6, 1e-6));

      // 复位,避免污染同文件后续用例(单例 provider + 共享内存存储)。
      await container
          .read(danmakuSettingsProvider.notifier)
          .setAll(const DanmakuSettings());
      await _pumpFrames(tester, 2);

      // 切回聊天 tab:侧栏聊天仍正常(状态条 + 刷新按钮)。
      await tester.tap(find.byKey(const Key('play-side-tab-chat')));
      await _pumpFrames(tester, 3);
      expect(find.byKey(const Key('play-side-chat-refresh')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('A9c 聊天侧栏渲染设置(对齐 web SideSettingsTab 41-105)', () {
    testWidgets('聊天字号/透明度/行距设置生效:_ChatTab 消息渲染跟随',
        (tester) async {
      final connector = _FakeDanmakuConnector();
      final play = await _pumpPlay(tester, danmakuConnector: connector);
      final container = play.container;
      await _awaitSettingsHydrated(tester, container);
      for (var i = 0; i < 10 && connector.session == null; i++) {
        await _pumpFrames(tester, 1);
      }

      connector.session!.emitConnected();
      connector.session!.push(_chat('水友甲', '设置生效测试弹幕'));
      await _pumpFrames(tester, 4);

      Text message() => tester.widget<Text>(
            find.byKey(const Key('play-side-chat-message')).first,
          );
      TextStyle userStyle() =>
          ((message().textSpan! as TextSpan).children!.first as TextSpan)
              .style!;
      double opacity() => tester
          .widget<Opacity>(
            find.byKey(const Key('play-side-chat-opacity')),
          )
          .opacity;
      EdgeInsets rowPadding() => tester
          .widget<Padding>(
            find.byKey(const Key('play-side-chat-row')).first,
          )
          .padding as EdgeInsets;

      // 默认渲染:字号 14(web DEFAULT_CHAT.fontSize)、全不透明、行距 0。
      expect(userStyle().fontSize, 14.0);
      expect(opacity(), 1.0);
      expect(rowPadding(), const EdgeInsets.only(bottom: 0));

      // 改设置(持久化 setter)→ 消息渲染跟随。
      await container.read(settingsProvider.notifier).setChatFontSize(20);
      await container.read(settingsProvider.notifier).setChatOpacity(60);
      await container.read(settingsProvider.notifier).setChatLineSpacing(8);
      await _pumpFrames(tester, 4);

      expect(userStyle().fontSize, 20.0, reason: '消息字号应跟随 chatFontSize');
      expect(opacity(), closeTo(0.6, 1e-6), reason: '聊天区透明度应跟随 chatOpacity');
      expect(
        rowPadding(),
        const EdgeInsets.only(bottom: 8),
        reason: '消息行间距应跟随 chatLineSpacing',
      );

      // 写盘证明(与 chatEnabled 同模式的持久化)。
      expect(
        await SharedPreferencesAsync().getInt('zishu.settings.chatFontSize'),
        20,
      );
      expect(
        await SharedPreferencesAsync().getInt('zishu.settings.chatOpacity'),
        60,
      );
      expect(
        await SharedPreferencesAsync().getInt('zishu.settings.chatLineSpacing'),
        8,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('聊天节流:每N秒一条逐条放行,切回全量立即放完积压',
        (tester) async {
      final connector = _FakeDanmakuConnector();
      final play = await _pumpPlay(tester, danmakuConnector: connector);
      final container = play.container;
      await _awaitSettingsHydrated(tester, container);
      for (var i = 0; i < 10 && connector.session == null; i++) {
        await _pumpFrames(tester, 1);
      }

      // 开启限速 + 1 秒一条(速度滑杆最小档,缩短测试等待)。
      await container
          .read(settingsProvider.notifier)
          .setChatThrottleMode(ChatThrottleMode.perNSeconds);
      await container.read(settingsProvider.notifier).setChatSpeed(1);
      await _pumpFrames(tester, 2);

      final session = connector.session!;
      session.emitConnected();
      session.push(_chat('节流水友甲', '节流消息一'));
      session.push(_chat('节流水友乙', '节流消息二'));
      session.push(_chat('节流水友丙', '节流消息三'));
      await _pumpFrames(tester, 4);

      int count() => tester
          .widgetList<Text>(find.byKey(const Key('play-side-chat-message')))
          .length;

      // 首条立即显示(web pushChatPendingBatch 语义),其余进待放出队列。
      expect(count(), 1, reason: '限速开启时应只放行首条');

      // 每推进 1 秒放行 1 条(chatSpeed = 1)。
      await tester.pump(const Duration(seconds: 1));
      await _pumpFrames(tester, 1);
      expect(count(), 2, reason: '推进 1 秒应再放行 1 条');
      await tester.pump(const Duration(seconds: 1));
      await _pumpFrames(tester, 1);
      expect(count(), 3, reason: '再推进 1 秒应放完全部积压');

      // 限速中新消息不立即出现;切回全量 → 积压立即放出(drain 语义)。
      session.push(_chat('节流水友丁', '节流消息四'));
      await _pumpFrames(tester, 2);
      expect(count(), 3, reason: '限速下新消息不应立即出现');
      await container
          .read(settingsProvider.notifier)
          .setChatThrottleMode(ChatThrottleMode.unlimited);
      await _pumpFrames(tester, 2);
      expect(count(), 4, reason: '切回全量应立即放出全部积压');
      expect(tester.takeException(), isNull);
    });

    testWidgets('聊天全量直通:不限速时新消息当帧全部出现(无 1 秒节拍)',
        (tester) async {
      final connector = _FakeDanmakuConnector();
      final play = await _pumpPlay(tester, danmakuConnector: connector);
      final container = play.container;
      await _awaitSettingsHydrated(tester, container);
      for (var i = 0; i < 10 && connector.session == null; i++) {
        await _pumpFrames(tester, 1);
      }

      expect(
        container.read(settingsProvider).chatThrottleMode,
        ChatThrottleMode.unlimited,
        reason: '默认应为全量模式(web DEFAULT_CHAT.speedLimit = false)',
      );

      final session = connector.session!;
      session.emitConnected();
      for (var i = 0; i < 5; i++) {
        session.push(_chat('直通水友$i', '直通消息$i'));
      }
      // 推送后仅用帧级推进(3×50ms,远小于最小限速间隔 1s):5 条应全部
      // 直通出现,顺序保持推送顺序(web ingestChatBatch 限速关分支直通
      // pushChatDisplay)。多 pump 2 帧是因为中文化口径(2026-09-20)改为
      // 「译文就绪才放行」,放行落在微任务,渲染需要下一帧。
      await _pumpFrames(tester, 3);
      expect(_visibleChatTexts(tester), hasLength(5),
          reason: '全量模式新消息应直通显示,不进积压队列');
      expect(_visibleChatTexts(tester).first.startsWith('直通水友0：'), isTrue);
      expect(_visibleChatTexts(tester).last.startsWith('直通水友4：'), isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('聊天中文化:译文就绪才放行显示(双队列出口翻译)', (tester) async {
      final connector = _FakeDanmakuConnector();
      final play = await _pumpPlay(
        tester,
        danmakuConnector: connector,
        extraOverrides: [
          // fake 引擎:任何文本 → 固定译文,验证「显示队列里是终稿译文」。
          translationCoordinatorProvider.overrideWith(
            (ref) => TranslationCoordinator(
              engines: [_ScriptedTranslationEngine('你好世界(译)')],
            ),
          ),
        ],
      );
      final container = play.container;
      await _awaitSettingsHydrated(tester, container);
      for (var i = 0; i < 10 && connector.session == null; i++) {
        await _pumpFrames(tester, 1);
      }

      final session = connector.session!;
      session.emitConnected();
      // 外文消息:译文未就绪前不得以原文出现;放行后显示译文。
      session.push(_chat('foreign fan', 'Hello world'));
      await _pumpFrames(tester, 3);

      final texts = _visibleChatTexts(tester);
      expect(texts, isNotEmpty, reason: '译文就绪后应放行显示');
      expect(
        texts.last,
        contains('你好世界(译)'),
        reason: '显示队列出口应是译文终稿',
      );
      expect(
        texts.last,
        isNot(contains('Hello world')),
        reason: '外文原文不应原样进入显示队列',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('聊天限速积压超限:pending 裁头丢最旧,放行从剩余最旧开始',
        (tester) async {
      final connector = _FakeDanmakuConnector();
      final play = await _pumpPlay(tester, danmakuConnector: connector);
      final container = play.container;
      await _awaitSettingsHydrated(tester, container);
      for (var i = 0; i < 10 && connector.session == null; i++) {
        await _pumpFrames(tester, 1);
      }

      await container
          .read(settingsProvider.notifier)
          .setChatThrottleMode(ChatThrottleMode.perNSeconds);
      await container.read(settingsProvider.notifier).setChatSpeed(1);
      await _pumpFrames(tester, 2);

      final session = connector.session!;
      session.emitConnected();
      // 一次灌 105 条(> 积压上限 100):最旧 5 条(000-004)应被裁头丢弃
      // (对齐 web CHAT_PENDING_LIMIT + splice 头部)。
      for (var i = 0; i < 105; i++) {
        session.push(
          _chat('积压水友${i.toString().padLeft(3, '0')}', '积压消息$i'),
        );
      }
      await _pumpFrames(tester, 4);

      // 首条立即显示,且是裁头后剩余的最旧一条(005)。
      expect(_visibleChatTexts(tester), hasLength(1),
          reason: '限速下应只放行首条');
      expect(_visibleChatTexts(tester).first.startsWith('积压水友005：'), isTrue,
          reason: '积压 105 > 上限 100 应裁掉最旧 5 条,首显 005');

      // 逐条放行:推进 1 秒 → 006。
      await tester.pump(const Duration(seconds: 1));
      await _pumpFrames(tester, 1);
      expect(_visibleChatTexts(tester), hasLength(2));
      expect(_visibleChatTexts(tester).last.startsWith('积压水友006：'), isTrue);

      // 切回全量:剩余积压一次放完(drain),贴底自动跟随;
      // 最后一条应为 104,被裁掉的 000 永不出现。
      await container
          .read(settingsProvider.notifier)
          .setChatThrottleMode(ChatThrottleMode.unlimited);
      await _pumpFrames(tester, 3);
      final controller = _chatScrollController(tester);
      controller.jumpTo(controller.position.maxScrollExtent);
      await _pumpFrames(tester, 2);
      final texts = _visibleChatTexts(tester);
      expect(texts, isNotEmpty);
      expect(texts.last.startsWith('积压水友104：'), isTrue,
          reason: 'drain 后最后一条应为 104(105 条灌入、裁掉最旧 5 条)');
      expect(find.textContaining('积压水友000：'), findsNothing,
          reason: '被积压上限裁掉的最旧消息不应再出现');
      expect(tester.takeException(), isNull);
    });

    testWidgets('聊天默认锚底:首刷滚到最底、贴底跟随、离底计数与跳底',
        (tester) async {
      final connector = _FakeDanmakuConnector();
      final play = await _pumpPlay(tester, danmakuConnector: connector);
      final container = play.container;
      await _awaitSettingsHydrated(tester, container);
      for (var i = 0; i < 10 && connector.session == null; i++) {
        await _pumpFrames(tester, 1);
      }

      final session = connector.session!;
      session.emitConnected();
      // 80 条一次性灌入(足以撑出滚动),首刷后应默认锚定底部
      // (用户口径 2026-09-19:默认从最底下往上走)。
      for (var i = 0; i < 80; i++) {
        session.push(_chat('锚底水友$i', '锚底消息$i'));
      }
      await _pumpFrames(tester, 3);

      final controller = _chatScrollController(tester);
      double bottomGap() =>
          (controller.position.pixels - controller.position.maxScrollExtent)
              .abs();
      expect(bottomGap(), lessThan(1), reason: '首刷后应默认锚定底部');

      // 贴底时新消息自动跟随。
      session.push(_chat('锚底水友f', '跟随消息'));
      await _pumpFrames(tester, 2);
      expect(bottomGap(), lessThan(1), reason: '贴底时新消息应自动跟随滚底');

      // 用户上滑离底:新消息不再强制滚底,出现「1 条新消息」。
      final listFinder = find.descendant(
        of: find.byKey(const Key('play-side-chat-opacity')),
        matching: find.byType(ListView),
      );
      await tester.drag(listFinder, const Offset(0, 320));
      await _pumpFrames(tester, 8); // 等拖拽惯性结束
      expect(
        controller.position.pixels,
        lessThan(controller.position.maxScrollExtent - 24),
        reason: '拖拽后应离开底部',
      );

      session.push(_chat('锚底水友x', '离底期间消息'));
      await _pumpFrames(tester, 2);
      expect(bottomGap(), greaterThan(1), reason: '离底时新消息不应强制滚底');
      expect(find.text('1 条新消息'), findsOneWidget,
          reason: '离底期间新消息应计入「N 条新消息」');

      // 点按钮回底:计数清零、按钮消失、位置回 max。
      await tester.tap(find.byKey(const Key('play-side-chat-jump-bottom')));
      await _pumpFrames(tester, 6); // 220ms 动画 + 240ms extent 校正
      expect(find.text('1 条新消息'), findsNothing);
      expect(bottomGap(), lessThan(1), reason: '点击「N 条新消息」应回到底部');
      expect(tester.takeException(), isNull);
    });
  });

  group('A10 推荐 Tab', () {
    testWidgets('推荐 Tab 渲染 fixture 房间且条目可点跳转', (tester) async {
      final play = await _pumpPlay(tester);
      await _pumpFrames(tester, 2);

      // 切到推荐 tab。TabBar 动画 + 异步拉取 fixture,给足帧数。
      await tester.tap(find.byKey(const Key('play-side-tab-recommend')));
      await _pumpFrames(tester, 8);

      // 至少渲染 1 条房间条目(锚点 play-recommend-room-{site}-{roomId})。
      final anchors = tester
          .widgetList(
            find.byWidgetPredicate(
              (widget) =>
                  widget.key is ValueKey<String> &&
                  (widget.key as ValueKey<String>)
                      .value
                      .startsWith('play-recommend-room-'),
            ),
          )
          .map((w) => (w.key as ValueKey<String>).value)
          .toList();
      expect(anchors.length, greaterThanOrEqualTo(1),
          reason: '推荐 Tab 应渲染至少 1 条 fixture 房间');

      // 选一个不是当前房间(63136)的条目,点它应深链跳转。
      final target = anchors.firstWhere(
        (key) => !key.endsWith('-63136'),
        orElse: () => anchors.first,
      );
      final match = RegExp(r'play-recommend-room-(.+)-(.+)$').firstMatch(target)!;
      final targetSite = match.group(1)!;
      final targetRoom = match.group(2)!;

      // ListView.builder 会构建折叠线以下的缓存条目:widgetList 能找到不代表
      // 可点,先滚入视口再点击,否则 tap 落空、路由不变(实测)。
      await tester.ensureVisible(find.byKey(Key(target)));
      await tester.tap(find.byKey(Key(target)));
      await _pumpFrames(tester, 3);

      final path = play.router.routeInformationProvider.value.uri.path;
      expect(path, '/$targetSite/play/$targetRoom',
          reason: '点击推荐条目应跳转到对应播放页');
      expect(tester.takeException(), isNull);
    });
  });

  group('C1 开播提醒铃铛', () {
    testWidgets('未关注禁用;关注后点按切换 remindOn 两态并落盘', (tester) async {
      final play = await _pumpPlay(tester, location: _playLocationA8);
      final container = play.container;
      const roomKey = 'douyu:606118';

      InkWell notifyInkWell() => tester.widget<InkWell>(find.descendant(
            of: find.byKey(const Key('play-side-notify')),
            matching: find.byType(InkWell),
          ));
      // 用户口径(2026-09-20):提醒入口显示为文字,激活态为「直播提醒中」。
      String? notifyLabel() {
        final texts = tester.widgetList<Text>(find.descendant(
          of: find.byKey(const Key('play-side-notify')),
          matching: find.byType(Text),
        ));
        return texts.isEmpty ? null : texts.first.data;
      }

      // 未关注:无提醒目标,按钮禁用(bell-off 态);点按不产生关注条目。
      expect(notifyInkWell().onTap, isNull);
      expect(notifyLabel(), '直播提醒');
      await tester.tap(find.byKey(const Key('play-side-notify')),
          warnIfMissed: false);
      await _pumpFrames(tester, 2);
      expect(container.read(followProvider).any((e) => e.key == roomKey),
          isFalse);

      // 关注(默认提醒关)→ 按钮可用,仍为 bell-off。
      await tester.tap(find.byKey(const Key('play-side-follow-btn')));
      await _pumpFrames(tester, 2);
      expect(notifyInkWell().onTap, isNotNull);
      expect(notifyLabel(), '直播提醒');

      // 点亮:remindOn 翻 true + bell 态,且写盘。
      await tester.tap(find.byKey(const Key('play-side-notify')));
      await _pumpFrames(tester, 2);
      expect(
        container
            .read(followProvider)
            .firstWhere((e) => e.key == roomKey)
            .remindOn,
        isTrue,
      );
      expect(notifyLabel(), '直播提醒中');
      final rawOn = await SharedPreferencesAsync().getString('zishu.follow.list');
      final storedOn = (jsonDecode(rawOn!) as List)
          .firstWhere((e) => e['roomId'] == '606118') as Map;
      expect(storedOn['remindOn'], isTrue);

      // 再点关闭:回 bell-off 态。
      await tester.tap(find.byKey(const Key('play-side-notify')));
      await _pumpFrames(tester, 2);
      expect(
        container
            .read(followProvider)
            .firstWhere((e) => e.key == roomKey)
            .remindOn,
        isFalse,
      );
      expect(notifyLabel(), '直播提醒');
      expect(tester.takeException(), isNull);
    });
  });

  group('C2 房间外链按钮', () {
    testWidgets('douyu 外链可用;URL 解析按 payload url 优先、平台拼接兜底',
        (tester) async {
      await _pumpPlay(tester, location: _playLocationA8);

      // 有稳定外链 → 按钮可点(真实点击会拉起系统浏览器,这里只断言接线)。
      final externalInkWell = tester.widget<InkWell>(find.descendant(
        of: find.byKey(const Key('play-side-external')),
        matching: find.byType(InkWell),
      ));
      expect(externalInkWell.onTap, isNotNull);

      // 解析规则:payload sourceUrl 优先(fixture payload 恒带 douyu url,
      // 任何 site 都以其为准);无 payload 时 douyu/huya/bilibili 按平台拼。
      expect(roomExternalUrl('douyu', '63136', null),
          'https://www.douyu.com/63136');
      expect(roomExternalUrl('huya', '11342412', null),
          'https://www.huya.com/11342412');
      expect(roomExternalUrl('bilibili', '6', null),
          'https://live.bilibili.com/6');
      // douyin 无稳定 web url:无 payload url 时禁用(返回 null)。
      expect(roomExternalUrl('douyin', '123', null), isNull);
      expect(roomExternalUrl('douyin', '123', fixtureRoomPayload('123')),
          'https://www.douyu.com/123');
      // 房间号为空一律禁用。
      expect(roomExternalUrl('douyu', ' ', null), isNull);
      expect(tester.takeException(), isNull);
    });
  });
}

/// 脚本化翻译引擎:所有文本返回同一固定译文(验证显示队列出口口径)。
class _ScriptedTranslationEngine implements TranslationEngine {
  _ScriptedTranslationEngine(this.translation);

  final String translation;

  @override
  Future<String?> translate(String text) async => translation;
}
