import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/anchor/views/anchor_view.dart';
import '../features/anchor/views/timeline_view.dart';
import '../features/browse/views/category_view.dart';
import '../features/browse/views/home_view.dart';
import '../features/follow/views/follow_view.dart';
import '../features/follow/views/settings_view.dart';
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
      // 播放页不套应用壳层(视频占主空间)。
      GoRoute(
        path: '/:site/play/:id',
        pageBuilder: (_, state) => NoTransitionPage(
          key: state.pageKey,
          child: PlayView(
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
