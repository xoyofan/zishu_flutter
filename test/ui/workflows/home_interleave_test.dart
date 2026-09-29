/// 全平台首页(`/all`)回归:交错混排网格 + 骨架 + 每平台请求量按首屏容量。
///
/// 用户口径(2026-09-25):`/all` 要**一张交错混排网格**(不是按平台分区),
/// 加载中显示与真实卡等大的骨架;每平台首屏请求条数由「当前列数 × 首屏行数」
/// 算出并作为聚合查询 limit 下发,避免每个平台固定 30 条。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_parser/live_parser.dart';
import 'package:zishu_flutter/src/features/browse/views/home_view.dart';
import 'package:zishu_flutter/src/shared/application/browse_source.dart';
import 'package:zishu_flutter/src/shared/application/providers.dart';

/// 记录调用参数的假数据源。
class _RecordingBrowseSource implements BrowseSource {
  _RecordingBrowseSource(this.rooms);

  final List<RoomRecord> rooms;
  final List<({String site, int? limit, int page})> calls = [];

  @override
  Future<CategoryResult> fetchCategories(String site) async =>
      CategoryResult(site: site, groups: const []);

  @override
  Future<RoomListResult> fetchRooms({
    required String site,
    String? cid,
    int page = 1,
    int? limit,
  }) async {
    calls.add((site: site, limit: limit, page: page));
    return RoomListResult(rooms: rooms, page: page, hasMore: false);
  }
}

RoomRecord _room(String site, String id) => RoomRecord(
  site: site,
  roomId: id,
  roomState: RoomState.live,
  title: '房间 $id',
  anchorName: '主播 $id',
  cover: 'https://example.test/$id.jpg',
);

void main() {
  // HomeView 用静态缓存做 stale-while-revalidate,跨用例会泄漏。
  setUp(debugResetHomeVisibleRooms);


  testWidgets('/all 首页:只发一次聚合请求,limit=首屏容量(列数×行数)', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final source = _RecordingBrowseSource([
      _room('douyu', '1'),
      _room('huya', '2'),
    ]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [browseSourceProvider.overrideWithValue(source)],
        child: const MaterialApp(home: Scaffold(body: HomeView(site: 'all'))),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(source.calls, hasLength(1), reason: '全平台首页只发一次聚合请求');
    final limit = source.calls.single.limit;
    expect(limit, isNotNull, reason: '首页必须下发首屏容量');
    // 1600 视口 → 6 列;900 高 → 至少 1 行;容量应为列数的整数倍且 ≥ 列数。
    expect(limit! % 6, 0);
    expect(limit, greaterThanOrEqualTo(6));
  });

  testWidgets('可用宽度决定刷新条数:视口变窄 → 列数变少 → limit 变小', (tester) async {
    // 1600(6 列)与 900(4 列)两个视口,断言容量随列数/行数变化,
    // 且各自是列数的整数倍(整行拉取,不拉半行)。
    // 注意:改 physicalSize 会让旧树按新尺寸重建,必须先断言完旧 source
    // 并用空壳排空旧树,再挂新视口的 HomeView,否则旧 source 出现第二次
    // 调用、single 断言误炸。
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final source1600 = _RecordingBrowseSource([_room('douyin', '1')]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [browseSourceProvider.overrideWithValue(source1600)],
        child: const MaterialApp(home: Scaffold(body: HomeView(site: 'douyin'))),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final limit1600 = source1600.calls.single.limit;
    expect(limit1600, isNotNull);
    expect(limit1600! % 6, 0, reason: '1600 视口 → 6 列,整行拉取');

    // 排空旧树(此时旧 source 被新尺寸多打一次,已无所谓),再挂 900 视口。
    tester.view.physicalSize = const Size(900, 900);
    await tester.pumpWidget(const SizedBox.shrink());
    final source900 = _RecordingBrowseSource([_room('douyin', '1')]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [browseSourceProvider.overrideWithValue(source900)],
        child: const MaterialApp(home: Scaffold(body: HomeView(site: 'douyin'))),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final limit900 = source900.calls.single.limit;
    expect(limit900, isNotNull);
    expect(limit900! % 4, 0, reason: '900 视口 → 4 列,整行拉取');

    expect(limit900, isNot(equals(limit1600)),
        reason: '可用宽度不同(列数 6 vs 4),一次刷新条数必须不同');
    expect(limit900 < limit1600, isTrue, reason: '更窄的视口刷新条数应更少');
  });

  testWidgets('/all 首屏加载中:显示与真实卡等大的骨架卡(数量=首屏容量)', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final completer = Completer<RoomListResult>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          browseSourceProvider.overrideWithValue(
            _SlowBrowseSource(completer),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: HomeView(site: 'all'))),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.byKey(const Key('home-skeleton-grid')),
      findsOneWidget,
      reason: '加载中必须显示骨架网格而不是空白',
    );
    expect(
      find.byKey(const Key('home-skeleton-0')),
      findsOneWidget,
      reason: '骨架卡与真实卡同尺寸占位',
    );

    completer.complete(
      RoomListResult(rooms: [_room('douyu', '1')], page: 1, hasMore: false),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      find.byKey(const Key('home-skeleton-grid')),
      findsNothing,
      reason: '数据到达后骨架必须被真实卡片替换',
    );
  });

  testWidgets('单平台首页:limit=首屏容量(列数×行数,按可用宽度决定刷新条数)', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final source = _RecordingBrowseSource([_room('huya', '2')]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [browseSourceProvider.overrideWithValue(source)],
        child: const MaterialApp(home: Scaffold(body: HomeView(site: 'huya'))),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(source.calls, hasLength(1));
    final limit = source.calls.single.limit;
    expect(limit, isNotNull, reason: '单平台首页同样按视口容量下发刷新条数');
    // 1600 视口 → 6 列;容量为列数整数倍且 ≥ 列数。
    expect(limit! % 6, 0);
    expect(limit, greaterThanOrEqualTo(6));
  });
}

/// 让首屏请求挂起的假源,用于观察骨架态。
class _SlowBrowseSource implements BrowseSource {
  _SlowBrowseSource(this._completer);

  final Completer<RoomListResult> _completer;

  @override
  Future<CategoryResult> fetchCategories(String site) async =>
      CategoryResult(site: site, groups: const []);

  @override
  Future<RoomListResult> fetchRooms({
    required String site,
    String? cid,
    int page = 1,
    int? limit,
  }) => _completer.future;
}
