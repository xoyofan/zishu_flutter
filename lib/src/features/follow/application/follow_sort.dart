/// 关注条目的排序与筛选**单一来源**。
///
/// 「我的关注」页(FollowView)与播放页侧栏关注面板(_FollowPanel)共用本文件:
/// 同一份关注列表在两个入口必须呈现同一顺序,否则用户会看到两个不同的世界。
/// UI 层只负责把结果铺开,不各自实现 sort。
library;

import 'follow_provider.dart';

/// 列表排序方式。
enum FollowSort {
  liveFirst('开播优先'),
  recentlyFollowed('最近关注');

  const FollowSort(this.label);

  final String label;
}

/// 排序档位:**超关(0) → 开播(1) → 未开播(2)**。
///
/// 用户口径是「按超关、关注、没直播的排列」:超关是用户亲手标记的「最在意」,
/// 即便当期没开播也置顶 —— 他关心的是人,不是这一场直播。其余按是否开播分档,
/// 未开播沉底。
int followSortRank(FollowEntry entry) {
  if (entry.isSpecial) return 0;
  return entry.isLive ? 1 : 2;
}

/// 按 [sort] 就地排序。
///
/// 两个排序方式都以「关注时间倒序」作为档内次序,与参考实现一致:
/// 同档内新关注的在前。
void sortFollowEntries(List<FollowEntry> items, FollowSort sort) {
  int byFollowedDesc(FollowEntry a, FollowEntry b) =>
      b.followedAt.compareTo(a.followedAt);
  switch (sort) {
    case FollowSort.recentlyFollowed:
      items.sort(byFollowedDesc);
    case FollowSort.liveFirst:
      items.sort((a, b) {
        final rank = followSortRank(a).compareTo(followSortRank(b));
        if (rank != 0) return rank;
        return byFollowedDesc(a, b);
      });
  }
}

/// 播放页侧栏的可见性口径(与 SFVideoLive `isPlayFollowVisible` 同源):
/// **在播显示;离线但超关也显示;其余离线隐藏**。
///
/// 与 [visibleFollowEntries] 的 `liveOnly` 的差别:那个把离线一律丢掉,
/// 于是「关注的主播恰好都没开播」时侧栏整片空白(用户报的「关注没显示」)。
/// 而超关是用户亲手标的「最在意的人」——web 的空态文案也写明了这一点:
/// 离线超关主播会保留在列表里。
bool isPlayFollowVisible(FollowEntry entry) => entry.isLive || entry.isSpecial;

/// 播放页侧栏的关注列表:平台筛选 + 侧栏可见性 + 统一排序。
///
/// 与「我的关注」页([visibleFollowEntries] 不带 `liveOnly`)的差别只在可见性
/// 谓词 —— 排序仍走 [sortFollowEntries] 同一档位(超关 → 开播 → 未开播),
/// 保证两个入口顺序一致。
List<FollowEntry> playSidebarFollowEntries(
  Iterable<FollowEntry> entries, {
  String site = 'all',
}) {
  final filtered = <FollowEntry>[
    for (final entry in entries)
      if ((site == 'all' || entry.room.site == site) &&
          isPlayFollowVisible(entry))
        entry,
  ];
  sortFollowEntries(filtered, FollowSort.liveFirst);
  return filtered;
}

/// 平台筛选 + 排序(+ 可选只保留开播),返回新列表(不修改入参)。
///
/// [liveOnly] 保留给「确实只要在播」的调用点;播放页侧栏**不要**再用它
/// (会把离线超关也丢掉),改用 [playSidebarFollowEntries]。
List<FollowEntry> visibleFollowEntries(
  Iterable<FollowEntry> entries, {
  String site = 'all',
  FollowSort sort = FollowSort.liveFirst,
  bool liveOnly = false,
}) {
  final filtered = <FollowEntry>[
    for (final entry in entries)
      if ((site == 'all' || entry.room.site == site) &&
          (!liveOnly || entry.isLive))
        entry,
  ];
  sortFollowEntries(filtered, sort);
  return filtered;
}
