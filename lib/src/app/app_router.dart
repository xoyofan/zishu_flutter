import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/anchor/views/anchor_view.dart';
import '../features/anchor/views/timeline_view.dart';
import '../features/browse/views/category_view.dart';
import '../features/browse/views/home_view.dart';
import '../features/follow/views/follow_view.dart';
import '../features/follow/views/settings_view.dart';
import '../features/play/application/play_screen_provider.dart';
import '../features/play/views/play_view.dart';
import '../features/search/views/search_view.dart';
import 'app_shell.dart';
import '../shared/presentation/platform_brands.dart';

/// 路由语义与 SFVideoLive 对齐(implementation-plan 6.3)。
/// route 参数只存 site/id/cid,不传大型对象。
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/all',
    routes: [
      // 静态路由声明在 /:site 之前,保证优先匹配。
      GoRoute(
        path: '/follow',
        pageBuilder: (_, state) => _shellPage(state, 'all', const FollowView()),
      ),
      GoRoute(
        path: '/time',
        pageBuilder: (_, state) =>
            _shellPage(state, 'all', const TimelineView()),
      ),
      GoRoute(
        path: '/settings',
        pageBuilder: (_, state) =>
            _shellPage(state, 'all', const SettingsView()),
      ),
      GoRoute(
        path: '/search',
        pageBuilder: (_, state) => _shellPage(state, 'all', const SearchView()),
      ),
      GoRoute(
        path: '/all',
        pageBuilder: (_, state) =>
            _shellPage(state, 'all', const HomeView(site: 'all')),
      ),
      // 分类落地页(不带子分类):对齐 SFVideoLive `/${site}/category`,
      // 进入后由 CategoryView 默认选中第一组。
      GoRoute(
        path: '/all/category',
        pageBuilder: (_, state) =>
            _shellPage(state, 'all', const CategoryView(site: 'all')),
      ),
      GoRoute(
        path: '/all/category/:key',
        pageBuilder: (_, state) => _shellPage(
          state,
          'all',
          CategoryView(site: 'all', categoryKey: state.pathParameters['key']),
        ),
      ),
      // 播放页同样套应用壳层(对齐参考实现:`AppLayout` 包裹 `PlayView`,
      // 顶栏在播放页常驻);沉浸态(网页全屏/全屏/画中画)由 _PlayRoute
      // 收起 chrome,视频占满窗口。
      GoRoute(
        path: '/:site/play/:id',
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
        ),
      ),
      GoRoute(
        path: '/:site/category',
        redirect: (_, state) {
          final site = state.pathParameters['site']!;
          return PlatformBrandCatalog.supportsBrowse(site) ? null : '/all';
        },
        pageBuilder: (_, state) {
          final site = state.pathParameters['site']!;
          return _shellPage(state, site, CategoryView(site: site));
        },
      ),
      GoRoute(
        path: '/:site/category/:cid',
        redirect: (_, state) {
          final site = state.pathParameters['site']!;
          return PlatformBrandCatalog.supportsBrowse(site) ? null : '/all';
        },
        pageBuilder: (_, state) {
          final site = state.pathParameters['site']!;
          return _shellPage(
            state,
            site,
            CategoryView(site: site, cid: state.pathParameters['cid']),
          );
        },
      ),
      GoRoute(
        path: '/:site',
        redirect: (_, state) {
          final site = state.pathParameters['site']!;
          return PlatformBrandCatalog.supportsBrowse(site) ? null : '/all';
        },
        pageBuilder: (_, state) {
          final site = state.pathParameters['site']!;
          return _shellPage(state, site, HomeView(site: site));
        },
      ),
    ],
  );
});

/// 除播放页外的页面都包在应用壳层里。
Page<dynamic> _shellPage(GoRouterState state, String site, Widget child) =>
    NoTransitionPage(
      key: state.pageKey,
      child: AppShell(site: site, child: child),
    );

/// 播放页宿主:壳层 + 播放页。
///
/// 沉浸态(网页全屏/全屏/画中画)收 chrome 的判定放在路由层,由
/// [playScreenProvider] 单源驱动 —— 播放页内部不需要知道壳层是否存在。
class _PlayRoute extends ConsumerWidget {
  const _PlayRoute({required this.site, required this.roomId});

  final String site;
  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 必须 watch(而非 read):chrome 显隐要随呈现态切换立即重建。
    final chromeHidden = ref.watch(playScreenProvider).hidesChrome;
    return AppShell(
      site: site,
      chromeHidden: chromeHidden,
      child: PlayView(site: site, roomId: roomId),
    );
  }
}
