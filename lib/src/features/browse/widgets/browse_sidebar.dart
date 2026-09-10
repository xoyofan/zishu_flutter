import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:live_parser/live_parser.dart';

import '../../../shared/presentation/category_colors.dart';
import '../../../shared/presentation/design_tokens.dart';
import '../../../shared/presentation/platform_brands.dart';
import '../../../shared/presentation/widgets/platform_icon.dart';
import '../../../shared/presentation/zishu_tokens.dart';
import '../application/browse_provider.dart';

/// 桌面首页常驻左侧栏:上段平台图标网格 + 下段分类树。
///
/// 对齐 SFVideoLive 桌面首页默认展开的 `DirectoryDrawer`(drawerPref 默认
/// `open: true`,`--directory-drawer-width: 220px`);内容区经 `margin-left` 让位,
/// 房间网格列数仍按 **视口断点** 固定(见 [RoomGrid]),卡片按剩余内容宽收窄。
/// 上段平台网格直接复用 [home-platform-chip-{id}] 锚点契约(把平台入口从左栏
/// 出发,内容区的横向 chips 行由 home_view 不再重复渲染),保证
/// `test/ui/browse_home_test.dart` 与 `navigation_test.dart` 的锚点/选中态断言
/// 仍能命中。下段分类树数据来自 [browseCategoriesProvider],不新造硬编码表。
class BrowseSidebar extends ConsumerWidget {
  const BrowseSidebar({super.key, required this.site});

  /// 当前平台 id(`all` = 全平台聚合)。
  final String site;

  /// 左栏宽度,对齐参考实现默认展开抽屉 220px(`--directory-drawer-width`)。
  static const double width = 220;

  /// 上段平台网格列数,对齐参考实现 3 列图标网格。
  static const int platformColumns = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final categoriesAsync = ref.watch(browseCategoriesProvider(site));
    return Container(
      width: width,
      color: tokens.surfaceSoft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PlatformGrid(site: site),
          Container(height: 1, color: tokens.border),
          Expanded(
            child: _CategoryTree(
              site: site,
              categoriesAsync: categoriesAsync,
            ),
          ),
        ],
      ),
    );
  }
}

/// 上段:平台图标网格(3 列)。每项即 [home-platform-chip-{id}] 锚点。
class _PlatformGrid extends StatelessWidget {
  const _PlatformGrid({required this.site});

  final String site;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xs),
      child: GridView.count(
        crossAxisCount: BrowseSidebar.platformColumns,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: AppSpacing.xs,
        crossAxisSpacing: AppSpacing.xs,
        childAspectRatio: 1,
        children: [
          for (final brand in PlatformBrandCatalog.navPlatforms)
            _PlatformTile(
              brand: brand,
              selected: brand.id == site,
              tokens: tokens,
            ),
        ],
      ),
    );
  }
}

/// 单个平台入口:图标型 FilterChip,承载 [home-platform-chip-{id}] 锚点。
class _PlatformTile extends StatelessWidget {
  const _PlatformTile({
    required this.brand,
    required this.selected,
    required this.tokens,
  });

  final PlatformBrand brand;
  final bool selected;
  final ZishuTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: brand.name,
      child: ChipTheme(
        data: ChipTheme.of(context).copyWith(
          backgroundColor: tokens.surface,
          selectedColor: brand.color.withValues(alpha: 0.22),
          checkmarkColor: brand.color,
          labelStyle: AppTypography.body.copyWith(
            color: selected ? brand.color : tokens.textSecondary,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
          ),
          side: BorderSide(color: selected ? brand.color : tokens.border),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.allSm),
        ),
        child: FilterChip(
          // 测试锚点:定位/点击平台入口(前缀同原内容区 chips,见 [BrowseSidebar])。
          key: Key('home-platform-chip-${brand.id}'),
          selected: selected,
          showCheckmark: false,
          avatar: PlatformIcon(id: brand.id, size: 22),
          label: const SizedBox.shrink(),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: EdgeInsets.zero,
          labelPadding: EdgeInsets.zero,
          onSelected: (_) =>
              context.go(brand.id == 'all' ? '/all' : '/${brand.id}'),
        ),
      ),
    );
  }
}

/// 下段:分类树(分组 + 子分类),数据来自 [browseCategoriesProvider]。
class _CategoryTree extends StatelessWidget {
  const _CategoryTree({
    required this.site,
    required this.categoriesAsync,
  });

  final String site;
  final AsyncValue<CategoryResult> categoriesAsync;

  @override
  Widget build(BuildContext context) {
    return switch (categoriesAsync) {
      AsyncValue(:final value?) => value.groups.isEmpty
          ? const SizedBox.shrink()
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              children: [
                for (final group in value.groups) ...[
                  _GroupHeader(name: group.name),
                  for (final item in group.items)
                    _CategoryLeaf(site: site, cid: item.cid, name: item.name),
                ],
              ],
            ),
      // 加载中/出错时折叠分类树,不阻塞房间网格渲染。
      _ => const SizedBox.shrink(),
    };
  }
}

/// 分组标题:名称 + 按分类配色取的色点(复用 [CategoryColors])。
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final color = CategoryColors.opaqueFor(category: name)?.background ??
        tokens.textSecondary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.xs,
      ),
      child: Row(
        children: [
          Container(
            width: AppSpacing.sm,
            height: AppSpacing.sm,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.caption.copyWith(
                color: tokens.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 子分类叶子:点击跳转到平台/全平台分类页。
class _CategoryLeaf extends StatelessWidget {
  const _CategoryLeaf({
    required this.site,
    required this.cid,
    required this.name,
  });

  final String site;
  final String cid;
  final String name;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return InkWell(
      key: Key('browse-sidebar-cat-$cid'),
      onTap: () => context.go(
        site == 'all' ? '/all/category/$cid' : '/$site/category/$cid',
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.bodySecondary.copyWith(
            color: tokens.textPrimary,
          ),
        ),
      ),
    );
  }
}
