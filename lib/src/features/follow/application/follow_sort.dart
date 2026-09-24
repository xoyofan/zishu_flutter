/// 关注条目的排序与筛选**单一来源**。
///
/// 「我的关注」页(FollowView)与播放页侧栏关注面板(_FollowPanel)共用本文件:
/// 同一份关注列表在两个入口必须呈现同一顺序,否则用户会看到两个不同的世界。
/// UI 层只负责把结果铺开,不各自实现 sort。
library;

import 'package:live_parser/live_parser.dart' show tryParseOnlineCount;

import 'follow_provider.dart';

/// 列表排序方式。
///
/// 「最近关注」选项已按用户口径(2026-09-22)移除,枚举只剩 [FollowSort.liveFirst];
/// 保留枚举与 [sortFollowEntries] 的参数签名,让「我的关注」页与播放侧栏的
/// 调用点不变,未来若新增档位必须在 sortFollowEntries 显式接线。
enum FollowSort {
  liveFirst('开播优先');

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

/// 单条观看数:**缺失(空串/不可解析)为 null 沉底,合法零是有效值 0**。
///
/// 复用解析核心 `tryParseOnlineCount`(1.2万/3.4千/1,234 同尺),不复制解析规则。
/// 合法零必须与缺失区分:关注记录可从本地原样恢复 `online: "0"`
/// (follow_provider 视非空串为在播),它参与数值序排在所有正数之后、
/// 不可解析/缺失之前(审阅口径 2026-09-24)。
int? _onlineCountOrNull(FollowEntry entry) =>
    tryParseOnlineCount(entry.room.online);

/// 档内次序:观看数倒序(缺失/不可解析沉底) → 平局回退关注时间倒序。
int _byOnlineThenFollowedAtDesc(FollowEntry a, FollowEntry b) {
  final onlineA = _onlineCountOrNull(a);
  final onlineB = _onlineCountOrNull(b);
  if (onlineA == null || onlineB == null) {
    if (onlineA == null && onlineB == null) {
      return b.followedAt.compareTo(a.followedAt);
    }
    return onlineA == null ? 1 : -1;
  }
  if (onlineA != onlineB) return onlineB.compareTo(onlineA);
  return b.followedAt.compareTo(a.followedAt);
}

/// 按 [sort] 就地排序。
///
/// 四档(见 [followSortRank])之后,档内按**观看数从高到低**;
/// 合法零参与数值序,观看数缺失/不可解析排档尾,数值相同或同缺失时
/// 按关注时间倒序(用户口径 2026-09-22,审阅 P2 边界 2026-09-24)。
void sortFollowEntries(List<FollowEntry> items, FollowSort sort) {
  switch (sort) {
    case FollowSort.liveFirst:
      items.sort((a, b) {
        final rank = followSortRank(a).compareTo(followSortRank(b));
        if (rank != 0) return rank;
        return _byOnlineThenFollowedAtDesc(a, b);
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
/// 排序走 [sortFollowEntries] 同一档位(超关在播 → 普通在播,档内观看数
/// 倒序;只显在播后轮播/离线档自然为空),保证侧栏与「我的关注」页在播
/// 条目的相对顺序一致。
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
