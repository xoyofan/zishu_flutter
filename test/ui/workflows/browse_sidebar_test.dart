/// 首页左栏 workflow 测试:宽屏渲染左栏(平台锚点 + 分类树)、房间网格仍在;
/// 窄屏左栏不渲染(平台切换由 AppShell 平台条承担)。
///
/// 宿主约定(复用 workflow 目录既有测试):
/// - media_kit 禁止在 VM 初始化:注入 FakeLivePlayer。
/// - 走真实 go_router 宿主(MaterialApp.router + builder 补 Material 祖先)。
/// - 媒体查询必须写 tester.view.physicalSize(setSurfaceSize 不会让 MediaQuery
///   同步,断点会误判)。
/// - 全程固定次数 pump,不使用 pumpAndSettle(封面图片在 VM 中不真正加载)。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:live_parser/live_parser.dart' show StreamLine;
import 'package:zishu_flutter/src/app/app_router.dart';
import 'package:zishu_flutter/src/app/app_theme.dart';
import 'package:zishu_flutter/src/features/browse/widgets/browse_sidebar.dart';
import 'package:zishu_flutter/src/features/play/application/play_provider.dart';
import 'package:zishu_flutter/src/platforms/common/playback/live_player.dart';
import 'package:zishu_flutter/src/shared/presentation/design_tokens.dart';

/// 测试替身:VM 下替代 MediaKitLivePlayer,快照立即给一帧,方法只记录调用。
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

/// 测试宿主:与 WindowsApp 相同的 router/theme,额外在 builder 补 Material 祖先。
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

void main() {
  /// 均匀 pump host(注入 FakeLivePlayer)并返回 router。
  ///
  /// [width]/[height] 直接写 tester.view(断点几何据此计算,setSurfaceSize 不会
  /// 同步 MediaQuery)。
  Future<GoRouter> pumpApp(
    WidgetTester tester, {
    double width = 1600,
    double height = 1200,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = Size(width, height);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer(
      overrides: [playerProvider.overrideWithValue(FakeLivePlayer())],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const _TestApp()),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    return container.read(routerProvider);
  }

  /// room-card-* 锚点数量。
  int roomCardCount(WidgetTester tester) =>
      tester
          .widgetList(
            find.byWidgetPredicate(
              (widget) =>
                  widget.key is ValueKey<String> &&
                  (widget.key as ValueKey<String>).value.startsWith('room-card-'),
            ),
          )
          .length;

  testWidgets('wideScreen:左栏存在,平台锚点可命中,房间网格仍在',
      (tester) async {
    final router = await pumpApp(tester, width: 1600, height: 1200);

    // 1) 宽屏(>=768)渲染左栏。
    expect(find.byType(BrowseSidebar), findsOneWidget);

    // 2) 平台锚点(契约 home-platform-chip-{id})全部可命中且为 FilterChip。
    expect(
      tester.widget<FilterChip>(find.byKey(const Key('home-platform-chip-all'))),
      isA<FilterChip>(),
    );
    expect(
      tester.widget<FilterChip>(
        find.byKey(const Key('home-platform-chip-bilibili')),
      ),
      isA<FilterChip>(),
    );
    // /all 下全平台 chip 选中。
    expect(
      tester.widget<FilterChip>(find.byKey(const Key('home-platform-chip-all'))).selected,
      isTrue,
    );

    // 3) 房间网格仍在(全部 fixture 卡片挂载,见 browse_home_test 同档 surface)。
    expect(roomCardCount(tester), greaterThan(0));
    expect(find.byKey(const Key('room-card-douyu-63136')), findsOneWidget);

    // 4) 点平台锚点切换路由与选中态。
    await tester.tap(find.byKey(const Key('home-platform-chip-bilibili')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(router.routeInformationProvider.value.uri.path, '/bilibili');
    expect(
      tester.widget<FilterChip>(
        find.byKey(const Key('home-platform-chip-bilibili')),
      ).selected,
      isTrue,
    );
    expect(find.byKey(const Key('room-card-douyu-63136')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrowScreen:左栏不渲染,房间网格仍可用', (tester) async {
    // 手机窄屏(<768):平台切换由 AppShell 平台条承担,内容区不渲染左栏。
    await pumpApp(tester, width: 480, height: 900);

    expect(find.byType(BrowseSidebar), findsNothing);
    // 平台条锚点(phone 档)存在,房间网格仍在。
    expect(find.byKey(const Key('platform-tab-all')), findsOneWidget);
    expect(find.byKey(const Key('room-card-douyu-63136')), findsOneWidget);
    expect(roomCardCount(tester), greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('wideScreenLayout:首张房间卡片顶部不低于顶导航底部(左栏不顶出导航)',
      (tester) async {
    await pumpApp(tester, width: 1600, height: 1200);

    // 顶导航容器高 == AppSpacing.topNavHeight,贴视口顶部。
    final topNav = find.ancestor(
      of: find.byKey(const Key('nav-home')),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.constraints?.minHeight == AppSpacing.topNavHeight &&
            widget.constraints?.maxHeight == AppSpacing.topNavHeight,
      ),
    );
    expect(topNav, findsOneWidget);
    final navRect = tester.getRect(topNav);

    final cards = find.byWidgetPredicate(
      (widget) =>
          widget.key is ValueKey<String> &&
          (widget.key as ValueKey<String>).value.startsWith('room-card-'),
    );
    expect(tester.widgetList(cards).length, greaterThan(0));

    var minTop = double.infinity;
    for (final widget in tester.widgetList(cards)) {
      final rect = tester.getRect(find.byWidget(widget));
      minTop = minTop < rect.top ? minTop : rect.top;
    }
    expect(minTop, greaterThanOrEqualTo(navRect.bottom));
  });

  /// 左栏当前渲染宽度(取根 Container 的 BoxConstraints 实际生效值)。
  double sidebarWidth(WidgetTester tester) {
    final box = tester.renderObject<RenderBox>(find.byType(BrowseSidebar));
    return box.size.width;
  }

  testWidgets('collapse:点击 toggle 收起(220→52),平台锚点仍命中,分类树隐藏',
      (tester) async {
    await pumpApp(tester, width: 1600, height: 1200);
    expect(find.byType(BrowseSidebar), findsOneWidget);

    // 默认展开:220px,分类树在;toggle 锚点存在。
    expect(sidebarWidth(tester), closeTo(BrowseSidebar.width, 0.01));
    expect(find.byKey(BrowseSidebar.toggleKey), findsOneWidget);
    expect(find.byKey(const Key('browse-sidebar-cat-1')), findsOneWidget);
    expect(
      find.byKey(const Key('home-platform-chip-douyu')),
      findsOneWidget,
    );

    // 点击 toggle → 收起为 52px;分类树隐藏,平台锚点仍唯一命中。
    await tester.tap(find.byKey(BrowseSidebar.toggleKey));
    await tester.pump();
    await tester.pump(AppMotion.normal);
    await tester.pump(const Duration(milliseconds: 50));
    expect(sidebarWidth(tester), closeTo(BrowseSidebar.railWidth, 0.01));
    expect(find.byKey(const Key('browse-sidebar-cat-1')), findsNothing);
    expect(find.byKey(const Key('home-platform-chip-douyu')), findsOneWidget);
    expect(find.byKey(const Key('home-platform-chip-all')), findsOneWidget);

    // 再点一次 → 回到 220px 展开态,分类树恢复。
    await tester.tap(find.byKey(BrowseSidebar.toggleKey));
    await tester.pump();
    await tester.pump(AppMotion.normal);
    await tester.pump(const Duration(milliseconds: 50));
    expect(sidebarWidth(tester), closeTo(BrowseSidebar.width, 0.01));
    expect(find.byKey(const Key('browse-sidebar-cat-1')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('collapse:收起态点平台锚点仍可切换路由', (tester) async {
    final router = await pumpApp(tester, width: 1600, height: 1200);

    await tester.tap(find.byKey(BrowseSidebar.toggleKey));
    await tester.pump();
    await tester.pump(AppMotion.normal);
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byKey(const Key('home-platform-chip-douyu')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(router.routeInformationProvider.value.uri.path, '/douyu');
    expect(
      tester
          .widget<FilterChip>(find.byKey(const Key('home-platform-chip-douyu')))
          .selected,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrowScreen:左栏与 toggle 均不渲染', (tester) async {
    await pumpApp(tester, width: 480, height: 900);
    expect(find.byType(BrowseSidebar), findsNothing);
    expect(find.byKey(BrowseSidebar.toggleKey), findsNothing);
  });

  testWidgets('wideScreenCategoryTree:左栏分类树叶子可命中并跳转', (tester) async {
    final router = await pumpApp(tester, width: 1600, height: 1200);

    // 分类树来自 browseCategoriesProvider(fixture 含 网游竞技/英雄联盟 等)。
    expect(find.byKey(const Key('browse-sidebar-cat-1')), findsOneWidget);
    await tester.tap(find.byKey(const Key('browse-sidebar-cat-1')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(router.routeInformationProvider.value.uri.path, '/all/category/1');
    expect(tester.takeException(), isNull);
  });
}
