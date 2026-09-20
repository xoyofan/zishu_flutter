# -*- coding: utf-8 -*-
"""播放页统计兜底 + 提醒/跳转文字化(用户口径 2026-09-20)。"""
import io


def patch(path, pairs):
    s = io.open(path, encoding="utf-8").read()
    for old, new in pairs:
        n = s.count(old)
        assert n == 1, (path, repr(old[:60]), "count=", n)
        s = s.replace(old, new)
    io.open(path, "w", encoding="utf-8", newline="").write(s)
    print("ok", path)


# ── 1. 新建房间统计兜底 provider ──
provider = '''import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_parser/live_parser.dart' show RoomSummary;

import '../../../shared/application/providers.dart' show roomRefresherProvider;

/// 播放页当前房间的统计兜底(用户口径 2026-09-20:huya 等平台的关注/VIP
/// 统计不能只服务已关注房间)。
///
/// 对任意房间直接调解析侧 `RoomSummaryRefresher.refreshRoom` —— 与关注行
/// 刷新同一条真源链(huya profileRoom / douyu getAnchorNewCard 等),不需要
/// 关注状态。已关注房间优先消费关注条目的 summary(关注链路维护、带离线
/// 跃迁记账),本 provider 只在条目缺失/未回填时兜底。
///
/// 单房间 10s 超时;失败返回 null(展示「—」,数据诚实性:不伪造)。
final roomStatsProvider = FutureProvider.autoDispose
    .family<RoomSummary?, ({String site, String roomId})>((ref, key) async {
  final refresher = ref.read(roomRefresherProvider);
  if (refresher == null) return null;
  try {
    return await refresher
        .refreshRoom(site: key.site, roomId: key.roomId)
        .timeout(const Duration(seconds: 10));
  } catch (_) {
    return null;
  }
});
'''
io.open(
    "lib/src/features/play/application/room_stats_provider.dart",
    "w",
    encoding="utf-8",
    newline="",
).write(provider)
print("ok room_stats_provider.dart")

# ── 2. 主播卡(play_meta_bar):关注条目缺失时用统计兜底 ──
patch("lib/src/features/play/widgets/play_meta_bar.dart", [
    ("""    // 统计区数据源:与桌面侧栏信息头同源 —— followProvider 中当前房间关注
    // 条目的 [RoomSummary](followers/online 由 refreshStatuses 按真源回填)。
    // 未关注/上游未提供的字段显示「—」,不伪造、不发起新的网络请求。
    final site = payload?.site ?? '';
    final roomId = payload?.roomId ?? '';
    final matched = ref
        .watch(followProvider)
        .where((entry) => entry.key == '$site:$roomId');
    final RoomSummary? summary = matched.isNotEmpty ? matched.first.room : null;""",
     """    // 统计区数据源(用户口径 2026-09-20 huya 等平台统计不能只服务已关注
    // 房间):已关注房间取关注条目的 [RoomSummary](refreshStatuses 按真源
    // 回填);未关注/未回填时兜底调 [roomStatsProvider](同一条解析真源,
    // 对任意房间可查)。上游未提供的字段仍显示「—」,不伪造。
    final site = payload?.site ?? '';
    final roomId = payload?.roomId ?? '';
    final matched = ref
        .watch(followProvider)
        .where((entry) => entry.key == '$site:$roomId');
    final RoomSummary? followedSummary =
        matched.isNotEmpty ? matched.first.room : null;
    final RoomSummary? summary = followedSummary ??
        ref
            .watch(
              roomStatsProvider((site: site, roomId: roomId)),
            )
            .value;"""),
])

# play_meta_bar import
s = io.open("lib/src/features/play/widgets/play_meta_bar.dart", encoding="utf-8").read()
old = "import '../../follow/application/follow_provider.dart';"
if s.count(old) == 1:
    s = s.replace(old, old + "\nimport '../application/room_stats_provider.dart';")
else:
    # import 路径不同:相对路径按文件位置推
    old2 = "import '../application/follow_provider.dart';"
    assert s.count(old2) == 1, "follow_provider import not found"
    s = s.replace(old2, old2 + "\nimport '../application/room_stats_provider.dart';")
io.open("lib/src/features/play/widgets/play_meta_bar.dart", "w", encoding="utf-8", newline="").write(s)
print("ok play_meta_bar import")

# ── 3. 侧栏头(_SideHeader):ConsumerWidget + 统计兜底 + 提醒/跳转改文字 ──
patch("lib/src/features/play/widgets/play_side_panel.dart", [
    ("""class _SideHeader extends StatelessWidget {
  const _SideHeader({""",
     """class _SideHeader extends ConsumerWidget {
  const _SideHeader({"""),
    ("""  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final anchor = payload?.anchorName.trim().isNotEmpty == true
        ? payload!.anchorName
        : '主播信息';""",
     """  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final anchor = payload?.anchorName.trim().isNotEmpty == true
        ? payload!.anchorName
        : '主播信息';"""),
    ("""    // 统计区(对齐 web SideHeader「关注：N」行 + stats 列):
    // 未关注/上游未提供 → '—' 占位,不伪造(数据诚实性)。
    final followRoom = this.followRoom;
    final followersText = _formatFollowersText(followRoom?.followers);
    final audienceText = _statText(followRoom?.online);
    final vipText = _statText(followRoom?.vip);""",
     """    // 统计区(对齐 web SideHeader「关注：N」行 + stats 列):已关注房间
    // 取关注条目回填;未关注/未回填时兜底调 roomStatsProvider(同一条解析
    // 真源,任意房间可查 —— 用户口径 2026-09-20 huya 等平台统计不能只服务
    // 已关注房间)。上游未提供 → '—' 占位,不伪造(数据诚实性)。
    final followRoom = this.followRoom;
    final RoomSummary? stats = followRoom ??
        ref
            .watch(
              roomStatsProvider((site: site, roomId: roomId)),
            )
            .value;
    final followersText = _formatFollowersText(stats?.followers);
    final audienceText = _statText(stats?.online);
    final vipText = _statText(stats?.vip);"""),
    # 铃铛/外链两个 icon 圆钮 → 文字 pill
    ("""                    // 开播提醒 + 外链(用户口径 2026-09-20:从头像悬浮挪到
                    // 第二排分类名后,不再遮头像)。
                    const SizedBox(width: 4),
                    _HeaderIconButton(
                      key: const Key('play-side-notify'),
                      size: 16,
                      icon: remindOn
                          ? Icons.notifications_rounded
                          : Icons.notifications_off_rounded,
                      tooltip: followed
                          ? (remindOn ? '已开启开播/下播提醒，点击关闭' : '开启开播/下播提醒')
                          : '关注后可开启开播提醒',
                      onPressed: followed ? onToggleRemind : null,
                      activeColor: remindOn ? tokens.accent : null,
                    ),
                    const SizedBox(width: 3),
                    _HeaderIconButton(
                      key: const Key('play-side-external'),
                      size: 16,
                      icon: Icons.open_in_new_rounded,
                      tooltip: '打开直播间页面',
                      onPressed: externalUrl == null
                          ? null
                          : () => onOpenExternal(externalUrl!),
                      accent: const Color(0xFF60A5FA),
                    ),""",
     """                    // 开播提醒 + 外链(用户口径 2026-09-20:从头像悬浮挪到
                    // 第二排分类名后,不再遮头像;显示改为文字)。
                    const SizedBox(width: 4),
                    _SideTextAction(
                      key: const Key('play-side-notify'),
                      label: remindOn ? '直播提醒中' : '直播提醒',
                      tooltip: followed
                          ? (remindOn ? '已开启开播/下播提醒，点击关闭' : '开启开播/下播提醒')
                          : '关注后可开启开播提醒',
                      onPressed: followed ? onToggleRemind : null,
                      active: remindOn,
                    ),
                    const SizedBox(width: 3),
                    _SideTextAction(
                      key: const Key('play-side-external'),
                      label: '跳转',
                      tooltip: '打开直播间页面',
                      onPressed: externalUrl == null
                          ? null
                          : () => onOpenExternal(externalUrl!),
                    ),"""),
])

# _SideHeader import room_stats_provider + _SideTextAction 组件
p = "lib/src/features/play/widgets/play_side_panel.dart"
s = io.open(p, encoding="utf-8").read()
old_import = "import '../application/follow_provider.dart';"
if s.count(old_import) == 1:
    s = s.replace(old_import, old_import + "\nimport '../application/room_stats_provider.dart';")
else:
    old2 = "import '../../follow/application/follow_provider.dart';"
    assert s.count(old2) == 1, "follow import"
    s = s.replace(old2, old2 + "\nimport '../application/room_stats_provider.dart';")

# 文字按钮组件(挂在 _HeaderIconButton 类后面)
anchor_cls = """class _HeaderIconButton extends StatelessWidget {"""
text_action = """/// 侧栏头第二排的小文字按钮(用户口径 2026-09-20:开播提醒/跳转显示为
/// 文字而非 icon)。描边 pill;[active] 时走品牌紫强调。
class _SideTextAction extends StatelessWidget {
  const _SideTextAction({
    super.key,
    required this.label,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
  });

  final String label;
  final String tooltip;

  /// null = 禁用(未关注无可提醒目标 / 无稳定 web url)。
  final VoidCallback? onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final enabled = onPressed != null;
    final fg = !enabled
        ? tokens.textSecondary.withValues(alpha: 0.55)
        : active
        ? tokens.accent
        : tokens.textSecondary;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active && enabled
            ? tokens.accent.withValues(alpha: 0.14)
            : Colors.transparent,
        shape: StadiumBorder(
          side: BorderSide(
            color: active && enabled
                ? tokens.accent.withValues(alpha: 0.55)
                : tokens.border,
          ),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 9.5,
                height: 1.2,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {"""
assert s.count(anchor_cls) == 1
s = s.replace(anchor_cls, text_action)
io.open(p, "w", encoding="utf-8", newline="").write(s)
print("ok side_panel text action")
print("ALL DONE")
