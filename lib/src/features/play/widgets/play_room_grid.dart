/// 播放页侧栏「推荐」tab 的房间封面网格。
///
/// 对齐 SFVideoLive:`FollowRoomPreviewView`(sidebar + compact)的封面网格。
/// 「关注」tab 已改与「我的关注」页共用 `FollowRoomList`,本文件的
/// [PlayRoomGrid] / [PlayRoomCard] 现仅供 [_RecommendPanel] 与骨架占位复用。
///
/// 卡片结构(对齐 `.follow-preview-item` + `FollowRoomPreviewView.vue`):
/// - 16:9 封面四象限:左上**平台**徽章(`.platform-cover-badge`,贴左上、内角 8px)、
///   右上**分类**徽章(`.follow-preview-cat`)、右下**热度**(`.cover-online-badge`)、
///   左下**特别关注 ★**(本仓特有能力:参考实现的侧栏卡用整卡背景着色标超关,
///   不占角标位,故本仓占用唯一空置的左下角);
/// - 离线:整封面压暗 + 居中「未开播」(web `.follow-preview-offline`);
/// - 封面下方:主播名(单行省略)→ 标题(单行省略,次级色)。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:live_parser/live_parser.dart';

import '../../../shared/domain/category_display.dart';
import '../../../shared/presentation/design_tokens.dart';
import '../../../shared/presentation/widgets/cover_badges.dart';
import '../../../shared/presentation/widgets/translated_text.dart';
import '../../../shared/presentation/zishu_tokens.dart';
import '../../follow/widgets/follow_common.dart';

/// 特别关注标记键集合:'site:roomId'。
typedef RoomKeySet = Set<String>;

/// 侧栏封面网格:列数自适应(默认 2 列),条目点击回调上抛。
class PlayRoomGrid extends StatelessWidget {
  const PlayRoomGrid({
    super.key,
    required this.rooms,
    this.columns = 2,
    this.superKeys = const <String>{},
    this.keyPrefix = 'play-room-card-',
    this.onTap,
  });

  final List<RoomSummary> rooms;

  /// 列数;侧栏宽度下 2 列对齐参考实现的紧凑预览网格。
  final int columns;

  /// 特别关注条目键集合(命中则显示金色 ★)。
  final RoomKeySet superKeys;

  /// 条目锚点前缀:推荐 tab 沿用 `play-recommend-room-`(既有测试契约),
  /// 关注 tab 用 `play-follow-room-`。
  final String keyPrefix;

  final void Function(RoomSummary room)? onTap;

  /// 卡片元信息区(封面下两行文本)的高度预算。
  static const double _cardMetaHeight = 36;

  @override
  Widget build(BuildContext context) {
    const padding = EdgeInsets.fromLTRB(
      AppSpacing.sm,
      0,
      AppSpacing.sm,
      AppSpacing.sm,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        // 由实际列宽推导纵横比,让卡片高恰好 = 封面(16:9) + 元信息两行。
        // 原固定 0.86 在窄侧栏(2 列约 158dp/列)下把卡片拉高近 60dp,
        // 元信息区只剩空底 —— 这里按内容收紧。
        final width = math.max(0.0, constraints.maxWidth - padding.horizontal);
        final gaps = AppSpacing.sm * (columns - 1);
        final columnWidth = math.max(1.0, (width - gaps) / columns);
        final metaHeight = metaHeightFor(_cardMetaHeight, context);
        return GridView.builder(
          padding: padding,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: AppSpacing.sm,
            crossAxisSpacing: AppSpacing.sm,
            childAspectRatio: columnWidth / (columnWidth * 9 / 16 + metaHeight),
          ),
          itemCount: rooms.length,
          itemBuilder: (context, index) {
            final room = rooms[index];
            return PlayRoomCard(
              key: ValueKey('$keyPrefix${room.site}-${room.roomId}'),
              room: room,
              isSpecial: superKeys.contains('${room.site}:${room.roomId}'),
              onTap: onTap == null ? null : () => onTap!(room),
            );
          },
        );
      },
    );
  }
}

/// 单张封面卡:16:9 封面 + 角标 + 主播名 + 标题。
class PlayRoomCard extends StatelessWidget {
  const PlayRoomCard({
    super.key,
    required this.room,
    this.isSpecial = false,
    this.onTap,
  });

  final RoomSummary room;
  final bool isSpecial;
  final VoidCallback? onTap;

  /// 是否开播:沿用全站约定 online 非空即开播。
  bool get _live => room.online.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Material(
      color: tokens.surface,
      borderRadius: AppRadius.allSm,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        // 卡片 hover 抬一档底(surface → surfaceRaised,DESIGN.md §4.2);
        // 按下/键盘焦点走 accent 低 alpha。只改颜色,不动尺寸与位置。
        hoverColor: tokens.surfaceRaised,
        splashColor: tokens.accent.withValues(alpha: 0.12),
        highlightColor: tokens.accent.withValues(alpha: 0.16),
        focusColor: tokens.accent.withValues(alpha: 0.24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  FollowCoverImage(
                    cover: room.cover,
                    fallbackLabel: room.category.isEmpty
                        ? room.site
                        : displayCategoryName(
                            room.site,
                            room.category,
                            room.cid,
                          ),
                    offline: !_live,
                  ),
                  // 左上:平台徽章(web `.platform-cover-badge` 贴左上)。
                  Positioned(
                    left: 0,
                    top: 0,
                    child: CoverPlatformBadge(
                      key: const Key('cover-badge-platform'),
                      corner: CoverCorner.topLeft,
                      site: room.site,
                    ),
                  ),
                  // 右上:分类徽章(web `.follow-preview-cat` 贴右上)。
                  Positioned(
                    right: 0,
                    top: 0,
                    child: CoverCategoryBadge(
                      key: const Key('cover-badge-category'),
                      corner: CoverCorner.topRight,
                      category: room.category,
                      site: room.site,
                      cid: room.cid,
                    ),
                  ),
                  // 右下:热度。
                  if (_live)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: CoverOnlineBadge(
                        key: const Key('cover-badge-online'),
                        corner: CoverCorner.bottomRight,
                        online: room.online,
                      ),
                    ),
                  // 左下:特别关注 ★(本仓特有能力,占唯一空置的左下角)。
                  if (isSpecial)
                    Positioned(
                      left: 0,
                      bottom: 0,
                      child: CoverBadge(
                        key: const Key('cover-badge-special'),
                        corner: CoverCorner.bottomLeft,
                        background: tokens.coverScrim,
                        child: Icon(
                          Icons.star_rounded,
                          size: 11,
                          color: tokens.brand,
                        ),
                      ),
                    ),
                  // 离线:整封面压暗 + 居中「未开播」(web `.follow-preview-offline`)。
                  if (!_live)
                    Positioned.fill(
                      key: const Key('cover-offline-overlay'),
                      child: ColoredBox(
                        color: tokens.coverScrim.withValues(alpha: 0.55),
                        child: Center(
                          child: Text(
                            '未开播',
                            style: context.textCaption.copyWith(
                              fontSize: AppFontSize.caption,
                              color: tokens.coverScrimText,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                // 用户口径(2026-09-20):列表模式文字左侧 padding 收窄,行内容更贴分类条纹。
                padding: const EdgeInsets.fromLTRB(1, 3, 3, 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FollowAnchorName(
                      site: room.site,
                      name: room.anchorName,
                      live: _live,
                      fontSize: AppFontSize.caption,
                    ),
                    const SizedBox(height: 1),
                    TranslatedText(
                      room.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.textSecondary.copyWith(
                        fontSize: AppFontSize.label,
                        color: tokens.textSecondary,
                      ),
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
