/// 应用根：GetMaterialApp + 左侧 70px 导航（对标 SFVideoLive App.vue + NavSidebar）。
///
/// 路由表（URL 同步由 GetMaterialApp + getPages 在 web 上自动维护）：
/// - `/`                         → redirect `/all`
/// - `/all`                      → 全平台首页（占位，U3）
/// - `/all/category/:key`        → 跨平台分类（占位，U6）
/// - `/:site/category/:cid`      → 站内分类（占位，U6）
/// - `/:site/play/:roomId`       → 播放页（占位，U5）
/// - `/time`                     → 时间轴（占位）
/// - `/settings`                 → 设置（占位，U7）
/// - `/(.*)`                     → 兜底：斜杠穿段 roomId 的播放深链 / 未匹配地址
library;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'theme/design_tokens.dart';
import 'views/play_smoke_view.dart';
import 'views/placeholder_view.dart';

class ZishuApp extends StatelessWidget {
  const ZishuApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: '紫薯直播',
      debugShowCheckedModeBanner: false,
      theme: ZishuTheme.light(),
      darkTheme: ZishuTheme.dark(),
      themeMode: ThemeMode.dark, // web 默认暗色
      defaultTransition: Transition.fade,
      getPages: _routes,
    );
  }
}

/// 路由表。兜底路由 `/(.*)` 必须放最后（Get 按声明顺序首个正则命中生效）。
final List<GetPage> _routes = [
  GetPage(
    name: '/',
    page: () => const _RootRedirectPage(),
    middlewares: [_RootRedirect()],
  ),
  GetPage(
    name: '/all',
    page: () => const ZishuShell(
      child: PlaceholderView(title: '首页', detail: '全平台首页（U3 实现）'),
    ),
  ),
  GetPage(
    name: '/all/category/:key',
    page: () => const _AllCategoryPlaceholder(),
  ),
  GetPage(
    name: '/:site/category/:cid',
    page: () => const _SiteCategoryPlaceholder(),
  ),
  GetPage(
    name: '/:site/play/:roomId',
    page: () => const ZishuShell(child: PlaySmokeView()),
  ),
  GetPage(
    name: '/time',
    page: () => const ZishuShell(
      child: PlaceholderView(title: '时间轴', detail: '时间轴（占位）'),
    ),
  ),
  GetPage(
    name: '/settings',
    page: () => const ZishuShell(
      child: PlaceholderView(title: '设置', detail: '设置（U7 实现）'),
    ),
  ),
  GetPage(name: '/(.*)', page: () => const _FallbackRouter()),
];

/// `/` → `/all`（对标 router.js 的 `/` redirect，未登录态进全平台首页）。
class _RootRedirect extends GetMiddleware {
  // GetMiddleware 的构造函数非常量，这里只能普通构造。
  _RootRedirect();

  @override
  RouteSettings? redirect(String? route) =>
      route == '/' ? const RouteSettings(name: '/all') : null;
}

/// 双保险：middleware 对 web 首载路由若未生效，页面自身兜底跳转 `/all`。
class _RootRedirectPage extends StatelessWidget {
  const _RootRedirectPage();

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (Get.currentRoute == '/' || Get.currentRoute.isEmpty) {
        Get.offNamed('/all');
      }
    });
    return const ZishuShell(
      child: PlaceholderView(title: '紫薯直播', detail: '正在进入首页…'),
    );
  }
}

/// 占位页：跨平台分类。
class _AllCategoryPlaceholder extends StatelessWidget {
  const _AllCategoryPlaceholder();

  @override
  Widget build(BuildContext context) {
    final key = Get.parameters['key'] ?? '';
    return ZishuShell(
      child: PlaceholderView(title: '全平台分类', detail: 'crossKey=$key（U6 实现）'),
    );
  }
}

/// 占位页：站内分类。
class _SiteCategoryPlaceholder extends StatelessWidget {
  const _SiteCategoryPlaceholder();

  @override
  Widget build(BuildContext context) {
    final site = Get.parameters['site'] ?? '';
    final cid = Get.parameters['cid'] ?? '';
    return ZishuShell(
      child: PlaceholderView(
        title: '$site · 分类房间',
        detail: 'site=$site cid=$cid（U6 实现）',
      ),
    );
  }
}

/// 兜底路由：
/// 1. roomId 含 `/` 等穿段字符时 Get 的段内正则不命中，这里从 URL 手工解析出
///    `/{site}/play/{roomId(.+)}` 再渲染播放页（对标 router.js 的 `:id(.+)`），
///    site/roomId 的解析与参数缺失提示由 PlaySmokeView 内部兜底处理；
/// 2. 其余未匹配地址展示「未找到」。
class _FallbackRouter extends StatelessWidget {
  const _FallbackRouter();

  @override
  Widget build(BuildContext context) {
    final path = ModalRoute.of(context)?.settings.name ?? '/';
    final play = RegExp(r'^/([^/]+)/play/(.+)$').hasMatch(path);

    final Widget child;
    if (play) {
      child = const PlaySmokeView();
    } else {
      child = PlaceholderView(title: '未找到', detail: '$path 不在路由表内');
    }
    return ZishuShell(child: child);
  }
}

/// 应用壳：左侧 70px 固定导航 + 主内容区（对标 NavSidebar 信息架构）。
class ZishuShell extends StatelessWidget {
  const ZishuShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          const _NavRail(),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _NavItemSpec {
  const _NavItemSpec(this.label, this.icon, this.route);

  final String label;
  final IconData icon;
  final String route;
}

/// 左侧 70px 导航：顶部品牌 + 首页/时间轴/设置，底部登录/用户占位。
/// 窄于 768 断点时收窄为纯图标（隐藏文字标签）。
class _NavRail extends StatelessWidget {
  const _NavRail();

  static const _topItems = <_NavItemSpec>[
    _NavItemSpec('首页', Icons.home_outlined, '/all'),
    _NavItemSpec('时间轴', Icons.schedule_outlined, '/time'),
    _NavItemSpec('设置', Icons.settings_outlined, '/settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final current = Get.currentRoute;
    final showLabels = !ZishuBreakpoints.isMobile(
      MediaQuery.sizeOf(context).width,
    );
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: ZishuDims.navWidth,
      color: scheme.surface,
      child: SafeArea(
        child: Column(
          children: [
            // 品牌位（对标 nav-brand，M3 换真实 logo）。
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: _NavIcon(
                icon: Icons.circle,
                label: '紫薯',
                active: true,
                showLabel: showLabels,
                activeColor: ZishuColors.primary,
                onTap: () => Get.offNamedUntil('/all', (r) => false),
              ),
            ),
            for (final item in _topItems)
              _NavButton(
                spec: item,
                active: _isActive(current, item.route),
                showLabel: showLabels,
              ),
            const Spacer(),
            _NavButton(
              spec: const _NavItemSpec('登录', Icons.person_outline, ''),
              active: false,
              showLabel: showLabels,
              onTap: () => Get.snackbar('登录', '登录功能待后续任务卡接入'),
            ),
          ],
        ),
      ),
    );
  }

  /// 首页对 `/all` 与跨平台分类子路由保持激活；其余精确匹配。
  bool _isActive(String current, String route) {
    if (route == '/all') {
      return current == '/all' || current.startsWith('/all/category');
    }
    return current == route;
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.spec,
    required this.active,
    required this.showLabel,
    this.onTap,
  });

  final _NavItemSpec spec;
  final bool active;
  final bool showLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = active
        ? ZishuColors.primary
        : Theme.of(context).colorScheme.onSurface;
    return Tooltip(
      message: spec.label,
      child: InkWell(
        onTap: onTap ?? () => Get.toNamed(spec.route),
        borderRadius: BorderRadius.circular(ZishuDims.radiusSm),
        child: Container(
          width: ZishuDims.navWidth,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(spec.icon, size: 22, color: color),
              if (showLabel) ...[
                const SizedBox(height: 2),
                Text(
                  spec.label,
                  style: TextStyle(fontSize: 11, color: color),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 品牌圆标（占位 logo）。
class _NavIcon extends StatelessWidget {
  const _NavIcon({
    required this.icon,
    required this.label,
    required this.active,
    required this.showLabel,
    required this.activeColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final bool showLabel;
  final Color activeColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ZishuDims.radiusSm),
        child: SizedBox(
          width: ZishuDims.navWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 28, color: activeColor),
              if (showLabel) ...[
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: activeColor,
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
