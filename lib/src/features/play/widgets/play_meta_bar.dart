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
/// **数据诚实性**:全部取自 [RoomPayload] 的真实字段;解析层没给的项一律显示
/// 「—」,不伪造。当前 `RoomPayload` 只有 `startedAt`(斗鱼等平台真实返回)与
/// `anchorName`/`avatar`;`followers` / `audience` / 弹幕数尚无字段 —— 需解析轨
/// 补齐 `RoomPayload` 后本组件自动生效(见 todo.md 遗留项)。
library;

import 'package:flutter/material.dart';
import 'package:live_parser/live_parser.dart' show RoomPayload;

import '../../../shared/presentation/design_tokens.dart';
import '../../../shared/presentation/zishu_tokens.dart';

class PlayMetaBar extends StatelessWidget {
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

  /// 头像直径(实测 32-36px,取中值)。
  static const double _kAvatarSize = 34;

  /// 「关注 / 超关」按钮列宽(实测 ≈72px)。
  static const double _kActionsWidth = 72;

  /// 统计格图标尺寸。
  static const double _kStatIconSize = 12;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final anchor = payload?.anchorName.trim().isNotEmpty == true
        ? payload!.anchorName.trim()
        : '主播信息';
    final isLive = payload?.isLive ?? false;
    // 高度随系统字号缩放:与侧栏信息头同口径(固定高度在大字体下会把第二行
    // 统计挤出容器,移动端实测溢出)。
    final height = MediaQuery.textScalerOf(context).scale(64.0);
    return Container(
      key: const Key('play-meta-bar'),
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 5),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: _MetaAvatar(
              avatar: payload?.avatar.trim() ?? '',
              // 无头像时用昵称首字兜底(与侧栏信息头同语义)。
              label: anchor,
              live: isLive,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  anchor,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.08,
                    fontWeight: FontWeight.w600,
                    color: isLive ? tokens.liveBadge : tokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    _MetaStat(
                      key: const Key('play-meta-stat-followers'),
                      icon: Icons.favorite_border_rounded,
                      iconColor: AppColors.playFollowText,
                      label: '关注',
                      // 解析层暂无 followers 字段(见文件头「数据诚实性」)。
                      value: '—',
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    _MetaStat(
                      key: const Key('play-meta-stat-started'),
                      icon: Icons.schedule_rounded,
                      iconColor: isLive ? tokens.liveBadge : tokens.textSecondary,
                      label: '开播',
                      value: _startedText(isLive),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    _MetaStat(
                      key: const Key('play-meta-stat-audience'),
                      icon: Icons.people_alt_outlined,
                      iconColor: AppColors.playStatAudienceText,
                      label: '人气',
                      // 解析层暂无 audience 字段。
                      value: '—',
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
      height: PlayMetaBar._kAvatarSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
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
                  fontSize: 14,
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
                    fontSize: 14,
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
              fontSize: 10.5,
              height: 1.15,
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
            foreground: followed
                ? AppColors.playFollowTextActive
                : AppColors.playFollowText,
            background: followed
                ? AppColors.playFollowBgActive
                : AppColors.playFollowBg,
            border: AppColors.playFollowBorder,
            onPressed: onToggleFollow,
          ),
        ),
        const SizedBox(height: 2),
        Expanded(
          child: _MetaActionButton(
            key: const Key('play-side-super-follow'),
            icon: superFollowed ? Icons.star_rounded : Icons.star_border_rounded,
            label: superFollowed ? '已超关' : '超关',
            foreground: superFollowed
                ? AppColors.playSuperTextActive
                : AppColors.playSuperText,
            background: superFollowed
                ? AppColors.playSuperBgActive
                : AppColors.playSuperBg,
            border: AppColors.playSuperBorder,
            onPressed: onToggleSuperFollow,
          ),
        ),
      ],
    );
  }
}

class _MetaActionButton extends StatelessWidget {
  const _MetaActionButton({
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
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 12, color: foreground),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
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
    );
  }
}
