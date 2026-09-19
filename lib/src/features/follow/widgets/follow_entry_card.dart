/// 卡片密度条目:对齐 SFVideoLive `FollowRoomPreviewView.vue` 的封面网格项。
///
/// 结构(自上而下):
/// - 16:9 封面:左下分类角标、右上平台角标、左上特别关注 ★、右下在线角标;
///   离线时整幅置灰压暗,并在底部压一条「未开播」暗条(参考 `.follow-preview-offline`);
/// - 元信息区:主播名(可点进主播页)→ 标题 → 统计/操作行(平台圆点 + 在线数 + 三枚操作)。
library;

import 'package:flutter/material.dart';
import 'package:live_parser/live_parser.dart';

import '../../../shared/domain/category_display.dart';
import '../../../shared/presentation/design_tokens.dart';
import '../../../shared/presentation/platform_brands.dart';
import '../../../shared/presentation/zishu_tokens.dart';
import '../application/follow_provider.dart';
import 'follow_common.dart';

class FollowEntryCard extends StatelessWidget {
  const FollowEntryCard({
    super.key,
    required this.entry,
    this.selectMode = false,
    this.selected = false,
    this.compact = false,
    this.onTap,
    this.onLongPress,
    this.onToggleSelect,
    this.onToggleSpecial,
    this.onToggleRemind,
    this.onRemove,
    this.onAnchorTap,
  });

  final FollowEntry entry;

  /// 批量选择模式:显示复选框、点击改为切换选择。
  final bool selectMode;
  final bool selected;

  /// 侧栏紧凑态:元信息区只留「主播名 + 标题」,隐藏统计/操作行,
  /// 以适配窄列宽(对齐 web `FollowRoomPreviewView` 的 preview-compact/
  /// show-stats=false)。与「我的关注」页共用同一组件,仅配置不同。
  final bool compact;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onToggleSelect;
  final VoidCallback? onToggleSpecial;
  final VoidCallback? onToggleRemind;
  final VoidCallback? onRemove;

  /// 点击主播名进入主播页。
  final VoidCallback? onAnchorTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final room = entry.room;
    final live = entry.isLive;
    final replay = entry.isReplay;
    return Container(
      // 测试锚点:条目根节点(follow-entry-{site}-{roomId})。
      key: Key('follow-entry-${room.site}-${room.roomId}'),
      // 批量模式下选中项用品牌金描边提示。
      foregroundDecoration: BoxDecoration(
        borderRadius: AppRadius.allMd,
        border: Border.all(
          color: selected ? tokens.brand : tokens.border,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: Material(
        color: tokens.surface,
        borderRadius: AppRadius.allMd,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildCover(context, room),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.sm,
                    6,
                    AppSpacing.sm,
                    4,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 主播名:参考实现的封面下一律先给主播。
                      GestureDetector(
                        onTap: onAnchorTap,
                        child: Row(
                          children: [
                            if (entry.isSpecial) ...[
                              Icon(Icons.star_rounded,
                                  size: 12, color: tokens.brand),
                              const SizedBox(width: 2),
                            ],
                            Flexible(
                              child: FollowAnchorName(
                                site: room.site,
                                name: room.anchorName,
                                live: live,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        room.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.textSecondary.copyWith(
                          fontSize: 11,
                          color: tokens.textSecondary,
                        ),
                      ),
                      if (!compact) ...[
                        const Spacer(),
                        // 统计/操作行:平台圆点 + 在线数/轮播标,右侧三枚操作。
                        // 侧栏 compact 态隐藏(对齐 web show-stats=false)。
                        Row(
                        children: [
                          FollowPlatformDot(site: room.site),
                          const SizedBox(width: 4),
                          Icon(
                            live
                                ? Icons.people_alt_rounded
                                : (replay
                                      ? Icons.repeat_rounded
                                      : Icons.schedule_rounded),
                            size: 10,
                            color: live
                                ? tokens.liveBadge
                                : (replay
                                      ? kFollowReplayAccent
                                      : tokens.textSecondary),
                          ),
                          const SizedBox(width: 2),
                          Flexible(
                            child: Text(
                              // 在播:在线数;轮播:「轮播」;离线:有开播
                              // 记录显示「上次开播」,否则「未开播」
                              // (对齐 web offlineLastLiveLabel)。
                              live
                                  ? room.online
                                  : (replay ? '轮播' : offlineLastLiveLabel(entry.lastLiveAt)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.textCaption.copyWith(
                                fontSize: 10,
                                color: live
                                    ? tokens.textPrimary
                                    : (replay
                                          ? kFollowReplayAccent
                                          : tokens.textSecondary),
                              ),
                            ),
                          ),
                          if (!selectMode) ...[
                            const Spacer(),
                            FollowIconAction(
                              icon: entry.isSpecial
                                  ? Icons.star_rounded
                                  : Icons.star_border_rounded,
                              tooltip:
                                  entry.isSpecial ? '取消特别关注' : '设为特别关注',
                              active: entry.isSpecial,
                              onPressed: onToggleSpecial,
                            ),
                            FollowIconAction(
                              icon: entry.remindOn
                                  ? Icons.notifications_active_rounded
                                  : Icons.notifications_none_rounded,
                              tooltip:
                                  entry.remindOn ? '关闭开播提醒' : '开启开播提醒',
                              active: entry.remindOn,
                              onPressed: onToggleRemind,
                            ),
                            FollowIconAction(
                              icon: Icons.delete_outline_rounded,
                              tooltip: '移除关注',
                              danger: true,
                              onPressed: onRemove,
                            ),
                          ],
                        ],
                      ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 16:9 封面:分类(左下)/ 平台(右上)/ ★(左上)/ 在线·轮播(右下),
  /// 离线压暗 + 未开播条(轮播不置灰,金黄角标区分)。
  Widget _buildCover(BuildContext context, RoomSummary room) {
    final tokens = context.tokens;
    final brand = PlatformBrandCatalog.byId(room.site);
    final live = entry.isLive;
    final replay = entry.isReplay;
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(
        fit: StackFit.expand,
        children: [
          FollowCoverImage(
            cover: room.cover,
            fallbackLabel: room.category.isEmpty
                ? room.site
                : displayCategoryName(room.site, room.category, room.cid),
            // 轮播有内容在播,封面不置灰(web replay 态同在线封面)。
            offline: !live && !replay,
          ),
          // 左下:分类角标(品牌色底 + 深色字)。
          if (room.category.isNotEmpty)
            Positioned(
              left: 0,
              bottom: 0,
              child: FollowCoverTag(
                accent: brand?.color,
                child: Text(
                  // 跨平台统一中文分类名:命中映射用 canonical 名,否则回落平台原名。
                  displayCategoryName(room.site, room.category, room.cid),
                  style: context.textCaption.copyWith(
                    fontSize: 10,
                    color: tokens.surfaceSoft,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          // 右上:平台角标(品牌色底)。
          Positioned(
            right: 0,
            top: 0,
            child: FollowCoverTag(
              accent: brand?.color,
              child: Text(
                brand?.name ?? room.site,
                style: context.textCaption.copyWith(
                  fontSize: 10,
                  color: tokens.surfaceSoft,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          // 左上:特别关注 ★ / 批量模式复选框。
          Positioned(
            left: 0,
            top: 0,
            child: selectMode
                ? _SelectBox(selected: selected, onChanged: (_) => onToggleSelect?.call())
                : (entry.isSpecial
                    ? FollowCoverTag(
                        child: Icon(
                          Icons.star_rounded,
                          size: 12,
                          color: tokens.brand,
                        ),
                      )
                    : const SizedBox.shrink()),
          ),
          // 右下:在线人数;轮播改显金黄「轮播」角标;
          // 离线不重复显示(底部已有未开播条)。
          if (live)
            Positioned(
              right: 0,
              bottom: 0,
              child: FollowCoverTag(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.people_alt_rounded,
                        size: 10, color: tokens.liveBadge),
                    const SizedBox(width: 3),
                    Text(
                      room.online,
                      style: context.textCaption.copyWith(
                        fontSize: 10,
                        color: tokens.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (replay)
            Positioned(
              right: 0,
              bottom: 0,
              child: FollowCoverTag(
                accent: kFollowReplayAccent,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.repeat_rounded,
                        size: 10, color: kFollowReplayAccent),
                    const SizedBox(width: 3),
                    Text(
                      '轮播',
                      style: context.textCaption.copyWith(
                        fontSize: 10,
                        color: kFollowReplayAccent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // 离线遮罩条:整幅底部压一条暗带,显示「未开播」(轮播不压)。
          if (!live && !replay)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 3),
                color: tokens.textPrimary.withValues(alpha: 0.62),
                alignment: Alignment.center,
                child: Text(
                  // 与元信息行同源:有记录显示「上次开播」,否则「未开播」。
                  offlineLastLiveLabel(entry.lastLiveAt),
                  style: context.textCaption.copyWith(
                    fontSize: 10,
                    color: tokens.surface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 批量模式复选框(加浅色底保证在封面上可见)。
class _SelectBox extends StatelessWidget {
  const _SelectBox({required this.selected, required this.onChanged});

  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      decoration: BoxDecoration(
        color: tokens.surfaceSoft.withValues(alpha: 0.85),
        borderRadius: AppRadius.allSm,
      ),
      child: Checkbox(
        value: selected,
        onChanged: (value) => onChanged(value ?? false),
        visualDensity: VisualDensity.compact,
        activeColor: tokens.brand,
        checkColor: tokens.surfaceSoft,
        side: BorderSide(color: tokens.border),
      ),
    );
  }
}
