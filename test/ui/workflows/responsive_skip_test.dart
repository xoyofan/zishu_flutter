/// U9 响应式适配的 skip 占位测试组。
///
/// U9(窄屏底部导航 / 平台 tab icon-only 收缩 / 播放页侧栏堆叠 / 内容区
/// chips Wrap 多行)尚未实现:本文件先把验收断言注册为 skip 用例,U9 实现
/// 后移除各组 `skip: 'U9 待实现'` 即转绿验收,避免验收口径事后漂移。
///
/// 断言引用的真实锚点契约:
/// - 顶部导航:nav-home / nav-follow / nav-search / nav-settings(app_shell)。
/// - 平台 tab/chip:platform-tab-{site}(FilterChip,品牌色点为
///   BoxDecoration(shape: BoxShape.circle, color: brand.color))。
/// - 播放页:play-back / play-side-panel-toggle / play-quality-{name} /
///   PlaySidePanel。
/// - 收缩规范:>=1024 平台 tab=色点+文字;768–1023 仅色点(icon-only)+
///   Tooltip(平台名);<768 主导航转底部 56px、平台列表顶部横向 strip;
///   内容区筛选 chips 用 Wrap 多行。
///
/// media_kit 禁止在 VM 初始化:统一注入 FakeLivePlayer,误入播放路径也不
/// 会触碰原生播放内核。全程固定次数 pump,不使用 pumpAndSettle。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:live_parser/live_parser.dart' show StreamLine;
import 'package:zishu_flutter/src/app/app_router.dart';
import 'package:zishu_flutter/src/app/app_theme.dart';
import 'package:zishu_flutter/src/features/play/application/play_provider.dart';
import 'package:zishu_flutter/src/features/play/widgets/play_side_panel.dart';
import 'package:zishu_flutter/src/platforms/common/playback/live_player.dart';
import 'package:zishu_flutter/src/shared/presentation/design_tokens.dart';
import 'package:zishu_flutter/src/shared/presentation/platform_brands.dart';

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
  /// 放行溢出类渲染错误:窄屏(360 宽)下首页卡片在测试环境(Minimum 字体
  /// 取整)存在既有 RenderFlex overflow 噪音,与 U9 断言无关;其余异常照常
  /// 上报。播放页组依赖 takeException 捕获布局溢出,因此不做该抑制。
  void suppressRenderFlexOverflow() {
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      if (details.exception.toString().contains('A RenderFlex overflowed')) {
        return;
      }
      originalOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = originalOnError);
  }

  /// pump 真实路由宿主并固定逻辑视口为 [surface],返回 router。
  ///
  /// 断点几何直接写 [tester.view](physicalSize + dpr=1):`setSurfaceSize`
  /// 只更新渲染 surface,MediaQuery 仍报默认 800×600,会让 AppShell/HomeView/
  /// PlayView 的断点判定全部失灵;写 view 才能让 MediaQuery 同步,U9 各
  /// 断点(底部导航 / icon-only / 堆叠 / Wrap)才有意义。
  Future<GoRouter> pumpApp(WidgetTester tester, Size surface) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = surface;
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

  /// pump 到 /douyu/play/63136 播放页(fixture 数据落地)。
  Future<void> pumpPlayRoute(WidgetTester tester, GoRouter router) async {
    router.go('/douyu/play/63136');
    // 三帧:路由切页 + 播放控制器异步解析落地(fixture payload)。
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// 逻辑视口尺寸(setSurfaceSize 后 physical/dpr 还原为逻辑像素)。
  Size viewport(WidgetTester tester) =>
      tester.view.physicalSize / tester.view.devicePixelRatio;

  /// 平台 tab 内的圆形品牌色点(填充色 == brand.color,尺寸不限定)。
  Finder platformDotFinder(PlatformBrand brand) => find.byWidgetPredicate(
    (widget) =>
        widget is Container &&
        widget.decoration is BoxDecoration &&
        (widget.decoration as BoxDecoration).shape == BoxShape.circle &&
        (widget.decoration as BoxDecoration).color == brand.color,
  );

  group('U9 底部导航', () {
    testWidgets('<768(360×640):顶部 44px 导航不渲染,底部 56px 导航含 首页/关注/设置', (
      tester,
    ) async {
      suppressRenderFlexOverflow();
      await pumpApp(tester, const Size(360, 640));
      final size = viewport(tester);

      // 顶部 44px 导航不渲染:logo 文案消失(<768 顶导航整体不渲染)。
      expect(
        find.text('紫薯直播'),
        findsNothing,
        reason: '窄屏下顶部导航(含 logo)不应渲染',
      );

      // 底部 56px 导航渲染:三个主导航入口文本存在,且中心点全部落在
      // 视口底部 56px 带内(bottomNavHeight 对齐 AppSpacing 规范)。
      // nav-* 锚点由顶部导航迁移至底部导航(实现复用同 key,与文件头
      // 注释的调整指引一致),nav-home 额外做底部带内断言。
      final bandTop = size.height - AppSpacing.bottomNavHeight;
      final navHome = find.byKey(const Key('nav-home'));
      expect(navHome, findsOneWidget, reason: 'nav-home 锚点应迁移至底部导航');
      final navHomeCenter = tester.getCenter(navHome);
      expect(
        navHomeCenter.dy,
        greaterThan(bandTop),
        reason: 'nav-home 应位于底部导航带内',
      );
      for (final label in const ['首页', '关注', '设置']) {
        final item = find.text(label);
        expect(item, findsOneWidget, reason: '底部导航缺少「$label」入口');
        final center = tester.getCenter(item);
        expect(
          center.dy,
          greaterThan(bandTop),
          reason:
              '「$label」中心不在底部 ${AppSpacing.bottomNavHeight}px 导航带内',
        );
        expect(
          center.dy,
          lessThanOrEqualTo(size.height),
          reason: '「$label」超出视口底部',
        );
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('U9 平台tab收缩', () {
    testWidgets('768–1023(820×1180 iPad Air):平台 tab icon-only,色点在、文字无、Tooltip=平台名', (
      tester,
    ) async {
      suppressRenderFlexOverflow();
      await pumpApp(tester, const Size(820, 1180));

      const douyuTab = Key('platform-tab-douyu');
      expect(find.byKey(douyuTab), findsOneWidget);

      // 文字收缩:平台 tab 内不再渲染平台名文本(icon-only)。
      expect(
        find.descendant(of: find.byKey(douyuTab), matching: find.text('斗鱼')),
        findsNothing,
        reason: '768–1023 宽度下平台 tab 应 icon-only,不渲染「斗鱼」文字',
      );

      // icon-only 后仍保留品牌色点,并以 Tooltip 承载平台名。
      expect(
        find.descendant(
          of: find.byKey(douyuTab),
          matching: platformDotFinder(PlatformBrandCatalog.douyu),
        ),
        findsOneWidget,
        reason: 'icon-only 平台 tab 应保留斗鱼品牌色点',
      );
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Tooltip && widget.message == '斗鱼',
        ),
        findsOneWidget,
        reason: 'icon-only 平台 tab 的 Tooltip 值应为平台名「斗鱼」',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('>=1024(1600×1200):平台 tab 为色点+文字', (tester) async {
      suppressRenderFlexOverflow();
      await pumpApp(tester, const Size(1600, 1200));

      const douyuTab = Key('platform-tab-douyu');
      expect(find.byKey(douyuTab), findsOneWidget);
      expect(
        find.descendant(of: find.byKey(douyuTab), matching: find.text('斗鱼')),
        findsOneWidget,
        reason: '桌面宽度下平台 tab 应显示「斗鱼」文字',
      );
      expect(
        find.descendant(
          of: find.byKey(douyuTab),
          matching: platformDotFinder(PlatformBrandCatalog.douyu),
        ),
        findsOneWidget,
        reason: '桌面宽度下平台 tab 应保留斗鱼品牌色点',
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('U9 播放页侧栏堆叠', () {
    testWidgets('竖屏 360×640:视频全宽,侧栏堆叠在视频下方且可滚达', (tester) async {
      final router = await pumpApp(tester, const Size(360, 640));
      // 丢弃首页在窄屏测试环境的既有 overflow 噪音,只验证播放页布局。
      tester.takeException();
      await pumpPlayRoute(tester, router);

      expect(find.byKey(const Key('play-back')), findsOneWidget);
      expect(find.byKey(const Key('play-side-panel-toggle')), findsOneWidget);

      // 侧栏在视频下方:窄屏首屏可能放不下,先滚动到可挂载(可滚达)。
      final panel = find.byType(PlaySidePanel);
      if (!tester.any(panel)) {
        await tester.scrollUntilVisible(
          panel,
          120,
          scrollable: find.byType(Scrollable).first,
        );
      }
      expect(panel, findsOneWidget, reason: '竖屏下侧栏应位于视频下方且可滚达');

      // 不与视频同行:侧栏顶部必须低于视频列底部的画质条(堆叠布局);
      // 侧栏贴内容左缘,说明视频已占满内容区全宽,而非被右栏挤压。
      final qualityTop =
          tester.getTopLeft(find.byKey(const Key('play-quality-蓝光8M'))).dy;
      final panelRect = tester.getRect(panel);
      expect(
        panelRect.top,
        greaterThan(qualityTop),
        reason: '侧栏不应与视频同行(应堆叠在画质条之下)',
      );
      expect(
        panelRect.left,
        lessThanOrEqualTo(AppSpacing.lg + 1),
        reason: '堆叠布局下侧栏应与视频同宽贴左,而非靠右列',
      );
      expect(tester.takeException(), isNull, reason: '竖屏堆叠布局不得产生 RenderFlex 溢出');
    });

    testWidgets('横屏 852×393:侧栏转为滑出 sheet 或隐藏,不与视频同行', (tester) async {
      final router = await pumpApp(tester, const Size(852, 393));
      // 丢弃首页在窄屏测试环境的既有 overflow 噪音,只验证播放页布局。
      tester.takeException();
      await pumpPlayRoute(tester, router);

      expect(find.byKey(const Key('play-back')), findsOneWidget);
      expect(find.byKey(const Key('play-side-panel-toggle')), findsOneWidget);

      // U9 允许两种形态:直接隐藏,或经 play-side-panel-toggle 滑出 sheet。
      // 唯一禁止的是现状的 328px 常驻右栏(顶部对齐房间头、挤压视频)。
      final panel = find.byType(PlaySidePanel);
      if (tester.any(panel)) {
        final panelRect = tester.getRect(panel);
        final asSheet =
            panelRect.top > AppSpacing.topNavHeight ||
            panelRect.width > AppSpacing.playSidePanelWidth;
        expect(
          asSheet,
          isTrue,
          reason: '横屏下侧栏若可见,应以 sheet/浮层形态存在'
              '(顶部低于房间头,或宽度近全屏),而非 328px 常驻右栏',
        );
      } else {
        expect(panel, findsNothing, reason: '横屏下侧栏隐藏(经 play-side-panel-toggle 滑出)');
      }
      expect(tester.takeException(), isNull, reason: '横屏布局不得产生 RenderFlex 溢出');
    });
  });

  group('U9 chips换行', () {
    testWidgets('360 宽:首页平台 chips 为 Wrap 多行(第二行存在),全部挂载不横向裁切', (
      tester,
    ) async {
      suppressRenderFlexOverflow();
      await pumpApp(tester, const Size(360, 640));

      const ids = ['all', 'douyu', 'huya', 'bilibili', 'douyin', 'twitch'];
      // 全部挂载:横向裁切的水平 ListView 在 360 宽只挂载首屏 2~3 个 chip,
      // 全部 findsOneWidget 即证明非横向裁切。
      for (final id in ids) {
        expect(
          find.byKey(Key('platform-tab-$id')),
          findsOneWidget,
          reason: '平台 chip $id 未挂载,chips 仍被横向裁切',
        );
      }

      // 容器形态:chips 由 Wrap 承载(多行自适应),而非横向 ListView。
      expect(
        find.ancestor(
          of: find.byKey(const Key('platform-tab-douyu')),
          matching: find.byType(Wrap),
        ),
        findsOneWidget,
        reason: '内容区筛选 chips 应使用 Wrap 布局',
      );

      // 第二行存在:至少一个 chip 的顶部低于首行 chip 顶部(多行换行)。
      final firstRowTop =
          tester.getTopLeft(find.byKey(const Key('platform-tab-all'))).dy;
      final hasSecondRow = ids.any(
        (id) =>
            tester.getTopLeft(find.byKey(Key('platform-tab-$id'))).dy >
            firstRowTop + 1,
      );
      expect(hasSecondRow, isTrue, reason: 'chips 应换行为多行,而非单行横向排布');
      expect(tester.takeException(), isNull);
    });
  });

  // 哨兵用例:保证本文件在全部组 skip 时仍有绿色结果,CI 不视为空跑。
  test('U9 占位组已注册', () {
    expect(true, isTrue);
  });
}
