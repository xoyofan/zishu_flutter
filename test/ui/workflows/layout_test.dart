/// 全局布局 workflow 测试:顶导航几何、内容区不重叠、播放页无壳与侧栏折叠。
///
/// - media_kit 禁止在 VM 初始化:统一注入 FakeLivePlayer,误入播放路径也
///   不会触碰原生播放内核。全程固定次数 pump,不使用 pumpAndSettle。
/// - 走真实 go_router 宿主(MaterialApp.router + builder 补 Material 祖先,
///   播放页 PlayerControlsBar 的 Slider 依赖),几何断言基于真实布局 rect。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:live_parser/live_parser.dart' show StreamLine;
import 'package:zishu_flutter/src/app/app_router.dart';
import 'package:zishu_flutter/src/app/app_shell.dart';
import 'package:zishu_flutter/src/app/app_theme.dart';
import 'package:zishu_flutter/src/features/play/application/play_provider.dart';
import 'package:zishu_flutter/src/features/play/widgets/play_side_panel.dart';
import 'package:zishu_flutter/src/platforms/common/playback/live_player.dart';
import 'package:zishu_flutter/src/shared/presentation/design_tokens.dart';
import 'package:zishu_flutter/src/shared/presentation/platform_brands.dart';
import 'package:zishu_flutter/src/shared/presentation/widgets/platform_icon.dart';

/// 测试替身:VM 下替代 MediaKitLivePlayer,快照立即给一帧,方法只记录调用。
class FakeLivePlayer implements LivePlayer {
  FakeLivePlayer();

  /// 记录方法调用,便于必要时验证交互链路。
  final List<String> calls = [];

  @override
  Stream<PlayerSnapshot> get snapshots =>
      Stream<PlayerSnapshot>.value(const PlayerSnapshot());

  @override
  Widget buildVideoView({BoxFit fit = BoxFit.contain}) =>
      const SizedBox.expand();

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

/// 测试宿主:与 WindowsApp 相同的 router/theme,额外在 builder 补 Material
/// 祖先,保证播放页 Slider 等控件在 VM 测试环境可正常构建。
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
  /// pump 真实路由宿主并返回 router。
  ///
  /// 平台 tabs(水平 ListView)与首页网格(GridView.builder)均按视口惰性
  /// 挂载:放大 surface 保证全部锚点挂载,几何断言才有意义。
  Future<GoRouter> pumpApp(WidgetTester tester) async {
    // 断点几何直接写 tester.view(dpr=1):setSurfaceSize 只更新渲染 surface,
    // MediaQuery 仍报默认 800×600,U9 断点(>=1024 平台 tab 显示文字)会误判。
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1600, 1200);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [playerProvider.overrideWithValue(FakeLivePlayer())],
        child: const _TestApp(),
      ),
    );
    // 两帧:/all 骨架渲染 + fixture 数据落地。
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    final element = tester.element(find.byType(Scaffold));
    return ProviderScope.containerOf(element).read(routerProvider);
  }

  /// 顶部导航容器:_TopNav 的 topNavHeight 高 Container(nav-home 祖先)。
  Finder topNavFinder() => find.ancestor(
    of: find.byKey(const Key('nav-home')),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is Container &&
          widget.constraints?.minHeight == AppSpacing.topNavHeight &&
          widget.constraints?.maxHeight == AppSpacing.topNavHeight,
    ),
  );

  /// room-card-* 房间卡片锚点(key 均为 ValueKey<String>,前缀匹配)。
  Finder roomCardFinder() => find.byWidgetPredicate(
    (widget) =>
        widget.key is ValueKey<String> &&
        (widget.key as ValueKey<String>).value.startsWith('room-card-'),
  );

  /// 平台 tab 内的 SFVideo 风格品牌图标(`PlatformIcon`,含真实素材)。
  Finder platformIconFinder() => find.byType(PlatformIcon);

  /// pump 到 /douyu/play/63136 播放页(fixture 数据落地)。
  Future<void> pumpPlayRoute(WidgetTester tester, GoRouter router) async {
    router.go('/douyu/play/63136');
    // 三帧:路由切页 + 播放控制器异步解析落地(fixture payload)。
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('topNavGeometry:导航高 44,平台 tabs 有序,工具锚点横排在视口内', (
    tester,
  ) async {
    await pumpApp(tester);

    // 1) 顶导航容器高 == AppSpacing.topNavHeight,贴视口顶部。
    final topNav = topNavFinder();
    expect(topNav, findsOneWidget);
    final navRect = tester.getRect(topNav);
    expect(navRect.height, AppSpacing.topNavHeight);
    expect(navRect.top, 0);

    // 2) 平台 tabs 顺序 == navPlatforms 跳过 all:每个平台以
    //    `platform-tab-{id}` 锚点定位,内部为 SFVideo 风格品牌图标
    //    (`PlatformIcon`,真实素材),tabs 从左到右按目录顺序排列并落在
    //    44px 顶栏内。
    var previousTabLeft = -double.infinity;
    for (final brand in PlatformBrandCatalog.navPlatforms.skip(1)) {
      final tab = find.byKey(Key('platform-tab-${brand.id}'));
      expect(tab, findsOneWidget, reason: '顶导航缺少平台 tab ${brand.name}');
      expect(
        find.descendant(of: tab, matching: platformIconFinder()),
        findsOneWidget,
        reason: '平台 tab ${brand.name} 缺少品牌图标',
      );
      final tabRect = tester.getRect(tab);

      expect(
        tabRect.left,
        greaterThanOrEqualTo(previousTabLeft),
        reason: '平台 tab ${brand.name} 未按 navPlatforms 顺序从左到右排列',
      );
      expect(tabRect.top, greaterThanOrEqualTo(navRect.top));
      expect(tabRect.bottom, lessThanOrEqualTo(navRect.bottom));
      previousTabLeft = tabRect.left;
    }

    // 3) 工具区 4 个 nav 锚点横排(从左到右)且完整落在视口内。
    // 视口取根 Scaffold 的真实渲染 rect:setSurfaceSize 只更新渲染 surface,
    // tester.view/MediaQuery 仍报默认 800x600,与布局坐标不一致。
    final scaffoldElement = tester.element(find.byType(Scaffold).first);
    final viewport = tester.getRect(find.byWidget(scaffoldElement.widget));
    var previousLeft = -double.infinity;
    for (final id in const [
      'nav-home',
      'nav-follow',
      'nav-search',
      'nav-settings',
    ]) {
      final anchor = find.byKey(Key(id));
      expect(anchor, findsOneWidget, reason: '缺少导航锚点 $id');
      final rect = tester.getRect(anchor);
      expect(
        rect.left,
        greaterThanOrEqualTo(previousLeft),
        reason: '$id 未与其它锚点横排(从左到右)',
      );
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(viewport.width));
      expect(rect.bottom, lessThanOrEqualTo(viewport.height));
      previousLeft = rect.left;
    }
  });

  testWidgets('contentNotClipped:首张房间卡片顶部不低于顶导航底部', (tester) async {
    await pumpApp(tester);

    final navRect = tester.getRect(topNavFinder());
    final cards = roomCardFinder();
    expect(
      tester.widgetList(cards).length,
      greaterThan(0),
      reason: '首页应渲染至少一张房间卡片',
    );

    // 全部卡片中最早的 top(即首卡)不得越过顶导航底部:内容不与导航重叠。
    var minTop = double.infinity;
    for (final widget in tester.widgetList(cards)) {
      final rect = tester.getRect(find.byWidget(widget));
      minTop = math.min(minTop, rect.top);
    }
    expect(minTop, greaterThanOrEqualTo(navRect.bottom));
  });

  testWidgets(
    'playPageShellFree:播放页不套 AppShell,侧栏宽按视口分档',
    (tester) async {
      final router = await pumpApp(tester);
      await pumpPlayRoute(tester, router);

      // 播放页无壳:顶导航锚点与 AppShell 均不存在。
      expect(find.byKey(const Key('nav-home')), findsNothing);
      expect(find.byType(AppShell), findsNothing);

      // 播放页自身锚点可用。
      expect(find.byKey(const Key('play-back')), findsOneWidget);
      expect(find.byKey(const Key('play-side-panel-toggle')), findsOneWidget);

      // 右侧信息栏宽度 == 视口分档值(1600 档 = 392,
      // 对齐 SFVideoLive main.css:236-240)。
      const viewportWidth = 1600.0;
      final panelRect = tester.getRect(find.byType(PlaySidePanel));
      expect(
        panelRect.width,
        AppSpacing.playSidePanelWidthFor(viewportWidth),
      );
    },
  );

  testWidgets('sidePanelToggle:点 toggle 侧栏消失,再点恢复且宽度不变', (tester) async {
    final router = await pumpApp(tester);
    await pumpPlayRoute(tester, router);

    // 初始侧栏可见,宽度为视口分档值(1600 档 = 392)。
    const viewportWidth = 1600.0;
    expect(find.byType(PlaySidePanel), findsOneWidget);
    expect(
      tester.getRect(find.byType(PlaySidePanel)).width,
      AppSpacing.playSidePanelWidthFor(viewportWidth),
    );

    // 第一次点击:侧栏收起。
    await tester.tap(find.byKey(const Key('play-side-panel-toggle')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(PlaySidePanel), findsNothing);

    // 第二次点击:侧栏恢复,宽度与首次一致(同一视口分档)。
    await tester.tap(find.byKey(const Key('play-side-panel-toggle')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(PlaySidePanel), findsOneWidget);
    expect(
      tester.getRect(find.byType(PlaySidePanel)).width,
      AppSpacing.playSidePanelWidthFor(viewportWidth),
    );
    expect(tester.takeException(), isNull);
  });
}
