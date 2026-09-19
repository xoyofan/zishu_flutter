/// 关注列表**共享组件**(仿 web `FollowRoomViews.vue` 的调度器)。
///
/// 「我的关注」页与播放页侧栏「关注」面板都渲染同一个 `FollowRoomList`,
/// 只有两档视图(用户口径 2026-09-20:对齐 web,页面不提供「紧凑」):
/// - [FollowDensity.card] 卡片:封面卡网格(侧栏 compact 态固定 2 列、隐藏
///   操作/统计行;页面按宽度自适应分列)。
/// - [FollowDensity.row] 列表:每个主播一行的小四列表格,行有**最大宽度
///   400px** —— 窄容器(侧栏)只放得下一列,看起来就是每主播一行;宽容器
///   (「我的关注」页)按 300–400px/列 自适应横向平铺多列,与 web
///   `FollowRoomRowView` 的 `multiColumn = pageMode` 行为一致。
///
/// 排序/筛选在 `follow_sort.dart`,本组件只负责把给定条目按给定档位铺开。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../shared/presentation/design_tokens.dart';
import '../application/follow_provider.dart';
import 'follow_entry_card.dart';
import 'follow_entry_row.dart';

/// 视图档位:卡片网格 / 单行列。
enum FollowDensity {
  card('卡片'),
  row('列表');

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

  /// 列表档列宽约束(web `FollowRoomRowView--multi-col`):
  /// 列宽下限 300px、单行上限 400px、列距 0.28rem(16px 根字号 ≈ 4.5px)。
  static const double _rowColFloor = 300;
  static const double _rowColMax = 400;
  static const double _rowColGap = 4.5;

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
      FollowDensity.row => _buildRowGrid(),
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

  /// 列表档:单行小表格自适应多列平铺。列数按「每列不小于
  /// [_rowColFloor]、不超过 [_rowColMax]」推导(逐字移植 web
  /// `computeResponsiveColCount`),行本体在列内再限宽 [_rowColMax]、
  /// 靠左放置(对齐 web `justify-self: stretch` + `max-width`)。
  Widget _buildRowGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.max(0.0, constraints.maxWidth - padding.horizontal);
        final columns = _responsiveColCount(
          width,
          floor: _rowColFloor,
          max: _rowColMax,
          gap: _rowColGap,
        );
        final cellWidth = math.max(
          1.0,
          (width - _rowColGap * (columns - 1)) / columns,
        );
        return GridView.builder(
          padding: padding,
          shrinkWrap: shrinkWrap,
          controller: controller,
          physics: shrinkWrap
              ? const NeverScrollableScrollPhysics()
              : null,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 0,
            crossAxisSpacing: _rowColGap,
            childAspectRatio: cellWidth / FollowEntryRow.rowHeight,
          ),
          itemCount: entries.length,
          itemBuilder: (context, index) => Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _rowColMax),
              child: _item(context, entries[index]),
            ),
          ),
        );
      },
    );
  }

  /// 「列宽不小于 floor、不超过 max」的列数计算(web
  /// `computeResponsiveColCount` 直译):先按下限取列数,再上调到列宽
  /// ≤ max,最后回落保证列宽 ≥ floor。
  static int _responsiveColCount(
    double inner, {
    required double floor,
    required double max,
    required double gap,
  }) {
    if (inner <= 0) return 1;
    var cols = math.max(1, ((inner + gap) / (floor + gap)).floor());
    while (cols < 64) {
      final share = (inner - (cols - 1) * gap) / cols;
      if (share <= max) break;
      cols += 1;
    }
    while (cols > 1) {
      final share = (inner - (cols - 1) * gap) / cols;
      if (share >= floor) break;
      cols -= 1;
    }
    return cols;
  }

  /// 按当前档位实例化条目组件;批量选择态透传给条目。
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
