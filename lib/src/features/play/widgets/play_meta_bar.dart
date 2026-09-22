/// 移动端播放页「直播信息条」:窄屏(<768)视频正下方的紧凑主播/数据条。
///
/// 对齐参考实现 `SFVideoLive/apps/web/src/components/play/play-side/SideHeader.vue`
/// 在移动竖屏堆叠布局(`styles/play-layout.css` 的 `.play-layout--stack`)下的呈现,
/// 也即 `docs/ui-parity/visual-confirm.md`「新增 B. 直播信息条(mobile play meta bar)」:
/// 34px 圆形头像 + 昵称 + 4 项统计(关注 / 开播 / 人气 / 弹幕,每项图标 + 数值,
/// 2 行 × 2 列)+ 右贴边竖排「关注 / 超关」按钮(列宽 72,关注红、超关紫)。
///
/// 归属:桌面(>=768)仍用 [PlaySidePanel] 的完整信息头(54px 头像 + 角标按钮),
/// 本组件只在窄屏由侧栏以 compact 形态渲染 —— 信息条与侧栏信息头共用同一份
/// 关注状态与切换回调,不重复实现关注语义。
///
/// **数据诚实性**:统计格取自与桌面侧栏信息头**同一份**数据源 ——
/// [followProvider] 中当前房间关注条目的 [RoomSummary](`followers`/`online`
/// 由 `FollowController.refreshStatuses` 按各站真源回填,commit 6d920cf)。
/// 未关注、或解析层没给的项一律显示「—」,不伪造;纯复用已回填的关注快照,
/// 不另发网络请求。开播时间取 [RoomPayload].`startedAt`(斗鱼等平台真实返回);
/// 弹幕总数上游无字段,恒为「—」(会话内已收条数不是平台弹幕总数,不冒充)。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_parser/live_parser.dart' show RoomPayload, RoomSummary;

import '../../../shared/presentation/design_tokens.dart';
import '../../../shared/presentation/zishu_tokens.dart';
import '../../follow/application/follow_provider.dart';
import '../application/room_stats_provider.dart';

class PlayMetaBar extends ConsumerWidget {
  const PlayMetaBar({
    super.key,
    required this.payload,
    required this.followed,
    required this.superFollowed,
    required this.onToggleFollow,
    required this.onToggleSuperFollow,
  });

  /// 当前房间解析结果;为 null 时全部字段按「—」占位。
  final RoomPayload? payload;

  final bool followed;
  final bool superFollowed;
  final VoidCallback onToggleFollow;
  final VoidCallback onToggleSuperFollow;

  /// 头像尺寸(web 竖屏堆叠:head 44 + 2×pad-y ≈ 52,左侧贴边出血,
  /// 圆角 `0 0 2px 0`)。
  static const double _kAvatarSize = 52;

  /// 「关注 / 超关」按钮列宽(web `3.7rem` ≈ 59px)。
  static const double _kActionsWidth = 59;

  /// 统计格图标尺寸。
  static const double _kStatIconSize = 12;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final payload = this.payload;
    final anchor = payload?.anchorName.trim().isNotEmpty == true
        ? payload!.anchorName.trim()
        : '主播信息';
    final isLive = payload?.isLive ?? false;
    // 统计区数据源(用户口径 2026-09-20 huya 等平台统计不能只服务已关注
    // 房间):已关注房间取关注条目的 [RoomSummary](refreshStatuses 按真源
    // 回填);未关注/未回填时兜底调 [roomStatsProvider](同一条解析真源,
    // 对任意房间可查)。上游未提供的字段仍显示「—」,不伪造。
    final site = payload?.site ?? '';
    final roomId = payload?.roomId ?? '';
    final matched = ref
        .watch(followProvider)
        .where((entry) => entry.key == '$site:$roomId');
    final RoomSummary? followedSummary = matched.isNotEmpty
        ? matched.first.room
        : null;
    final RoomSummary? summary =
        followedSummary ??
        ref.watch(roomStatsProvider((site: site, roomId: roomId))).value;
    final followersText = _statText(summary?.followers);
    final audienceText = _statText(summary?.online);
    // 高度由内容撑开(web 竖屏堆叠基准 head-h 2.75rem ≈ 44,但 flutter 字体
    // metrics 实测装不下三行文字,固定高会溢出 2-6px;IntrinsicHeight 让头像
    // 与按钮列 stretch 到内容自然高,任何字体缩放档都不溢出)。
    return Container(
      key: const Key('play-meta-bar'),
      // 头像左侧贴边出血(web 负 margin),无左 padding。
      padding: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _MetaAvatar(
              avatar: payload?.avatar.trim() ?? '',
              // 无头像时用昵称首字兜底(与侧栏信息头同语义)。
              label: anchor,
              live: isLive,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    anchor,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppFontSize.body,
                      height: 1.05,
                      fontWeight: FontWeight.w600,
                      color: isLive ? tokens.liveBadge : tokens.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      _MetaStat(
                        key: const Key('play-meta-stat-followers'),
                        icon: Icons.favorite_border_rounded,
                        iconColor: context.tokens.playFollowText,
                        label: '关注',
                        // 关注条目快照的 followers(关注/人气同源回填)。
                        value: followersText,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      _MetaStat(
                        key: const Key('play-meta-stat-started'),
                        icon: Icons.schedule_rounded,
                        iconColor: isLive
                            ? tokens.liveBadge
                            : tokens.textSecondary,
                        label: '开播',
                        value: _startedText(isLive),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      _MetaStat(
                        key: const Key('play-meta-stat-audience'),
                        icon: Icons.people_alt_outlined,
                        iconColor: context.tokens.statAudience,
                        label: '人气',
                        // 关注条目快照的 online(在线人数文案,回填自真源)。
                        value: audienceText,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      _MetaStat(
                        key: const Key('play-meta-stat-danmaku'),
                        icon: Icons.chat_bubble_outline_rounded,
                        iconColor: tokens.textSecondary,
                        label: '弹幕',
                        // 解析层暂无弹幕数(会话内已收条数不是平台弹幕总数,不冒充)。
                        value: '—',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            SizedBox(
              width: _kActionsWidth,
              child: _MetaActions(
                followed: followed,
                superFollowed: superFollowed,
                onToggleFollow: onToggleFollow,
                onToggleSuperFollow: onToggleSuperFollow,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 开播时间文案:`MM-DD HH:mm`(参考实现 `formatLastLiveAt` 同格式)。
  ///
  /// 拿不到开播时间时,在播显示「开播中」、离线显示「—」——与侧栏信息头一致。
  String _startedText(bool isLive) {
    final startedAt = payload?.startedAt;
    if (startedAt == null) return isLive ? '开播中' : '—';
    final local = startedAt.toLocal();
    String pad(int value) => value.toString().padLeft(2, '0');
    return '${pad(local.month)}-${pad(local.day)} '
        '${pad(local.hour)}:${pad(local.minute)}';
  }
}

/// 统计文本:空串(未关注/上游未提供)显示「—」占位,不伪造。
///
/// (与 play_side_panel.dart 的 `_statText` 同语义;该文件由桌面信息头维护,
/// 私有函数跨文件不可复用,故在此等价实现。)
String _statText(String? value) {
  final text = value?.trim() ?? '';
  return text.isEmpty ? '—' : text;
}

/// 圆形头像:无图时以昵称首字兜底(品牌色底 + 主文字色)。
class _MetaAvatar extends StatelessWidget {
  const _MetaAvatar({
    required this.avatar,
    required this.label,
    required this.live,
  });

  final String avatar;
  final String label;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final fallback = label.isEmpty ? '?' : label.substring(0, 1);
    return Container(
      width: PlayMetaBar._kAvatarSize,
      height: double.infinity,
      // 左贴边出血 + 圆角 `0 0 2px 0`(web SideHeader.vue:326-350)。
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.only(bottomRight: Radius.circular(2)),
        color: tokens.surfaceRaised,
        border: Border.all(
          color: live ? tokens.liveBadge : tokens.border,
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: avatar.isEmpty
          ? Center(
              child: Text(
                fallback,
                style: TextStyle(
                  fontSize: AppFontSize.subtitle,
                  fontWeight: FontWeight.w700,
                  color: live ? tokens.liveBadge : tokens.textSecondary,
                ),
              ),
            )
          : Image.network(
              avatar,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Center(
                child: Text(
                  fallback,
                  style: TextStyle(
                    fontSize: AppFontSize.subtitle,
                    fontWeight: FontWeight.w700,
                    color: live ? tokens.liveBadge : tokens.textSecondary,
                  ),
                ),
              ),
            ),
    );
  }
}

/// 单个统计格:图标 + 「标签 值」。标签用次级色、值用主文字色。
class _MetaStat extends StatelessWidget {
  const _MetaStat({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: PlayMetaBar._kStatIconSize, color: iconColor),
        const SizedBox(width: 3),
        Flexible(
          child: Text(
            '$label $value',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: AppFontSize.caption,
              height: 1.05,
              color: tokens.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

/// 右贴边竖排「关注 / 超关」。
///
/// 与侧栏 `_SideActionButton` 同语义、同 token(该类为 play_side_panel.dart 的
/// 私有类,跨文件不可复用,故在此实现等价样式);锚点沿用既有测试契约
/// `play-side-follow-btn` / `play-side-super-follow` —— 同一时刻只有一处渲染
/// (窄屏走本组件,桌面走侧栏信息头),不会出现重复锚点。
class _MetaActions extends StatelessWidget {
  const _MetaActions({
    required this.followed,
    required this.superFollowed,
    required this.onToggleFollow,
    required this.onToggleSuperFollow,
  });

  final bool followed;
  final bool superFollowed;
  final VoidCallback onToggleFollow;
  final VoidCallback onToggleSuperFollow;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(
          child: _MetaActionButton(
            key: const Key('play-side-follow-btn'),
            icon: followed
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            label: followed ? '已关注' : '关注',
            selected: followed,
            colors: _MetaChipColors(
              background: tokens.playFollowBg,
              hoverBackground: tokens.playFollowBgHover,
              activeBackground: tokens.playFollowBgActive,
              border: tokens.playFollowBorder,
              foreground: tokens.playFollowText,
              activeForeground: tokens.playFollowTextActive,
            ),
            onPressed: onToggleFollow,
          ),
        ),
        const SizedBox(height: 2),
        Expanded(
          child: _MetaActionButton(
            key: const Key('play-side-super-follow'),
            icon: superFollowed
                ? Icons.star_rounded
                : Icons.star_border_rounded,
            label: superFollowed ? '已超关' : '超关',
            selected: superFollowed,
            colors: _MetaChipColors(
              background: tokens.playSuperBg,
              hoverBackground: tokens.playSuperBgHover,
              activeBackground: tokens.playSuperBgActive,
              border: tokens.playSuperBorder,
              foreground: tokens.playSuperText,
              activeForeground: tokens.playSuperTextActive,
            ),
            onPressed: onToggleSuperFollow,
          ),
        ),
      ],
    );
  }
}

/// 关注 / 超关 chip 的状态配色族(与桌面侧栏 `_ActionChipColors` 同口径:
/// 红系 `playFollow*` / 紫系 `playSuper*`,六值全部来自 `context.tokens`)。
class _MetaChipColors {
  const _MetaChipColors({
    required this.background,
    required this.hoverBackground,
    required this.activeBackground,
    required this.border,
    required this.foreground,
    required this.activeForeground,
  });

  final Color background;

  /// hover 底:token `playFollowBgHover` / `playSuperBgHover`(**零引用死 token 的接线点**)。
  final Color hoverBackground;

  /// 已关注底 / 按下底。
  final Color activeBackground;

  final Color border;
  final Color foreground;

  /// 已关注 / 按下时的文字与图标。
  final Color activeForeground;
}

/// 「关注 / 超关」chip(窄屏信息条版):与桌面侧栏 `_SideActionButton` 同构 ——
/// rest / hover / pressed 由 `AnimatedContainer`(AppMotion.fast + curve)着色,
/// focus 用 `AppFocus.ring` 外扩,hover/pressed 叠 `AppElevation.accentGlow`;
/// 一律不改尺寸与位置(DESIGN.md §7)。
class _MetaActionButton extends StatefulWidget {
  const _MetaActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.colors,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final _MetaChipColors colors;
  final VoidCallback onPressed;

  @override
  State<_MetaActionButton> createState() => _MetaActionButtonState();
}

class _MetaActionButtonState extends State<_MetaActionButton> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = widget.colors;
    final active = widget.selected || _pressed;
    final background = active
        ? colors.activeBackground
        : (_hovered ? colors.hoverBackground : colors.background);
    final foreground = active ? colors.activeForeground : colors.foreground;
    final glow = _focused
        ? AppFocus.ring(tokens.accent)
        : (_hovered || _pressed
              ? AppElevation.accentGlow(colors.border)
              : null);
    return Tooltip(
      message: widget.label,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.curve,
        decoration: BoxDecoration(
          color: background,
          borderRadius: AppRadius.allPill,
          border: Border.all(color: colors.border),
          boxShadow: glow,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: AppRadius.allPill,
            onTap: widget.onPressed,
            onHover: (value) => setState(() => _hovered = value),
            onFocusChange: (value) => setState(() => _focused = value),
            onTapDown: (_) => setState(() => _pressed = true),
            onTapUp: (_) => setState(() => _pressed = false),
            onTapCancel: () => setState(() => _pressed = false),
            // 覆盖色从 chip 自身文字色推导(状态色由基色推导),不引入外来色相。
            splashColor: AppStateLayer.splashOf(colors.activeForeground),
            highlightColor: AppStateLayer.pressedOf(colors.activeForeground),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(widget.icon, size: 12, color: foreground),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppFontSize.caption,
                        height: 1.1,
                        fontWeight: FontWeight.w600,
                        color: foreground,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
