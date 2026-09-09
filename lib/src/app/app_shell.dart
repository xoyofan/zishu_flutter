import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../shared/presentation/design_tokens.dart';
import '../shared/presentation/platform_brands.dart';

/// 应用壳层:44px 顶部导航(Logo + 平台 tabs + 工具区)+ 内容区。
/// 播放页不显示目录 drawer;窄屏断点切换底部导航由 U9 处理。
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.site, required this.child});

  /// 当前选中的平台 id(`all` = 全平台聚合)。
  final String site;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TopNav(currentSite: site),
          Expanded(child: child),
        ],
      ),
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
    // 响应式收缩(对齐 U9 / W12 断点规范与 `.agents/skills/vue-ui-to-flutter`):
    // - <640(compact):Logo 仅图标、隐藏「分类」,给主导航与工具区让位;
    // - 平台 tabs:>=1024 色点+文字,768-1023 仅品牌色点,窄屏继续保留但可横向滚动。
    // 注意:nav-home / nav-follow / nav-search / nav-settings 为测试锚点,任何断点下都必须保留。
    final compact = width < AppBreakpoints.compact;
    // >=768 才显示平台名(窄屏只留品牌色点,避免文字挤占主导航)。
    final tabsWithLabel = width >= AppBreakpoints.phone;

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

  /// 窄屏(<640)只保留图标,避免 Logo 文案挤占主导航。
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
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    return ListView(
      scrollDirection: Axis.horizontal,
      children: [
        for (final brand in PlatformBrandCatalog.navPlatforms.skip(1))
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            child: InkWell(
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
