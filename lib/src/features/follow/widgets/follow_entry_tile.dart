/// 紧凑密度条目(Tile):对齐 SFVideoLive `FollowRoomTileView.vue` 的 pageTile 三段式。
///
/// 上段横向两列:
/// - 左列(自上而下):分类 tag → 封面缩略图 → 平台 tag;
/// - 右列(自上而下):主播名(+ 特别关注 ★)→ 在线/离线元信息 → 提醒铃铛;
/// 下段:房间标题整行单行省略。
///
/// 批量选择模式在左列顶部插入复选框,并隐藏右侧操作。
library;

import 'package:flutter/material.dart';

import '../../../shared/presentation/design_tokens.dart';
import '../../../shared/presentation/platform_brands.dart';
import '../../../shared/presentation/zishu_tokens.dart';
import '../application/follow_provider.dart';
import 'follow_common.dart';

/// 封面缩略尺寸(16:9)。
const double _thumbWidth = 104;
const double _thumbHeight = 58;

class FollowEntryTile extends StatelessWidget {
  const FollowEntryTile({
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
    final brand = PlatformBrandCatalog.byId(room.site);
    final live = entry.isLive;
    return Container(
      // 测试锚点:条目根节点(follow-entry-{site}-{roomId})。
      key: Key('follow-entry-${room.site}-${room.roomId}'),
      foregroundDecoration: BoxDecoration(
        borderRadius: AppRadius.allMd,
        border: Border.all(
          color: selected ? tokens.brand : tokens.border,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: Material(
        color: tokens.surface,
        borderRadius: AppRadius.allMd,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              AppSpacing.sm,
              AppSpacing.sm,
              6,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
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
                    // 左列:分类 tag → 封面 → 平台 tag。
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (room.category.isNotEmpty)
                          _TileCategoryTag(label: room.category),
                        const SizedBox(height: 3),
                        SizedBox(
                          width: _thumbWidth,
                          height: _thumbHeight,
                          child: ClipRRect(
                            borderRadius: AppRadius.allSm,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                FollowCoverImage(
                                  cover: room.cover,
                                  fallbackLabel: room.category.isEmpty
                                      ? room.site
                                      : room.category,
                                  offline: !live,
                                  width: _thumbWidth,
                                  height: _thumbHeight,
                                ),
                                if (entry.isSpecial)
                                  Positioned(
                                    right: 3,
                                    top: 3,
                                    child: Icon(
                                      Icons.star_rounded,
                                      size: 12,
                                      color: tokens.brand,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 3),
                        _TilePlatformTag(
                          label: brand?.name ?? room.site,
                          color: brand?.color ?? tokens.textSecondary,
                        ),
                      ],
                    ),
                    const SizedBox(width: AppSpacing.md),
                    // 右列:主播名 → 在线/离线 → 操作。
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: GestureDetector(
                                  onTap: onAnchorTap,
                                  child: Text(
                                    room.anchorName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTypography.body.copyWith(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                      color: live
                                          ? tokens.textPrimary
                                          : tokens.textSecondary,
                                    ),
                                  ),
                                ),
                              ),
                              if (entry.isSpecial) ...[
                                const SizedBox(width: 3),
                                Icon(Icons.star_rounded,
                                    size: 12, color: tokens.brand),
                              ],
                            ],
                          ),
                          const SizedBox(height: 5),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                live
                                    ? Icons.people_alt_rounded
                                    : Icons.schedule_rounded,
                                size: 11,
                                color: live
                                    ? tokens.liveBadge
                                    : tokens.textSecondary,
                              ),
                              const SizedBox(width: 3),
                              Flexible(
                                child: Text(
                                  live ? room.online : '未开播',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTypography.caption.copyWith(
                                    fontSize: 10.5,
                                    color: live
                                        ? tokens.textPrimary
                                        : tokens.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (!selectMode) ...[
                            const SizedBox(height: 2),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                FollowIconAction(
                                  icon: entry.remindOn
                                      ? Icons.notifications_active_rounded
                                      : Icons.notifications_none_rounded,
                                  tooltip: entry.remindOn
                                      ? '关闭开播提醒'
                                      : '开启开播提醒',
                                  active: entry.remindOn,
                                  onPressed: onToggleRemind,
                                ),
                                FollowIconAction(
                                  icon: entry.isSpecial
                                      ? Icons.star_rounded
                                      : Icons.star_border_rounded,
                                  tooltip: entry.isSpecial
                                      ? '取消特别关注'
                                      : '设为特别关注',
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
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                // 下段:房间标题整行。
                Text(
                  room.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySecondary.copyWith(
                    fontSize: 11.5,
                    color: tokens.textSecondary,
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

/// 左列顶部的小分类 tag(品牌金描边 + 低透明度底)。
class _TileCategoryTag extends StatelessWidget {
  const _TileCategoryTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: tokens.brand.withValues(alpha: 0.12),
        borderRadius: AppRadius.allSm,
        border: Border.all(color: tokens.brand.withValues(alpha: 0.45)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.caption.copyWith(
          fontSize: 10,
          color: tokens.brand,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 左列底部的平台 tag(品牌色底 + 深色字)。
class _TilePlatformTag extends StatelessWidget {
  const _TilePlatformTag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: AppRadius.allSm,
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.caption.copyWith(
          fontSize: 10,
          color: tokens.surface,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
