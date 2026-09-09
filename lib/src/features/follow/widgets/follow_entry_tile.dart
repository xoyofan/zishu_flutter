/// 紧凑密度条目(Tile):横向小图行,一行放更多信息。
/// 对齐 SFVideoLive FollowRoomTileView 的信息结构,纯渲染组件。
library;

import 'package:flutter/material.dart';

import '../../../shared/presentation/design_tokens.dart';
import '../../../shared/presentation/platform_brands.dart';
import '../../../shared/presentation/zishu_tokens.dart';
import '../application/follow_provider.dart';
import 'follow_common.dart';

/// 小图缩略尺寸(约 16:9)。
const double _thumbWidth = 120;
const double _thumbHeight = 68;

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
    return Container(
      // 测试锚点:条目根节点(follow-entry-{site}-{roomId})。
      key: Key('follow-entry-${room.site}-${room.roomId}'),
      foregroundDecoration: BoxDecoration(
        borderRadius: AppRadius.allMd,
        border: Border.all(color: selected ? tokens.brand : tokens.border),
      ),
      child: Material(
        color: tokens.surface,
        borderRadius: AppRadius.allMd,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
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
                ],
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
                          fallbackLabel: room.category.isEmpty ? room.site : room.category,
                          offline: !entry.isLive,
                          width: _thumbWidth,
                          height: _thumbHeight,
                        ),
                        Positioned(
                          left: AppSpacing.xs,
                          top: AppSpacing.xs,
                          child: FollowCoverTag(
                            accent: brand?.color,
                            child: Text(
                              brand?.name ?? room.site,
                              style: AppTypography.caption.copyWith(
                                fontSize: 10,
                                color: tokens.surfaceSoft,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        if (entry.isSpecial)
                          Positioned(
                            right: AppSpacing.xs,
                            top: AppSpacing.xs,
                            child: Icon(
                              Icons.star_rounded,
                              size: 14,
                              color: tokens.brand,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
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
                                  fontWeight: FontWeight.w700,
                                  color:
                                      entry.isLive ? tokens.textPrimary : tokens.textSecondary,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          FollowPlatformDot(site: room.site),
                          const SizedBox(width: AppSpacing.xs),
                          if (room.category.isNotEmpty)
                            Flexible(child: FollowCategoryTag(label: room.category)),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        room.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodySecondary.copyWith(
                          color: entry.isLive ? tokens.textSecondary : tokens.textSecondary.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                // 在线人数/离线 + 提醒/删除操作(批量模式隐藏)。
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FollowStatusDot(live: entry.isLive),
                        const SizedBox(width: 4),
                        Text(
                          entry.isLive ? room.online : '离线',
                          style: AppTypography.caption,
                        ),
                      ],
                    ),
                    if (!selectMode)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
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
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
