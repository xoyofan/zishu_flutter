/// 单行密度条目(共享):web `FollowRoomRowView.vue` 的**四列表格**
/// —— 分类 / 主播名 / 标题 / 观看人数,一行独占。
///
/// 「我的关注」页(`FollowRoomList` row 密度)与播放页侧栏「关注」列表
/// 共用本组件,与 web 一致:两处只有一套行视图。侧栏只显示在播,页面
/// 会显示轮播/离线,故人数列对三态都给出标注(在播=online、轮播=「轮播」
/// 小标签、离线=「未开播」)。批量模式在行首插入复选框。
library;

import 'package:flutter/material.dart';

import '../../../shared/domain/category_display.dart';
import '../../../shared/presentation/category_colors.dart';
import '../../../shared/presentation/design_tokens.dart';
import '../../../shared/presentation/platform_brands.dart';
import '../../../shared/presentation/zishu_tokens.dart';
import '../../../shared/presentation/widgets/translated_text.dart';
import '../application/follow_provider.dart';
import 'follow_common.dart';

class FollowEntryRow extends StatelessWidget {
  const FollowEntryRow({
    super.key,
    required this.entry,
    this.selectMode = false,
    this.selected = false,
    this.onTap,
    this.onLongPress,
    this.onToggleSelect,
    this.onToggleSpecial,
    this.onToggleRemind,
    this.onRemove,
    this.onAnchorTap,
  });

  /// 行高(web `--ffc-row-height: 1.4rem` 的既有 Flutter 取值),
  /// `FollowRoomList` 列表档按它推导单元格纵横比。
  static const double rowHeight = 26;

  final FollowEntry entry;
  final bool selectMode;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onToggleSelect;
  final VoidCallback? onToggleSpecial;
  final VoidCallback? onToggleRemind;
  final VoidCallback? onRemove;
  final VoidCallback? onAnchorTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final room = entry.room;
    final live = entry.isLive;
    final replay = entry.isReplay;
    final brand = PlatformBrandCatalog.byId(room.site);
    final selectedBg = (brand?.color ?? tokens.accent).withValues(alpha: 0.14);
    final category = displayCategoryName(room.site, room.category, room.cid);
    final categoryStyle = CategoryColors.opaqueFor(
      category: room.category,
      site: room.site,
      cid: room.cid,
    );

    return Material(
      // 测试锚点:条目根节点(follow-entry-{site}-{roomId})。
      key: Key('follow-entry-${room.site}-${room.roomId}'),
      color: selected ? selectedBg : tokens.surface,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        // 状态反馈(全部走 token):hover 抬亮;焦点/按压用 accent 低 alpha。
        hoverColor: tokens.surfaceRaised,
        splashColor: AppStateLayer.splashOf(tokens.accent),
        highlightColor: AppStateLayer.pressedOf(tokens.accent),
        focusColor: AppStateLayer.focusOf(tokens.accent),
        child: Container(
          height: rowHeight,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: tokens.border.withValues(alpha: 0.5)),
            ),
          ),
          child: Row(
            children: [
              if (selectMode) ...[
                SizedBox(
                  width: 18,
                  height: 18,
                  child: Checkbox(
                    value: selected,
                    onChanged: (_) => onToggleSelect?.call(),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    activeColor: tokens.accent,
                    checkColor: tokens.surfaceSoft,
                    side: BorderSide(color: tokens.border),
                    // hover/焦点/按压状态层走 token(默认是 ThemeData 的白 4%/12%)。
                    overlayColor: controlStateLayer(tokens),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
              ],
              // 分类条:分类色底 + 中性前景(对齐 web 行首分类列)。
              SizedBox(
                width: 54,
                child: Container(
                  height: double.infinity,
                  alignment: Alignment.center,
                  color: categoryStyle?.background.withValues(alpha: 0.18),
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Text(
                    category,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: context.textCaption.copyWith(
                      fontSize: AppFontSize.label,
                      color: tokens.textSecondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // 主播名:固定列宽,平台色(在播),特别关注 ★ 前缀,单行省略。
              SizedBox(
                width: 84,
                child: Row(
                  children: [
                    if (entry.isSpecial) ...[
                      Icon(Icons.star_rounded, size: 11, color: tokens.brand),
                      const SizedBox(width: 2),
                    ],
                    Expanded(
                      child: MouseRegion(
                        cursor: onAnchorTap == null
                            ? MouseCursor.defer
                            : SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: onAnchorTap,
                          // 可点主播名:补指针光标。
                          child: FollowAnchorName(
                            site: room.site,
                            name: room.anchorName,
                            live: live,
                            fontSize: AppFontSize.caption,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              // 标题:弹性列,单行省略。
              Expanded(
                child: TranslatedText(
                  room.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textCaption.copyWith(
                    color: tokens.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // 观看人数列:在播人形图标 + 数字;轮播「轮播」小标签;离线「未开播」。
              if (live)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.people_alt_rounded,
                      size: 11,
                      color: tokens.liveBadge,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      room.online,
                      style: context.textCaption.copyWith(
                        fontSize: AppFontSize.label,
                        color: tokens.textSecondary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                )
              else if (replay)
                const FollowReplayBadge()
              else
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      size: 11,
                      color: tokens.textSecondary,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      '未开播',
                      style: context.textCaption.copyWith(
                        fontSize: AppFontSize.label,
                        color: tokens.textSecondary,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
