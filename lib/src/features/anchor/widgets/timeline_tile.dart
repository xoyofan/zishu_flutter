import 'package:flutter/material.dart';
import 'package:live_parser/live_parser.dart';

import '../../../shared/presentation/design_tokens.dart';
import '../../../shared/presentation/platform_brands.dart';
import '../../../shared/presentation/zishu_tokens.dart';
import '../application/timeline_provider.dart';
import 'badge_chips.dart';
import 'network_cover.dart';

/// 时间线单条:左侧相对时间 + 中轴节点(平台色圆点 + 竖线) + 右侧房间卡。
class TimelineTile extends StatelessWidget {
  const TimelineTile({
    super.key,
    required this.entry,
    required this.isFirst,
    required this.isLast,
    required this.onTap,
  });

  final TimelineEntry entry;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onTap;

  static const double _timeWidth = 72;
  static const double _railWidth = 28;
  static const double _dotSize = 14;
  static const double _coverWidth = 96;
  static const double _coverHeight = 60;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final brand = PlatformBrandCatalog.byId(entry.room.site);
    final dotColor = brand?.color ?? tokens.brand;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: _timeWidth,
              child: Padding(
                padding: const EdgeInsets.only(top: 2, right: AppSpacing.xs),
                child: Text(
                  entry.relativeLabel,
                  textAlign: TextAlign.right,
                  style: AppTypography.caption,
                ),
              ),
            ),
            SizedBox(
              width: _railWidth,
              child: Stack(
                children: [
                  // 中轴竖线:首条从圆点下方开始,末条不再向下延伸。
                  if (!isLast)
                    Positioned(
                      top: isFirst ? _dotSize + 4 : 0,
                      bottom: 0,
                      left: (_railWidth - 2) / 2,
                      width: 2,
                      child: ColoredBox(color: tokens.border),
                    ),
                  Positioned(
                    top: 2,
                    left: (_railWidth - _dotSize) / 2,
                    child: Container(
                      width: _dotSize,
                      height: _dotSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: dotColor,
                        border: Border.all(color: tokens.surface, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(child: _EntryCard(room: entry.room, onTap: onTap)),
          ],
        ),
      ),
    );
  }
}

/// 条目卡片:封面小图 + 标题/主播/分类/在线人数。
class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.room, required this.onTap});

  final RoomSummary room;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Material(
      color: tokens.surface,
      borderRadius: AppRadius.allMd,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: AppRadius.allMd,
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: TimelineTile._coverWidth,
              height: TimelineTile._coverHeight,
              child: NetworkCover(url: room.cover, fallbackLabel: room.category),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      room.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            room.anchorName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.caption,
                          ),
                        ),
                        if (room.category.isNotEmpty) ...[
                          const SizedBox(width: AppSpacing.sm),
                          CategoryChip(label: room.category),
                        ],
                        const Spacer(),
                        Icon(Icons.visibility_rounded, size: 10, color: tokens.textSecondary),
                        const SizedBox(width: 3),
                        Text(room.online, style: AppTypography.caption),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
