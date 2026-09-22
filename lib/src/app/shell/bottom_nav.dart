part of '../app_shell.dart';

/// 手机(<768)底部主导航:56px 高,保留既有 nav-* 锚点契约。
///
/// 8 项对齐 SFVideoLive 移动端底部栏(真源 360×640 / 640×800 截图):
/// 紫薯 logo / 首页 / 分类 / 我的分类 / 关注 / 搜索 / 主题 / 我的。
/// 其中 `nav-home`/`nav-follow`/`nav-search`/`nav-settings` 锚点必须保留
/// (`nav-settings` 挂在「我的」项上,该路由到 `/settings`)。
///
/// 「动态」(/timeline)不再占底栏项 —— 真源底栏没有它(2026-09-21 截图核对),
/// 桌面顶栏 `nav-time` 仍是它的入口(见 `shell/top_nav.dart`);
/// 路由可达性由 `test/ui/workflows/shell_mobile_align_test.dart` 钉死。
class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.currentSite});

  final String currentSite;

  @override
  Widget build(BuildContext context) {
    return Container(
      // 测试锚点:移动底栏容器(桌面顶栏形态下不存在)。
      key: const Key('bottom-nav'),
      height: AppSpacing.bottomNavHeight,
      decoration: BoxDecoration(
        color: context.tokens.surfaceSoft,
        border: Border(top: BorderSide(color: context.tokens.border)),
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
                  decoration: BoxDecoration(
                    color: context.tokens.accent,
                    shape: BoxShape.circle,
                  ),
                  child: const Text(
                    '薯',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: AppFontSize.subtitle,
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
            leading: _bottomIcon(
              Icons.home_rounded,
              currentSite == 'all',
              context.tokens,
            ),
            label: '首页',
            route: '/all',
            active: currentSite == 'all',
          ),
          _BottomItem(
            key: const Key('nav-category'),
            leading: _bottomIcon(
              Icons.grid_view_rounded,
              false,
              context.tokens,
            ),
            label: '分类',
            route: _categoryRoute(currentSite),
            active: false,
          ),
          _BottomMyCategoryItem(currentSite: currentSite),
          _BottomItem(
            key: const Key('nav-follow'),
            leading: const _NavFollowAvatars(
              size: _NavFollowAvatars.bottomSize,
            ),
            label: '关注',
            route: '/follow',
            active: currentSite == 'follow',
          ),
          _BottomItem(
            key: const Key('nav-search'),
            leading: _bottomIcon(Icons.search_rounded, false, context.tokens),
            label: '搜索',
            // 与顶栏同源:搜索是全局弹框,不切页面。
            onTap: () => openSearchDialog(context),
            active: false,
          ),
          const _BottomThemeItem(),
          _BottomItem(
            key: const Key('nav-settings'),
            leading: _bottomIcon(
              Icons.person_outline_rounded,
              currentSite == 'settings',
              context.tokens,
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
Widget _bottomIcon(IconData icon, bool active, ZishuTokens tokens) =>
    Icon(icon, size: 20, color: active ? tokens.accent : tokens.textSecondary);

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
    final color = active ? context.tokens.accent : context.tokens.textSecondary;
    return Expanded(
      child: InkWell(
        hoverColor: context.tokens.surface,
        onTap: onTap ?? (route == null ? null : () => context.go(route!)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            leading,
            if (label.isNotEmpty) ...[
              const SizedBox(height: 2),
              // 8 项挤在 360px 宽下时,靠 scaleDown 收敛而不是溢出
              // (「我的分类」4 字在 40px 槽位里必须缩)。
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: TextStyle(fontSize: AppFontSize.caption, color: color),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 底栏「我的分类」项:桌面走 hover 浮层,触屏没有 hover —— 直接开管理弹窗
/// (与顶栏 hover 浮层里的「管理分类」是同一个弹窗,不是另一套实现)。
class _BottomMyCategoryItem extends StatelessWidget {
  const _BottomMyCategoryItem({required this.currentSite});

  final String currentSite;

  @override
  Widget build(BuildContext context) {
    return _BottomItem(
      key: const Key('nav-my-category'),
      leading: _bottomIcon(Icons.category_outlined, false, context.tokens),
      label: '我的分类',
      active: false,
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) => _MyCategoryManageDialog(site: currentSite),
      ),
    );
  }
}
