import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:live_parser/live_parser.dart';

import '../../../shared/presentation/design_tokens.dart';
import '../../../shared/presentation/zishu_tokens.dart';
import '../application/browse_provider.dart';
import '../widgets/browse_sidebar.dart';
import '../widgets/room_grid.dart';

/// 全平台/平台首页:宽屏渲染「左侧栏 + 房间网格」,窄屏仅房间网格。
///
/// 平台入口锚点 [home-platform-chip-{id}] 已迁至左侧栏(见 [BrowseSidebar]),
/// 此处内容区不再重复渲染横向 chips 行(窄屏平台切换由 AppShell 平台条承担)。
class HomeView extends ConsumerStatefulWidget {
  const HomeView({super.key, required this.site});

  /// `all` 表示全平台聚合。
  final String site;

  @override
  ConsumerState<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends ConsumerState<HomeView> {
  @override
  Widget build(BuildContext context) {
    final query = BrowseRoomQuery(site: widget.site);
    final roomsAsync = ref.watch(browseRoomsProvider(query));
    final controller = ref.read(browseRoomsProvider(query).notifier);
    // 断点沿用 AppBreakpoints.phone(768):与旧 chips 行同档,避免 768–1365
    // 区间出现平台入口真空;左栏在此档出现,内容区不再渲染 chips。
    // <768:平台切换由 AppShell 平台条(nav-platform-strip)承担。
    final isPhone = MediaQuery.sizeOf(context).width < AppBreakpoints.phone;
    final tokens = context.tokens;

    // 房间网格主体(下拉刷新 + 滚动加载 + 空态/错误)。
    final body = switch (roomsAsync) {
      AsyncValue(:final value?) => _body(
          context,
          rooms: value.rooms,
          hasMore: value.hasMore,
        ),
      AsyncValue(:final error?) => _ErrorRetry(
          message: '房间列表加载失败：$error',
          onRetry: controller.refresh,
        ),
      _ => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!isPhone) BrowseSidebar(site: widget.site),
        if (!isPhone) Container(width: 1, color: tokens.border),
        Expanded(child: body),
      ],
    );
  }

  /// 有数据(含刷新中)时的网格主体:下拉刷新 + 滚动加载 + 空态。
  Widget _body(
    BuildContext context, {
    required List<RoomSummary> rooms,
    required bool hasMore,
  }) {
    final query = BrowseRoomQuery(site: widget.site);
    final controller = ref.read(browseRoomsProvider(query).notifier);
    if (rooms.isEmpty) {
      return RefreshIndicator(
        onRefresh: controller.refresh,
        color: context.tokens.brand,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: AppSpacing.xxl * 6),
            Icon(
              Icons.live_tv_rounded,
              size: 48,
              color: context.tokens.textSecondary,
            ),
            const SizedBox(height: AppSpacing.md),
            Center(
              child: Text(
                '暂无直播间,下拉刷新试试',
                style: context.textSecondary,
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: controller.refresh,
      color: context.tokens.brand,
      child: RoomGrid(
        rooms: rooms,
        hasMore: hasMore,
        onLoadMore: controller.loadMore,
        // 跨站聚合时才展示平台角标(对齐 Vue 版行为)。
        showPlatformBadge: widget.site == 'all',
        onRoomTap: (room) => context.push('/${room.site}/play/${room.roomId}'),
      ),
    );
  }
}

/// 错误占位:错误说明 + 重试按钮。
class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded, size: 40, color: context.tokens.error),
          const SizedBox(height: AppSpacing.md),
          Text(message, style: context.textSecondary),
          const SizedBox(height: AppSpacing.lg),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('重试'),
            style: TextButton.styleFrom(foregroundColor: context.tokens.brand),
          ),
        ],
      ),
    );
  }
}
