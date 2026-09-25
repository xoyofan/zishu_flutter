/// 首页「按平台独立区块 + 骨架 + 每平台少量请求」workflow 测试。
///
/// 覆盖(与任务口径一一对应):
/// 1. 每平台独立首屏请求:page=1、limit == 当前网格列数,不再发 `site:'all'` 聚合请求;
/// 2. 某平台失败只影响该平台区块(错误态 + 可重试),其它平台照常渲染;
/// 3. 某平台慢(门未放行)不阻塞其它平台;该平台显示骨架卡片(数量=列数),
///    数据到达后骨架替换为真实卡片;
/// 4. 单平台页(/twitch)保持现有单请求逻辑:limit 不下发、无区块布局;
/// 5. 点「更多」按既有 loadMore 语义增量追加该平台下一页(page+1、limit 不变);
/// 6. 区块头可点进该平台首页 /{site};
/// 7. F5/刷新动作(GlobalActions.refreshHome)重置所有平台区块;
/// 8. 区块网格盒高 == 内容高(RoomGrid 同公式),卡片不被裁切、盒底不留空段;
/// 9. 视口宽度变化 → 列数变化 → 按新 limit 重新拉取(provider key 带 limit)。
///
/// 宿主约定(复用 workflow 目录既有测试):
/// - media_kit 禁止在 VM 初始化:注入 FakeLivePlayer;
/// - 走真实 go_router 宿主(MaterialApp.router + builder 补 Material 祖先);
/// - 断点几何直接写 tester.view.physicalSize(setSurfaceSize 不同步 MediaQuery);
/// - 全程固定次数 pump,不使用 pumpAndSettle(封面图片在 VM 中不真正加载)。
///
/// 数据源:fake BrowseSource(记录每次 fetchRooms 的 site/cid/page/limit),
/// 与公共 fixture 解耦,可精确断言请求参数与按平台失败/挂起。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:live_parser/live_parser.dart';
import 'package:zishu_flutter/src/app/app_router.dart';
import 'package:zishu_flutter/src/app/app_theme.dart';
import 'package:zishu_flutter/src/features/play/application/play_provider.dart';
import 'package:zishu_flutter/src/platforms/common/playback/live_player.dart';
import 'package:zishu_flutter/src/shared/application/browse_source.dart';
import 'package:zishu_flutter/src/shared/application/global_actions.dart';
import 'package:zishu_flutter/src/shared/application/providers.dart';
import 'package:zishu_flutter/src/shared/presentation/design_tokens.dart';
import 'package:zishu_flutter/src/shared/presentation/platform_brands.dart';
import 'package:zishu_flutter/src/shared/presentation/widgets/retry_button.dart';

import 'platform_workflow.dart' show anchorKeysWithPrefix;

/// 一次 fetchRooms 调用的记录。
class _FetchCall {
  const _FetchCall({
    required this.site,
    required this.cid,
    required this.page,
    required this.limit,
  });

  final String site;
  final String? cid;
  final int page;

  /// null = 调用方未下发 limit(单平台页旧路径)。
  final int? limit;
}

/// 测试替身:记录调用参数,可按平台失败 / 挂起(门) / 翻页。
class _RecordingBrowseSource implements BrowseSource {
  _RecordingBrowseSource({Set<String>? failSites})
    : failSites = failSites ?? <String>{};

  /// 这些平台 fetchRooms 直接抛错(模拟单平台失败)。
  final Set<String> failSites;

  /// 挂起门:命中平台的 fetchRooms 等待门完成(模拟慢平台)。
  final Map<String, Completer<RoomListResult>> gates =
      <String, Completer<RoomListResult>>{};

  /// 每次调用的参数记录。
  final List<_FetchCall> calls = <_FetchCall>[];

  /// page 1 返回 hasMore=true(驱动「更多」按钮),page 2 及之后为 false。
  bool hasMoreFirstPage = false;

  @override
  Future<CategoryResult> fetchCategories(String site) async =>
      CategoryResult(site: site, groups: const <CategoryGroup>[]);

  @override
  Future<RoomListResult> fetchRooms({
    required String site,
    String? cid,
    int page = 1,
    int? limit,
  }) async {
    calls.add(_FetchCall(site: site, cid: cid, page: page, limit: limit));
    final gate = gates[site];
    if (gate != null) await gate.future;
    if (failSites.contains(site)) {
      throw StateError('模拟平台失败: $site');
    }
    // 与真实源同语义:按 limit 截断;未下发 limit 时返回 10 条样例。
    final count = limit ?? 10;
    final start = (page - 1) * count;
    return RoomListResult(
      rooms: [
        for (var i = 0; i < count; i++)
          RoomRecord(
            site: site,
            roomId: 'r${start + i}',
            roomState: RoomState.live,
            title: '直播间${start + i}',
            anchorName: '主播${start + i}',
          ),
      ],
      page: page,
      hasMore: page < 2 && hasMoreFirstPage,
    );
  }
}

/// 测试替身:VM 下替代 MediaKitLivePlayer(误入播放路径也不触碰原生内核)。
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

/// 测试宿主:与 WindowsApp 相同的 router/theme,builder 补 Material 祖先。
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

/// 首页区块的平台 id 列表(与实现同口径:导航平台目录去掉「全平台」)。
List<String> _sectionSites() => PlatformBrandCatalog.navigationPlatforms
    .map((brand) => brand.id)
    .where((id) => id != 'all')
    .toList();

/// 以 [prefix] 开头的 `room-card-{site}-*` 卡片数量。
int _cardCount(WidgetTester tester, String site) =>
    anchorKeysWithPrefix(tester, 'room-card-$site-').length;

/// 以 [prefix] 开头的任意 key 数量。
int _keyCount(WidgetTester tester, String prefix) =>
    anchorKeysWithPrefix(tester, prefix).length;

void main() {
  /// pump 宿主(注入 fake 数据源)并返回 router;初始路由即 /all。
  Future<GoRouter> pumpApp(
    WidgetTester tester,
    _RecordingBrowseSource source, {
    double width = 1600,
    double height = 1200,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = Size(width, height);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer(
      overrides: [
        playerProvider.overrideWithValue(_FakeLivePlayer()),
        browseSourceProvider.overrideWithValue(source),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const _TestApp()),
    );
    // 两帧:区块骨架渲染 + 数据落地。
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    return container.read(routerProvider);
  }

  /// 再推三帧(数据/状态落地 + 消化 TranslatedText 的零延迟聚合 Timer)。
  Future<void> pump2(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('每平台独立首屏请求:limit=列数、page=1、不发聚合请求', (tester) async {
    final fake = _RecordingBrowseSource();
    final router = await pumpApp(tester, fake);
    await pump2(tester);

    expect(router.routeInformationProvider.value.uri.path, '/all');
    expect(fake.calls, isNotEmpty, reason: '首页应按平台发起 fetchRooms');
    expect(
      fake.calls.map((call) => call.site),
      isNot(contains('all')),
      reason: 'site=all 聚合请求应被按平台独立请求取代',
    );
    final columns = AppRoomGrid.columnsFor(1600);
    for (final call in fake.calls) {
      expect(call.page, 1, reason: '首屏只请求第一页');
      expect(call.limit, columns, reason: '首屏每平台只请求当前列数条(${call.site})');
    }
    // 首屏可见的前几个区块各自发起了请求(互不阻塞)。
    expect(
      fake.calls.map((call) => call.site).toSet(),
      containsAll(<String>{'douyu', 'huya', 'bilibili'}),
    );
    // 区块头渲染(平台名锚点)。
    expect(find.byKey(const Key('home-section-header-douyu')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('某平台失败只影响该平台区块:其它平台照常渲染,该平台错误态可重试', (tester) async {
    final fake = _RecordingBrowseSource(failSites: <String>{'huya'});
    await pumpApp(tester, fake);
    await pump2(tester);

    // 其它平台照常渲染。
    expect(find.byKey(const Key('room-card-douyu-r0')), findsOneWidget);
    // 失败平台区块:错误态 + 重试入口,不拖垮整页。
    final errorSection = find.byKey(const Key('home-section-error-huya'));
    expect(errorSection, findsOneWidget);

    // 修复数据源后点重试,该平台恢复卡片。
    fake.failSites.clear();
    await tester.tap(
      find.descendant(of: errorSection, matching: find.byType(RetryButton)),
    );
    await pump2(tester);
    expect(find.byKey(const Key('home-section-error-huya')), findsNothing);
    expect(find.byKey(const Key('room-card-huya-r0')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('慢平台显示骨架(数量=列数),数据到达后替换为真实卡片;其它平台不等待', (tester) async {
    final fake = _RecordingBrowseSource();
    final gate = Completer<RoomListResult>();
    fake.gates['huya'] = gate;
    await pumpApp(tester, fake);
    await pump2(tester);

    final columns = AppRoomGrid.columnsFor(1600);

    // 慢平台:骨架卡片数 == 列数(首屏一行,与请求条数一致)。
    expect(
      _keyCount(tester, 'home-section-skeleton-huya-'),
      columns,
      reason: '骨架卡片数量应等于当前列数',
    );
    // 其它平台不被慢平台阻塞:已渲染真实卡片且无骨架。
    expect(find.byKey(const Key('room-card-douyu-r0')), findsOneWidget);
    expect(_keyCount(tester, 'home-section-skeleton-douyu-'), 0);

    // 门放行 → 骨架消失,换成真实卡片(数量 == 列数)。
    gate.complete(
      RoomListResult(
        rooms: [
          for (var i = 0; i < columns; i++)
            RoomRecord(
              site: 'huya',
              roomId: 'g$i',
              roomState: RoomState.live,
              title: '门控直播间$i',
            ),
        ],
        page: 1,
        hasMore: false,
      ),
    );
    await pump2(tester);
    expect(_keyCount(tester, 'home-section-skeleton-huya-'), 0);
    expect(_cardCount(tester, 'huya'), columns);
    expect(tester.takeException(), isNull);
  });

  testWidgets('单平台页保持单请求逻辑:limit 不下发,无区块布局', (tester) async {
    final fake = _RecordingBrowseSource();
    final router = await pumpApp(tester, fake);
    router.go('/twitch');
    await pump2(tester);

    final twitchCalls = fake.calls
        .where((call) => call.site == 'twitch')
        .toList();
    // /all 首屏区块也会按列数拉 twitch；单平台页自己的请求是**不带 limit**
    // 的那一次（旧路径口径不变）。
    final single = twitchCalls.where((call) => call.limit == null).toList();
    expect(single, hasLength(1), reason: '单平台页仍是单次 fetchRooms');
    expect(single.single.page, 1);
    // 无区块头/骨架,房间网格照常。
    expect(find.byKey(const Key('home-section-header-twitch')), findsNothing);
    expect(
      anchorKeysWithPrefix(tester, 'room-card-twitch-'),
      isNotEmpty,
      reason: '单平台页房间网格应照常渲染',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('点「更多」:该平台按 loadMore 语义追加下一页(page+1、limit 不变)', (tester) async {
    final fake = _RecordingBrowseSource()..hasMoreFirstPage = true;
    await pumpApp(tester, fake);
    await pump2(tester);

    final columns = AppRoomGrid.columnsFor(1600);
    expect(_cardCount(tester, 'douyu'), columns, reason: '首屏 = 列数条');

    final more = find.byKey(const Key('home-section-more-douyu'));
    expect(more, findsOneWidget, reason: 'hasMore 时应有「更多」入口');
    await tester.tap(more);
    await pump2(tester);

    expect(_cardCount(tester, 'douyu'), columns * 2, reason: '追加一页后翻倍');
    final second = fake.calls
        .where((call) => call.site == 'douyu' && call.page == 2)
        .single;
    expect(second.limit, columns, reason: '下一页沿用列数 limit');
    expect(tester.takeException(), isNull);
  });

  testWidgets('区块头可点进该平台首页 /{site}', (tester) async {
    final fake = _RecordingBrowseSource();
    final router = await pumpApp(tester, fake);
    await pump2(tester);

    final header = find.byKey(const Key('home-section-header-twitch'));
    // twitch 区块在列表后段：先滚到它（懒建区块在滚动中挂载）。
    await tester.dragUntilVisible(
      header,
      find.byKey(const Key('home-sections-list')),
      const Offset(0, -300),
    );
    await pump2(tester);
    expect(header, findsOneWidget);
    await tester.tap(header);
    await pump2(tester);
    expect(router.routeInformationProvider.value.uri.path, '/twitch');
    expect(tester.takeException(), isNull);
  });

  testWidgets('F5/刷新动作重置所有平台区块(每个导航平台都重新拉取)', (tester) async {
    final fake = _RecordingBrowseSource();
    await pumpApp(tester, fake);
    await pump2(tester);

    final before = fake.calls.length;
    expect(before, greaterThan(0));
    GlobalActions.call(GlobalActionNames.refreshHome);
    await pump2(tester);

    final refreshed = fake.calls.skip(before).map((call) => call.site).toSet();
    expect(
      refreshed,
      unorderedEquals(_sectionSites()),
      reason: '刷新应重置全部平台区块(含未滚入视口的)',
    );
    expect(
      fake.calls.skip(before).every((call) => call.page == 1),
      isTrue,
      reason: '刷新回到第一页',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('区块网格盒高==内容高:卡片不被裁切,盒底不留空段', (tester) async {
    final fake = _RecordingBrowseSource();
    await pumpApp(tester, fake);
    await pump2(tester);

    final gridBox = tester.getRect(
      find.byKey(const Key('home-section-grid-douyu')),
    );
    final cards = find.byWidgetPredicate(
      (widget) =>
          widget.key is ValueKey<String> &&
          (widget.key as ValueKey<String>).value.startsWith('room-card-douyu-'),
    );
    expect(tester.widgetList(cards).length, greaterThan(0));
    var maxBottom = 0.0;
    for (final widget in tester.widgetList(cards)) {
      final bottom = tester.getRect(find.byWidget(widget)).bottom;
      if (bottom > maxBottom) maxBottom = bottom;
    }
    // 不裁切:最后一行卡片底 <= 盒底。
    expect(maxBottom, lessThanOrEqualTo(gridBox.bottom + 0.01));
    // 不留空段:盒底到卡片底只差网格自身 padding(AppSpacing.lg)。
    expect(
      gridBox.bottom - maxBottom,
      lessThanOrEqualTo(AppSpacing.lg + 0.01),
      reason: '区块网格盒高必须与 RoomGrid 内容高一致(镜像其布局公式)',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('视口变宽/变窄 → 列数变化 → 按新 limit 重新拉取', (tester) async {
    final fake = _RecordingBrowseSource();
    await pumpApp(tester, fake, width: 1600, height: 1200);
    await pump2(tester);

    final wideColumns = AppRoomGrid.columnsFor(1600);
    expect(fake.calls.where((call) => call.limit == wideColumns), isNotEmpty);

    // 1600 → 800:列数 6 → 4,按新 limit 重新拉取。
    tester.view.physicalSize = const Size(800, 1200);
    await pump2(tester);

    final narrowColumns = AppRoomGrid.columnsFor(800);
    expect(narrowColumns, lessThan(wideColumns));
    expect(
      fake.calls.any(
        (call) =>
            call.site != 'all' && call.page == 1 && call.limit == narrowColumns,
      ),
      isTrue,
      reason: '列数变化后应按新 limit 重新请求首屏',
    );
    expect(tester.takeException(), isNull);
  });
}
