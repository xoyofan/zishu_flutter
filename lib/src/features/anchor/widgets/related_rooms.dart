import 'package:flutter/material.dart';
import 'package:live_parser/live_parser.dart';

import '../../../shared/domain/category_display.dart';
import '../../../shared/presentation/design_tokens.dart';
import '../../../shared/presentation/zishu_tokens.dart';
import '../../../shared/presentation/widgets/translated_text.dart';
import 'badge_chips.dart';
import 'network_cover.dart';

/// 「相关直播」横向滑动卡片列表。
class RelatedRoomList extends StatelessWidget {
  const RelatedRoomList({
    super.key,
    required this.rooms,
    required this.onRoomTap,
  });

  final List<RoomSummary> rooms;
  final ValueChanged<RoomSummary> onRoomTap;

  static const double _cardWidth = 168;
  static const double _listHeight = 152;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('相关直播', style: context.textTitle),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          height: _listHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            itemCount: rooms.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
            itemBuilder: (context, index) => _RelatedCard(
              room: rooms[index],
              onTap: () => onRoomTap(rooms[index]),
            ),
          ),
        ),
      ],
    );
  }
}

class _RelatedCard extends StatelessWidget {
  const _RelatedCard({required this.room, required this.onTap});

  final RoomSummary room;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return SizedBox(
      width: RelatedRoomList._cardWidth,
      child: Material(
        color: tokens.surface,
        borderRadius: AppRadius.allMd,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: AppRadius.allMd,
          onTap: onTap,
          // 状态反馈(全部走 token):hover 抬亮;焦点/按压用 accent 低 alpha。
          hoverColor: tokens.surfaceRaised,
          splashColor: tokens.accent.withValues(alpha: 0.12),
          highlightColor: tokens.accent.withValues(alpha: 0.10),
          focusColor: tokens.accent.withValues(alpha: 0.10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: NetworkCover(
                  url: room.cover,
                  fallbackLabel: displayCategoryName(
                    room.site,
                    room.category,
                    room.cid,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TranslatedText(
                      room.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.textBody.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            room.anchorName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.textCaption,
                          ),
                        ),
                        if (room.category.isNotEmpty) ...[
                          const SizedBox(width: AppSpacing.xs),
                          CategoryChip(label: room.category, site: room.site),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
