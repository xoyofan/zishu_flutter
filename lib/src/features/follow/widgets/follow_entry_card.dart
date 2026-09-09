/// 卡片密度条目:约 240px 宽封面卡(16:9 封面 + 元信息区)。
/// 纯渲染组件:状态全部来自 [FollowEntry],交互通过回调上抛。
library;

import 'package:flutter/material.dart';
import 'package:live_parser/live_parser.dart';

import '../../../shared/presentation/design_tokens.dart';
import '../../../shared/presentation/platform_brands.dart';
import '../../../shared/presentation/zishu_tokens.dart';
import '../application/follow_provider.dart';
import 'follow_common.dart';

class FollowEntryCard extends StatelessWidget {
  const FollowEntryCard({
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

  /// 批量选择模式:显示复选框、点击改为切换选择。
  final bool selectMode;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onToggleSelect;
  final VoidCallback? onToggleSpecial;
  final VoidCallback? onToggleRemind;
  final VoidCallback? onRemove;

  /// 点击主播名进入主播页。
  final VoidCallback? onAnchorTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final room = entry.room;
    final brand = PlatformBrandCatalog.byId(room.site);
    return Container(
      // 测试锚点:条目根节点(follow-entry-{site}-{roomId})。
      key: Key('follow-entry-${room.site}-${room.roomId}'),
      // 批量模式下选中项用品牌金描边提示。
      foregroundDecoration: BoxDecoration(
        borderRadius: AppRadius.allMd,
        border: Border.all(
          color: selected ? tokens.brand : tokens.border,
        ),
      ),
      child: Material(
        color: tokens.surface,
        borderRadius: AppRadius.allMd,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildCover(context, room, brand),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        room.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.title.copyWith(
                          fontSize: 13,
                          color: entry.isLive ? tokens.textPrimary : tokens.textSecondary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      GestureDetector(
                        onTap: onAnchorTap,
                        child: Text(
                          room.anchorName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodySecondary.copyWith(
                            decoration: TextDecoration.underline,
                            decorationColor: tokens.border,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          if (room.category.isNotEmpty) ...[
                            Flexible(child: FollowCategoryTag(label: room.category)),
                            const SizedBox(width: AppSpacing.sm),
                          ],
                          const Spacer(),
                          FollowIconAction(
                            icon: entry.isSpecial
                                ? Icons.star_rounded
                                : Icons.star_border_rounded,
                            tooltip: entry.isSpecial ? '取消特别关注' : '设为特别关注',
                            active: entry.isSpecial,
                            onPressed: selectMode ? null : onToggleSpecial,
                          ),
                          FollowIconAction(
                            icon: entry.remindOn
                                ? Icons.notifications_active_rounded
                                : Icons.notifications_none_rounded,
                            tooltip: entry.remindOn ? '关闭开播提醒' : '开启开播提醒',
                            active: entry.remindOn,
                            onPressed: selectMode ? null : onToggleRemind,
                          ),
                          FollowIconAction(
                            icon: Icons.delete_outline_rounded,
                            tooltip: '移除关注',
                            danger: true,
                            onPressed: selectMode ? null : onRemove,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 16:9 封面:平台角标 + 特别关注★ + 在线人数/离线标,批量模式左上为复选框。
  Widget _buildCover(BuildContext context, RoomSummary room, PlatformBrand? brand) {
    final tokens = context.tokens;
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(
        fit: StackFit.expand,
        children: [
          FollowCoverImage(
            cover: room.cover,
            fallbackLabel: room.category.isEmpty ? room.site : room.category,
            offline: !entry.isLive,
          ),
          Positioned(
            left: AppSpacing.sm,
            top: AppSpacing.sm,
            child: selectMode
                ? _SelectBox(selected: selected, onChanged: (_) => onToggleSelect?.call())
                : Row(
                    children: [
                      // 平台角标:品牌色底 + 深色字(surfaceSoft 在深浅主题下都与品牌色拉开对比)。
                      FollowCoverTag(
                        accent: brand?.color,
                        child: Text(
                          brand?.name ?? room.site,
                          style: AppTypography.caption.copyWith(
                            color: tokens.surfaceSoft,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (entry.isSpecial) ...[
                        const SizedBox(width: AppSpacing.xs),
                        FollowCoverTag(
                          child: Icon(
                            Icons.star_rounded,
                            size: 12,
                            color: tokens.brand,
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
          Positioned(
            right: AppSpacing.sm,
            bottom: AppSpacing.sm,
            child: FollowCoverTag(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    entry.isLive
                        ? Icons.visibility_rounded
                        : Icons.nightlight_round,
                    size: 10,
                    color: entry.isLive ? tokens.liveBadge : tokens.textSecondary,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    entry.isLive ? room.online : '离线',
                    style: AppTypography.caption.copyWith(
                      color: entry.isLive ? tokens.textPrimary : tokens.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 批量模式复选框(加浅色底保证在封面上可见)。
class _SelectBox extends StatelessWidget {
  const _SelectBox({required this.selected, required this.onChanged});

  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      decoration: BoxDecoration(
        color: tokens.surfaceSoft.withValues(alpha: 0.85),
        borderRadius: AppRadius.allSm,
      ),
      child: Checkbox(
        value: selected,
        onChanged: (value) => onChanged(value ?? false),
        visualDensity: VisualDensity.compact,
        activeColor: tokens.brand,
        checkColor: tokens.surfaceSoft,
        side: BorderSide(color: tokens.border),
      ),
    );
  }
}
