import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:live_parser/live_parser.dart';

import '../../../shared/presentation/design_tokens.dart';
import '../../../shared/presentation/widgets/cover_badges.dart';
import '../../../shared/presentation/zishu_tokens.dart';
import '../../follow/widgets/follow_common.dart';

/// SFVideoLive 风格房间卡片:16:9 封面 + 四象限徽章 + 标题/主播。
///
/// 四象限角位与配色**逐条对齐参考实现**(`RoomCard.vue` + `CoverBadges.vue`):
/// - 左上:分类色块(`.room-card__badge--category`,内角 8px 圆角);
/// - 右上:促销/画质标签(`.room-card__badge--promo`,琥珀底);
/// - 右下:热度(`.cover-online-badge`,暗底白字);
/// - 左下:平台 pill(`.room-card__foot-left`,仅跨站聚合显示)。
///
/// 四枚角标统一由 [CoverBadge] 家族渲染(圆角/内边距/字号一处定义),
/// 与播放页侧栏预览卡共用,避免两处角位漂移。
class RoomCard extends StatelessWidget {
  const RoomCard({
    super.key,
    required this.room,
    this.onTap,
    this.showPlatformBadge = true,
  });

  final RoomSummary room;
  final VoidCallback? onTap;

  /// 是否显示平台角标;单平台网格(参考 Vue:仅跨站聚合显示)可关闭。
  final bool showPlatformBadge;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Material(
      // 测试锚点:定位/点击具体房间卡片。
      key: Key('room-card-${room.site}-${room.roomId}'),
      color: tokens.surface,
      borderRadius: AppRadius.allMd,
      child: InkWell(
        borderRadius: AppRadius.allMd,
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Cover(room: room, showPlatformBadge: showPlatformBadge),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    room.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.title.copyWith(fontSize: 14),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  // 分类已由封面左上角色块承载,文本区只保留主播名。
                  FollowAnchorName(
                    site: room.site,
                    name: room.anchorName,
                    live: room.online.trim().isNotEmpty,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.room, required this.showPlatformBadge});

  final RoomSummary room;
  final bool showPlatformBadge;

  @override
  Widget build(BuildContext context) {
    final live = room.online.trim().isNotEmpty;
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            color: context.tokens.surfaceSoft,
            child: room.cover.isEmpty
                ? _CoverPlaceholder(room: room)
                : CachedNetworkImage(
                    imageUrl: room.cover,
                    fit: BoxFit.cover,
                    placeholder: (_, _) =>
                        ColoredBox(color: context.tokens.surfaceRaised),
                    errorWidget: (_, _, _) => _CoverPlaceholder(room: room),
                  ),
          ),
          // 左上:分类色块。
          Positioned(
            left: 0,
            top: 0,
            child: CoverCategoryBadge(
              // 测试锚点:按角位断言用(卡片各自子树内唯一,不与同页其它卡冲突)。
              key: const Key('cover-badge-category'),
              corner: CoverCorner.topLeft,
              category: room.category,
              site: room.site,
              cid: room.cid,
            ),
          ),
          // 右上:促销/画质标签。
          if (room.promoTag != null)
            Positioned(
              right: 0,
              top: 0,
              child: CoverPromoBadge(
                key: const Key('cover-badge-promo'),
                corner: CoverCorner.topRight,
                text: room.promoTag!,
              ),
            ),
          // 右下:热度(未开播不显示)。
          if (live)
            Positioned(
              right: 0,
              bottom: 0,
              child: CoverOnlineBadge(
                key: const Key('cover-badge-online'),
                corner: CoverCorner.bottomRight,
                online: room.online,
              ),
            ),
          // 左下:平台 pill(单平台网格可关闭)。
          if (showPlatformBadge)
            Positioned(
              left: 0,
              bottom: 0,
              child: CoverPlatformBadge(
                key: const Key('cover-badge-platform'),
                corner: CoverCorner.bottomLeft,
                site: room.site,
              ),
            ),
        ],
      ),
    );
  }
}

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder({required this.room});

  final RoomSummary room;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.tokens.surfaceRaised,
      child: Center(
        child: Text(
          room.category.isEmpty ? room.site : room.category,
          style: AppTypography.bodySecondary,
        ),
      ),
    );
  }
}
