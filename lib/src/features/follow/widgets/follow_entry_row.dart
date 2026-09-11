/// 单行密度条目(Row):对齐 SFVideoLive `FollowRoomRowView.vue` 的四列表格。
///
/// 列结构(自左向右):
/// 1. 分类 chip —— 固定宽,条纹底(斜纹用重复渐变近似),文字单行省略;
/// 2. 主播名 —— 固定宽,加粗,点击进主播页,特别关注带金色 ★;
/// 3. 标题 —— 吃剩余空间,单行省略;
/// 4. 在线数 —— 固定宽右对齐,人形图标 + 数字;离线为时钟图标 + 破折号。
///
/// 关注独立页宽屏下由 [FollowView] 按 300–400px/列拆成多列(见 `_buildList`),
/// 因此本组件**不带行内操作按钮**(参考实现同样没有),增删改走「批量管理」。
library;

import 'package:flutter/material.dart';

import '../../../shared/presentation/design_tokens.dart';
import '../../../shared/presentation/zishu_tokens.dart';
import '../application/follow_provider.dart';
import 'follow_common.dart';

/// 分类列宽(约 4.6em @13px)。
const double kFollowRowCategoryWidth = 60;

/// 主播列宽(约 6.5em)。
const double kFollowRowAnchorWidth = 84;

/// 在线列宽(约 3.2em)。
const double kFollowRowOnlineWidth = 54;

/// 行高:四列单行文本 + 上下 padding,供多列网格推导纵横比。
const double kFollowRowHeight = 34;

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
    final live = entry.isLive;
    final textColor = live ? tokens.textPrimary : tokens.textSecondary;

    return InkWell(
      // 测试锚点:条目根节点(follow-entry-{site}-{roomId})。
      key: Key('follow-entry-${room.site}-${room.roomId}'),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        height: kFollowRowHeight,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        decoration: BoxDecoration(
          // 选中态用品牌金低透明度底色提示。
          color: selected ? tokens.brand.withValues(alpha: 0.1) : null,
          border: Border(
            bottom: BorderSide(color: tokens.border.withValues(alpha: 0.7)),
          ),
        ),
        child: Row(
          children: [
            if (selectMode) ...[
              SizedBox(
                width: 20,
                height: 20,
                child: Checkbox(
                  value: selected,
                  onChanged: (_) => onToggleSelect?.call(),
                  visualDensity: VisualDensity.compact,
                  activeColor: tokens.brand,
                  checkColor: tokens.surfaceSoft,
                  side: BorderSide(color: tokens.border),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
            ],
            // 1) 分类 chip:条纹底 + 单行省略,空分类退化为站点名。
            SizedBox(
              width: kFollowRowCategoryWidth,
              child: _StripedCategoryChip(
                label: room.category.isEmpty ? room.site : room.category,
                live: live,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            // 2) 主播名:特别关注带金色 ★ 前缀。
            SizedBox(
              width: kFollowRowAnchorWidth,
              child: GestureDetector(
                onTap: onAnchorTap,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (entry.isSpecial) ...[
                      Icon(Icons.star_rounded, size: 11, color: tokens.brand),
                      const SizedBox(width: 2),
                    ],
                    Flexible(
                      child: FollowAnchorName(
                        site: room.site,
                        name: room.anchorName,
                        live: live,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            // 3) 标题。
            Expanded(
              child: Text(
                room.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.body.copyWith(
                  fontSize: 12,
                  color: textColor,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            // 4) 在线数:开播为人形图标 + 数字,离线为时钟图标 + 破折号。
            SizedBox(
              width: kFollowRowOnlineWidth,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    live ? Icons.people_alt_rounded : Icons.schedule_rounded,
                    size: 11,
                    color: live ? tokens.liveBadge : tokens.textSecondary,
                  ),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text(
                      live ? room.online : '—',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: AppTypography.bodySecondary.copyWith(
                        fontSize: 11,
                        color: live ? tokens.textPrimary : tokens.textSecondary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 5) 行内操作:提醒 / 特别关注 / 移除(批量模式由复选框与底部按钮接管)。
            if (!selectMode) ...[
              const SizedBox(width: AppSpacing.xs),
              FollowIconAction(
                icon: entry.remindOn
                    ? Icons.notifications_active_rounded
                    : Icons.notifications_none_rounded,
                tooltip: entry.remindOn ? '关闭开播提醒' : '开启开播提醒',
                active: entry.remindOn,
                onPressed: onToggleRemind,
              ),
              FollowIconAction(
                icon: entry.isSpecial
                    ? Icons.star_rounded
                    : Icons.star_border_rounded,
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

/// 分类 chip:条纹底 + 单行文本,对齐 `.follow-four-col-table__cell--striped`。
///
/// 45° 斜纹用多 stop 线性渐变近似 CSS repeating-linear-gradient;
/// 开播态描边取品牌金低透明度,离线态整体压暗。
class _StripedCategoryChip extends StatelessWidget {
  const _StripedCategoryChip({required this.label, required this.live});

  final String label;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final base = tokens.surfaceRaised;
    final stripe = tokens.border.withValues(alpha: 0.55);
    return Container(
      height: 20,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        borderRadius: AppRadius.allSm,
        border: Border.all(
          color: live
              ? tokens.brand.withValues(alpha: 0.35)
              : tokens.border.withValues(alpha: 0.6),
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [base, base, stripe, base, base],
          stops: const [0, 0.34, 0.4, 0.46, 1],
        ),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.caption.copyWith(
          fontSize: 10.5,
          color: live ? tokens.textPrimary : tokens.textSecondary,
        ),
      ),
    );
  }
}
