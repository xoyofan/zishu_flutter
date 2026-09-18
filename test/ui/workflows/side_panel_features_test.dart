/// 侧栏功能 workflow 测试(任务卡 A8/A9/A10):关注落库、设置接线、推荐 Tab。
///
/// 覆盖三条真交互链路,全部走真实路由宿主 + 注入 FakeLivePlayer
/// (VM 下禁止初始化 media_kit);存储后端注入 InMemorySharedPreferencesAsync,
/// 与既有 play_controls_test.dart 宿主写法一致:固定次数 pump,不用 pumpAndSettle。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:live_parser/live_parser.dart' show StreamLine;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:zishu_flutter/src/app/app_router.dart';
import 'package:zishu_flutter/src/app/app_theme.dart';
import 'package:zishu_flutter/src/features/danmaku/application/danmaku_settings_provider.dart';
import 'package:zishu_flutter/src/features/danmaku/domain/danmaku_settings.dart';
import 'package:zishu_flutter/src/features/danmaku/widgets/danmaku_overlay.dart';
import 'package:zishu_flutter/src/features/follow/application/follow_provider.dart';
import 'package:zishu_flutter/src/features/follow/application/settings_provider.dart';
import 'package:zishu_flutter/src/features/play/application/play_provider.dart';
import 'package:zishu_flutter/src/platforms/common/playback/live_player.dart';

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

/// 启动宿主并深链到播放页,返回 router 与 container。
///
/// 每次调用都会重建 ProviderScope(间接触发各 provider 的持久化恢复),
/// A8 的「重建 ProviderScope 后仍在」即复用此语义。
Future<({GoRouter router, ProviderContainer container})> _pumpPlay(
  WidgetTester tester, {
  String location = _playLocation,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1600, 1200);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  _player = FakeLivePlayer();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [playerProvider.overrideWithValue(_player)],
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

  group('A9b 弹幕样式接线', () {
    testWidgets('侧栏「弹幕样式」打开对话框,细项改动直达 overlay', (tester) async {
      final play = await _pumpPlay(tester);
      final container = play.container;
      await _awaitSettingsHydrated(tester, container);

      // overlay 已挂载且默认不透明(出厂值)。
      final overlay = find.byType(DanmakuOverlay);
      expect(overlay, findsOneWidget);
      expect(tester.widget<DanmakuOverlay>(overlay).opacity, closeTo(1.0, 1e-6));

      // 侧栏设置 tab → 「弹幕样式」按钮(旧实现是两个写死的死滑杆)→ 对话框。
      await tester.tap(find.byKey(const Key('play-side-tab-settings')));
      await _pumpFrames(tester, 8);
      await tester.ensureVisible(
        find.byKey(const Key('play-side-setting-danmaku-style')),
      );
      await tester.tap(
        find.byKey(const Key('play-side-setting-danmaku-style')),
      );
      await _pumpFrames(tester, 4);
      expect(find.byKey(const Key('danmaku-settings-dialog')), findsOneWidget);

      // provider 改值 → overlay 入参跟随(接线证明:此前只传 messages/enabled)。
      await container.read(danmakuSettingsProvider.notifier).setOpacity(60);
      await container.read(danmakuSettingsProvider.notifier).setFontSize(28);
      await container.read(danmakuSettingsProvider.notifier).setSpeed(3);
      await _pumpFrames(tester, 3);
      final wired = tester.widget<DanmakuOverlay>(overlay);
      expect(wired.opacity, closeTo(0.6, 1e-6));
      expect(wired.fontSize, closeTo(28, 1e-6));
      expect(wired.speedFactor, 3);

      // 复位,避免污染同文件后续用例(单例 provider + 共享内存存储)。
      await container
          .read(danmakuSettingsProvider.notifier)
          .setAll(const DanmakuSettings());
      await _pumpFrames(tester, 2);
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
}
