import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/presentation/design_tokens.dart';
import '../../../shared/presentation/platform_brands.dart';
import '../../../shared/presentation/zishu_tokens.dart';
import '../application/search_provider.dart';

/// 搜索页平台切换 chips:全平台聚合 + 各平台,选中色取自平台品牌。
class SearchPlatformChips extends ConsumerWidget {
  const SearchPlatformChips({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(searchProvider).site;
    return SizedBox(
      height: AppSpacing.topNavHeight,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        children: [
          for (final brand in PlatformBrandCatalog.searchPlatforms)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: _PlatformChip(
                brand: brand,
                selected: brand.id == selected,
                onTap: () =>
                    ref.read(searchProvider.notifier).setSite(brand.id),
              ),
            ),
        ],
      ),
    );
  }
}

class _PlatformChip extends StatelessWidget {
  const _PlatformChip({
    required this.brand,
    required this.selected,
    required this.onTap,
  });

  final PlatformBrand brand;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return InkWell(
      borderRadius: AppRadius.allSm,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: selected
              ? brand.color.withValues(alpha: 0.18)
              : tokens.surface,
          borderRadius: AppRadius.allSm,
          border: Border.all(color: selected ? brand.color : tokens.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: brand.color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              brand.name,
              style: context.textSecondary.copyWith(
                color: selected ? brand.color : tokens.textSecondary,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
