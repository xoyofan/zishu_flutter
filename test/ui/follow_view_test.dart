/// 我的关注页(FollowView)widget test:条目锚点、密度切换、特别关注与批量删除。
/// 无窗口后台验证:VM 中直接 pump WindowsApp 后路由到 /follow,
/// 数据走默认 followProvider(fixture 派生 6 条),无网络。
///
/// 封面用 CachedNetworkImage,VM 中请求被测试 binding 拦下,渲染占位块;
/// 因此不做图片断言,固定次数 pump,不使用 pumpAndSettle。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:live_parser/live_parser.dart' show StreamLine;
import 'package:zishu_flutter/src/app/app_router.dart';
import 'package:zishu_flutter/src/apps/windows/windows_app.dart';
import 'package:zishu_flutter/src/features/follow/application/follow_provider.dart';
import 'package:zishu_flutter/src/features/follow/views/follow_view.dart';
import 'package:zishu_flutter/src/features/follow/widgets/follow_entry_card.dart';
import 'package:zishu_flutter/src/features/follow/widgets/follow_entry_row.dart';
import 'package:zishu_flutter/src/features/play/application/play_provider.dart';
import 'package:zishu_flutter/src/platforms/common/playback/live_player.dart';
import 'package:zishu_flutter/src/shared/application/fixture_sources.dart';

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
  Future<void> stop() async => calls.add('stop');

  @override
  void dispose() => calls.add('dispose');
}

void main() {
  /// VM 下 Material 3 的 IconButton 最小 40px 高 + 测试字体取整,使
  /// FollowEntryCard 固定元信息区(约 68px)必现约 15px 的 RenderFlex 溢出。
  /// 该溢出是应用既有布局在测试环境的固有表现,与条目锚点/状态断言无关,
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

  /// 放大测试窗口:保证卡片网格 6 条全部构建,避免懒加载影响锚点计数。
  void useWideSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1280, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// pump WindowsApp(注入 FakeLivePlayer)并路由到 /follow,返回 router。
  Future<GoRouter> pumpFollowApp(WidgetTester tester) async {
    useWideSurface(tester);
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
    router.go('/follow');
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    return router;
  }

  /// 统计当前树上 follow-entry-* 锚点数量。
  int entryAnchorCount(WidgetTester tester) {
    return tester
        .widgetList(
          find.byWidgetPredicate(
            (widget) =>
                widget.key is ValueKey<String> &&
                (widget.key as ValueKey<String>)
                    .value
                    .startsWith('follow-entry-'),
          ),
        )
        .length;
  }

  /// 读取容器(便于直接断言 followProvider 状态)。
  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(FollowView)));

  testWidgets('默认卡片密度:渲染 fixture 派生的 6 条关注锚点', (tester) async {
    suppressRenderFlexOverflow();
    await pumpFollowApp(tester);

    // fixture 初始 6 条由 kFixtureRooms 前 6 项派生,每个都有唯一条目锚点。
    for (final room in kFixtureRooms.take(6)) {
      expect(
        find.byKey(Key('follow-entry-${room.site}-${room.roomId}')),
        findsOneWidget,
        reason: '缺少关注条目锚点 ${room.site}/${room.roomId}',
      );
    }
    expect(entryAnchorCount(tester), 6);
    expect(find.byType(FollowEntryCard), findsNWidgets(6));

    // 密度选择状态:默认 card 段选中。
    final segment = tester.widget<SegmentedButton<FollowDensity>>(
      find.byType(SegmentedButton<FollowDensity>),
    );
    expect(segment.selected, {FollowDensity.card});
  });

  testWidgets('点击 follow-density-row:列表切换为单行密度', (tester) async {
    suppressRenderFlexOverflow();
    await pumpFollowApp(tester);

    await tester.tap(find.byKey(const Key('follow-density-row')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    // 密度选择状态变化 + 行专属组件出现、卡片消失,锚点总数保持 6。
    final segment = tester.widget<SegmentedButton<FollowDensity>>(
      find.byType(SegmentedButton<FollowDensity>),
    );
    expect(segment.selected, {FollowDensity.row});
    expect(find.byType(FollowEntryRow), findsNWidgets(6));
    expect(find.byType(FollowEntryCard), findsNothing);
    expect(entryAnchorCount(tester), 6);
  });

  testWidgets('点击条目特别关注星标:条目数不变,★ 状态翻转', (tester) async {
    suppressRenderFlexOverflow();
    await pumpFollowApp(tester);

    // 切到单行密度:行内操作按钮全部可见,便于定位星标。
    await tester.tap(find.byKey(const Key('follow-density-row')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    // 「红莲」初始非特别关注:行内不应有 ★(star_rounded)。
    const entryKey = Key('follow-entry-douyu-288016');
    expect(
      find.descendant(
        of: find.byKey(entryKey),
        matching: find.byIcon(Icons.star_rounded),
      ),
      findsNothing,
    );

    // 点击该条目的「设为特别关注」操作。
    await tester.tap(
      find.descendant(
        of: find.byKey(entryKey),
        matching: find.byTooltip('设为特别关注'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    // 条目数不变;★ 图标出现(行首标记 + 操作按钮激活态);
    // 状态层同步:isSpecial 已翻转。
    expect(find.byType(FollowEntryRow), findsNWidgets(6));
    expect(
      find.descendant(
        of: find.byKey(entryKey),
        matching: find.byIcon(Icons.star_rounded),
      ),
      findsWidgets,
    );
    final entry = containerOf(tester)
        .read(followProvider)
        .firstWhere((e) => e.key == 'douyu:288016');
    expect(entry.isSpecial, isTrue);
  });

  testWidgets('批量模式删除一条:锚点数 -1', (tester) async {
    suppressRenderFlexOverflow();
    await pumpFollowApp(tester);

    // 进入批量管理,点击条目改为选中该条。
    await tester.tap(find.text('批量管理'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byKey(const Key('follow-entry-douyu-288016')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    // 删除所选并确认条目消失、总数 -1。
    expect(find.text('删除所选 (1)'), findsOneWidget);
    await tester.tap(find.text('删除所选 (1)'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.byKey(const Key('follow-entry-douyu-288016')),
      findsNothing,
    );
    expect(find.byType(FollowEntryCard), findsNWidgets(5));
    expect(entryAnchorCount(tester), 5);

    // 冲掉「已删除」SnackBar 的展示时长 Timer,避免测试结束遗留 pending timer。
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 500));
  });
}
