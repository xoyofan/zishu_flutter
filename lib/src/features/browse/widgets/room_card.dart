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
            _RoomCardMeta(
              room: room,
              showPlatformBadge: showPlatformBadge,
            ),
          ],
        ),
      ),
    );
  }
}

/// 封面下元信息:恒定**两行**。
///
/// 对齐参考实现 `RoomCard.vue` 的 `.room-card__body`(padding 6/8/8)与
/// `.room-card__meta`(margin-top 4 / gap 6):
/// - 第 1 行:房间标题(缺标题回退主播名,仍缺则占位不塌陷);
/// - 第 2 行:主播名 + 特色 chip(促销/画质标签;平台名不进 chip,由封面
///   平台角标或单平台页签上下文承载)。
///
/// **两行高度必须恒定**:有的主播没有名字、多数房间没有 chip,若不占位,同一
/// 网格里卡片高度参差(用户报「都保持2行的行高,不要多余 padding」)。
class _RoomCardMeta extends StatelessWidget {
  const _RoomCardMeta({required this.room, required this.showPlatformBadge});

  final RoomSummary room;
  final bool showPlatformBadge;

  /// 元信息行高:12px 字号 × 1.35 行高(与参考实现 `min-height: 1.35em` 同口径)。
  static const double _metaLineHeight = 17;

  @override
  Widget build(BuildContext context) {
    final title = room.title.trim().isNotEmpty
        ? room.title
        : (room.anchorName.trim().isNotEmpty ? room.anchorName : ' ');
    final anchor = room.anchorName.trim();
    final chips = <String>[
      if (room.promoTag != null && room.promoTag!.trim().isNotEmpty)
        room.promoTag!.trim(),
      // 平台名不进 chip(用户口径 2026-09-18):平台信息由封面平台角标
      // (CoverPlatformBadge,跨平台网格)或单平台页签上下文承载。
    ];
    return Padding(
      // 参考实现 .room-card__body:padding 6px 8px 8px。
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.textTitle.copyWith(fontSize: 14),
          ),
          const SizedBox(height: AppSpacing.xs),
          // 固定行高:内容缺失也占满一行,保证同网格卡片等高。
          SizedBox(
            height: _metaLineHeight,
            child: Row(
              children: [
                if (anchor.isNotEmpty)
                  Flexible(
                    child: FollowAnchorName(
                      site: room.site,
                      name: anchor,
                      live: room.online.trim().isNotEmpty,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                if (anchor.isNotEmpty && chips.isNotEmpty)
                  const SizedBox(width: 6),
                for (final chip in chips) ...[
                  _MetaChip(key: Key('room-meta-chip-$chip'), text: chip),
                  if (chip != chips.last) const SizedBox(width: 6),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 元信息行里的特色 chip:对齐 `.room-card__tag`(小圆角浅底、次级文字)。
class _MetaChip extends StatelessWidget {
  const _MetaChip({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        borderRadius: AppRadius.allSm,
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.textCaption.copyWith(fontSize: 10.5),
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
          // 离线:整封面遮罩 + 「未开播」(web `.room-card__offline`,z-index 2)。
          // 放在角标之前复刻 web 的层级(遮罩 z2 低于角标 z3,角标浮于其上);
          // 判据沿用本组件既有的 `live`(online 非空),不另造第二套离线判定。
          // 注:web 的「上次开播 X」文案由 follow 域数据支撑,网格数据源
          // (RoomSummary)无该字段,离线一律显示「未开播」。
          if (!live)
            const Positioned.fill(
              key: Key('room-card-offline'),
              child: CoverOfflineOverlay(),
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
          // 右上:促销/画质标签已移到封面下方的特色 chip 行(用户口径:
          // 「预览图下面第二行是各种特色 chip」),同一信息不在封面与行内各显示一次。
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
          style: context.textSecondary,
        ),
      ),
    );
  }
}
