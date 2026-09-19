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

/// 排序档位:**超关在播(0) → 普通在播(1) → 轮播(2) → 离线(3)**。
///
/// 用户口径(2026-09-19):「超关 关注 轮播 没直播的顺序排」—— 在播段里
/// 超关置顶(用户亲手标记的「最在意」),轮播(录播循环,不是实时直播)
/// 排在全部在播之后、离线之前,且不分超关(对齐 web `followSortTier` 的
/// replay=2 档,SFVideoLive `followDisplay.ts:92`);没直播的沉底。
/// 播放页侧栏只显在播([isPlayFollowVisible]),轮播/离线档自然为空 ——
/// 两页共用同一 [followSortRank],顺序口径单一来源。
int followSortRank(FollowEntry entry) {
  if (entry.isLive) return entry.isSpecial ? 0 : 1;
  if (entry.isReplay) return 2;
  return 3;
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

/// 播放页侧栏的可见性口径:**只显示在播**。
///
/// 用户口径(2026-09-19):「侧边栏只显示直播的而已」—— 轮播与离线都
/// 只出现在「我的关注」页(排序共用 [followSortRank] 四档)。这是对 web
/// 真源 `isPlayFollowVisible`(`followDisplay.ts:235`,在播 ∨ 重播 ∨
/// 离线超关)的**有意偏离**:该口径曾在 2026-09-18 对齐落地(离线超关
/// 保留),随后被用户口径覆盖;空态文案同步去掉「离线超关会保留」的半句。
///
/// 与 [visibleFollowEntries] 的 `liveOnly` 目前语义相同,但侧栏仍走
/// [playSidebarFollowEntries] 专用入口:口径再变时只改一处。
bool isPlayFollowVisible(FollowEntry entry) => entry.isLive;

/// 播放页侧栏的关注列表:平台筛选 + 侧栏可见性 + 统一排序。
///
/// 排序走 [sortFollowEntries] 同一档位(超关在播 → 普通在播;只显在播后
/// 轮播/离线档自然为空),保证侧栏与「我的关注」页在播条目的相对顺序一致。
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
/// [liveOnly] 保留给「确实只要在播」的调用点;播放页侧栏走
/// [playSidebarFollowEntries](口径再变时只改那一处)。
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
