part of '../play_side_panel.dart';

/// SFVideo 侧栏信息头:头像 + 主播元信息 + 统计 + 关注操作。
class _SideHeader extends ConsumerWidget {
  const _SideHeader({
    required this.site,
    required this.roomId,
    required this.payload,
    required this.followRoom,
    required this.followed,
    required this.superFollowed,
    required this.remindOn,
    required this.externalUrl,
    required this.onToggleFollow,
    required this.onToggleSuperFollow,
    required this.onToggleRemind,
    required this.onOpenExternal,
  });

  final String site;
  final String roomId;
  final RoomPayload? payload;

  /// 当前房间的关注条目(null = 未关注)。
  ///
  /// 统计区数据源对齐 web `SideHeader.vue` + `useRoomStats.ts`:粉丝/贵宾/
  /// 人气等统计来自关注状态快照(本仓等价物 = 关注条目随
  /// `FollowController.refreshStatuses` 回填的 [RoomSummary]);[RoomPayload]
  /// 不携带统计字段,故未关注(或尚未刷新回填)时该项显示「—」,
  /// 不伪造数据。
  final RoomSummary? followRoom;

  final bool followed;
  final bool superFollowed;

  /// 开播提醒开关(关注条目 remindOn)。未关注时按钮禁用,该值无意义。
  final bool remindOn;

  /// 当前房间 web 页地址(null = 无稳定外链,按钮禁用)。
  final String? externalUrl;
  final VoidCallback onToggleFollow;
  final VoidCallback onToggleSuperFollow;
  final VoidCallback onToggleRemind;
  final ValueChanged<String> onOpenExternal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final anchor = payload?.anchorName.trim().isNotEmpty == true
        ? payload!.anchorName
        : '主播信息';
    final avatar = payload?.avatar.trim() ?? '';
    final title = payload?.title.trim() ?? '';
    final category = payload?.category.trim() ?? '';
    final isLive = payload?.isLive ?? false;
    // 统计区(对齐 web SideHeader「关注：N」行 + stats 列):已关注房间
    // 取关注条目回填;未关注/未回填时兜底调 roomStatsProvider(同一条解析
    // 真源,任意房间可查 —— 用户口径 2026-09-20 huya 等平台统计不能只服务
    // 已关注房间)。上游未提供 → '—' 占位,不伪造(数据诚实性)。
    final followRoom = this.followRoom;
    final RoomSummary? stats =
        followRoom ??
        ref.watch(roomStatsProvider((site: site, roomId: roomId))).value;
    final followersText = _formatFollowersText(stats?.followers);
    final audienceText = _statText(stats?.online);
    final vipText = _statText(stats?.vip);

    // 信息头高度随系统字号缩放:固定 64px 在大字体(1.15x/1.3x)下会把
    // 中间三行元信息挤出容器底部(移动端实测 1px RenderFlex 溢出)。
    final headerHeight = MediaQuery.textScalerOf(context).scale(64.0);
    return Container(
      key: const Key('play-side-header'),
      height: headerHeight,
      decoration: BoxDecoration(
        color: context.tokens.surface,
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 头像贴边出血:占满头高(无上下内边距、左侧贴边),对齐 web
          // `--room-aside-avatar-size = head-h + 2*pad-y`。
          _SideAvatar(avatar: avatar, label: anchor, live: isLive),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 主播名中文化(韩/日名翻,英文/中文名原样)。
                  TranslatedText(
                    anchor,
                    translateName: true,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.08,
                      fontWeight: FontWeight.w600,
                      color: isLive ? tokens.liveBadge : tokens.textPrimary,
                    ),
                  ),
                  // 分类显示在主播名后面那一行(用户口径 2026-09-19);
                  // 关注数与人气/VIP 合并到同一统计行,控制头高不溢出。
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          formatCategoryHeaderLabel(
                            payload?.site,
                            category,
                            payload?.cid,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10, height: 1.15),
                        ),
                      ),
                      // 开播提醒 + 外链(用户口径 2026-09-20:从头像悬浮挪到
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
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          '关注 $followersText',
                          key: const Key('play-side-stat-followers'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, height: 1.08),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      // 人气/观众(web stats[0]「观众」列;online 为空 = 离线或
                      // 尚未刷新回填,显示「—」)。
                      _StatValue(
                        icon: Icons.people_alt_outlined,
                        value: audienceText,
                        color: context.tokens.statAudience,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      // VIP/贵宾(web stats[1] vip 列;douyu/huya 贵宾、
                      // douyin 会员、soop 订阅;其余平台上游无 → 「—」)。
                      _StatValue(
                        icon: Icons.workspace_premium_outlined,
                        value: vipText,
                        color: context.tokens.statVip,
                      ),
                    ],
                  ),
                  if (title.isNotEmpty && title != anchor)
                    Semantics(
                      label: '房间标题 $title',
                      child: const SizedBox.shrink(),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Padding(
            padding: const EdgeInsets.only(
              top: 5,
              bottom: 5,
              right: AppSpacing.sm,
            ),
            child: _SideActions(
              followed: followed,
              superFollowed: superFollowed,
              onToggleFollow: onToggleFollow,
              onToggleSuperFollow: onToggleSuperFollow,
            ),
          ),
        ],
      ),
    );
  }
}

/// 统计文本:空串(未关注/上游未提供)显示「—」占位,不伪造。
String _statText(String? value) {
  final text = value?.trim() ?? '';
  return text.isEmpty ? '—' : text;
}

/// 关注数显示格式(用户口径 2026-09-20):纯数字 ≥1万 显示「X.X万」
/// (≥100万 收敛为整数万);已带单位或非数字文本原样返回,不伪造。
String _formatFollowersText(String? raw) {
  final text = (raw?.trim() ?? '').replaceAll(',', '');
  if (text.isEmpty) return '—';
  final value = int.tryParse(text);
  if (value == null) return text;
  if (value >= 10000) {
    final wan = value / 10000;
    return wan >= 100
        ? '${wan.toStringAsFixed(0)}万'
        : '${wan.toStringAsFixed(1)}万';
  }
  return text;
}

class _SideAvatar extends StatelessWidget {
  const _SideAvatar({
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
    // 64×头高(贴边出血:高度由 Row stretch 撑满,不留上下 padding)。
    return SizedBox(
      width: 64,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                bottomRight: Radius.circular(AppRadius.sm),
              ),
              child: avatar.isEmpty
                  ? ColoredBox(
                      color: tokens.surfaceRaised,
                      child: Center(
                        child: Text(
                          fallback,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: live
                                ? tokens.liveBadge
                                : tokens.textSecondary,
                          ),
                        ),
                      ),
                    )
                  : Image.network(
                      avatar,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => ColoredBox(
                        color: tokens.surfaceRaised,
                        child: Center(
                          child: Text(
                            fallback,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: live
                                  ? tokens.liveBadge
                                  : tokens.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 侧栏头第二排的小文字按钮(用户口径 2026-09-20:开播提醒/跳转显示为
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

class _SideActions extends StatelessWidget {
  const _SideActions({
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
    return SizedBox(
      width: 59,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: _SideActionButton(
              key: const Key('play-side-follow-btn'),
              icon: followed
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              label: followed ? '已关注' : '关注',
              foreground: followed
                  ? context.tokens.playFollowTextActive
                  : context.tokens.playFollowText,
              background: followed
                  ? context.tokens.playFollowBgActive
                  : context.tokens.playFollowBg,
              border: context.tokens.playFollowBorder,
              onPressed: onToggleFollow,
            ),
          ),
          const SizedBox(height: 2),
          Expanded(
            child: _SideActionButton(
              key: const Key('play-side-super-follow'),
              icon: superFollowed
                  ? Icons.star_rounded
                  : Icons.star_border_rounded,
              label: superFollowed ? '已超关' : '超关',
              foreground: superFollowed
                  ? context.tokens.playSuperTextActive
                  : context.tokens.playSuperText,
              background: superFollowed
                  ? context.tokens.playSuperBgActive
                  : context.tokens.playSuperBg,
              border: context.tokens.playSuperBorder,
              onPressed: onToggleSuperFollow,
            ),
          ),
        ],
      ),
    );
  }
}

class _SideActionButton extends StatelessWidget {
  const _SideActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.foreground,
    required this.background,
    required this.border,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color foreground;
  final Color background;
  final Color border;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Material(
        color: background,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.allSm,
          side: BorderSide(color: border),
        ),
        child: InkWell(
          borderRadius: AppRadius.allSm,
          onTap: onPressed,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 12, color: foreground),
              const SizedBox(width: 2),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    height: 1,
                    fontWeight: FontWeight.w600,
                    color: foreground,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatValue extends StatelessWidget {
  const _StatValue({
    required this.icon,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: color.withValues(alpha: 0.88)),
        const SizedBox(width: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 10,
            height: 1,
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
