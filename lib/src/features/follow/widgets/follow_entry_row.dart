/// 单行密度条目(名单):纯文字流 —— 只有「主播名 + 在线人数」。
///
/// 对齐用户诉求:不要缩略图 / 分类 / 标题 / 操作按钮;每项宽度按内容
/// 自适应,由 [FollowView] 用 `Wrap` 横向排布,排满一行即换行往下。
/// 批量模式下前置一枚复选框,点击整体进播放页、长按进批量。
library;

import 'package:flutter/material.dart';

import '../../../shared/presentation/design_tokens.dart';
import '../../../shared/presentation/platform_brands.dart';
import '../../../shared/presentation/zishu_tokens.dart';
import '../application/follow_provider.dart';
import 'follow_common.dart';

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
    final brand = PlatformBrandCatalog.byId(room.site);
    final selectedBg = (brand?.color ?? tokens.brand).withValues(alpha: 0.14);

    return Material(
      // 测试锚点:条目根节点(follow-entry-{site}-{roomId})。
      key: Key('follow-entry-${room.site}-${room.roomId}'),
      color: selected ? selectedBg : tokens.surface,
      borderRadius: AppRadius.allSm,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: AppRadius.allSm,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: 5,
          ),
          decoration: BoxDecoration(
            borderRadius: AppRadius.allSm,
            border: Border.all(color: tokens.border.withValues(alpha: 0.7)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selectMode) ...[
                SizedBox(
                  width: 18,
                  height: 18,
                  child: Checkbox(
                    value: selected,
                    onChanged: (_) => onToggleSelect?.call(),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    activeColor: tokens.brand,
                    checkColor: tokens.surfaceSoft,
                    side: BorderSide(color: tokens.border),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
              ],
              // 特别关注 ★ 前缀。
              if (entry.isSpecial) ...[
                Icon(Icons.star_rounded, size: 11, color: tokens.brand),
                const SizedBox(width: 2),
              ],
              // 主播名:全站统一平台品牌色。
              FollowAnchorName(
                site: room.site,
                name: room.anchorName,
                live: live,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              const SizedBox(width: 6),
              // 在线人数:开播为人形图标 + 数字,离线为时钟 + 「未开播」。
              Icon(
                live ? Icons.people_alt_rounded : Icons.schedule_rounded,
                size: 11,
                color: live ? tokens.liveBadge : tokens.textSecondary,
              ),
              const SizedBox(width: 2),
              Text(
                live ? room.online : '未开播',
                style: AppTypography.caption.copyWith(
                  fontSize: 11,
                  color: live ? tokens.textPrimary : tokens.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
