part of '../app_shell.dart';

/// 桌面顶栏:品牌/主导航在左,平台图标居中,工具区在右。
///
/// SFVideoLive 的桌面 `NavSidebar.vue` 使用 44px 高度、30px 品牌图标、
/// 34px 平台 tab 与 36px 级工具点击目标;平台 tab 默认只显示真实品牌图标,
/// 平台名通过 Tooltip 提供,避免 12 个平台文字把中心区域挤变形。
class _TopNav extends StatelessWidget implements PreferredSizeWidget {
  const _TopNav({
    required this.currentSite,
    required this.onPlatformHover,
    required this.onPlatformHoverEnd,
    required this.onFollowHover,
    required this.onFollowHoverEnd,
    required this.onMyCategoryHover,
    required this.onMyCategoryTap,
    required this.onMyCategoryHoverEnd,
  });

  final String currentSite;

  /// 平台 tab hover → `(平台 id, 触发点中心 x)`;移出触发 800ms 后关闭浮层。
  final void Function(String id, double centerX) onPlatformHover;
  final VoidCallback onPlatformHoverEnd;

  /// 「我的关注」入口 hover → 触发点中心 x。
  final void Function(double centerX) onFollowHover;
  final VoidCallback onFollowHoverEnd;

  /// 「我的分类」入口:hover 打开浮层,点击 toggle(均回传触发点中心 x)。
  final void Function(double centerX) onMyCategoryHover;
  final void Function(double centerX) onMyCategoryTap;
  final VoidCallback onMyCategoryHoverEnd;

  @override
  Size get preferredSize => const Size.fromHeight(AppSpacing.topNavHeight);

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final showLabels = width >= AppBreakpoints.desktop;
    return Container(
      height: AppSpacing.topNavHeight,
      decoration: BoxDecoration(
        color: context.tokens.surface,
        border: Border(bottom: BorderSide(color: context.tokens.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: Row(
        children: [
          _TopNavLeading(
            currentSite: currentSite,
            showLabels: showLabels,
            onMyCategoryHover: onMyCategoryHover,
            onMyCategoryTap: onMyCategoryTap,
            onMyCategoryHoverEnd: onMyCategoryHoverEnd,
          ),
          Expanded(
            child: Center(
              child: _PlatformTabs(
                currentSite: currentSite,
                onHover: onPlatformHover,
                onHoverEnd: onPlatformHoverEnd,
              ),
            ),
          ),
          _TopNavTools(
            showLabels: showLabels,
            onFollowHover: onFollowHover,
            onFollowHoverEnd: onFollowHoverEnd,
          ),
        ],
      ),
    );
  }
}

class _TopNavLeading extends StatelessWidget {
  const _TopNavLeading({
    required this.currentSite,
    required this.showLabels,
    required this.onMyCategoryHover,
    required this.onMyCategoryTap,
    required this.onMyCategoryHoverEnd,
  });

  final String currentSite;
  final bool showLabels;

  /// 「我的分类」:hover 打开浮层,点击 toggle。
  final void Function(double centerX) onMyCategoryHover;
  final void Function(double centerX) onMyCategoryTap;
  final VoidCallback onMyCategoryHoverEnd;

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
          key: const Key('nav-category'),
          icon: Icons.grid_view_rounded,
          label: '分类',
          tooltip: '分类',
          route: _categoryRoute(currentSite),
          showLabel: showLabels,
        ),
        _NavAction(
          key: const Key('nav-my-category'),
          icon: Icons.star_border_rounded,
          label: '我的分类',
          tooltip: '我的分类(收藏常用分类)',
          showLabel: showLabels,
          onTap: onMyCategoryTap,
          onHoverStart: onMyCategoryHover,
          onHoverEnd: onMyCategoryHoverEnd,
        ),
      ],
    );
  }
}

class _TopNavTools extends StatelessWidget {
  const _TopNavTools({
    required this.showLabels,
    required this.onFollowHover,
    required this.onFollowHoverEnd,
  });

  final bool showLabels;
  final void Function(double centerX) onFollowHover;
  final VoidCallback onFollowHoverEnd;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _NavAction(
          key: const Key('nav-follow'),
          icon: Icons.star_border_rounded,
          // 有在播时显示最多 3 个头像堆叠(web `nav-follow-avatars`),
          // 无在播回落星形图标。
          leading: const _NavFollowAvatars(),
          label: '我的关注',
          tooltip: '我的关注',
          route: '/follow',
          showLabel: showLabels,
          onHoverStart: onFollowHover,
          onHoverEnd: onFollowHoverEnd,
        ),
        _NavAction(
          key: const Key('nav-search'),
          icon: Icons.search_rounded,
          label: '搜索',
          tooltip: '搜索进房',
          // 对齐 web:搜索是全局弹框(`SearchDialog.vue`),不再切页面。
          onTap: (_) => openSearchDialog(context),
          showLabel: showLabels,
        ),
        _NavAction(
          key: const Key('nav-time'),
          icon: Icons.timeline_rounded,
          label: '动态',
          tooltip: '动态时间线',
          route: '/timeline',
          showLabel: showLabels,
        ),
        _NavThemeAction(showLabel: showLabels),
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
        // hover 压暗一档是导航品牌块的 web 真源(`.nav-brand:hover{background:var(--bg-soft)}`,
        // DESIGN.md §11.2);焦点另走 focusColor。
        hoverColor: context.tokens.surfaceSoft,
        focusColor: AppStateLayer.focusOf(context.tokens.accent),
        splashColor: AppStateLayer.splashOf(context.tokens.accent),
        highlightColor: AppStateLayer.pressedOf(context.tokens.accent),
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
                    color: context.tokens.accent,
                    borderRadius: AppRadius.allMd,
                  ),
                  child: const Text(
                    '薯',
                    style: TextStyle(
                      color: AppOnBright.white,
                      fontSize: AppFontSize.title,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              if (showLabel) ...[
                const SizedBox(width: AppSpacing.xs),
                Text(
                  '紫薯直播',
                  style: TextStyle(
                    fontSize: AppFontSize.subtitle,
                    fontWeight: FontWeight.w600,
                    color: context.tokens.textPrimary,
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
    this.leading,
    this.onTap,
    this.onHoverStart,
    this.onHoverEnd,
  });

  final IconData icon;
  final String label;

  /// 自定义左侧图形(如「我的关注」的在播头像堆叠);为空时渲染 [icon]。
  final Widget? leading;
  final String tooltip;
  final String? route;
  final bool active;
  final bool showLabel;

  /// 自定义点击(回传触发点中心 x,供浮层定位);为空时按 [route] 跳转。
  final void Function(double centerX)? onTap;

  /// hover 浮层挂钩:进入时回传触发点中心 x(全局坐标),移出时通知关闭。
  final void Function(double centerX)? onHoverStart;
  final VoidCallback? onHoverEnd;

  @override
  Widget build(BuildContext context) {
    final color = active ? context.tokens.accent : context.tokens.textSecondary;
    return Builder(
      builder: (hoverContext) {
        // 触发点中心 x:MouseRegion 与 InkWell 共用同一个 RenderBox 快照。
        RenderBox? box;
        double centerX() {
          final target = box ??= hoverContext.findRenderObject() as RenderBox?;
          if (target == null) return 0;
          final dx = target.localToGlobal(Offset.zero).dx;
          return dx + target.size.width / 2;
        }

        return MouseRegion(
          onEnter: (onHoverStart == null && onTap == null)
              ? null
              : (_) => onHoverStart?.call(centerX()),
          onExit: onHoverEnd == null ? null : (_) => onHoverEnd!(),
          child: Tooltip(
            message: tooltip,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: AppRadius.allMd,
                hoverColor: context.tokens.surfaceSoft,
                focusColor: AppStateLayer.focusOf(context.tokens.accent),
                splashColor: AppStateLayer.splashOf(context.tokens.accent),
                highlightColor: AppStateLayer.pressedOf(context.tokens.accent),
                onTap: onTap != null
                    ? () => onTap!(centerX())
                    : (route == null ? null : () => context.go(route!)),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: showLabel ? AppSpacing.sm : AppSpacing.xs,
                    vertical: 3,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      leading ?? Icon(icon, size: 18, color: color),
                      if (showLabel) ...[
                        const SizedBox(width: 5),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: AppFontSize.bodySecondary,
                            fontWeight: active
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: color,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
