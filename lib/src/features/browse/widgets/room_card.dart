import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:live_parser/live_parser.dart';

import '../../../shared/presentation/category_colors.dart';
import '../../../shared/presentation/design_tokens.dart';
import '../../../shared/presentation/platform_brands.dart';
import '../../../shared/presentation/zishu_tokens.dart';
import '../../follow/widgets/follow_common.dart';

/// SFVideoLive 风格房间卡片:16:9 封面 + 四象限徽章 + 标题/主播。
///
/// 封面徽章采用参考实现的「四象限」模板,四枚角标**一律紧贴所在角、直角无圆角**
/// (与关注/播放页共用 [FollowCoverTag]):
/// - 左上:分类色块(配色见 [CategoryColors]);
/// - 左下:平台 pill;
/// - 右上:促销/画质标签;
/// - 右下:热度。
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
    final brand = PlatformBrandCatalog.byId(room.site);
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
            _Cover(
              room: room,
              brandColor: brand?.color,
              showPlatformBadge: showPlatformBadge,
            ),
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
  const _Cover({
    required this.room,
    required this.brandColor,
    required this.showPlatformBadge,
  });

  final RoomSummary room;
  final Color? brandColor;
  final bool showPlatformBadge;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            color: context.tokens.surfaceSoft,
            child: room.cover.isEmpty
                ? _CoverPlaceholder(room: room)
                // 深色遮罩用 background token 压暗,保持无裸色值。
                : CachedNetworkImage(
                    imageUrl: room.cover,
                    fit: BoxFit.cover,
                    placeholder: (_, _) =>
                        ColoredBox(color: context.tokens.surfaceRaised),
                    errorWidget: (_, _, _) => _CoverPlaceholder(room: room),
                  ),
          ),
          // 左上:分类色块(配色取自 CategoryColors)。
          if (room.category.isNotEmpty)
            Positioned(
              left: 0,
              top: 0,
              child: _CategoryBadge(category: room.category, site: room.site),
            ),
          // 左下:平台角标(单平台网格可关闭)。
          if (showPlatformBadge)
            Positioned(
              left: 0,
              bottom: 0,
              child: _PlatformBadge(site: room.site, color: brandColor),
            ),
          if (room.promoTag != null)
            Positioned(
              right: 0,
              top: 0,
              child: _PromoTag(tag: room.promoTag!),
            ),
          Positioned(
            right: 0,
            bottom: 0,
            child: _OnlineTag(online: room.online),
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

/// 左下平台角标:直角色块(与关注/播放页角标同款)。
class _PlatformBadge extends StatelessWidget {
  const _PlatformBadge({required this.site, required this.color});

  final String site;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final brand = PlatformBrandCatalog.byId(site);
    final label = brand?.name ?? site;
    return FollowCoverTag(
      accent: color ?? tokens.brand,
      child: Text(
        label,
        // 平台色底上用深色 token 文字保证可读。
        style: AppTypography.caption.copyWith(
          color: tokens.surfaceSoft,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// 左上分类角标:底色/文字色由 [CategoryColors] 计算,未命中时退化为空。
class _CategoryBadge extends StatelessWidget {
  const _CategoryBadge({required this.category, required this.site});

  final String category;
  final String site;

  @override
  Widget build(BuildContext context) {
    final style = CategoryColors.opaqueFor(category: category, site: site);
    if (style == null) return const SizedBox.shrink();
    return FollowCoverTag(
      accent: style.background,
      child: Text(
        category,
        style: AppTypography.caption.copyWith(
          color: style.foreground,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _OnlineTag extends StatelessWidget {
  const _OnlineTag({required this.online});

  final String online;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return FollowCoverTag(
      child: Text(
        online,
        style: AppTypography.caption.copyWith(color: tokens.textPrimary),
      ),
    );
  }
}

class _PromoTag extends StatelessWidget {
  const _PromoTag({required this.tag});

  final String tag;

  @override
  Widget build(BuildContext context) {
    return FollowCoverTag(
      accent: context.tokens.liveBadge,
      child: Text(
        tag,
        style: AppTypography.caption.copyWith(
          color: context.tokens.surfaceSoft,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
