/// 关注排序/筛选单一来源单测(纯 Dart,无 Flutter 运行时依赖)。
///
/// 覆盖用户口径(2026-09-19)「超关 关注 轮播 没直播的顺序排」:
/// 1. **四档**:超关在播 0 / 普通在播 1 / 轮播 2 / 离线 3 —— 超关只在
///    在播段置顶(用户在意的是人,但「在意」的排序权不越过直播状态);
///    轮播(replay)排在全部在播之后、离线之前,且不分超关;
/// 2. 档内按关注时间倒序;
/// 3. 「最近关注」排序不受超关/开播/轮播影响;
/// 4. 播放页侧栏只显在播(轮播/离线归「我的关注」页),两页共用同一
///    followSortRank。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:live_parser/live_parser.dart' show RoomState, RoomSummary;
import 'package:zishu_flutter/src/features/follow/application/follow_provider.dart';
import 'package:zishu_flutter/src/features/follow/application/follow_sort.dart';

/// 构造一条关注:只关心 site / 状态(live/replay/offline)/ 超关 / 关注时间。
///
/// [followedDaysAgo] 越大表示关注得越早(时间越旧),便于校验档内倒序。
FollowEntry _entry({
  String roomId = '1',
  String site = 'douyu',
  bool live = true,
  bool replay = false,
  bool special = false,
  int followedDaysAgo = 1,
}) {
  return FollowEntry(
    room: RoomSummary(
      site: site,
      roomId: roomId,
      title: '房间 $roomId',
      anchorName: '主播 $roomId',
      cid: 'c-$roomId',
      category: '分类',
      // fixture 约定:online 为空即未开播;轮播同样空串、靠 roomState 区分。
      online: live ? '1.2万' : '',
      cover: '',
      roomState: live
          ? RoomState.live
          : (replay ? RoomState.replay : RoomState.offline),
    ),
    isSpecial: special,
    remindOn: false,
    followedAt: DateTime(2026, 1, 1).subtract(Duration(days: followedDaysAgo)),
  );
}

List<String> _ids(List<FollowEntry> items) =>
    [for (final entry in items) entry.room.roomId];

void main() {
  group('followSortRank', () {
    test('超关在播 → 0', () {
      expect(followSortRank(_entry(special: true)), 0);
    });

    test('在播但非超关 → 1', () {
      expect(followSortRank(_entry(live: true)), 1);
    });

    test('轮播 → 2(不分超关)', () {
      expect(followSortRank(_entry(live: false, replay: true)), 2);
      expect(followSortRank(_entry(live: false, replay: true, special: true)), 2,
          reason: '轮播档不享超关置顶');
    });

    test('未开播且非超关 → 3', () {
      expect(followSortRank(_entry(live: false)), 3);
    });

    test('超关且未开播 → 3(超关只在在播段置顶)', () {
      expect(followSortRank(_entry(live: false, special: true)), 3);
    });
  });

  group('sortFollowEntries / liveFirst', () {
    test('四档顺序:超关在播 → 在播 → 轮播 → 离线,档内按关注时间倒序', () {
      final items = [
        _entry(roomId: 'r1', live: false, replay: true, followedDaysAgo: 1), // 档2
        _entry(roomId: 'n1', followedDaysAgo: 1), // 档1,较新
        _entry(roomId: 'x1', live: false, followedDaysAgo: 2), // 档3
        _entry(roomId: 's1', special: true, followedDaysAgo: 5), // 档0
        _entry(roomId: 'n2', followedDaysAgo: 3), // 档1,较旧
        _entry(
          roomId: 'r2',
          live: false,
          replay: true,
          special: true,
          followedDaysAgo: 30,
        ), // 档2:超关轮播不置顶
      ];
      sortFollowEntries(items, FollowSort.liveFirst);
      // 档0:[s1] → 档1:[n1(1天), n2(3天)] → 档2:[r1(1天), r2(30天)]
      // → 档3:[x1]
      expect(_ids(items), ['s1', 'n1', 'n2', 'r1', 'r2', 'x1']);
    });

    test('全未开播:超关不再置顶,按关注时间倒序', () {
      final items = [
        _entry(roomId: 'a', live: false, followedDaysAgo: 1),
        _entry(roomId: 'b', live: false, special: true, followedDaysAgo: 9),
        _entry(roomId: 'c', live: false, followedDaysAgo: 4),
      ];
      sortFollowEntries(items, FollowSort.liveFirst);
      expect(_ids(items), ['a', 'c', 'b']);
    });

    test('空列表不抛异常', () {
      final items = <FollowEntry>[];
      sortFollowEntries(items, FollowSort.liveFirst);
      expect(items, isEmpty);
    });
  });

  group('sortFollowEntries / recentlyFollowed', () {
    test('纯按关注时间倒序,超关与开播状态都不参与', () {
      final items = [
        _entry(roomId: 'n1', followedDaysAgo: 1),
        _entry(roomId: 'x1', live: false, followedDaysAgo: 2),
        _entry(roomId: 'n2', followedDaysAgo: 3),
        _entry(roomId: 's1', special: true, followedDaysAgo: 5),
        _entry(roomId: 'x2', live: false, special: true, followedDaysAgo: 30),
      ];
      sortFollowEntries(items, FollowSort.recentlyFollowed);
      expect(_ids(items), ['n1', 'x1', 'n2', 's1', 'x2']);
    });
  });

  group('playSidebarFollowEntries / isPlayFollowVisible', () {
    test('侧栏只显在播:轮播与离线(含超关)都过滤掉', () {
      final entries = [
        _entry(roomId: 's1', special: true, followedDaysAgo: 5),
        _entry(roomId: 'n1', followedDaysAgo: 1),
        _entry(roomId: 'r1', live: false, replay: true, followedDaysAgo: 2),
        _entry(roomId: 'x1', live: false, followedDaysAgo: 3),
        _entry(roomId: 'x2', live: false, special: true, followedDaysAgo: 30),
      ];
      // 用户口径 2026-09-19:侧栏只显示直播的,轮播归「我的关注」页。
      expect(_ids(playSidebarFollowEntries(entries)), ['s1', 'n1']);
      expect(isPlayFollowVisible(_entry(live: false, replay: true)), isFalse);
      expect(isPlayFollowVisible(_entry(live: false)), isFalse);
    });

    test('「我的关注」页(默认不过滤)保留轮播,且排在在播之后、离线之前', () {
      final entries = [
        _entry(roomId: 'x1', live: false, followedDaysAgo: 2),
        _entry(roomId: 'r1', live: false, replay: true, followedDaysAgo: 1),
        _entry(roomId: 'n1', followedDaysAgo: 1),
      ];
      expect(_ids(visibleFollowEntries(entries)), ['n1', 'r1', 'x1']);
    });
  });

  group('visibleFollowEntries', () {
    test('liveOnly 过滤掉未开播与轮播(播放页侧栏口径)', () {
      final entries = [
        _entry(roomId: 's1', special: true, followedDaysAgo: 5),
        _entry(roomId: 'n1', followedDaysAgo: 1),
        _entry(roomId: 'r1', live: false, replay: true, followedDaysAgo: 2),
        _entry(roomId: 'x1', live: false, followedDaysAgo: 3),
        _entry(roomId: 'x2', live: false, special: true, followedDaysAgo: 30),
      ];
      final visible = visibleFollowEntries(entries, liveOnly: true);
      expect(_ids(visible), ['s1', 'n1']);
    });

    test('默认不过滤(关注页口径)', () {
      final entries = [
        _entry(roomId: 'n1', followedDaysAgo: 1),
        _entry(roomId: 'x1', live: false, followedDaysAgo: 2),
      ];
      expect(_ids(visibleFollowEntries(entries)), ['n1', 'x1']);
    });

    test('平台筛选与 liveOnly 同时生效', () {
      final entries = [
        _entry(roomId: 'dy1', site: 'douyu'),
        _entry(roomId: 'b1', site: 'bilibili'),
        _entry(roomId: 'b2', site: 'bilibili', live: false),
      ];
      expect(
        _ids(visibleFollowEntries(entries, site: 'bilibili')),
        ['b1', 'b2'],
      );
      expect(
        _ids(visibleFollowEntries(entries, site: 'bilibili', liveOnly: true)),
        ['b1'],
      );
      expect(_ids(visibleFollowEntries(entries, site: 'huya')), isEmpty);
    });

    test('返回新列表,不修改入参顺序', () {
      final entries = [
        _entry(roomId: 'z', followedDaysAgo: 9),
        _entry(roomId: 'a', special: true, followedDaysAgo: 1),
      ];
      final before = _ids(entries);
      final visible = visibleFollowEntries(entries);
      expect(_ids(entries), before, reason: '排序应作用于副本');
      expect(visible, isNot(same(entries)));
      expect(_ids(visible), ['a', 'z']);
    });
  });
}
