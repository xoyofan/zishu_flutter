/// 关注排序/筛选单一来源单测(纯 Dart,无 Flutter 运行时依赖)。
///
/// 覆盖用户口径「按超关、关注、没直播的来排列」:
/// 1. **档位**:超关 0 / 开播 1 / 未开播 2 —— 关键在于**超关即使未开播也置顶**
///    (用户在意的是人,不是这一场直播);
/// 2. 档内按关注时间倒序;
/// 3. 「最近关注」排序不受超关/开播影响;
/// 4. 播放页侧栏的 `liveOnly` 过滤(不展示未开播);
/// 5. 平台筛选,且不修改入参列表。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:live_parser/live_parser.dart' show RoomSummary;
import 'package:zishu_flutter/src/features/follow/application/follow_provider.dart';
import 'package:zishu_flutter/src/features/follow/application/follow_sort.dart';

/// 构造一条关注:只关心 site / 是否开播 / 是否超关 / 关注时间。
///
/// [followedDaysAgo] 越大表示关注得越早(时间越旧),便于校验档内倒序。
FollowEntry _entry({
  String roomId = '1',
  String site = 'douyu',
  bool live = true,
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
      // fixture 约定:online 为空即未开播。
      online: live ? '1.2万' : '',
      cover: '',
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
    test('超关 → 0', () {
      expect(followSortRank(_entry(special: true)), 0);
    });

    test('开播但非超关 → 1', () {
      expect(followSortRank(_entry(live: true)), 1);
    });

    test('未开播且非超关 → 2', () {
      expect(followSortRank(_entry(live: false)), 2);
    });

    test('超关且未开播仍 → 0(超关置顶高于开播状态)', () {
      expect(followSortRank(_entry(live: false, special: true)), 0);
    });
  });

  group('sortFollowEntries / liveFirst', () {
    test('三档顺序:超关 → 开播 → 未开播,档内按关注时间倒序', () {
      final items = [
        _entry(roomId: 'n1', followedDaysAgo: 1), // 档1,较新
        _entry(roomId: 'x1', live: false, followedDaysAgo: 2), // 档2
        _entry(roomId: 's1', special: true, followedDaysAgo: 5), // 档0
        _entry(roomId: 'n2', followedDaysAgo: 3), // 档1,较旧
        _entry(
          roomId: 'x2',
          live: false,
          special: true,
          followedDaysAgo: 30,
        ), // 档0 且未开播 → 仍在最前
      ];
      sortFollowEntries(items, FollowSort.liveFirst);
      // 档0:[s1(5天前), x2(30天前)] → 档1:[n1(1天), n2(3天)] → 档2:[x1]
      expect(_ids(items), ['s1', 'x2', 'n1', 'n2', 'x1']);
    });

    test('全未开播时仍按超关优先、其次关注时间', () {
      final items = [
        _entry(roomId: 'a', live: false, followedDaysAgo: 1),
        _entry(roomId: 'b', live: false, special: true, followedDaysAgo: 9),
        _entry(roomId: 'c', live: false, followedDaysAgo: 4),
      ];
      sortFollowEntries(items, FollowSort.liveFirst);
      expect(_ids(items), ['b', 'a', 'c']);
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

  group('visibleFollowEntries', () {
    test('liveOnly 过滤掉未开播(播放页侧栏口径)', () {
      final entries = [
        _entry(roomId: 's1', special: true, followedDaysAgo: 5),
        _entry(roomId: 'n1', followedDaysAgo: 1),
        _entry(roomId: 'x1', live: false, followedDaysAgo: 2),
        _entry(roomId: 'x2', live: false, special: true, followedDaysAgo: 30),
      ];
      final visible = visibleFollowEntries(entries, liveOnly: true);
      expect(_ids(visible), ['s1', 'n1']);
    });

    test('默认不过滤未开播(关注页口径)', () {
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
