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
import '../application/sidebar_pref_provider.dart';

/// 桌面首页常驻左侧栏:可折叠 rail(收起 52px ↔ 展开 220px)。
///
/// 对齐 SFVideoLive 桌面首页的 `DirectoryDrawer`(drawerPref 默认 `open: true`,
/// `--directory-rail-width: 52px`,`--directory-drawer-width: 220px`);内容区经
/// `margin-left` 让位(见 [HomeView] 的 Row + Expanded),房间网格列数仍按
/// **视口断点** 固定(见 [RoomGrid]),卡片按剩余内容宽收窄。
///
/// 开合控件固定在左栏**右缘、垂直居中**(参考 `directory-drawer__toggle-rail`),
/// 由左栏自身用 [Stack] 叠加渲染,不依赖父级改造;锚点
/// [Key('browse-sidebar-toggle')] 用于测试与可达性。
///
/// 两态共用的平台入口锚点 [home-platform-chip-{id}] 始终唯一命中:
/// 收起态是 52px 图标竖列(单列),展开态是 3 列图标网格 + 分类树。
/// 分类树锚点 [browse-sidebar-cat-{cid}] 仅展开态渲染。下段分类树数据来自
/// [browseCategoriesProvider],不新造硬编码表。
class BrowseSidebar extends ConsumerWidget {
  const BrowseSidebar({super.key, required this.site});

  /// 当前平台 id(`all` = 全平台聚合)。
  final String site;

  /// 展开态宽度,对齐参考实现 `--directory-drawer-width`。
  static const double width = 220;

  /// 收起态宽度,对齐参考实现 `--directory-rail-width`。
  static const double railWidth = 52;

  /// 开合按钮的测试锚点。
  static const Key toggleKey = Key('browse-sidebar-toggle');

  /// 上段平台网格列数,对齐参考实现 3 列图标网格。
  static const int platformColumns = 3;

  /// 是否展开(默认展开,见 [sidebarOpenProvider])。
  static bool isOpen(WidgetRef ref) => ref.watch(sidebarOpenProvider);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final open = isOpen(ref);
    final categoriesAsync = ref.watch(browseCategoriesProvider(site));

    return AnimatedContainer(
      duration: AppMotion.normal,
      curve: AppMotion.curve,
      width: open ? width : railWidth,
      color: tokens.surfaceSoft,
      child: Stack(
        children: [
          Positioned.fill(
            child: open
                ? _ExpandedContent(site: site, categoriesAsync: categoriesAsync)
                : _RailContent(site: site),
          ),
          // 右缘中央开合按钮:横向小胶囊,压在面板右边缘(中部)。
          Positioned(
            top: 0,
            bottom: 0,
            right: 0,
            child: _ToggleRail(
              open: open,
              tokens: tokens,
              onTap: () =>
                  ref.read(sidebarOpenProvider.notifier).toggle(),
            ),
          ),
        ],
      ),
    );
  }
}

/// 展开态内容:上段平台图标网格 + 分隔线 + 下段分类树。
class _ExpandedContent extends StatelessWidget {
  const _ExpandedContent({required this.site, required this.categoriesAsync});

  final String site;
  final AsyncValue<CategoryResult> categoriesAsync;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PlatformGrid(site: site),
        Container(height: 1, color: tokens.border),
        Expanded(
          child: _CategoryTree(site: site, categoriesAsync: categoriesAsync),
        ),
      ],
    );
  }
}

/// 收起态内容:平台图标竖列(单列,无文字),对齐参考
/// `directory-drawer__rail-platforms`。
class _RailContent extends StatelessWidget {
  const _RailContent({required this.site});

  final String site;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      children: [
        for (final brand in PlatformBrandCatalog.navPlatforms)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Center(
              child: _PlatformTile(
                brand: brand,
                selected: brand.id == site,
                tokens: tokens,
                // 收起态图标略大:52px 内单列展示,留白对齐参考竖列。
                iconSize: AppSpacing.xxl,
                compact: true,
              ),
            ),
          ),
      ],
    );
  }
}

/// 右缘中央的开合按钮:收起时朝右(展开),展开时朝左(收起)。
class _ToggleRail extends StatelessWidget {
  const _ToggleRail({
    required this.open,
    required this.tokens,
    required this.onTap,
  });

  final bool open;
  final ZishuTokens tokens;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final icon = Icon(
      open ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
      size: 14,
      color: tokens.textSecondary,
    );
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.only(right: AppSpacing.xs),
        child: SizedBox(
          // 收起态宽度受限于 52px rail,压到右缘留 4px;展开态给固定胶囊宽。
          width: open ? AppSpacing.xl : AppSpacing.md,
          height: AppSpacing.xxl,
          child: Tooltip(
            message: open ? '收起平台栏' : '展开平台栏',
            child: Material(
              key: BrowseSidebar.toggleKey,
              color: tokens.surfaceRaised,
              borderRadius: AppRadius.allSm,
              child: InkWell(
                onTap: onTap,
                borderRadius: AppRadius.allSm,
                child: Center(child: icon),
              ),
            ),
          ),
        ),
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
///
/// 收起态([compact])把图标撑满 52px rail 的可用宽,展开态保持 22px 图标。
class _PlatformTile extends StatelessWidget {
  const _PlatformTile({
    required this.brand,
    required this.selected,
    required this.tokens,
    this.iconSize = 22,
    this.compact = false,
  });

  final PlatformBrand brand;
  final bool selected;
  final ZishuTokens tokens;
  final double iconSize;
  final bool compact;

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
          avatar: PlatformIcon(id: brand.id, size: iconSize),
          label: const SizedBox.shrink(),
          visualDensity: compact ? VisualDensity.standard : VisualDensity.compact,
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
