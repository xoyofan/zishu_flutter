/// 路由可达性与导航遍历 workflow test。
///
/// 覆盖四条链路:
/// 1. routeReachability:逐个深链路由表全部路径,断言标志性锚点/文本出现且无异常;
///    播放页同样渲染 AppShell 顶导航(nav-home 存在)。
/// 2. navTraversal:从 /all 起经顶部导航锚点遍历 Follow/Settings/Home/Search,
///    每步断言前一页锚点消失、新页锚点出现。
/// 3. platformSwitch:platform-tab chip 点击切换平台路由与选中态。
/// 4. 未知路由兜底:go('/nonexistent') 不抛框架异常。
///
/// 宿主约定(与 workflow_browse_play_test.dart 一致):
/// - media_kit 禁止在 VM 初始化:注入 FakeLivePlayer。
/// - 播放页套 AppShell(自身也有 Scaffold),QualityLineBar 的 ChoiceChip、
///   PlayerControlsBar 的 Slider 依赖 Material 祖先,测试宿主用
///   MaterialApp.router 的 builder 统一补一层透明 Material。
/// - 全程固定次数 pump,不使用 pumpAndSettle(封面图片在 VM 中不会真正加载)。
/// - router 通过显式 ProviderContainer 读取(routerProvider),播放页无 Scaffold
///   也能拿到,便于 router.go 深链与路径断言。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:live_parser/live_parser.dart' show StreamLine;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:zishu_flutter/src/app/app_router.dart';
import 'package:zishu_flutter/src/app/app_shell.dart';
import 'package:zishu_flutter/src/app/app_theme.dart';
import 'package:zishu_flutter/src/features/follow/application/settings_provider.dart';
import 'package:zishu_flutter/src/features/play/application/play_provider.dart';
import 'package:zishu_flutter/src/platforms/common/playback/live_player.dart';
import 'package:zishu_flutter/src/shared/application/auth_provider.dart';

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

/// 测试替身:登录态固定匿名。真实 AuthController 在「有存储后端 + 无缓存凭据」
/// 时会向 data-server 发起默认账号登录(themeToggle 用例注入内存存储后触发),
/// fake_async 测试环境不允许真实 HTTP,这里整体替换掉登录态。
class _AnonymousAuthController extends AuthController {
  @override
  AuthState build() => const AuthState(phase: AuthPhase.anonymous);
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
  /// [anonymousAuth] 为真时追加匿名 auth 覆盖(themeToggle 用例注入内存存储
  /// 后,真实 AuthController 会向 data-server 发起登录),默认不改变既有
  /// 用例的容器构成。
  Future<GoRouter> pumpApp(WidgetTester tester, {bool anonymousAuth = false}) async {
    final container = ProviderContainer(
      overrides: [
        playerProvider.overrideWithValue(_FakeLivePlayer()),
        if (anonymousAuth) authProvider.overrideWith(_AnonymousAuthController.new),
      ],
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

  /// 把 SharedPreferencesAsync 切到独立内存后端(用例结束恢复原实例)。
  /// 持久化断言用:被测代码与测试读回共享同一存储,写盘即可同步回读。
  void useInMemoryPrefs() {
    final previous = SharedPreferencesAsyncPlatform.instance;
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData(<String, Object>{});
    addTearDown(() => SharedPreferencesAsyncPlatform.instance = previous);
  }

  /// 窄屏/宽屏视口切换(用例结束恢复默认 800x600)。
  void useViewport(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// 轮询至 settingsProvider hydrated(异步 _restore 挂在 microtask/await 后)。
  Future<void> pumpUntilHydrated(WidgetTester tester, ProviderContainer container) async {
    for (var attempt = 0; attempt < 10; attempt++) {
      if (container.read(settingsProvider).hydrated) {
        await tester.pump(const Duration(milliseconds: 50));
        return;
      }
      await tester.pump(const Duration(milliseconds: 50));
    }
    fail('settingsProvider 未在限定帧数内完成 hydrated');
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

    // 3. /timeline 动态时间线:标题 + 平台筛选 chip。
    await goAndStabilize(tester, router, '/timeline');
    expectTopNavAnchors('/timeline');
    expect(find.text('动态时间线'), findsOneWidget);
    expect(find.byKey(const Key('timeline-filter-all')), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 3b. /time 解析耗时基准(对齐 web `TimeView.vue`,不是时间线)。
    await goAndStabilize(tester, router, '/time');
    expectTopNavAnchors('/time');
    expect(find.byKey(const Key('bench-site')), findsOneWidget);
    expect(find.byKey(const Key('bench-run')), findsOneWidget);
    expect(find.byKey(const Key('timeline-filter-all')), findsNothing);
    expect(tester.takeException(), isNull);

    // 4. /settings 设置页:标题 + 外观分组行。
    await goAndStabilize(tester, router, '/settings');
    expectTopNavAnchors('/settings');
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('主题模式'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 4b. 设置页「工具」组 → 解析耗时基准页(顶/底栏无入口,这是唯一可达路径)。
    // 注:入口走 `context.push`(保留返回栈),go_router 的 push 不改
    // `routeInformationProvider` 的 uri(只走 Navigator),所以这里断言**渲染结果**
    // 而不是路径字符串。
    final benchEntry = find.byKey(const Key('settings-parse-benchmark'));
    await tester.ensureVisible(benchEntry);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(benchEntry);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const Key('bench-run')), findsOneWidget);
    expect(find.byKey(const Key('settings-parse-benchmark')), findsNothing);
    expect(tester.takeException(), isNull);

    // 5. /search 深链兼容:搜索已改为全局弹框,该路径重定向回首页。
    await goAndStabilize(tester, router, '/search');
    expect(
      router.routeInformationProvider.value.uri.path,
      '/all',
      reason: '/search 应重定向回 /all(搜索改弹框后不再有搜索页)',
    );
    expectTopNavAnchors('/all');
    expect(find.byKey(const Key('search-input')), findsNothing);
    expect(tester.takeException(), isNull);

    // 5b. 搜索弹框:点顶栏 nav-search 拉起,关框后仍在原页。
    await tester.tap(find.byKey(const Key('nav-search')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const Key('search-dialog')), findsOneWidget);
    expect(find.byKey(const Key('search-input')), findsOneWidget);
    expect(find.text('搜索主播 / 房间号 / 直播间链接'), findsWidgets);
    expect(
      router.routeInformationProvider.value.uri.path,
      '/all',
      reason: '搜索弹框不应改变路由位置',
    );
    await tester.tap(find.byKey(const Key('search-dialog-close')));
    // 对话框退场动画约 150ms:按固定步长推够时间,不使用 pumpAndSettle。
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(find.byKey(const Key('search-dialog')), findsNothing);
    expect(find.byKey(const Key('room-card-douyu-63136')), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 6. /douyu 平台首页:导航锚点 + 斗鱼 chip 选中 + 房间网格。
    await goAndStabilize(tester, router, '/douyu');
    expectTopNavAnchors('/douyu');
    expect(
      tester
          .widget<FilterChip>(find.byKey(const Key('home-platform-chip-douyu')))
          .selected,
      isTrue,
      reason: '/douyu 页斗鱼平台 chip 应为选中态',
    );
    expect(find.byKey(const Key('room-card-douyu-63136')), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 7. /douyu/category/1 分类房间页(用户口径 2026-09-19:带 cid 直达
    //    房间列表,无分组 tabs/子分类网格;房间 fixture 含 63136)。
    await goAndStabilize(tester, router, '/douyu/category/1');
    expectTopNavAnchors('/douyu/category/1');
    expect(find.byKey(const Key('category-group-1')), findsNothing,
        reason: '带 cid 进入不再渲染分组 tabs');
    expect(find.byKey(const Key('category-item-1')), findsNothing,
        reason: '带 cid 进入不再渲染子分类网格');
    expect(find.byKey(const Key('room-card-douyu-63136')), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 8. /douyu/play/63136 播放页:同样套 AppShell(顶导航常在,对齐参考实现
    //    AppLayout 包裹 PlayView),播放页自身锚点齐备。
    await goAndStabilize(tester, router, '/douyu/play/63136');
    expect(find.byKey(const Key('play-back')), findsOneWidget);
    expect(find.byType(AppShell), findsOneWidget, reason: '播放页套应用壳层');
    expect(find.byKey(const Key('nav-home')), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 9. /douyu/anchor/神超 主播主页:昵称 + 进入直播间 + 关注按钮锚点。
    await goAndStabilize(tester, router, '/douyu/anchor/神超');
    expectTopNavAnchors('/douyu/anchor/神超');
    expect(find.text('神超'), findsOneWidget);
    expect(find.text('进入直播间'), findsOneWidget);
    expect(find.byKey(const Key('anchor-follow-btn')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('navTraversal:顶部导航遍历 follow → settings → home → search', (
    tester,
  ) async {
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

    // Step 2:点 nav-settings → 设置**对话框**(2026-09-23 改弹框不切页):
    // 路由与底层关注页保持不变,「主题模式」在对话框里可见,
    // 关注锚点仍挂在底下(dialog 叠加于页面之上)。
    await tester.tap(find.byKey(const Key('nav-settings')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      router.routeInformationProvider.value.uri.path,
      '/follow',
      reason: '设置改弹框,不再切路由',
    );
    expect(find.byKey(const Key('settings-dialog')), findsOneWidget);
    expect(find.text('主题模式'), findsOneWidget);
    expect(find.byKey(const Key('follow-entry-douyu-63136')), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 关闭对话框回到底层关注页(退场动画约 150ms,推够帧)。
    await tester.tap(find.byKey(const Key('settings-dialog-close')));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(find.byKey(const Key('settings-dialog')), findsNothing);
    expect(find.text('主题模式'), findsNothing);

    // Step 3:点 nav-home 回首页;设置文案消失,房间网格恢复。
    await tester.tap(find.byKey(const Key('nav-home')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(router.routeInformationProvider.value.uri.path, '/all');
    expect(find.byKey(const Key('room-card-douyu-63136')), findsOneWidget);
    expect(find.text('主题模式'), findsNothing);
    expect(tester.takeException(), isNull);

    // Step 4:搜索弹框。nav-search 不再跳路由,而是拉起全局搜索框。
    await tester.tap(find.byKey(const Key('nav-search')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const Key('search-dialog')), findsOneWidget);
    expect(find.byKey(const Key('search-input')), findsOneWidget);
    expect(
      router.routeInformationProvider.value.uri.path,
      '/all',
      reason: '搜索弹框不切路由',
    );
    expect(tester.takeException(), isNull);

    // Esc 关框(搜索框自身的快捷键):回到原页,首页网格仍在。
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(find.byKey(const Key('search-dialog')), findsNothing);
    expect(find.byKey(const Key('room-card-douyu-63136')), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Step 5:从搜索页点 nav-home 收尾回首页,导航锚点全程可用。
    await tester.tap(find.byKey(const Key('nav-home')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(router.routeInformationProvider.value.uri.path, '/all');
    expect(find.byKey(const Key('room-card-douyu-63136')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('platformSwitch:platform-tab chip 切换平台路由与选中态', (tester) async {
    suppressRenderFlexOverflow();
    final router = await pumpApp(tester);

    // 起点 /all:全平台 chip 选中。
    expect(
      tester
          .widget<FilterChip>(find.byKey(const Key('home-platform-chip-all')))
          .selected,
      isTrue,
    );

    // 点 platform-tab-huya → 路由切到 /huya,虎牙 chip 选中、全平台取消。
    await tester.tap(find.byKey(const Key('home-platform-chip-huya')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(router.routeInformationProvider.value.uri.path, '/huya');
    expect(
      tester
          .widget<FilterChip>(find.byKey(const Key('home-platform-chip-huya')))
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<FilterChip>(find.byKey(const Key('home-platform-chip-all')))
          .selected,
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
      tester
          .widget<FilterChip>(find.byKey(const Key('home-platform-chip-all')))
          .selected,
      isTrue,
    );
    expect(find.byKey(const Key('room-card-douyu-63136')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unknownRoute:go(/nonexistent) 不抛框架异常', (tester) async {
    suppressRenderFlexOverflow();
    final router = await pumpApp(tester);

    // 未知平台统一回退到全平台首页,避免构造无效 site 后继续渲染 fixture/真实数据。
    await goAndStabilize(tester, router, '/nonexistent');
    expect(tester.takeException(), isNull);
    expectTopNavAnchors('/all');
    expect(find.byKey(const Key('room-card-douyu-63136')), findsOneWidget);

    // 非法平台不应进入任何选中态。
    expect(find.byKey(const Key('home-platform-chip-all')), findsOneWidget);
    expect(
      tester
          .widget<FilterChip>(find.byKey(const Key('home-platform-chip-all')))
          .selected,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('顶栏契约:nav-theme 已移除(主题收进设置),nav-settings 弹设置对话框', (
    tester,
  ) async {
    suppressRenderFlexOverflow();
    // 1600x900:≥ desktop 断点(1366)顶栏动作显示文案。
    useViewport(tester, const Size(1600, 900));
    useInMemoryPrefs();
    final router = await pumpApp(tester, anonymousAuth: true);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    );
    await pumpUntilHydrated(tester, container);

    // 新契约(2026-09-23):顶栏主题快捷按钮移除,浅色/主题收进设置对话框。
    expect(find.byKey(const Key('nav-theme')), findsNothing);
    expect(container.read(settingsProvider).themeMode, ThemeModeChoice.dark);
    expect(router.routeInformationProvider.value.uri.path, '/all');
    expect(
      await SharedPreferencesAsync().getString('zishu.settings.themeMode'),
      isNull,
      reason: '出厂默认深色不经写入,存储为空',
    );

    // 点设置 → 对话框,不切路由。
    await tester.tap(find.byKey(const Key('nav-settings')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const Key('settings-dialog')), findsOneWidget);
    expect(
      router.routeInformationProvider.value.uri.path,
      '/all',
      reason: '设置改弹框不切路由',
    );

    // 关闭回原页(退场动画推够帧)。
    await tester.tap(find.byKey(const Key('settings-dialog-close')));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(find.byKey(const Key('settings-dialog')), findsNothing);
    expect(router.routeInformationProvider.value.uri.path, '/all');
    expect(tester.takeException(), isNull);
  });

  testWidgets('themeToggleBottomBar:移动底栏 nav-theme 与顶栏同款切换且持久化', (
    tester,
  ) async {
    suppressRenderFlexOverflow();
    // 390x844:窄于 phone 断点(768),AppShell 渲染移动底栏(顶栏让位平台条,
    // nav-theme 锚点唯一落在底栏「主题」项)。
    useViewport(tester, const Size(390, 844));
    useInMemoryPrefs();
    await pumpApp(
      tester,
      anonymousAuth: true,
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    );
    await pumpUntilHydrated(tester, container);

    // 默认深色:底栏「主题」项文案同样表示目标态(浅色),与顶栏同源。
    expect(container.read(settingsProvider).themeMode, ThemeModeChoice.dark);
    expect(find.text('浅色'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('nav-theme')),
        matching: find.byIcon(Icons.light_mode_outlined),
      ),
      findsOneWidget,
    );

    // 点击 → light:状态与持久化字段同步更新(与顶栏共用 _toggleTheme)。
    await tester.tap(find.byKey(const Key('nav-theme')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(container.read(settingsProvider).themeMode, ThemeModeChoice.light);
    expect(find.text('深色'), findsOneWidget);
    expect(
      await SharedPreferencesAsync().getString('zishu.settings.themeMode'),
      'light',
    );

    // 再点 → 还原 dark,与顶栏行为一致(同份判定与切换实现)。
    await tester.tap(find.byKey(const Key('nav-theme')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(container.read(settingsProvider).themeMode, ThemeModeChoice.dark);
    expect(find.text('浅色'), findsOneWidget);
    expect(
      await SharedPreferencesAsync().getString('zishu.settings.themeMode'),
      'dark',
    );
    expect(tester.takeException(), isNull);
  });
}
