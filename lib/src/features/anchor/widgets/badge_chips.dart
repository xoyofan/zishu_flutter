import 'package:flutter/material.dart';

import '../../../shared/domain/category_display.dart';
import '../../../shared/presentation/design_tokens.dart';
import '../../../shared/presentation/platform_brands.dart';
import '../../../shared/presentation/zishu_tokens.dart';

/// 平台徽标 chip:平台色底 + 平台名,用于主播头部与卡片角标。
class PlatformBadgeChip extends StatelessWidget {
  const PlatformBadgeChip({super.key, required this.site});

  final String site;

  @override
  Widget build(BuildContext context) {
    final brand = PlatformBrandCatalog.byId(site);
    final color = brand?.color ?? context.tokens.brand;
    return _BadgeChip(
      label: brand?.name ?? site,
      background: color.withValues(alpha: 0.22),
      foreground: color,
    );
  }
}

/// 直播状态徽标:在播红色「直播中」,回放品牌色,离线灰态。
class LiveStateChip extends StatelessWidget {
  const LiveStateChip({super.key, required this.isLive, this.isReplay = false});

  final bool isLive;
  final bool isReplay;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    if (isLive) {
      return _BadgeChip(
        label: '直播中',
        background: tokens.liveBadge,
        foreground: tokens.textPrimary,
      );
    }
    if (isReplay) {
      return _BadgeChip(
        label: '回放',
        background: tokens.brand.withValues(alpha: 0.22),
        foreground: tokens.brand,
      );
    }
    return _BadgeChip(
      label: '离线',
      background: tokens.surfaceRaised,
      foreground: tokens.textSecondary,
    );
  }
}

/// 分类徽标:中性底色小 chip。
class CategoryChip extends StatelessWidget {
  const CategoryChip({
    super.key,
    required this.label,
    this.site = '',
    this.cid = '',
  });

  final String label;
  final String site;
  final String cid;

  @override
  Widget build(BuildContext context) {
    // 跨平台统一中文分类名:命中映射用 canonical 名,否则回落平台原名。
    final display = displayCategoryName(site, label, cid);
    return _BadgeChip(
      label: display,
      background: context.tokens.surfaceRaised,
      foreground: context.tokens.textSecondary,
    );
  }
}

/// 在线人数角标:深色半透明底,叠放在封面上。
class OnlineTag extends StatelessWidget {
  const OnlineTag({super.key, required this.online});

  final String online;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: tokens.surfaceSoft.withValues(alpha: 0.78),
        borderRadius: AppRadius.allSm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.visibility_rounded, size: 10, color: tokens.textSecondary),
          const SizedBox(width: 3),
          Text(online, style: AppTypography.caption),
        ],
      ),
    );
  }
}

/// chip 基础样式:圆角 sm + caption 字号。
class _BadgeChip extends StatelessWidget {
  const _BadgeChip({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadius.allSm,
      ),
      child: Text(
        label,
        style: AppTypography.caption.copyWith(
          color: foreground,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
