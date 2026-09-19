/// 平台筛选 chips:全平台 + 各平台(对齐 SFVideoLive FollowPlatformFilter)。
/// 选中态用平台品牌色点缀底色与描边,文字对比度交给主题文字色。
library;

import 'package:flutter/material.dart';

import '../../../shared/presentation/design_tokens.dart';
import '../../../shared/presentation/platform_brands.dart';
import '../../../shared/presentation/zishu_tokens.dart';

/// 当前值为平台 id,'all' 表示全平台。
class FollowPlatformFilter extends StatelessWidget {
  const FollowPlatformFilter({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final brand in PlatformBrandCatalog.navPlatforms)
          _PlatformChip(
            label: brand.id == 'all' ? '全平台' : brand.name,
            accent: brand.id == 'all'
                ? context.tokens.brand
                : brand.color,
            showDot: brand.id != 'all',
            selected: value == brand.id,
            onTap: () => onChanged(brand.id),
          ),
      ],
    );
  }
}

class _PlatformChip extends StatelessWidget {
  const _PlatformChip({
    required this.label,
    required this.accent,
    required this.showDot,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color accent;
  final bool showDot;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return InkWell(
      borderRadius: AppRadius.allSm,
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.curve,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.18) : tokens.surface,
          borderRadius: AppRadius.allSm,
          border: Border.all(color: selected ? accent : tokens.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showDot) ...[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
              ),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: context.textBody.copyWith(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                color: selected ? tokens.textPrimary : tokens.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
