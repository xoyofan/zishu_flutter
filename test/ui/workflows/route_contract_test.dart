/// 路由契约测试:根路径、legacy 深链、播放 id 形态与平台纠偏、未知路由兜底。
///
/// 逐条对齐 SFVideoLive `apps/web/src/router.js`:根路径按登录态分流、`/watch/*`
/// 与 `/platform/*` 旧链重定向、播放页 id 允许斜杠并纠正平台、未知路由不白屏。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:live_parser/live_parser.dart' show StreamLine;
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:zishu_flutter/src/app/app_router.dart';
import 'package:zishu_flutter/src/apps/windows/windows_app.dart';
import 'package:zishu_flutter/src/features/browse/views/home_view.dart';
import 'package:zishu_flutter/src/features/play/application/play_provider.dart';
import 'package:zishu_flutter/src/features/play/views/play_view.dart';
import 'package:zishu_flutter/src/platforms/common/playback/live_player.dart';

class _FakeLivePlayer implements LivePlayer {
  @override
  Stream<PlayerSnapshot> get snapshots =>
      Stream<PlayerSnapshot>.value(const PlayerSnapshot());

  @override
  Widget buildVideoView({BoxFit fit = BoxFit.contain}) =>
      const SizedBox.expand();

  @override
  Future<void> open(
    StreamLine line, [
    List<StreamLine> fallbacks = const [],
    bool resetRetries = true,
  ]) async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> setMuted(bool muted) async {}

  @override
  Future<void> toggleFullscreen() async {}

  @override
  Future<void> setFullscreen(bool fullscreen) async {}

  @override
  Future<void> enterPictureInPicture({double? aspectRatio}) async {}

  @override
  Future<void> exitPictureInPicture() async {}

  @override
  Future<void> stop() async {}

  @override
  Widget wrapPipSurface(Widget child) => child;

  @override
  void dispose() {}
}

Future<GoRouter> _pumpApp(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1280, 900);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [playerProvider.overrideWithValue(_FakeLivePlayer())],
      child: const WindowsApp(),
    ),
  );
  for (var i = 0; i < 2; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  final element = tester.element(find.byType(Navigator).first);
  return ProviderScope.containerOf(element).read(routerProvider);
}

/// `go` 到 [location] 并推进若干帧(重定向都是同步的,两帧足够挂载页面)。
Future<void> _go(WidgetTester tester, GoRouter router, String location) async {
  router.go(location);
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

String _pathOf(GoRouter router) =>
    router.routeInformationProvider.value.uri.path;

/// 当前可见的播放页(未进入播放页则返回 null)。
PlayView? _playView(WidgetTester tester) {
  final finder = find.byType(PlayView);
  if (finder.evaluate().isEmpty) return null;
  return tester.widget<PlayView>(finder);
}

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData(<String, Object>{});
  });

  testWidgets('/user 深链:重定向回 /all(凭证已改为弹框)', (tester) async {
    final router = await _pumpApp(tester);
    await _go(tester, router, '/user');

    expect(_pathOf(router), '/all');
    expect(find.byType(HomeView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('根路径 /:未登录(恢复中/匿名)回退 /all', (tester) async {
    final router = await _pumpApp(tester);
    await _go(tester, router, '/');

    expect(_pathOf(router), '/all');
    expect(find.byType(HomeView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('/search 深链:重定向回 /all(搜索已改为弹框)', (tester) async {
    final router = await _pumpApp(tester);
    await _go(tester, router, '/search');

    expect(_pathOf(router), '/all');
    expect(find.byType(HomeView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('legacy 深链 /watch/* 与 /platform/* 逐条重定向', (tester) async {
    final router = await _pumpApp(tester);

    // /watch/:site/play/:id → /:site/play/:id
    await _go(tester, router, '/watch/douyu/play/63136');
    expect(_pathOf(router), '/douyu/play/63136');
    expect(_playView(tester)?.roomId, '63136');

    // /watch/:site/category/:cid → /:site/category/:cid
    await _go(tester, router, '/watch/douyu/category/1');
    expect(_pathOf(router), '/douyu/category/1');

    // /watch/:site/:room → /:site/play/:room
    await _go(tester, router, '/watch/douyu/63136');
    expect(_pathOf(router), '/douyu/play/63136');
    expect(_playView(tester)?.roomId, '63136');

    // /watch/:site → /:site
    await _go(tester, router, '/watch/douyu');
    expect(_pathOf(router), '/douyu');
    expect(find.byType(HomeView), findsOneWidget);

    // /platform/:site → /:site
    await _go(tester, router, '/platform/twitch');
    expect(_pathOf(router), '/twitch');
    expect(tester.takeException(), isNull);
  });

  testWidgets('播放 id 允许带斜杠:整条直播间链接可直接打开', (tester) async {
    final router = await _pumpApp(tester);
    const link = 'https://www.douyu.com/63136';
    await _go(tester, router, '/douyu/play/${Uri.encodeComponent(link)}');

    // 带 `.m3u8` 段的链接也应是同一个房间号形态(路径段原样保留)。
    final play = _playView(tester);
    expect(play, isNotNull);
    expect(play!.roomId, link, reason: 'roomId 应还原为原始链接(路径参数解码)');
    expect(play.site, 'douyu');
    expect(tester.takeException(), isNull);
  });

  testWidgets('平台纠偏:URL 域名与路由 site 不符时改投真实平台', (tester) async {
    final router = await _pumpApp(tester);
    const douyuLink = 'https://www.douyu.com/63136';
    await _go(tester, router, '/huya/play/${Uri.encodeComponent(douyuLink)}');

    // 纠偏改写的是 site 段,id 段原样保留(仍是那条链接的编码形式)。
    expect(_pathOf(router), '/douyu/play/${Uri.encodeComponent(douyuLink)}');
    final play = _playView(tester);
    expect(play?.site, 'douyu', reason: '应纠正到链接里写明的平台');
    expect(play?.roomId, douyuLink, reason: '路径参数解码后仍是原始链接');
    expect(tester.takeException(), isNull);
  });

  testWidgets('未知路由:给出可见兜底页且可一键回首页(不再白屏)', (tester) async {
    final router = await _pumpApp(tester);
    await _go(tester, router, '/nonexistent/deep/path');

    expect(find.byKey(const Key('route-fallback-home')), findsOneWidget);
    expect(find.text('页面不存在'), findsOneWidget);

    await tester.tap(find.byKey(const Key('route-fallback-home')));
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(HomeView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窗口标题同步不抛异常(window_manager 缺失时静默跳过)', (tester) async {
    final router = await _pumpApp(tester);
    await _go(tester, router, '/settings');
    await _go(tester, router, '/douyu/play/63136');

    // 单测环境无 window_manager 原生实现:标题同步必须被吞掉,不能冒泡。
    expect(tester.takeException(), isNull);
  });
}
