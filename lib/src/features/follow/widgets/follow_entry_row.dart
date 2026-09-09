/// 单行密度条目(Row):纯文字行,对齐 SFVideoLive 四列关注表
/// (状态点/主播/标题/分类/在线/操作),信息密度最高。
library;

import 'package:flutter/material.dart';

import '../../../shared/presentation/design_tokens.dart';
import '../../../shared/presentation/zishu_tokens.dart';
import '../application/follow_provider.dart';
import 'follow_common.dart';

/// 主播名列固定宽,标题吃剩余空间。
const double _anchorWidth = 96;
const double _onlineWidth = 64;

class FollowEntryRow extends StatelessWidget {
  const FollowEntryRow({
    super.key,
    required this.entry,
    this.selectMode = false,
    this.selected = false,
    this.onTap,
    this.onLongPress,
    this.onToggleSelect,
    this.onToggleSpecial,
    this.onToggleRemind,
    this.onRemove,
    this.onAnchorTap,
  });

  final FollowEntry entry;
  final bool selectMode;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onToggleSelect;
  final VoidCallback? onToggleSpecial;
  final VoidCallback? onToggleRemind;
  final VoidCallback? onRemove;
  final VoidCallback? onAnchorTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final room = entry.room;
    return InkWell(
      // 测试锚点:条目根节点(follow-entry-{site}-{roomId})。
      key: Key('follow-entry-${room.site}-${room.roomId}'),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          // 选中态用品牌金低透明度底色提示。
          color: selected ? tokens.brand.withValues(alpha: 0.1) : null,
          border: Border(bottom: BorderSide(color: tokens.border)),
        ),
        child: Row(
          children: [
            if (selectMode) ...[
              Checkbox(
                value: selected,
                onChanged: (_) => onToggleSelect?.call(),
                visualDensity: VisualDensity.compact,
                activeColor: tokens.brand,
                checkColor: tokens.surfaceSoft,
                side: BorderSide(color: tokens.border),
              ),
              const SizedBox(width: AppSpacing.xs),
            ] else ...[
              FollowStatusDot(live: entry.isLive),
              const SizedBox(width: AppSpacing.sm),
            ],
            if (entry.isSpecial) ...[
              Icon(Icons.star_rounded, size: 14, color: tokens.brand),
              const SizedBox(width: 2),
            ],
            // 主播名(点击进主播页)。
            SizedBox(
              width: _anchorWidth,
              child: GestureDetector(
                onTap: onAnchorTap,
                child: Text(
                  room.anchorName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: entry.isLive ? tokens.textPrimary : tokens.textSecondary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                room.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.body.copyWith(
                  fontSize: 12,
                  color: entry.isLive ? tokens.textPrimary : tokens.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            if (room.category.isNotEmpty) FollowCategoryTag(label: room.category),
            SizedBox(
              width: _onlineWidth,
              child: Text(
                entry.isLive ? room.online : '离线',
                textAlign: TextAlign.right,
                style: AppTypography.bodySecondary,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            if (!selectMode) ...[
              FollowIconAction(
                icon: entry.remindOn
                    ? Icons.notifications_active_rounded
                    : Icons.notifications_none_rounded,
                tooltip: entry.remindOn ? '关闭开播提醒' : '开启开播提醒',
                active: entry.remindOn,
                onPressed: onToggleRemind,
              ),
              FollowIconAction(
                icon: entry.isSpecial ? Icons.star_rounded : Icons.star_border_rounded,
                tooltip: entry.isSpecial ? '取消特别关注' : '设为特别关注',
                active: entry.isSpecial,
                onPressed: onToggleSpecial,
              ),
              FollowIconAction(
                icon: Icons.delete_outline_rounded,
                tooltip: '移除关注',
                danger: true,
                onPressed: onRemove,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
