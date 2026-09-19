import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:window_manager/window_manager.dart';

import '../features/anchor/views/anchor_view.dart';
import '../features/anchor/views/timeline_view.dart';
import '../features/browse/views/category_view.dart';
import '../features/browse/views/home_view.dart';
import '../features/dev/views/parse_benchmark_view.dart';
import '../features/follow/views/follow_view.dart';
import '../features/follow/views/settings_view.dart';
import '../features/user/views/user_credentials_view.dart';
import '../features/play/application/play_provider.dart';
import '../features/play/application/play_screen_provider.dart';
import '../features/play/views/play_view.dart';
import '../shared/application/auth_provider.dart';
import '../shared/presentation/design_tokens.dart';
import '../shared/presentation/platform_brands.dart';
import '../shared/presentation/zishu_tokens.dart';
import 'app_shell.dart';

/// 路由语义与 SFVideoLive 对齐(implementation-plan 6.3)。
/// route 参数只存 site/id/cid,不传大型对象。

/// 启动路由:exe 命令行 `--route <path>` 指定初始路由,供真机自动化验证
/// 直达目标页面(普通启动无此参数,行为不变)。Flutter 桌面下命令行参数经
/// `main(List<String> args)` 注入,由 [configure] 在启动最早期登记。
class StartupRoute {
  static String value = '/all';

  static void configure(List<String> args) {
    final i = args.indexOf('--route');
    if (i >= 0 && i + 1 < args.length && args[i + 1].startsWith('/')) {
      value = args[i + 1];
    }
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: StartupRoute.value,
    // 未知路由兜底:参考实现有独立 404 入口,桌面端至少不能白屏。
    errorBuilder: (context, state) => _RouteFallback(uri: state.uri.toString()),
    routes: [
      // 根路径:对齐 web `redirect: isLoggedIn ? '/follow' : '/all'`。
      // 登录态**恢复中/匿名**一律回退 `/all`,不阻塞启动(store 未就绪时读到的
      // 就是 restoring,行为与"未登录"一致,不会闪进关注页再跳回)。
      GoRoute(
        path: '/',
        redirect: (_, _) =>
            ref.read(authProvider).phase == AuthPhase.authenticated
            ? '/follow'
            : '/all',
      ),
      // ---- legacy 深链兼容(web 有一整套 `/watch/*` 与 `/platform/*`)----
      // 旧版/网页版分享出来的 URL 直接打开不再落到 404。
      GoRoute(
        path: '/watch/:site/play/:id',
        redirect: (_, state) =>
            '/${state.pathParameters['site']}/play/${state.pathParameters['id']}',
      ),
      GoRoute(
        path: '/watch/:site/category/:cid',
        redirect: (_, state) =>
            '/${state.pathParameters['site']}/category/'
            '${state.pathParameters['cid']}',
      ),
      GoRoute(
        path: '/watch/:site/:room',
        redirect: (_, state) =>
            '/${state.pathParameters['site']}/play/${state.pathParameters['room']}',
      ),
      GoRoute(
        path: '/watch/:site',
        redirect: (_, state) => '/${state.pathParameters['site']}',
      ),
      GoRoute(
        path: '/platform/:site',
        redirect: (_, state) => '/${state.pathParameters['site']}',
      ),
      // ---- 固定路由(声明在 /:site 之前,保证优先匹配)----
      GoRoute(
        path: '/follow',
        pageBuilder: (_, state) =>
            _shellPage(state, 'all', const FollowView(), title: '我的关注'),
      ),
      // `/time` 语义对齐 web(`router.js` → `TimeView.vue`):解析耗时基准页
      // (冷解析 vs 缓存命中的客户端墙钟对比),**不是**动态时间线。
      GoRoute(
        path: '/time',
        pageBuilder: (_, state) => _shellPage(
          state,
          'all',
          const ParseBenchmarkView(),
          title: '解析耗时',
        ),
      ),
      // 动态时间线是本仓私有页面(web 无对应路由),从 `/time` 让位到 `/timeline`,
      // 顶/底栏「动态」入口同步指向它。
      GoRoute(
        path: '/timeline',
        pageBuilder: (_, state) =>
            _shellPage(state, 'all', const TimelineView(), title: '动态时间线'),
      ),
      GoRoute(
        path: '/settings',
        pageBuilder: (_, state) =>
            _shellPage(state, 'all', const SettingsView(), title: '设置'),
      ),
      // 用户/平台凭证页:保存 YouTube / 小红书 等平台的登录态 cookie/token
      // (web 的 `/user` 只是弹登录框;桌面端收敢成一页统一管理)。
      GoRoute(
        path: '/user',
        pageBuilder: (_, state) =>
            _shellPage(state, 'all', const UserCredentialsView(), title: '平台凭证'),
      ),
      // 搜索已改为全局对话框(见 features/search/widgets/search_dialog.dart):
      // `/search` 与 web 一样不再承载页面,保留深链兼容 → 重定向到平台首页。
      // 回 `/all` 而非 web 的 `/douyu`:本仓导航以「全平台」为默认入口,且
      // `/douyu` 在关闭该平台能力时会再被守卫弹回 /all,少一跳。
      GoRoute(path: '/search', redirect: (_, _) => '/all'),
      GoRoute(
        path: '/all',
        pageBuilder: (_, state) =>
            _shellPage(state, 'all', const HomeView(site: 'all'), title: '全平台首页'),
      ),
      // 分类落地页(不带子分类):对齐 SFVideoLive `/${site}/category`,
      // 进入后由 CategoryView 默认选中第一组。
      GoRoute(
        path: '/all/category',
        pageBuilder: (_, state) =>
            _shellPage(state, 'all', const CategoryView(site: 'all'), title: '跨平台分类'),
      ),
      GoRoute(
        path: '/all/category/:key',
        pageBuilder: (_, state) => _shellPage(
          state,
          'all',
          CategoryView(site: 'all', categoryKey: state.pathParameters['key']),
          title: '跨平台分类',
        ),
      ),
      // 播放页同样套应用壳层(对齐参考实现:`AppLayout` 包裹 `PlayView`,
      // 顶栏在播放页常驻);沉浸态(网页全屏/全屏/画中画)由 _PlayRoute
      // 收起 chrome,视频占满窗口。
      //
      // `:id(.+)` 允许斜杠:粘贴整条直播间链接(`https://www.douyu.com/63136`)
      // 会作为一段路径进来,不允许斜杠时根本匹配不到(web 同样是 `:id(.+)`)。
      GoRoute(
        path: '/:site/play/:id(.+)',
        redirect: (_, state) {
          final site = state.pathParameters['site']!;
          final id = state.pathParameters['id']!;
          final inferred = siteHintFromInput(id);
          // 输入里带了明确的平台域名,但与路由 site 不符 → 纠正到真实平台
          // (对齐 web `inferPlaySiteForRoom` 的 URL hints 分支;不认识的输入
          // 一律不动,不做猜测)。
          return inferred.isNotEmpty && inferred != site
              ? '/$inferred/play/${Uri.encodeComponent(id)}'
              : null;
        },
        pageBuilder: (_, state) => NoTransitionPage(
          key: state.pageKey,
          child: _PlayRoute(
            site: state.pathParameters['site']!,
            roomId: state.pathParameters['id']!,
          ),
        ),
      ),
      GoRoute(
        path: '/:site/anchor/:id',
        pageBuilder: (_, state) => _shellPage(
          state,
          state.pathParameters['site']!,
          AnchorView(
            site: state.pathParameters['site']!,
            anchorId: state.pathParameters['id']!,
          ),
          title: '主播主页',
        ),
      ),
      GoRoute(
        path: '/:site/category',
        redirect: (_, state) =>
            PlatformBrandCatalog.supportsBrowse(state.pathParameters['site']!)
            ? null
            : '/all',
        pageBuilder: (_, state) {
          final site = state.pathParameters['site']!;
          return _shellPage(
            state,
            site,
            CategoryView(site: site),
            title: '${_siteLabel(site)} · 分类',
          );
        },
      ),
      GoRoute(
        path: '/:site/category/:cid',
        redirect: (_, state) =>
            PlatformBrandCatalog.supportsBrowse(state.pathParameters['site']!)
            ? null
            : '/all',
        pageBuilder: (_, state) {
          final site = state.pathParameters['site']!;
          return _shellPage(
            state,
            site,
            CategoryView(site: site, cid: state.pathParameters['cid']),
            title: '${_siteLabel(site)} · 分类',
          );
        },
      ),
      GoRoute(
        path: '/:site',
        redirect: (_, state) =>
            PlatformBrandCatalog.supportsBrowse(state.pathParameters['site']!)
            ? null
            : '/all',
        pageBuilder: (_, state) {
          final site = state.pathParameters['site']!;
          return _shellPage(
            state,
            site,
            HomeView(site: site),
            title: _siteLabel(site),
          );
        },
      ),
    ],
  );
});

/// 除播放页外的页面都包在应用壳层里。
Page<dynamic> _shellPage(
  GoRouterState state,
  String site,
  Widget child, {
  required String title,
}) => NoTransitionPage(
  key: state.pageKey,
  child: _WindowTitle(
    title: '$title · $_kAppTitle',
    child: AppShell(site: site, child: child),
  ),
);

/// 播放页宿主:壳层 + 播放页。
///
/// 沉浸态(网页全屏/全屏/画中画)收 chrome 的判定放在路由层,由
/// [playScreenProvider] 单源驱动 —— 播放页内部不需要知道壳层是否存在。
/// 窗口标题取**房间标题**(对齐 web 播放页用 `displayTitle` 覆盖 document.title),
/// 解析完成前先用「直播间」占位。
class _PlayRoute extends ConsumerWidget {
  const _PlayRoute({required this.site, required this.roomId});

  final String site;
  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 必须 watch(而非 read):chrome 显隐要随呈现态切换立即重建。
    final chromeHidden = ref.watch(playScreenProvider).hidesChrome;
    final roomTitle = ref.watch(
      playControllerProvider((site: site, roomId: roomId)),
    ).value?.payload?.title;
    final title = roomTitle == null || roomTitle.trim().isEmpty
        ? '${_siteLabel(site)} · 直播间'
        : roomTitle.trim();
    return _WindowTitle(
      title: '$title · $_kAppTitle',
      child: AppShell(
        site: site,
        chromeHidden: chromeHidden,
        child: PlayView(site: site, roomId: roomId),
      ),
    );
  }
}

/// 桌面窗口标题同步。
///
/// 参考实现用路由 `meta.title` 更新 `document.title`(播放页用房间标题覆盖);
/// 桌面端等价物是窗口标题。非桌面平台(`window_manager` 无实现 / VM 测试)
/// 静默跳过 —— 标题是增强项,失败绝不冒泡到 UI。
class _WindowTitle extends StatefulWidget {
  const _WindowTitle({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  State<_WindowTitle> createState() => _WindowTitleState();
}

class _WindowTitleState extends State<_WindowTitle> {
  @override
  void initState() {
    super.initState();
    unawaited(_applyWindowTitle(widget.title));
  }

  @override
  void didUpdateWidget(_WindowTitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.title != widget.title) {
      unawaited(_applyWindowTitle(widget.title));
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

Future<void> _applyWindowTitle(String title) async {
  try {
    await windowManager.setTitle(title);
  } catch (_) {
    // Web/Android/单测环境无 window_manager 原生实现:忽略。
  }
}

/// 未知路由兜底页(GoRouter.errorBuilder):给出可见的反馈与一键回到首页。
class _RouteFallback extends StatelessWidget {
  const _RouteFallback({required this.uri});

  final String uri;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Scaffold(
      backgroundColor: tokens.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.explore_off_outlined, size: 40, color: tokens.textSecondary),
            const SizedBox(height: AppSpacing.md),
            Text(
              '页面不存在',
              style: AppTypography.title.copyWith(color: tokens.textPrimary),
            ),
            const SizedBox(height: AppSpacing.xs),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(
                uri,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AppTypography.caption.copyWith(color: tokens.textSecondary),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              key: const Key('route-fallback-home'),
              onPressed: () => context.go('/all'),
              child: const Text('回到首页'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 应用名(窗口标题后缀,与 MaterialApp.title 一致)。
const String _kAppTitle = '紫薯直播';

/// 平台显示名(未收录平台回落 id 本身)。
String _siteLabel(String site) {
  if (site == 'all') return '全平台';
  return PlatformBrandCatalog.byId(site)?.name ?? site;
}

/// 从房间入参里解析**明确写出**的平台(`URL_SITE_HINTS`)。
///
/// 与 web `utils/browse/resolvePlaySite.ts` 的 `URL_SITE_HINTS` 同源:只在输入
/// 含平台域名时给结论,其余(纯数字房间号、主播别名等)返回空串 —— 桌面端不做
/// 联网探测(`inferPlaySiteForRoom` 的 probe 分支),避免进房前多发请求。
String siteHintFromInput(String input) {
  final text = input.trim();
  if (text.isEmpty) return '';
  for (final (site, pattern) in _kUrlSiteHints) {
    if (pattern.hasMatch(text)) return site;
  }
  return '';
}

final List<(String, RegExp)> _kUrlSiteHints = [
  ('twitch', RegExp(r'(?:^|/)(?:www\.)?twitch\.tv/', caseSensitive: false)),
  (
    'soop',
    RegExp(r'(?:^|/)(?:play\.)?sooplive\.(?:co\.kr|com)/', caseSensitive: false),
  ),
  ('soop', RegExp(r'(?:^|/)afreeca\.com/', caseSensitive: false)),
  ('kuaishou', RegExp(r'(?:^|/)live\.kuaishou\.com/u/', caseSensitive: false)),
  ('yy', RegExp(r'(?:^|/)(?:www\.)?yy\.com/', caseSensitive: false)),
  ('bilibili', RegExp(r'(?:^|/)(?:live\.)?bilibili\.com/', caseSensitive: false)),
  ('douyin', RegExp(r'(?:^|/)(?:live\.)?douyin\.com/', caseSensitive: false)),
  ('huya', RegExp(r'(?:^|/)(?:www\.)?huya\.com/', caseSensitive: false)),
  ('douyu', RegExp(r'(?:^|/)(?:www\.)?douyu\.com/', caseSensitive: false)),
];
