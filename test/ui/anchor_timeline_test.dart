/// 动态时间线(TimelineView)与主播主页(FollowButton)widget test:
/// 平台筛选锚点与节点过滤、主播页关注按钮状态翻转。
/// 无窗口后台验证:VM 中直接 pump WindowsApp,fixture 数据走默认 provider。
///
/// 封面/头像用 CachedNetworkImage,VM 中请求被测试 binding 拦下,渲染占位;
/// 不做图片断言,固定次数 pump,不使用 pumpAndSettle。media_kit 禁止在 VM
/// 初始化:注入 FakeLivePlayer 兜底。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:live_parser/live_parser.dart' show StreamLine;
import 'package:zishu_flutter/src/app/app_router.dart';
import 'package:zishu_flutter/src/apps/windows/windows_app.dart';
import 'package:zishu_flutter/src/features/anchor/widgets/timeline_tile.dart';
import 'package:zishu_flutter/src/features/play/application/play_provider.dart';
import 'package:zishu_flutter/src/platforms/common/playback/live_player.dart';
import 'package:zishu_flutter/src/shared/application/fixture_sources.dart';
import 'package:zishu_flutter/src/shared/presentation/platform_brands.dart';

/// 测试替身:VM 下替代 MediaKitLivePlayer,不触碰任何原生播放内核。
class _FakeLivePlayer implements LivePlayer {
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

void main() {
  /// 放大测试窗口:时间线 10 个节点全部构建,避免懒加载影响计数。
  void useTallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1280, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// pump WindowsApp(注入 FakeLivePlayer),导航到 [location] 并返回 router。
  Future<GoRouter> pumpApp(WidgetTester tester, {required String location}) async {
    useTallSurface(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [playerProvider.overrideWithValue(_FakeLivePlayer())],
        child: const WindowsApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    final element = tester.element(find.byType(Scaffold));
    final router = ProviderScope.containerOf(element).read(routerProvider);
    router.go(location);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    return router;
  }

  /// 当前树上时间线节点(TimelineTile)数量。
  int tileCount(WidgetTester tester) =>
      tester.widgetList(find.byType(TimelineTile)).length;

  testWidgets('/time:timeline-filter-* 锚点齐全且时间线节点 > 0',
      (tester) async {
    await pumpApp(tester, location: '/time');

    // 每个导航平台都有筛选 chip 锚点。
    for (final brand in PlatformBrandCatalog.navPlatforms) {
      expect(
        find.byKey(Key('timeline-filter-${brand.id}')),
        findsOneWidget,
        reason: '缺少时间线筛选锚点 ${brand.id}',
      );
    }
    // fixture 派生的时间线节点全部渲染(kFixtureRooms.length 个,> 0)。
    expect(tileCount(tester), kFixtureRooms.length);
    expect(tileCount(tester), greaterThan(0));
  });

  testWidgets('点击 timeline-filter-douyu:条目全为 douyu;切 huya 后筛空',
      (tester) async {
    await pumpApp(tester, location: '/time');

    // 选中 douyu:fixture 全部为 douyu,节点数 == douyu 样例数,chip 进入选中态。
    final douyuCount =
        kFixtureRooms.where((room) => room.site == 'douyu').length;
    await tester.tap(find.byKey(const Key('timeline-filter-douyu')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(tileCount(tester), douyuCount);
    expect(
      tester.widget<FilterChip>(
        find.descendant(
          of: find.byKey(const Key('timeline-filter-douyu')),
          matching: find.byType(FilterChip),
        ),
      ).selected,
      isTrue,
    );

    // 切到无样例数据的 huya:节点被筛空(数量变化),出现空态文案。
    await tester.tap(find.byKey(const Key('timeline-filter-huya')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('该平台暂无动态'), findsOneWidget);
    expect(find.byType(TimelineTile), findsNothing);
  });

  testWidgets('/douyu/anchor/神超:anchor-follow-btn 存在,点击后关注状态翻转',
      (tester) async {
    await pumpApp(tester, location: '/douyu/anchor/神超');

    // 主播资料卡渲染,关注按钮初始为「关注」。
    expect(find.byKey(const Key('anchor-follow-btn')), findsOneWidget);
    expect(find.text('关注'), findsOneWidget);
    expect(find.text('已关注'), findsNothing);

    await tester.tap(find.byKey(const Key('anchor-follow-btn')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    // 点击后按钮翻转为「已关注」。
    expect(find.text('已关注'), findsOneWidget);
    expect(find.text('关注'), findsNothing);
  });
}
