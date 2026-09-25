import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:live_parser/live_parser.dart';

import '../../../shared/presentation/design_tokens.dart';
import '../../../shared/presentation/platform_brands.dart';
import '../../../shared/presentation/widgets/retry_button.dart';
import '../../../shared/presentation/zishu_tokens.dart';
import '../application/platform_rooms_provider.dart';
import 'room_card_skeleton.dart';
import 'room_grid.dart';

/// 全平台首页内容:竖向滚动,每个平台一个**独立区块**
/// (区块头 + 该平台网格),区块顺序 = 平台目录顺序。
///
/// - 首屏每平台只请求当前列数条(见 [PlatformRoomsQuery.limit]);
/// - 数据到达前显示 [RoomGridSkeleton](数量 = 列数);
/// - 单平台失败只把自己的区块换成错误态 + 重试,其它平台照常;
/// - 下拉刷新 = 重置全部平台区块(与 F5 的 `GlobalActions.refreshHome`
///   同通路,见 [refreshAllHomeSections])。
class HomeSections extends ConsumerWidget {
  const HomeSections({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final columns = AppRoomGrid.columnsFor(MediaQuery.sizeOf(context).width);
    return RefreshIndicator(
      onRefresh: () => refreshAllHomeSections(ref, columns: columns),
      color: context.tokens.accent,
      child: ListView(
        // 测试锚点：区块列表滚动定位（scrollUntilVisible 的 scrollable）。
        key: const Key('home-sections-list'),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          for (final brand in homeSectionBrands)
            _PlatformSection(brand: brand, columns: columns),
        ],
      ),
    );
  }
}

/// 重置全部平台区块(下拉/F5 同通路):每个平台回第一页重新拉取。
///
/// 对**未滚入视口、尚未挂载**的区块也执行 —— `refresh()` 会先触发
/// 首次 build 再拉取,保证「刷新 = 重置所有平台区块」。
Future<void> refreshAllHomeSections(
  WidgetRef ref, {
  required int columns,
}) async {
  await Future.wait([
    for (final brand in homeSectionBrands)
      ref
          .read(
            platformRoomsProvider(
              PlatformRoomsQuery(site: brand.id, limit: columns),
            ).notifier,
          )
          .refresh(),
  ]);
}

/// 单个平台区块:区块头 + 数据态(骨架/网格/空/错误)。
class _PlatformSection extends ConsumerWidget {
  const _PlatformSection({required this.brand, required this.columns});

  final PlatformBrand brand;
  final int columns;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = PlatformRoomsQuery(site: brand.id, limit: columns);
    final roomsAsync = ref.watch(platformRoomsProvider(query));
    final controller = ref.read(platformRoomsProvider(query).notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(brand: brand),
        switch (roomsAsync) {
          AsyncValue(:final value?) =>
            value.rooms.isEmpty
                ? const _SectionEmpty()
                : _SectionGrid(
                    site: brand.id,
                    rooms: value.rooms,
                    hasMore: value.hasMore,
                    columns: columns,
                    onLoadMore: controller.loadMore,
                  ),
          AsyncValue(:final error?) => _SectionError(
            site: brand.id,
            message: '$error',
            onRetry: controller.refresh,
          ),
          // 首屏在途(骨架数量 = 列数 = 首屏请求条数,落地原位替换)。
          _ => RoomGridSkeleton(count: columns, site: brand.id),
        },
      ],
    );
  }
}

/// 区块头:平台色点 + 平台名,点击进入该平台首页 `/{site}`。
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.brand});

  final PlatformBrand brand;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final shape = RoundedRectangleBorder(borderRadius: AppRadius.allMd);
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        // 测试锚点:定位/点击区块头(进平台页)。
        key: Key('home-section-header-${brand.id}'),
        onTap: () => context.go('/${brand.id}'),
        customBorder: shape,
        hoverColor: tokens.surfaceRaised,
        splashColor: AppStateLayer.splashOf(tokens.accent),
        highlightColor: AppStateLayer.pressedOf(tokens.accent),
        focusColor: AppStateLayer.focusOf(tokens.accent),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              // 平台色点(品牌色是平台数据,非 UI 裸值)。
              Container(
                width: AppSpacing.sm,
                height: AppSpacing.sm,
                decoration: BoxDecoration(
                  color: brand.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(brand.name, style: context.textBody),
              const Spacer(),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: tokens.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 该平台网格:RoomGrid 装进**内容高盒**(镜像 RoomGrid 布局公式),
/// 让整页只有一条竖向滚动 —— 盒高 == 内容高时 GridView 不产生内部滚动,
/// 既不会把卡片裁掉,也不会在盒底留空段。
class _SectionGrid extends StatelessWidget {
  const _SectionGrid({
    required this.site,
    required this.rooms,
    required this.hasMore,
    required this.columns,
    required this.onLoadMore,
  });

  final String site;
  final List<RoomRecord> rooms;
  final bool hasMore;
  final int columns;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) => SizedBox(
            // 测试锚点:断言盒高与 RoomGrid 内容高一致(不裁切、不留空段)。
            key: Key('home-section-grid-$site'),
            height: roomGridBoxHeightFor(
              context: context,
              width: constraints.maxWidth,
              columns: columns,
              itemCount: rooms.length + (hasMore ? 1 : 0),
            ),
            child: RoomGrid(
              rooms: rooms,
              hasMore: hasMore,
              onLoadMore: onLoadMore,
              onRoomTap: (room) =>
                  context.push('/${room.site}/play/${room.roomId}'),
            ),
          ),
        ),
        if (hasMore)
          Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.lg),
              child: TextButton.icon(
                // 测试锚点:「更多」→ 该平台下一页(loadMore 语义)。
                key: Key('home-section-more-$site'),
                onPressed: onLoadMore,
                icon: const Icon(Icons.expand_more_rounded),
                label: const Text('加载更多'),
                style: TextButton.styleFrom(foregroundColor: tokens.accent),
              ),
            ),
          ),
      ],
    );
  }
}

/// 区块空态:紧凑一行提示(不出现大段空白)。
class _SectionEmpty extends StatelessWidget {
  const _SectionEmpty();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Text(
        '暂无直播间',
        style: context.textCaption.copyWith(color: tokens.textSecondary),
      ),
    );
  }
}

/// 区块错误态:该平台加载失败的提示 + 重试(只影响本区块)。
class _SectionError extends StatelessWidget {
  const _SectionError({
    required this.site,
    required this.message,
    required this.onRetry,
  });

  final String site;
  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      // 测试锚点:失败平台的错误态;内部为 RetryButton(可点重试)。
      key: Key('home-section-error-$site'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, size: 18, color: tokens.error),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              '加载失败:$message',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textCaption.copyWith(color: tokens.textSecondary),
            ),
          ),
          RetryButton(onRetry: onRetry),
        ],
      ),
    );
  }
}

/// 区块网格盒高:镜像 [RoomGrid] 的布局公式(断点列数、格宽、16:9 + 元信息
/// 预算的单元格高、行距、grid padding),保证内嵌 RoomGrid 的 viewport 高
/// **恰好等于**内容高。
///
/// ⚠️ 与 room_grid.dart 的 SliverGrid 委托同源:列数、cardWidth、
/// childHeight、行距任何一处改动必须同步这里(home_sections_test 的
/// 「盒高==内容高」用例会机械拦截不同步)。
double roomGridBoxHeightFor({
  required BuildContext context,
  required double width,
  required int columns,
  required int itemCount,
}) {
  const padding = EdgeInsets.all(AppSpacing.lg);
  final available = width - padding.horizontal;
  final cardWidth =
      (available - AppSpacing.gridCrossAxisSpacing * (columns - 1)) / columns;
  final childHeight =
      cardWidth * 9 / 16 + metaHeightFor(roomGridMetaBudget, context);
  final rows = (itemCount + columns - 1) ~/ columns;
  if (rows <= 0) return padding.vertical;
  return padding.vertical +
      rows * childHeight +
      (rows - 1) * AppSpacing.gridMainAxisSpacing;
}
