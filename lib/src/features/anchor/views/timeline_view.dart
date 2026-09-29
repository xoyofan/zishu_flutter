import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:live_parser/live_parser.dart';

import '../../../platforms/common/playback/playback_log.dart';
import '../../../shared/presentation/design_tokens.dart';
import '../../../shared/presentation/platform_brands.dart';
import '../../../shared/presentation/zishu_tokens.dart';
import '../application/timeline_provider.dart';
import '../widgets/timeline_tile.dart';

/// 动态时间线(U8):平台筛选 chips + 左侧时间轴节点 + 右侧房间卡,
/// 视觉基调对齐 SFVideoLive TimeView(居中窄栏 + 标题/副标题)。
class TimelineView extends ConsumerWidget {
  const TimelineView({super.key});

  /// SFVideoLive .time-page 的 max-width 960px。
  static const double _contentMaxWidth = 960;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(timelineControllerProvider);
    final state = async.value;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '动态时间线',
                    style: context.textTitle.copyWith(
                      fontSize: AppFontSize.display,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text('主播开播动态流,按时间从近到远排列(样例数据)', style: context.textSecondary),
                ],
              ),
            ),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                children: [
                  for (final brand in PlatformBrandCatalog.navigationPlatforms)
                    Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.sm),
                      child: _SiteFilterChip(
                        // 测试锚点:平台筛选 chip(timeline-filter-{site})。
                        key: Key('timeline-filter-${brand.id}'),
                        brand: brand,
                        selected: brand.id == (state?.filterSite ?? 'all'),
                        onTap: () => ref
                            .read(timelineControllerProvider.notifier)
                            .setFilter(brand.id),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(child: _buildBody(context, ref, async)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<TimelineState> async,
  ) {
    if (async.isLoading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (async.hasError) {
      return Center(child: Text('加载失败,请稍后重试', style: context.textSecondary));
    }
    final entries = async.value?.visible ?? const [];
    if (entries.isEmpty) {
      return Center(child: Text('该平台暂无动态', style: context.textSecondary));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        return TimelineTile(
          entry: entry,
          isFirst: index == 0,
          isLast: index == entries.length - 1,
          onTap: () => _openRoom(context, entry.room),
        );
      },
    );
  }

  void _openRoom(BuildContext context, RoomSummary room) {
    PlaybackLog.logRoomNav(
      source: 'timeline_view',
      site: room.site,
      roomId: room.roomId,
    );
    context.push('/${room.site}/play/${room.roomId}');
  }
}

/// 平台筛选 chip:选中时平台色描边 + 平台色文字,与首页 chips 同基线。
class _SiteFilterChip extends StatelessWidget {
  const _SiteFilterChip({
    super.key,
    required this.brand,
    required this.selected,
    required this.onTap,
  });

  final PlatformBrand brand;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return FilterChip(
      selected: selected,
      label: Text(brand.name),
      onSelected: (_) => onTap(),
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      // 状态矩阵(全部走 token):hover 抬到 surfaceRaised;键盘焦点用 accent
      // 低 alpha;选中用平台色淡底。FilterChip 的状态层走 color 解析器
      // (给 color 后 RawChip 不再叠默认 hover 遮罩)。
      color: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return brand.color.withValues(alpha: 0.22);
        }
        if (states.contains(WidgetState.focused)) {
          return tokens.accent.withValues(alpha: 0.10);
        }
        if (states.contains(WidgetState.hovered)) {
          return tokens.surfaceRaised;
        }
        return tokens.surface;
      }),
      checkmarkColor: brand.color,
      side: BorderSide(color: selected ? brand.color : tokens.border),
      shape: RoundedRectangleBorder(borderRadius: AppRadius.allSm),
      labelStyle: context.textBody.copyWith(
        color: selected ? brand.color : tokens.textSecondary,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
      ),
    );
  }
}
