import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:live_parser/live_parser.dart';

import '../../../shared/domain/category_display.dart';
import '../../../shared/presentation/design_tokens.dart';
import '../../../shared/presentation/platform_brands.dart';
import '../../../shared/presentation/widgets/platform_icon.dart';
import '../../../shared/presentation/zishu_tokens.dart';
import '../../follow/application/follow_provider.dart';
import '../../follow/widgets/follow_common.dart';
import '../application/browse_provider.dart';
import '../application/sidebar_pref_provider.dart';

/// 桌面首页常驻左侧栏:可折叠 rail(收起 52px ↔ 展开 220px)。
///
/// 对齐 SFVideoLive 桌面首页的 `DirectoryDrawer.vue`(mumu 分支),逐项复刻:
/// - 收藏星区(`__follow-wrap`):64px 行 + 36px 金色实心星,底部分隔线;
/// - 平台 tab 网格(`__platform-tabs`):38.4px 方形 tab + 32px 图标,Wrap 流式
///   排布,非选中无边框透明底,选中金色边框 + 金色 12% 底;
/// - 分类网格(`__cat-grid`):2 列(minmax(80px,1fr) 在 220px 抽屉下的落位),
///   条目居中、fill 底、11.5px 最多 2 行,active 金边 + 金 12% 底;
/// - 开合按钮(`__toggle`):13.6x44 细长竖条,仅右侧圆角,贴抽屉右缘垂直居中。
///
/// 开合控件由左栏自身用 [Stack] 叠加渲染;锚点 [Key('browse-sidebar-toggle')]
/// 用于测试与可达性。平台入口锚点 [home-platform-chip-{id}] 始终唯一命中
/// (收起态 52px 竖列 / 展开态 tab 网格),分类树锚点 [browse-sidebar-cat-{cid}]
/// 仅展开态渲染。分类数据来自 [browseCategoriesProvider],不新造硬编码表。
class BrowseSidebar extends ConsumerWidget {
  const BrowseSidebar({super.key, required this.site});

  /// 当前平台 id(`all` = 全平台聚合)。
  final String site;

  /// 展开态宽度,对齐参考实现 `--directory-drawer-width`。
  static const double width = AppDirectoryDrawer.width;

  /// 收起态宽度,对齐参考实现 `--directory-rail-width`。
  static const double railWidth = AppDirectoryDrawer.railWidth;

  /// 开合按钮的测试锚点。
  static const Key toggleKey = Key('browse-sidebar-toggle');

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
      // 参考实现:背景 --sidebar-bg + 右缘 1px --chrome-border。
      decoration: BoxDecoration(
        color: tokens.surfaceSoft,
        border: Border(right: BorderSide(color: tokens.border)),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: open
                ? _ExpandedContent(site: site, categoriesAsync: categoriesAsync)
                : _RailContent(site: site),
          ),
          // 右缘中央开合按钮:细长竖条,贴在面板右边缘(中部)。
          Positioned(
            top: 0,
            bottom: 0,
            right: 0,
            child: _ToggleRail(
              open: open,
              tokens: tokens,
              onTap: () => ref.read(sidebarOpenProvider.notifier).toggle(),
            ),
          ),
        ],
      ),
    );
  }
}

/// 展开态内容:收藏星区 + 平台 tab 网格 + 分类网格(参考实现自上而下三段)。
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
        _FollowRow(tokens: tokens),
        _PlatformTabs(site: site, tokens: tokens),
        Expanded(
          child: _CategoryTree(site: site, categoriesAsync: categoriesAsync),
        ),
      ],
    );
  }
}

/// 收藏星区(`__follow-wrap`):64px 行 + 36px 金色实心星,点击进入关注页。
///
/// 参考实现有关注时渲染头像堆叠;无关注时显示星标入口。
class _FollowRow extends ConsumerWidget {
  const _FollowRow({required this.tokens});

  final ZishuTokens tokens;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(followProvider);
    final live = entries.where((entry) => entry.isLive).take(3).toList();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.go('/follow'),
        child: Container(
          height: AppDirectoryDrawer.followRowHeight,
          padding: const EdgeInsets.only(
            left: AppDirectoryDrawer.followPadLeft,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: live.isEmpty
                ? Icon(
                    Icons.star_rounded,
                    size: AppDirectoryDrawer.followIconSize,
                    color: tokens.brand,
                  )
                : _FollowAvatarStack(entries: live),
          ),
        ),
      ),
    );
  }
}

class _FollowAvatarStack extends StatelessWidget {
  const _FollowAvatarStack({required this.entries});

  final List<FollowEntry> entries;

  @override
  Widget build(BuildContext context) {
    const size = AppDirectoryDrawer.followAvatarSize;
    const overlap = AppDirectoryDrawer.followAvatarOverlap;
    return SizedBox(
      width: size + (entries.length - 1) * (size - overlap),
      height: size,
      child: Stack(
        children: [
          for (var index = 0; index < entries.length; index++)
            Positioned(
              left: index * (size - overlap),
              child: ClipOval(
                child: FollowCoverImage(
                  cover: entries[index].room.cover,
                  fallbackLabel: entries[index].room.anchorName,
                  width: size,
                  height: size,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 展示最多 3 个开播关注头像,头像重叠约 33%。
/// 收起态内容:平台图标竖列(单列,无文字),对齐参考
/// `directory-drawer__rail-platform`(全宽按钮、竖直 padding .5rem、图标 32px)。
class _RailContent extends StatelessWidget {
  const _RailContent({required this.site});

  final String site;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      children: [
        for (final brand in PlatformBrandCatalog.navigationPlatforms)
          _PlatformTab(
            brand: brand,
            selected: brand.id == site,
            tokens: tokens,
            size: AppDirectoryDrawer.platformIconSize,
            fullWidth: true,
          ),
      ],
    );
  }
}

/// 右缘中央的开合按钮:收起时朝右(展开),展开时朝左(收起)。
///
/// 对齐参考 `__toggle`:0.85rem x 44px 细长竖条,仅右侧圆角,贴抽屉右缘。
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
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.horizontal(
        right: Radius.circular(AppRadius.sm),
      ),
    );
    return Align(
      alignment: Alignment.centerRight,
      child: SizedBox(
        width: AppDirectoryDrawer.toggleWidth,
        height: AppDirectoryDrawer.toggleHeight,
        child: Tooltip(
          message: open ? '收起平台栏' : '展开平台栏',
          child: Material(
            key: BrowseSidebar.toggleKey,
            color: tokens.surfaceRaised,
            shape: shape,
            child: InkWell(
              onTap: onTap,
              customBorder: shape,
              child: Icon(
                open ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
                size: 12,
                color: tokens.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 平台 tab 网格(`__platform-tabs`):Wrap 流式排布 + 底部分隔线。
class _PlatformTabs extends StatelessWidget {
  const _PlatformTabs({required this.site, required this.tokens});

  final String site;
  final ZishuTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: AppDirectoryDrawer.platformPadV,
        horizontal: AppDirectoryDrawer.platformPadH,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      child: Wrap(
        spacing: AppDirectoryDrawer.platformGap,
        runSpacing: AppDirectoryDrawer.platformGap,
        children: [
          for (final brand in PlatformBrandCatalog.navigationPlatforms)
            _PlatformTab(
              brand: brand,
              selected: brand.id == site,
              tokens: tokens,
              size: AppDirectoryDrawer.platformTabSize,
            ),
        ],
      ),
    );
  }
}

/// 单个平台入口:图标型 FilterChip,承载 [home-platform-chip-{id}] 锚点。
///
/// 对齐参考 `__platform-tab` / `__rail-platform`:非选中无边框透明底,
/// 选中金色边框 + 金色 12% 底;[fullWidth] 用于收起态(全宽按钮)。
class _PlatformTab extends StatelessWidget {
  const _PlatformTab({
    required this.brand,
    required this.selected,
    required this.tokens,
    required this.size,
    this.fullWidth = false,
  });

  final PlatformBrand brand;
  final bool selected;
  final ZishuTokens tokens;

  /// tab 容器边长(展开态 38.4 / 收起态图标 32)。
  final double size;

  /// 收起态:占满 rail 行宽(参考 `__rail-platform` 全宽按钮)。
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: brand.name,
      child: SizedBox(
        width: fullWidth ? double.infinity : size,
        height: size,
        child: FilterChip(
          // 测试锚点:定位/点击平台入口(前缀同原内容区 chips,见 [BrowseSidebar])。
          key: Key('home-platform-chip-${brand.id}'),
          selected: selected,
          showCheckmark: false,
          avatar: PlatformIcon(
            id: brand.id,
            size: AppDirectoryDrawer.platformIconSize,
          ),
          label: const SizedBox.shrink(),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: EdgeInsets.zero,
          labelPadding: EdgeInsets.zero,
          backgroundColor: Colors.transparent,
          selectedColor: tokens.accent.withValues(
            alpha: AppDirectoryDrawer.activeChipAlpha,
          ),
          checkmarkColor: tokens.accent,
          side: selected ? BorderSide(color: tokens.accent) : BorderSide.none,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.allSm),
          onSelected: (_) =>
              context.go(brand.id == 'all' ? '/all' : '/${brand.id}'),
        ),
      ),
    );
  }
}

/// 下段:分类网格(2 列),数据来自 [browseCategoriesProvider]。
///
/// 对齐参考 `__cat-grid`(auto-fill minmax(80px,1fr) 在 220px 抽屉下为 2 列):
/// 条目居中、fill 底、无边框;active 金边 + 金字 + 金 12% 底;空数据时
/// 显示参考实现的空态文案。
class _CategoryTree extends StatelessWidget {
  const _CategoryTree({required this.site, required this.categoriesAsync});

  final String site;
  final AsyncValue<CategoryResult> categoriesAsync;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return switch (categoriesAsync) {
      AsyncValue(:final value?) =>
        value.groups.isEmpty
            ? _DrawerHint(text: '该平台暂无分类', tokens: tokens)
            : GridView.count(
                padding: const EdgeInsets.fromLTRB(
                  AppDirectoryDrawer.catPadH,
                  AppDirectoryDrawer.catPadTop,
                  AppDirectoryDrawer.catPadH,
                  AppDirectoryDrawer.catPadBottom,
                ),
                crossAxisCount: 2,
                mainAxisSpacing: AppDirectoryDrawer.catGapMain,
                crossAxisSpacing: AppDirectoryDrawer.catGapCross,
                // 220px 抽屉、8.8px 左右内边距下条目宽约 99.4px;参考条目
                // min-height 20.8px,据此推 aspect 使默认行高一致。
                childAspectRatio: 99.4 / AppDirectoryDrawer.catItemHeight,
                children: [
                  for (final group in value.groups)
                    for (final item in group.items)
                      _CategoryLeaf(site: site, cid: item.cid, name: item.name),
                ],
              ),
      // 加载中/出错时折叠分类网格,不阻塞房间网格渲染。
      _ => const SizedBox.shrink(),
    };
  }
}

/// 抽屉空态/加载态文案(参考 `__hint`:居中、.78rem、muted)。
class _DrawerHint extends StatelessWidget {
  const _DrawerHint({required this.text, required this.tokens});

  final String text;
  final ZishuTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.md,
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: context.textCaption.copyWith(color: tokens.textSecondary),
        ),
      ),
    );
  }
}

/// 分类条目(`__cat-item`):fill 底、居中文字 11.5px 最多 2 行。
///
/// 参考 `__cat-item--active` 的金边高亮态暂未接线:当前侧栏仅首页渲染,
/// 点分类即跳转独立分类页(侧栏不在屏),无命中窗口;待侧栏常驻后再接。
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
    final shape = RoundedRectangleBorder(borderRadius: AppRadius.allSm);
    return Material(
      color: tokens.surfaceRaised,
      shape: shape,
      child: InkWell(
        key: Key('browse-sidebar-cat-$cid'),
        onTap: () => context.go(
          site == 'all' ? '/all/category/$cid' : '/$site/category/$cid',
        ),
        customBorder: shape,
        child: Align(
          alignment: Alignment.center,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1.92),
            child: Text(
              // 跨平台统一中文分类名:命中映射用 canonical 名,否则回落平台原名。
              displayCategoryName(site, name, cid),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.textCaption.copyWith(
                fontSize: AppDirectoryDrawer.catFontSize,
                height: 1.15,
                color: tokens.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
