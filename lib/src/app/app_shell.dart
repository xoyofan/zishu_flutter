import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../shared/presentation/design_tokens.dart';
import '../shared/presentation/platform_brands.dart';
import '../shared/presentation/widgets/platform_icon.dart';

/// 应用壳层:桌面/平板(>=768)为 44px 顶部导航;
/// 手机(<768)为平台条 + 56px 底部主导航。结构对齐 SFVideoLive
/// `NavSidebar.vue` 的品牌区、中心平台区与右侧工具区。
/// 播放页不套壳。
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.site, required this.child});

  /// 当前选中的平台 id(`all` = 全平台聚合)。
  final String site;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isPhone = MediaQuery.sizeOf(context).width < AppBreakpoints.phone;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isPhone)
            _PlatformStrip(currentSite: site)
          else
            _TopNav(currentSite: site),
          Expanded(child: child),
        ],
      ),
      bottomNavigationBar: isPhone ? _BottomNav(currentSite: site) : null,
    );
  }
}

/// 移动端平台条:竖屏(X < 768)两行网格,对齐 SFVideoLive
/// `responsive-chrome.css:265-369`(`nav-platform-strip__item` flex 1 1 15% →
/// 12 项平分两行、隐藏平台文字、图标 1.75rem、箭头列 1.8rem、不滚动)。
///
/// 每格 = 品牌图标入口(锚点 `platform-tab-{site}`)+ 独立分类箭头(锚点
/// `platform-category-{site}`),各自语义动作分离;平台清单来自
/// `PlatformBrandCatalog.navPlatforms`(每行 6 项,共 2 行)。
class _PlatformStrip extends StatelessWidget {
  const _PlatformStrip({required this.currentSite});

  final String currentSite;

  /// 图标尺寸(对齐 CSS 1.75rem,16px 基准 ≈ 28px)。
  static const double _kIconSize = 28;

  /// 分类箭头列宽(对齐 CSS 1.8rem ≈ 28.8px)。
  static const double _kArrowWidth = 28.8;

  /// 单行高度:图标 + 上下内边距。
  static const double _kRowHeight = 44;

  /// 两行内容高度(单行高 × 2 + 行距)。
  static const double _kContentHeight = _kRowHeight * 2 + 8;

  /// 每行平台数:12 项 → 6 × 2。
  static const int _kColumns = 6;

  @override
  Widget build(BuildContext context) {
    final safeTop = MediaQuery.paddingOf(context).top;
    final platforms = PlatformBrandCatalog.navPlatforms;
    final rows = <Widget>[
      for (int r = 0;
          r < ((platforms.length / _kColumns).ceil());
          r++)
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                for (int c = 0; c < _kColumns; c++)
                  if (r * _kColumns + c < platforms.length)
                    _StripGridCell(
                      brand: platforms[r * _kColumns + c],
                      selected: platforms[r * _kColumns + c].id == currentSite,
                    ),
              ],
            ),
          ),
        ),
    ];
    return Container(
      padding: EdgeInsets.only(top: safeTop),
      decoration: const BoxDecoration(
        color: AppColors.surfaceSoft,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: SizedBox(
        height: _kContentHeight,
        child: Column(children: rows),
      ),
    );
  }
}

/// 平台条单格:图标入口(点击跳平台首页)+ 分类箭头(点击跳平台分类页)。
class _StripGridCell extends StatelessWidget {
  const _StripGridCell({required this.brand, required this.selected});

  final PlatformBrand brand;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        children: [
          Expanded(
            child: Tooltip(
              message: brand.name,
              child: InkWell(
                key: Key('platform-tab-${brand.id}'),
                onTap: () => context.go(_platformRoute(brand.id)),
                hoverColor: AppColors.surfaceRaised,
                child: Container(
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: selected
                        ? brand.color.withValues(alpha: 0.16)
                        : Colors.transparent,
                    border: Border.all(
                      color: selected ? brand.color : Colors.transparent,
                    ),
                    borderRadius: AppRadius.allSm,
                  ),
                  child: Center(
                    child: PlatformIcon(id: brand.id, size: _PlatformStrip._kIconSize),
                  ),
                ),
              ),
            ),
          ),
          Tooltip(
            message: '${brand.name}分类',
            child: InkWell(
              key: Key('platform-category-${brand.id}'),
              onTap: () => context.go(_categoryRoute(brand.id)),
              hoverColor: AppColors.surfaceRaised,
              child: SizedBox(
                width: _PlatformStrip._kArrowWidth,
                child: const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 桌面顶栏:品牌/主导航在左,平台图标居中,工具区在右。
///
/// SFVideoLive 的桌面 `NavSidebar.vue` 使用 44px 高度、30px 品牌图标、
/// 34px 平台 tab 与 36px 级工具点击目标;平台 tab 默认只显示真实品牌图标,
/// 平台名通过 Tooltip 提供,避免 12 个平台文字把中心区域挤变形。
class _TopNav extends StatelessWidget implements PreferredSizeWidget {
  const _TopNav({required this.currentSite});

  final String currentSite;

  @override
  Size get preferredSize => const Size.fromHeight(AppSpacing.topNavHeight);

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final showLabels = width >= AppBreakpoints.desktop;
    return Container(
      height: AppSpacing.topNavHeight,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: Row(
        children: [
          _TopNavLeading(
            currentSite: currentSite,
            showLabels: showLabels,
          ),
          Expanded(
            child: Center(
              child: _PlatformTabs(currentSite: currentSite),
            ),
          ),
          _TopNavTools(showLabels: showLabels),
        ],
      ),
    );
  }
}

class _TopNavLeading extends StatelessWidget {
  const _TopNavLeading({required this.currentSite, required this.showLabels});

  final String currentSite;
  final bool showLabels;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Logo(showLabel: showLabels),
        const SizedBox(width: AppSpacing.xs),
        _NavAction(
          key: const Key('nav-home'),
          icon: Icons.home_rounded,
          label: '首页',
          tooltip: '首页',
          route: '/all',
          active: currentSite == 'all',
          showLabel: showLabels,
        ),
        _NavAction(
          icon: Icons.grid_view_rounded,
          label: '分类',
          tooltip: '分类',
          route: _categoryRoute(currentSite),
          active: false,
          showLabel: showLabels,
        ),
        _NavAction(
          key: const Key('nav-my-category'),
          icon: Icons.star_border_rounded,
          label: '我的分类',
          tooltip: '我的分类',
          route: '/time',
          active: false,
          showLabel: showLabels,
        ),
      ],
    );
  }
}

class _TopNavTools extends StatelessWidget {
  const _TopNavTools({required this.showLabels});

  final bool showLabels;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _NavAction(
          key: const Key('nav-follow'),
          icon: Icons.star_border_rounded,
          label: '我的关注',
          tooltip: '我的关注',
          route: '/follow',
          showLabel: showLabels,
        ),
        _NavAction(
          key: const Key('nav-search'),
          icon: Icons.search_rounded,
          label: '搜索',
          tooltip: '搜索进房',
          route: '/search',
          showLabel: showLabels,
        ),
        _NavAction(
          key: const Key('nav-theme'),
          icon: Icons.dark_mode_outlined,
          label: '深色',
          tooltip: '切换主题',
          showLabel: showLabels,
        ),
        _NavAction(
          key: const Key('nav-settings'),
          icon: Icons.settings_outlined,
          label: '设置',
          tooltip: '设置',
          route: '/settings',
          showLabel: showLabels,
        ),
        _UserAvatar(showLabels: showLabels),
      ],
    );
  }
}

/// 顶栏右侧账号区:对齐 SFVideoLive `NavSidebar.vue` 登录态的头像 + 用户名。
///
/// 当前无真实登录态,渲染圆形头像占位(人形图标),保留 `nav-user` 锚点,
/// hover 有反馈;`showLabels` 时附带「登录」文案。
class _UserAvatar extends StatelessWidget {
  const _UserAvatar({required this.showLabels});

  final bool showLabels;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '账号',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const Key('nav-user'),
          borderRadius: AppRadius.allPill,
          hoverColor: AppColors.surfaceSoft,
          onTap: () {},
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircleAvatar(
                  radius: 14,
                  backgroundColor: AppColors.brand,
                  child: Icon(
                    Icons.person_outline_rounded,
                    size: 16,
                    color: Colors.black87,
                  ),
                ),
                if (showLabels) ...[
                  const SizedBox(width: 5),
                  const Text(
                    '登录',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo({this.showLabel = true});

  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '紫薯直播',
      child: InkWell(
        key: const Key('nav-brand'),
        borderRadius: AppRadius.allMd,
        hoverColor: AppColors.surfaceSoft,
        onTap: () => context.go('/all'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/ui/logo/logo-128.png',
                width: 30,
                height: 30,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.brand,
                    borderRadius: AppRadius.allMd,
                  ),
                  child: const Text(
                    '薯',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              if (showLabel) ...[
                const SizedBox(width: AppSpacing.xs),
                const Text(
                  '紫薯直播',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 桌面主导航动作:36px 级点击目标,hover/active 由 InkWell 负责,
/// 小窗口自动切换为 icon-only,平台名和动作名由 Tooltip 承载。
class _NavAction extends StatelessWidget {
  const _NavAction({
    super.key,
    required this.icon,
    required this.label,
    required this.tooltip,
    this.route,
    this.active = false,
    this.showLabel = false,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final String? route;
  final bool active;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.brand : AppColors.textSecondary;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: AppRadius.allMd,
          hoverColor: AppColors.surfaceSoft,
          onTap: route == null ? null : () => context.go(route!),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: showLabel ? AppSpacing.sm : AppSpacing.xs,
              vertical: 3,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: color),
                if (showLabel) ...[
                  const SizedBox(width: 5),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                      color: color,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlatformTabs extends StatelessWidget {
  const _PlatformTabs({required this.currentSite});

  final String currentSite;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final brand in PlatformBrandCatalog.navPlatforms)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Tooltip(
                message: brand.name,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    key: Key('platform-tab-${brand.id}'),
                    borderRadius: AppRadius.allSm,
                    hoverColor: AppColors.surfaceSoft,
                    onTap: () => context.go(_platformRoute(brand.id)),
                    child: AnimatedContainer(
                      duration: AppMotion.fast,
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: currentSite == brand.id
                            ? AppColors.surfaceRaised
                            : Colors.transparent,
                        border: Border.all(
                          color: currentSite == brand.id
                              ? brand.color
                              : Colors.transparent,
                        ),
                        borderRadius: AppRadius.allSm,
                        boxShadow: currentSite == brand.id
                            ? [
                                BoxShadow(
                                  color: brand.color.withValues(alpha: 0.22),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      child: PlatformIcon(id: brand.id, size: 28),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String _platformRoute(String id) => id == 'all' ? '/all' : '/$id';

String _categoryRoute(String site) => site == 'all' || site.isEmpty
    ? '/all/category'
    : '/$site/category';

/// 手机(<768)底部主导航:56px 高,保留既有 nav-* 锚点契约。
///
/// 7 项对齐 SFVideoLive 移动端底部栏:紫薯 logo / 首页 / 分类 / 关注 / 搜索 /
/// 主题 / 我的。其中 `nav-home`/`nav-follow`/`nav-search`/`nav-settings` 锚点
/// 必须保留(`nav-settings` 挂在「我的」项上,该路由到 `/settings`)。
class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.currentSite});

  final String currentSite;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppSpacing.bottomNavHeight,
      decoration: const BoxDecoration(
        color: AppColors.surfaceSoft,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          _BottomItem(
            key: const Key('nav-brand'),
            leading: SizedBox(
              width: 26,
              height: 26,
              child: Image.asset(
                'assets/ui/logo/logo-128.png',
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: AppColors.brand,
                    shape: BoxShape.circle,
                  ),
                  child: const Text(
                    '薯',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
            label: '',
            route: '/all',
            active: currentSite == 'all',
          ),
          _BottomItem(
            key: const Key('nav-home'),
            leading: _bottomIcon(Icons.home_rounded, currentSite == 'all'),
            label: '首页',
            route: '/all',
            active: currentSite == 'all',
          ),
          _BottomItem(
            key: const Key('nav-category'),
            leading: _bottomIcon(Icons.grid_view_rounded, false),
            label: '分类',
            route: _categoryRoute(currentSite),
            active: false,
          ),
          _BottomItem(
            key: const Key('nav-follow'),
            leading: _bottomIcon(Icons.star_border_rounded, currentSite == 'follow'),
            label: '关注',
            route: '/follow',
            active: currentSite == 'follow',
          ),
          _BottomItem(
            key: const Key('nav-search'),
            leading: _bottomIcon(Icons.search_rounded, false),
            label: '搜索',
            route: '/search',
            active: false,
          ),
          _BottomItem(
            key: const Key('nav-theme'),
            leading: _bottomIcon(Icons.dark_mode_outlined, false),
            label: '主题',
            onTap: () {},
            active: false,
          ),
          _BottomItem(
            key: const Key('nav-settings'),
            leading: _bottomIcon(
              Icons.person_outline_rounded,
              currentSite == 'settings',
            ),
            label: '我的',
            route: '/settings',
            active: currentSite == 'settings',
          ),
        ],
      ),
    );
  }
}

/// 底部导航图标(按选中态着色)。
Widget _bottomIcon(IconData icon, bool active) =>
    Icon(icon, size: 20, color: active ? AppColors.brand : AppColors.textSecondary);

class _BottomItem extends StatelessWidget {
  const _BottomItem({
    super.key,
    required this.leading,
    required this.label,
    this.route,
    required this.active,
    this.onTap,
  });

  final Widget leading;
  final String label;
  final String? route;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.brand : AppColors.textSecondary;
    return Expanded(
      child: InkWell(
        hoverColor: AppColors.surface,
        onTap: onTap ?? (route == null ? null : () => context.go(route!)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            leading,
            if (label.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(label, style: TextStyle(fontSize: 11, color: color)),
            ],
          ],
        ),
      ),
    );
  }
}
