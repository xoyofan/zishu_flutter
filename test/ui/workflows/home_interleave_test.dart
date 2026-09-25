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

  testWidgets('单平台首页:不下发 limit,保持既有单请求分页行为', (tester) async {
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
    expect(source.calls.single.limit, isNull, reason: '单平台页不改变既有分页行为');
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
