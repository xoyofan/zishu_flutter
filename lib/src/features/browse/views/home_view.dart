import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:live_parser/live_parser.dart';

import '../../../shared/presentation/design_tokens.dart';
import '../../../shared/presentation/platform_brands.dart';
import '../../../shared/presentation/zishu_tokens.dart';
import '../application/browse_provider.dart';
import '../widgets/room_grid.dart';

/// 全平台/平台首页:顶部平台筛选 chips + 房间自适应网格。
/// 数据由 [browseRoomsProvider] 持有,本 Widget 只渲染并转发用户操作。
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
    // U9:内容区平台筛选 chips 用 Wrap 多行(360 宽两行,全部挂载不裁切)。
    // platform-tab-{site} 契约 key 在 <768 由本组件持有(顶导航已隐藏);
    // >=768 时让位给顶导航 tabs,改用 home-platform-chip-{site} 保证 key 全树唯一。
    final chipKeyPrefix =
        MediaQuery.sizeOf(context).width < AppBreakpoints.phone
        ? 'platform-tab-'
        : 'home-platform-chip-';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.xs,
          ),
          child: Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final brand in PlatformBrandCatalog.navPlatforms)
                _PlatformChip(
                  brand: brand,
                  selected: brand.id == widget.site,
                  keyPrefix: chipKeyPrefix,
                ),
            ],
          ),
        ),
        Expanded(
          child: switch (roomsAsync) {
            // 刷新中保留旧数据渲染(value 非 null 即有数据)。
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
          },
        ),
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
                style: AppTypography.bodySecondary,
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

/// 平台筛选 chip:选中态使用平台品牌色。
class _PlatformChip extends StatelessWidget {
  const _PlatformChip({
    required this.brand,
    required this.selected,
    required this.keyPrefix,
  });

  final PlatformBrand brand;
  final bool selected;

  /// 契约 key 前缀:<768 为 platform-tab-(U9,W12 验收),>=768 为
  /// home-platform-chip-(顶导航 tabs 持有 platform-tab-*)。
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    return ChipTheme(
      data: ChipTheme.of(context).copyWith(
        backgroundColor: context.tokens.surface,
        selectedColor: brand.color.withValues(alpha: 0.22),
        checkmarkColor: brand.color,
        labelStyle: AppTypography.body.copyWith(
          color: selected ? brand.color : context.tokens.textSecondary,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
        ),
        side: BorderSide(color: selected ? brand.color : context.tokens.border),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.allSm),
      ),
      child: FilterChip(
        // 测试锚点:定位/点击平台筛选 chip(前缀随断点,见 [keyPrefix])。
        key: Key('$keyPrefix${brand.id}'),
        selected: selected,
        label: Text(brand.name),
        onSelected: (_) =>
            context.go(brand.id == 'all' ? '/all' : '/${brand.id}'),
        showCheckmark: false,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
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
          Text(message, style: AppTypography.bodySecondary),
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
