/// 路由可达性与导航遍历 workflow test。
///
/// 覆盖四条链路:
/// 1. routeReachability:逐个深链路由表全部路径,断言标志性锚点/文本出现且无异常;
///    播放页额外断言不渲染 AppShell 顶导航(nav-home 不存在)。
/// 2. navTraversal:从 /all 起经顶部导航锚点遍历 Follow/Settings/Home/Search,
///    每步断言前一页锚点消失、新页锚点出现。
/// 3. platformSwitch:platform-tab chip 点击切换平台路由与选中态。
/// 4. 未知路由兜底:go('/nonexistent') 不抛框架异常。
///
/// 宿主约定(与 workflow_browse_play_test.dart 一致):
/// - media_kit 禁止在 VM 初始化:注入 FakeLivePlayer。
/// - 播放页不套 AppShell(无 Scaffold/Material),QualityLineBar 的 ChoiceChip、
///   PlayerControlsBar 的 Slider 依赖 Material 祖先,测试宿主用
///   MaterialApp.router 的 builder 统一补一层透明 Material。
/// - 全程固定次数 pump,不使用 pumpAndSettle(封面图片在 VM 中不会真正加载)。
/// - router 通过显式 ProviderContainer 读取(routerProvider),播放页无 Scaffold
///   也能拿到,便于 router.go 深链与路径断言。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:live_parser/live_parser.dart' show StreamLine;
import 'package:zishu_flutter/src/app/app_router.dart';
import 'package:zishu_flutter/src/app/app_shell.dart';
import 'package:zishu_flutter/src/app/app_theme.dart';
import 'package:zishu_flutter/src/features/play/application/play_provider.dart';
import 'package:zishu_flutter/src/platforms/common/playback/live_player.dart';

/// 测试替身:VM 下替代 MediaKitLivePlayer,不触碰任何原生播放内核。
class _FakeLivePlayer implements LivePlayer {
  _FakeLivePlayer();

  final List<String> calls = [];

  @override
  Stream<PlayerSnapshot> get snapshots =>
      Stream<PlayerSnapshot>.value(const PlayerSnapshot());

  @override
  Widget buildVideoView({BoxFit fit = BoxFit.contain}) =>
      const SizedBox.expand();

  @override
  Future<void> open(StreamLine line) async => calls.add('open:${line.url}');

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
  Future<void> stop() async => calls.add('stop');

  @override
  void dispose() => calls.add('dispose');
}

/// 测试宿主:与 WindowsApp 相同的 router/theme,额外在 builder 补 Material
/// 祖先,保证播放页 Slider/ChoiceChip 等控件在 VM 测试环境可正常构建。
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
  /// VM 下 Material 3 的 IconButton 最小 40px 高 + 测试字体取整,使
  /// FollowEntryCard 固定元信息区必现 RenderFlex 溢出(同 app_shell_test)。
  /// 该溢出是应用既有布局在测试环境的固有表现,与锚点/路由断言无关,
  /// 这里只放行溢出类渲染错误,其余异常照常上报。
  void suppressRenderFlexOverflow() {
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      if (details.exception.toString().contains('A RenderFlex overflowed')) {
        return;
      }
      originalOnError?.call(details);
    };
  }

  /// pump 测试宿主(注入 FakeLivePlayer)并返回 router。
  /// router 从显式 ProviderContainer 读取,播放页(无 Scaffold)同样可用。
  Future<GoRouter> pumpApp(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [playerProvider.overrideWithValue(_FakeLivePlayer())],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const _TestApp()),
    );
    // 两帧:首页(/all)骨架渲染 + fixture 数据落地。
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    return container.read(routerProvider);
  }

  /// 深链/跳转到 [location] 并稳定数帧(NoTransitionPage 无过渡动画)。
  Future<void> goAndStabilize(
    WidgetTester tester,
    GoRouter router,
    String location,
  ) async {
    router.go(location);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// 断言应用壳层顶导航四个锚点齐全。
  void expectTopNavAnchors(String location) {
    for (final id in const [
      'nav-home',
      'nav-follow',
      'nav-search',
      'nav-settings',
    ]) {
      expect(
        find.byKey(Key(id)),
        findsOneWidget,
        reason: '页面 $location 缺少导航锚点 $id',
      );
    }
  }

  testWidgets('routeReachability:逐个深链路由表,锚点齐全且无异常', (tester) async {
    suppressRenderFlexOverflow();
    final router = await pumpApp(tester);

    // 1. /all 全平台首页:导航锚点 + 平台 chips + 房间网格。
    await goAndStabilize(tester, router, '/all');
    expectTopNavAnchors('/all');
    expect(find.byKey(const Key('home-platform-chip-all')), findsOneWidget);
    expect(find.byKey(const Key('room-card-douyu-63136')), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 2. /follow 关注页:标题 + fixture 初始关注条目。
    await goAndStabilize(tester, router, '/follow');
    expectTopNavAnchors('/follow');
    expect(find.text('我的关注'), findsOneWidget);
    expect(find.byKey(const Key('follow-entry-douyu-63136')), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 3. /time 动态时间线:标题 + 平台筛选 chip。
    await goAndStabilize(tester, router, '/time');
    expectTopNavAnchors('/time');
    expect(find.text('动态时间线'), findsOneWidget);
    expect(find.byKey(const Key('timeline-filter-all')), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 4. /settings 设置页:标题 + 外观分组行。
    await goAndStabilize(tester, router, '/settings');
    expectTopNavAnchors('/settings');
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('主题模式'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 5. /search 搜索页:搜索框锚点 + 空态引导文案。
    await goAndStabilize(tester, router, '/search');
    expectTopNavAnchors('/search');
    expect(find.byKey(const Key('search-input')), findsOneWidget);
    expect(find.text('搜索主播 / 房间号 / 直播间链接'), findsWidgets);
    expect(tester.takeException(), isNull);

    // 6. /douyu 平台首页:导航锚点 + 斗鱼 chip 选中 + 房间网格。
    await goAndStabilize(tester, router, '/douyu');
    expectTopNavAnchors('/douyu');
    expect(
      tester.widget<FilterChip>(
        find.byKey(const Key('home-platform-chip-douyu')),
      ).selected,
      isTrue,
      reason: '/douyu 页斗鱼平台 chip 应为选中态',
    );
    expect(find.byKey(const Key('room-card-douyu-63136')), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 7. /douyu/category/1 分类页:分组 tab + 子分类 tile + 该分类房间。
    await goAndStabilize(tester, router, '/douyu/category/1');
    expectTopNavAnchors('/douyu/category/1');
    expect(find.byKey(const Key('category-group-1')), findsOneWidget);
    expect(find.byKey(const Key('category-item-1')), findsOneWidget);
    expect(find.byKey(const Key('room-card-douyu-63136')), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 8. /douyu/play/63136 播放页:不套 AppShell(无顶导航),返回锚点存在。
    await goAndStabilize(tester, router, '/douyu/play/63136');
    expect(find.byKey(const Key('play-back')), findsOneWidget);
    expect(find.byType(AppShell), findsNothing, reason: '播放页不套应用壳层');
    expect(find.byKey(const Key('nav-home')), findsNothing);
    expect(tester.takeException(), isNull);

    // 9. /douyu/anchor/神超 主播主页:昵称 + 进入直播间 + 关注按钮锚点。
    await goAndStabilize(tester, router, '/douyu/anchor/神超');
    expectTopNavAnchors('/douyu/anchor/神超');
    expect(find.text('神超'), findsOneWidget);
    expect(find.text('进入直播间'), findsOneWidget);
    expect(find.byKey(const Key('anchor-follow-btn')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('navTraversal:顶部导航遍历 follow → settings → home → search',
      (tester) async {
    suppressRenderFlexOverflow();
    final router = await pumpApp(tester);

    // 起点 /all:房间网格 + 四个导航锚点齐全。
    expect(router.routeInformationProvider.value.uri.path, '/all');
    expect(find.byKey(const Key('room-card-douyu-63136')), findsOneWidget);
    expectTopNavAnchors('/all');

    // Step 1:点 nav-follow → 关注页;前一页网格锚点消失,关注条目出现。
    await tester.tap(find.byKey(const Key('nav-follow')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(router.routeInformationProvider.value.uri.path, '/follow');
    expect(find.text('我的关注'), findsOneWidget);
    expect(find.byKey(const Key('follow-entry-douyu-63136')), findsOneWidget);
    expect(find.byKey(const Key('room-card-douyu-63136')), findsNothing);
    expect(tester.takeException(), isNull);

    // Step 2:点 nav-settings → 设置页;关注页文案/条目锚点消失。
    await tester.tap(find.byKey(const Key('nav-settings')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(router.routeInformationProvider.value.uri.path, '/settings');
    expect(find.text('主题模式'), findsOneWidget);
    expect(find.text('我的关注'), findsNothing);
    expect(find.byKey(const Key('follow-entry-douyu-63136')), findsNothing);
    expect(tester.takeException(), isNull);

    // Step 3:点 nav-home 回首页;设置文案消失,房间网格恢复。
    await tester.tap(find.byKey(const Key('nav-home')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(router.routeInformationProvider.value.uri.path, '/all');
    expect(find.byKey(const Key('room-card-douyu-63136')), findsOneWidget);
    expect(find.text('主题模式'), findsNothing);
    expect(tester.takeException(), isNull);

    // Step 4:搜索页。nav-search 已绑定 /search 路由,点击直接跳转。
    await tester.tap(find.byKey(const Key('nav-search')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(router.routeInformationProvider.value.uri.path, '/search');
    expect(find.byKey(const Key('search-input')), findsOneWidget);
    expect(tester.takeException(), isNull);

    router.go('/search');
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(router.routeInformationProvider.value.uri.path, '/search');
    expect(find.byKey(const Key('search-input')), findsOneWidget);
    expect(find.byKey(const Key('room-card-douyu-63136')), findsNothing);
    expect(tester.takeException(), isNull);

    // Step 5:从搜索页点 nav-home 收尾回首页,导航锚点全程可用。
    await tester.tap(find.byKey(const Key('nav-home')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(router.routeInformationProvider.value.uri.path, '/all');
    expect(find.byKey(const Key('room-card-douyu-63136')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('platformSwitch:platform-tab chip 切换平台路由与选中态',
      (tester) async {
    suppressRenderFlexOverflow();
    final router = await pumpApp(tester);

    // 起点 /all:全平台 chip 选中。
    expect(
      tester.widget<FilterChip>(
        find.byKey(const Key('home-platform-chip-all')),
      ).selected,
      isTrue,
    );

    // 点 platform-tab-huya → 路由切到 /huya,虎牙 chip 选中、全平台取消。
    await tester.tap(find.byKey(const Key('home-platform-chip-huya')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(router.routeInformationProvider.value.uri.path, '/huya');
    expect(
      tester.widget<FilterChip>(
        find.byKey(const Key('home-platform-chip-huya')),
      ).selected,
      isTrue,
    );
    expect(
      tester.widget<FilterChip>(
        find.byKey(const Key('home-platform-chip-all')),
      ).selected,
      isFalse,
    );
    expect(tester.takeException(), isNull);

    // 点 platform-tab-all → 回 /all,全平台 chip 恢复选中,房间网格可用。
    await tester.tap(find.byKey(const Key('home-platform-chip-all')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(router.routeInformationProvider.value.uri.path, '/all');
    expect(
      tester.widget<FilterChip>(
        find.byKey(const Key('home-platform-chip-all')),
      ).selected,
      isTrue,
    );
    expect(find.byKey(const Key('room-card-douyu-63136')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unknownRoute:go(/nonexistent) 不抛框架异常', (tester) async {
    suppressRenderFlexOverflow();
    final router = await pumpApp(tester);

    // 实际行为记录:路由表末尾的 /:site 是单段兜底路由,'/nonexistent' 并不会
    // 触发 go_router 的 no-match 错误,而是命中 HomeView(site: 'nonexistent')
    // + AppShell(site: 'nonexistent');fixture 数据源对任意 site 返回同一批
    // 样例房间,因此页面按普通平台首页语义渲染。这里断言:导航完成无框架异常
    // 且页面真实渲染出来(顶导航锚点 + 房间网格)。
    await goAndStabilize(tester, router, '/nonexistent');
    expect(tester.takeException(), isNull);
    expectTopNavAnchors('/nonexistent');
    expect(find.byKey(const Key('room-card-douyu-63136')), findsOneWidget);

    // 平台 chips 仍渲染,但没有任何一个被选中('nonexistent' 不在品牌目录中)。
    expect(find.byKey(const Key('home-platform-chip-all')), findsOneWidget);
    expect(
      tester.widget<FilterChip>(
        find.byKey(const Key('home-platform-chip-all')),
      ).selected,
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });
}
