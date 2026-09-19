/// 关注列表**共享组件**(仿 web `FollowRoomViews.vue` 的调度器)。
///
/// 「我的关注」页与播放页侧栏「关注」面板都渲染同一个 `FollowRoomList`:
/// 按 [density] 在卡片网格 / 紧凑 tile 列表 / 四列单行列表之间切换,内部统一
/// 复用 [FollowEntryCard] / [FollowEntryTile] / [FollowEntryRow]。排序/筛选在
/// `follow_sort.dart`,本组件只负责把给定条目按给定密度铺开。
///
/// [compact] 为侧栏窄列态:卡片隐藏统计/操作行、用固定 [cardColumns] 与更小
/// 元信息高;页面保持完整卡片。两者是**同一组件的不同配置**,不再各养一套视图。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../shared/presentation/design_tokens.dart';
import '../application/follow_provider.dart';
import 'follow_entry_card.dart';
import 'follow_entry_tile.dart';
import 'follow_entry_row.dart';

/// 列表密度:卡片网格 / 紧凑 Tile / 四列单行。
enum FollowDensity {
  card('卡片'),
  tile('紧凑'),
  row('单行');

  const FollowDensity(this.label);

  final String label;
}

/// 关注条目列表:根据 [density] 选用网格/列表布局,条目交给对应
/// `FollowEntry*` 组件渲染。空态由调用方自行处理(本页只铺非空列表)。
class FollowRoomList extends StatelessWidget {
  const FollowRoomList({
    super.key,
    required this.entries,
    required this.density,
    required this.onTap,
    this.compact = false,
    this.cardColumns,
    this.selectMode = false,
    this.selectedKeys = const <String>{},
    this.onLongPress,
    this.onToggleSelect,
    this.onToggleSpecial,
    this.onToggleRemind,
    this.onRemove,
    this.onAnchorTap,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.sm,
      AppSpacing.lg,
      AppSpacing.lg,
    ),
    this.shrinkWrap = false,
    this.controller,
  });

  final List<FollowEntry> entries;
  final FollowDensity density;

  /// 点击条目(进播放页 / 批量模式下由调用方改为选中)。
  final void Function(FollowEntry entry) onTap;

  /// 侧栏紧凑态:卡片元信息只留主播名 + 标题,并改用 [cardColumns] 固定列数。
  final bool compact;

  /// 卡片网格列数;为空则按内容区宽度以 `_cardMaxExtent` 自动分列(页面)。
  final int? cardColumns;

  final bool selectMode;
  final Set<String> selectedKeys;
  final void Function(FollowEntry entry)? onLongPress;
  final void Function(String key)? onToggleSelect;
  final void Function(FollowEntry entry)? onToggleSpecial;
  final void Function(FollowEntry entry)? onToggleRemind;
  final void Function(FollowEntry entry)? onRemove;
  final void Function(FollowEntry entry)? onAnchorTap;

  final EdgeInsetsGeometry padding;
  final bool shrinkWrap;
  final ScrollController? controller;

  /// 页面卡片自动分列时的最小列宽(对齐 Vue `minmax(240px, 1fr)`)。
  static const double _cardMaxExtent = 240;

  /// 卡片元信息区高度预算:页面 92(含统计/操作行),侧栏 compact 46。
  /// compact 只留「主播名 + 标题」两行 + 内层 padding(10),净高约 44,
  /// 取 46 留出字体浮点余量,避免窄列下的底部 RenderFlex 溢出。
  static const double _cardMetaHeight = 92;
  static const double _compactMetaHeight = 46;

  double _spacing() => compact ? AppSpacing.sm : AppSpacing.md;

  @override
  Widget build(BuildContext context) {
    return switch (density) {
      FollowDensity.card => _buildGrid(context),
      FollowDensity.tile => _buildList(paddingBottom: true),
      FollowDensity.row => _buildList(),
    };
  }

  /// 卡片网格:先按内容区宽(或固定 [cardColumns])算列数,再按「封面 16:9 +
  /// 元信息区」精确推导纵横比,避免不同宽度下溢出。
  ///
  /// 列宽口径与两处历史实现对齐,以免无谓改动既有 golden:页面非紧凑沿用
  /// `width / columns`(不扣间距),侧栏 compact 沿用旧 `PlayRoomGrid` 的
  /// `(width - gaps) / columns`。
  Widget _buildGrid(BuildContext context) {
    final spacing = _spacing();
    final metaBase = compact ? _compactMetaHeight : _cardMetaHeight;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.max(0.0, constraints.maxWidth - padding.horizontal);
        final columns = cardColumns ??
            math.max(1, (width / _cardMaxExtent).floor());
        final gaps = spacing * (columns - 1);
        final cardWidth = compact
            ? (width <= 0 ? 1.0 : (width - gaps) / columns)
            : (width <= 0 ? 1.0 : width / columns);
        final metaHeight = metaHeightFor(metaBase, context);
        return GridView.builder(
          padding: padding,
          shrinkWrap: shrinkWrap,
          physics: shrinkWrap
              ? const NeverScrollableScrollPhysics()
              : null,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: spacing,
            crossAxisSpacing: spacing,
            childAspectRatio:
                cardWidth / (cardWidth * 9 / 16 + metaHeight),
          ),
          itemCount: entries.length,
          itemBuilder: (context, index) => _item(context, entries[index]),
        );
      },
    );
  }

  /// 单列列表:tile 密度条目间留空隙,row 密度靠行自带底边框分隔。
  Widget _buildList({bool paddingBottom = false}) {
    return ListView.builder(
      padding: padding,
      shrinkWrap: shrinkWrap,
      controller: controller,
      physics: shrinkWrap
          ? const NeverScrollableScrollPhysics()
          : null,
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final item = _item(context, entries[index]);
        return paddingBottom
            ? Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: item,
              )
            : item;
      },
    );
  }

  /// 按当前密度实例化条目组件;批量选择态透传给条目。
  Widget _item(BuildContext context, FollowEntry entry) {
    final selected = selectedKeys.contains(entry.key);
    return switch (density) {
      FollowDensity.card => FollowEntryCard(
          entry: entry,
          compact: compact,
          selectMode: selectMode,
          selected: selected,
          onTap: () => onTap(entry),
          onLongPress:
              onLongPress == null ? null : () => onLongPress!(entry),
          onToggleSelect: () => onToggleSelect?.call(entry.key),
          onToggleSpecial: () => onToggleSpecial?.call(entry),
          onToggleRemind: () => onToggleRemind?.call(entry),
          onRemove: () => onRemove?.call(entry),
          onAnchorTap: () => onAnchorTap?.call(entry),
        ),
      FollowDensity.tile => FollowEntryTile(
          entry: entry,
          selectMode: selectMode,
          selected: selected,
          onTap: () => onTap(entry),
          onLongPress:
              onLongPress == null ? null : () => onLongPress!(entry),
          onToggleSelect: () => onToggleSelect?.call(entry.key),
          onToggleSpecial: () => onToggleSpecial?.call(entry),
          onToggleRemind: () => onToggleRemind?.call(entry),
          onRemove: () => onRemove?.call(entry),
          onAnchorTap: () => onAnchorTap?.call(entry),
        ),
      FollowDensity.row => FollowEntryRow(
          entry: entry,
          selectMode: selectMode,
          selected: selected,
          onTap: () => onTap(entry),
          onLongPress:
              onLongPress == null ? null : () => onLongPress!(entry),
          onToggleSelect: () => onToggleSelect?.call(entry.key),
          onToggleSpecial: () => onToggleSpecial?.call(entry),
          onToggleRemind: () => onToggleRemind?.call(entry),
          onRemove: () => onRemove?.call(entry),
          onAnchorTap: () => onAnchorTap?.call(entry),
        ),
    };
  }
}
