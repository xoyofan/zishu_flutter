/// 顶栏分类入口 + 「我的分类」的行为回归:
/// 1. 「分类」入口跳不带 cid 的落地页 `/all/category`(早期版本拼出
///    `/all/category` 却无对应路由 → go_router 抛 no-routes);
/// 2. 平台 hover 分类项跳 `/:site/category/:cid`,分类页据此高亮;
/// 3. 「我的分类」hover 浮层:空态 → 管理弹窗收藏 → chip 出现并可跳转。
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:live_parser/live_parser.dart' show StreamLine;
import 'package:zishu_flutter/src/app/app_router.dart';
import 'package:zishu_flutter/src/apps/windows/windows_app.dart';
import 'package:zishu_flutter/src/features/play/application/play_provider.dart';
import 'package:zishu_flutter/src/platforms/common/playback/live_player.dart';

/// 测试替身:VM 下替代 MediaKitLivePlayer。
class _FakeLivePlayer implements LivePlayer {
  @override
  Stream<PlayerSnapshot> get snapshots =>
      Stream<PlayerSnapshot>.value(const PlayerSnapshot());

  @override
  Widget buildVideoView({BoxFit fit = BoxFit.contain}) =>
      const SizedBox.expand();

  @override
  Future<void> open(StreamLine line, [List<StreamLine> fallbacks = const [], bool resetRetries = true]) async {}

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

void main() {
  void suppressRenderFlexOverflow() {
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      if (details.exception.toString().contains('A RenderFlex overflowed')) {
        return;
      }
      originalOnError?.call(details);
    };
  }

  void mockPathProvider() {
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => r'.tmp_cache');
  }

  /// 每个用例共用一只鼠标:重复 addPointer 会触发 MouseTracker 断言。
  TestGesture? gesture;

  Future<GoRouter> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [playerProvider.overrideWithValue(_FakeLivePlayer())],
        child: const WindowsApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture!.addPointer(location: Offset.zero);
    addTearDown(() => gesture?.removePointer());
    final element = tester.element(find.byType(Scaffold));
    return ProviderScope.containerOf(element).read(routerProvider);
  }

  /// 鼠标移入指定锚点,并 pump 若干帧等待异步分类数据落地。
  Future<void> hover(WidgetTester tester, Finder finder) async {
    final center = tester.getCenter(finder);
    await gesture!.moveTo(center);
    await tester.pump();
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('「分类」入口跳 /all/category 且不触发路由异常', (tester) async {
    suppressRenderFlexOverflow();
    mockPathProvider();
    final router = await pumpApp(tester);

    await tester.tap(find.byKey(const Key('nav-category')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      router.routeInformationProvider.value.uri.path,
      '/all/category',
      reason: '分类落地页必须命中路由(缺 cid 时不是 /all/category/:key)',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('平台 hover 分类项跳 /:site/category/:cid', (tester) async {
    suppressRenderFlexOverflow();
    mockPathProvider();
    final router = await pumpApp(tester);

    await hover(tester, find.byKey(const Key('platform-tab-douyu')));
    // 首页左抽屉也有同名分类项,这里必须点浮层内的 chip。
    expect(find.byKey(const ValueKey('flyout-category-1')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('flyout-category-1')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      router.routeInformationProvider.value.uri.path,
      '/douyu/category/1',
      reason: 'hover 分类项必须带 cid(fixture 首组首个 cid=1)',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('我的分类:hover 空态 → 管理弹窗收藏 → chip 跳转', (tester) async {
    suppressRenderFlexOverflow();
    mockPathProvider();
    final router = await pumpApp(tester);

    // 1) hover 打开浮层:空集合显示「暂无收藏分类」。
    await hover(tester, find.byKey(const Key('nav-my-category')));
    expect(find.text('暂无收藏分类'), findsOneWidget);

    // 2) 管理弹窗:勾选 fixture 的「英雄联盟」。
    await tester.tap(find.text('管理分类'));
    await tester.pump(const Duration(milliseconds: 50));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('英雄联盟'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('完成'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    // 3) 再次 hover:收藏 chip 出现,点击跳对应子分类。
    await hover(tester, find.byKey(const Key('nav-my-category')));
    expect(find.text('暂无收藏分类'), findsNothing);
    final chip = find.descendant(
      of: find.byType(InkWell),
      matching: find.text('英雄联盟'),
    );
    expect(chip, findsWidgets);
    await tester.tap(chip.first);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      router.routeInformationProvider.value.uri.path,
      '/all/category/1',
      reason: '全平台聚合下收藏条目 site=all,按 cid 跳转',
    );
    expect(tester.takeException(), isNull);
  });
}
