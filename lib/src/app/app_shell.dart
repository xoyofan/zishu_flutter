import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../shared/presentation/design_tokens.dart';
import '../shared/presentation/platform_brands.dart';

/// 应用壳层:桌面/平板(>=768)为 44px 顶部导航(Logo + 平台 tabs + 工具区);
/// 手机(<768,U9)顶部导航不渲染,主导航转为 56px 底部导航,平台切换由
/// 首页内容区顶部的平台筛选 chips(Wrap)承担。播放页不套壳。
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
          if (!isPhone) _TopNav(currentSite: site),
          Expanded(child: child),
        ],
      ),
      bottomNavigationBar: isPhone ? _BottomNav(currentSite: site) : null,
    );
  }
}

class _TopNav extends StatelessWidget implements PreferredSizeWidget {
  const _TopNav({required this.currentSite});

  final String currentSite;

  @override
  Size get preferredSize => const Size.fromHeight(AppSpacing.topNavHeight);

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    // 响应式收缩(U9/W12 断点规范):
    // - 平台 tab:>=1024 色点+文字;768–1023 仅色点(icon-only),平台名由
    //   Tooltip 承载;
    // - <1024 的 768+ 段同时收敛 Logo 文案与「分类」,保持 800×600 小窗可用;
    // - nav-home/nav-follow/nav-search/nav-settings 为测试锚点,任何断点保留。
    final compact = width < AppBreakpoints.tablet;
    final tabsWithLabel = width >= AppBreakpoints.tablet;

    return Container(
      height: AppSpacing.topNavHeight,
      decoration: const BoxDecoration(
        color: AppColors.surfaceSoft,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Row(
        children: [
          _Logo(showLabel: !compact),
          SizedBox(width: compact ? AppSpacing.sm : AppSpacing.xl),
          // 测试锚点:左侧「首页」入口(nav-home)。
          _NavItem(
            key: const Key('nav-home'),
            label: '首页',
            route: '/all',
            active: currentSite == 'all',
          ),
          if (!compact)
            _NavItem(label: '分类', route: '/all/category', active: false),
          SizedBox(width: compact ? AppSpacing.xs : AppSpacing.lg),
          Expanded(
            child: _PlatformTabs(
              currentSite: currentSite,
              showLabel: tabsWithLabel,
            ),
          ),
          // 测试锚点:右侧工具区按钮(nav-follow / nav-search / nav-settings)。
          _IconTool(
            key: const Key('nav-follow'),
            icon: Icons.favorite_border_rounded,
            tooltip: '我的关注',
            route: '/follow',
          ),
          _IconTool(
            key: const Key('nav-search'),
            icon: Icons.search_rounded,
            tooltip: '搜索',
            route: '/search',
          ),
          _IconTool(
            key: const Key('nav-settings'),
            icon: Icons.settings_outlined,
            tooltip: '设置',
            route: '/settings',
          ),
        ],
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo({this.showLabel = true});

  /// 窄视口(<1024)只保留图标,避免 Logo 文案挤占主导航。
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: AppColors.brand,
            borderRadius: BorderRadius.circular(6),
          ),
          alignment: Alignment.center,
          child: const Text(
            '薯',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: Colors.black87,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        if (showLabel)
          const Text(
            '紫薯直播',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
      ],
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({super.key, required this.label, required this.route, required this.active});

  final String label;
  final String route;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.lg),
      child: InkWell(
        borderRadius: AppRadius.allSm,
        onTap: () => context.go(route),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: active ? FontWeight.w700 : FontWeight.w400,
              color: active ? AppColors.brand : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _PlatformTabs extends StatelessWidget {
  const _PlatformTabs({required this.currentSite, required this.showLabel});

  final String currentSite;

  /// >=1024 显示平台名;768–1023 仅品牌色点(U9 icon-only 收缩)。
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    return ListView(
      scrollDirection: Axis.horizontal,
      children: [
        for (final brand in PlatformBrandCatalog.navPlatforms.skip(1))
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            child: Tooltip(
              // U9:icon-only 断点下平台名由 Tooltip 承载(显示文字时同样保留,
              // 无副作用)。W12 验收断言 Tooltip(message == 平台名)。
              message: brand.name,
              child: InkWell(
                // 测试锚点:顶导航平台 tab。W12 契约 key platform-tab-{site}
                // 由本组件持有;首页内容区 chips 在 >=768 时改用
                // home-platform-chip-{site},保证该 key 全树唯一。
                key: Key('platform-tab-${brand.id}'),
                borderRadius: AppRadius.allSm,
                onTap: () => context.go('/${brand.id}'),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: AppRadius.allSm,
                    border: Border(
                      bottom: BorderSide(
                        color: currentSite == brand.id ? brand.color : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(color: brand.color, shape: BoxShape.circle),
                      ),
                      if (showLabel) ...[
                        const SizedBox(width: 5),
                        Text(
                          brand.name,
                          style: TextStyle(
                            fontSize: 13,
                            color: currentSite == brand.id
                                ? AppColors.textPrimary
                                : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _IconTool extends StatelessWidget {
  const _IconTool({super.key, required this.icon, required this.tooltip, this.route});

  final IconData icon;
  final String tooltip;
  final String? route;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: 19, color: AppColors.textSecondary),
      onPressed: route == null ? null : () => context.go(route!),
    );
  }
}

/// 手机(<768)底部主导航(U9):56px 高,首页/关注/搜索/设置。
/// nav-* 测试锚点由顶部导航迁移至此(W9 navVisible 断言仍成立:完整在视口内)。
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
            key: const Key('nav-home'),
            icon: Icons.home_rounded,
            label: '首页',
            route: '/all',
            active: currentSite == 'all',
          ),
          _BottomItem(
            key: const Key('nav-follow'),
            icon: Icons.favorite_border_rounded,
            label: '关注',
            route: '/follow',
            active: currentSite == 'follow',
          ),
          _BottomItem(
            key: const Key('nav-search'),
            icon: Icons.search_rounded,
            label: '搜索',
            route: '/search',
            active: false,
          ),
          _BottomItem(
            key: const Key('nav-settings'),
            icon: Icons.settings_outlined,
            label: '设置',
            route: '/settings',
            active: currentSite == 'settings',
          ),
        ],
      ),
    );
  }
}

class _BottomItem extends StatelessWidget {
  const _BottomItem({
    super.key,
    required this.icon,
    required this.label,
    required this.route,
    required this.active,
  });

  final IconData icon;
  final String label;
  final String route;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.brand : AppColors.textSecondary;
    return Expanded(
      child: InkWell(
        onTap: () => context.go(route),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 11, color: color)),
          ],
        ),
      ),
    );
  }
}
