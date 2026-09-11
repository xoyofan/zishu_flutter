/// 我的关注页(U7):平台筛选 + 排序 + 三种密度 + 批量管理。
/// 对齐 SFVideoLive FollowView 的信息结构(Flutter 重写):
/// 业务状态收敛在 FollowController,本页只持有筛选/密度/选择等视图状态。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/presentation/design_tokens.dart';
import '../../../shared/presentation/zishu_tokens.dart';
import '../application/follow_provider.dart';
import '../widgets/follow_empty_state.dart';
import '../widgets/follow_entry_card.dart';
import '../widgets/follow_entry_row.dart';
import '../widgets/follow_entry_tile.dart';
import '../widgets/follow_platform_filter.dart';

/// 列表排序方式。
enum FollowSort {
  liveFirst('开播优先'),
  recentlyFollowed('最近关注');

  const FollowSort(this.label);

  final String label;
}

/// 列表密度:封面卡 / 横向小图 Tile / 纯文字行。
enum FollowDensity {
  card('卡片'),
  tile('紧凑'),
  row('单行');

  const FollowDensity(this.label);

  final String label;
}

class FollowView extends ConsumerStatefulWidget {
  const FollowView({super.key});

  @override
  ConsumerState<FollowView> createState() => _FollowViewState();
}

class _FollowViewState extends ConsumerState<FollowView> {
  /// 卡片密度下封面卡最大宽(对齐 Vue minmax(240px, 1fr))。
  static const double _cardMaxExtent = 240;

  /// 列视图单列目标宽(对齐 Vue 300–400px/列,取中位 340)。
  static const double _rowColumnExtent = 380;

  /// 卡片元信息区固定高:上下 12px padding + 标题/主播/操作行。
  static const double _cardMetaHeight = 106;

  String _siteFilter = 'all';
  FollowSort _sort = FollowSort.liveFirst;
  FollowDensity _density = FollowDensity.card;
  bool _batchMode = false;
  bool _refreshing = false;
  final Set<String> _selectedKeys = {};

  /// 平台筛选 + 排序(纯视图计算,不改动 controller 状态)。
  List<FollowEntry> _visible(List<FollowEntry> entries) {
    final filtered = _siteFilter == 'all'
        ? List<FollowEntry>.of(entries)
        : entries.where((e) => e.room.site == _siteFilter).toList();
    int byFollowedDesc(FollowEntry a, FollowEntry b) =>
        b.followedAt.compareTo(a.followedAt);
    switch (_sort) {
      case FollowSort.recentlyFollowed:
        return filtered..sort(byFollowedDesc);
      case FollowSort.liveFirst:
        return filtered..sort((a, b) {
          // 开播在前;同状态特别关注置前;再按关注时间倒序。
          if (a.isLive != b.isLive) return a.isLive ? -1 : 1;
          if (a.isSpecial != b.isSpecial) return a.isSpecial ? -1 : 1;
          return byFollowedDesc(a, b);
        });
    }
  }

  /// 模拟刷新封面与状态(fixture 恒定,仅模拟耗时反馈)。
  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    setState(() => _refreshing = false);
  }

  void _enterBatch([String? selectKey]) {
    setState(() {
      _batchMode = true;
      if (selectKey != null) _selectedKeys.add(selectKey);
    });
  }

  void _exitBatch() {
    setState(() {
      _batchMode = false;
      _selectedKeys.clear();
    });
  }

  void _toggleSelect(String key) {
    setState(() {
      if (_selectedKeys.contains(key)) {
        _selectedKeys.remove(key);
      } else {
        _selectedKeys.add(key);
      }
    });
  }

  bool _allSelected(List<FollowEntry> items) =>
      items.isNotEmpty && _selectedKeys.containsAll(items.map((e) => e.key));

  void _toggleSelectAll(List<FollowEntry> items) {
    setState(() {
      if (_allSelected(items)) {
        _selectedKeys.clear();
      } else {
        _selectedKeys
          ..clear()
          ..addAll(items.map((e) => e.key));
      }
    });
  }

  void _deleteSelected() {
    if (_selectedKeys.isEmpty) return;
    final count = _selectedKeys.length;
    ref.read(followProvider.notifier).removeMany(_selectedKeys);
    _exitBatch();
    _toast('已删除 $count 个关注');
  }

  void _setRemindSelected(bool enabled) {
    if (_selectedKeys.isEmpty) return;
    final count = _selectedKeys.length;
    ref.read(followProvider.notifier).setRemindMany(_selectedKeys, enabled);
    _toast(enabled ? '已为 $count 个关注开启提醒' : '已为 $count 个关注关闭提醒');
  }

  void _removeEntry(FollowEntry entry) {
    ref.read(followProvider.notifier).remove(entry.key);
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text('已移除「${entry.room.anchorName}」的关注'),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () => ref.read(followProvider.notifier).addFromRoom(
                entry.room,
                isSpecial: entry.isSpecial,
                remindOn: entry.remindOn,
                followedAt: entry.followedAt,
              ),
        ),
      ),
    );
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  void _goPlay(FollowEntry entry) =>
      context.push('/${entry.room.site}/play/${entry.room.roomId}');

  void _goAnchor(FollowEntry entry) =>
      context.push('/${entry.room.site}/anchor/${entry.room.anchorName}');

  @override
  Widget build(BuildContext context) {
    final entries = _visible(ref.watch(followProvider));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(entries),
        _buildToolbar(),
        Expanded(child: _buildList(entries)),
      ],
    );
  }

  /// 标题 + 刷新/批量操作行(批量模式下展开全选/删除/开关提醒)。
  Widget _buildHeader(List<FollowEntry> items) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Text(
            '我的关注',
            style: AppTypography.title.copyWith(fontSize: 18),
          ),
          const Spacer(),
          Flexible(
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (_refreshing)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  IconButton(
                    tooltip: '刷新封面与状态',
                    onPressed: _refresh,
                    icon: Icon(Icons.refresh_rounded,
                        size: 20, color: tokens.textSecondary),
                  ),
                if (_batchMode) ...[
                  TextButton(
                    onPressed: _exitBatch,
                    child: Text('取消',
                        style:
                            AppTypography.body.copyWith(color: tokens.textSecondary)),
                  ),
                  TextButton(
                    onPressed: () => _toggleSelectAll(items),
                    child: Text(
                      _allSelected(items) ? '全不选' : '全选',
                      style: AppTypography.body,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _selectedKeys.isEmpty ? null : _deleteSelected,
                    icon: Icon(Icons.delete_outline_rounded,
                        size: 16, color: tokens.error),
                    label: Text(
                      '删除所选 (${_selectedKeys.length})',
                      style: AppTypography.body.copyWith(color: tokens.error),
                    ),
                  ),
                  TextButton.icon(
                    onPressed:
                        _selectedKeys.isEmpty ? null : () => _setRemindSelected(true),
                    icon: Icon(Icons.notifications_active_rounded,
                        size: 16, color: tokens.brand),
                    label: Text(
                      '开提醒 (${_selectedKeys.length})',
                      style: AppTypography.body.copyWith(color: tokens.brand),
                    ),
                  ),
                  TextButton(
                    onPressed:
                        _selectedKeys.isEmpty ? null : () => _setRemindSelected(false),
                    child: Text('关提醒',
                        style:
                            AppTypography.body.copyWith(color: tokens.textSecondary)),
                  ),
                ] else
                  TextButton.icon(
                    onPressed: () => _enterBatch(),
                    icon: Icon(Icons.checklist_rounded,
                        size: 16, color: tokens.textSecondary),
                    label: Text('批量管理',
                        style:
                            AppTypography.body.copyWith(color: tokens.textSecondary)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 筛选行:平台 chips + 排序下拉 + 密度切换。
  Widget _buildToolbar() {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FollowPlatformFilter(
            value: _siteFilter,
            onChanged: (site) => setState(() => _siteFilter = site),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            decoration: BoxDecoration(
              color: tokens.surface,
              borderRadius: AppRadius.allSm,
              border: Border.all(color: tokens.border),
            ),
            child: DropdownButton<FollowSort>(
              value: _sort,
              isDense: true,
              underline: const SizedBox.shrink(),
              dropdownColor: tokens.surfaceRaised,
              icon: Icon(Icons.expand_more_rounded,
                  size: 16, color: tokens.textSecondary),
              style: AppTypography.body,
              items: [
                for (final sort in FollowSort.values)
                  DropdownMenuItem(value: sort, child: Text(sort.label)),
              ],
              onChanged: (sort) {
                if (sort != null) setState(() => _sort = sort);
              },
            ),
          ),
          SegmentedButton<FollowDensity>(
            segments: [
              // ButtonSegment 本身无 key 参数,锚点落在各段的 label 上,
              // 点击 label 与点击整段等价(follow-density-card/tile/row)。
              for (final density in FollowDensity.values)
                ButtonSegment(
                  value: density,
                  label: Text(
                    density.label,
                    // 测试锚点:密度切换段。
                    key: Key('follow-density-${density.name}'),
                  ),
                  icon: Icon(_densityIcon(density), size: 14),
                ),
            ],
            selected: {_density},
            showSelectedIcon: false,
            onSelectionChanged: (selection) =>
                setState(() => _density = selection.first),
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              backgroundColor: WidgetStateProperty.resolveWith((states) =>
                  states.contains(WidgetState.selected)
                      ? tokens.brand.withValues(alpha: 0.18)
                      : tokens.surface),
              foregroundColor: WidgetStateProperty.resolveWith((states) =>
                  states.contains(WidgetState.selected)
                      ? tokens.brand
                      : tokens.textSecondary),
              side: WidgetStatePropertyAll(BorderSide(color: tokens.border)),
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(borderRadius: AppRadius.allSm),
              ),
              textStyle: WidgetStatePropertyAll(AppTypography.body.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              )),
            ),
          ),
        ],
      ),
    );
  }

  IconData _densityIcon(FollowDensity density) => switch (density) {
        FollowDensity.card => Icons.grid_view_rounded,
        FollowDensity.tile => Icons.view_agenda_outlined,
        FollowDensity.row => Icons.format_list_bulleted_rounded,
      };

  Widget _buildList(List<FollowEntry> items) {
    if (items.isEmpty) {
      return FollowEmptyState(onBrowse: () => context.go('/all'));
    }
    const padding = EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.sm,
      AppSpacing.lg,
      AppSpacing.lg,
    );
    return switch (_density) {
      // 卡片网格:先按内容区宽算列数,再用精确格宽推导纵横比,
      // 保证「封面 16:9 + 固定元信息区」在不同宽度下都不溢出。
      FollowDensity.card => LayoutBuilder(builder: (context, constraints) {
          final width = math.max(0.0, constraints.maxWidth - padding.horizontal);
          final columns = math.max(1, (width / _cardMaxExtent).floor());
          final cardWidth = width / columns;
          return GridView.builder(
            padding: padding,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: AppSpacing.md,
              crossAxisSpacing: AppSpacing.md,
              childAspectRatio:
                  cardWidth /
                  (cardWidth * 9 / 16 + metaHeightFor(_cardMetaHeight, context)),
            ),
            itemCount: items.length,
            itemBuilder: (context, index) => _buildItem(items[index]),
          );
        }),
      FollowDensity.tile => ListView.builder(
          padding: padding,
          itemCount: items.length,
          itemBuilder: (context, index) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _buildItem(items[index]),
          ),
        ),
      // 列视图:宽屏按 300–400px/列拆成多列(对齐 `FollowRoomRowView`
      // 的 `multiColumn`),行高固定 34px,纵横比由列宽推导。
      FollowDensity.row => LayoutBuilder(builder: (context, constraints) {
          final width = math.max(0.0, constraints.maxWidth - padding.horizontal);
          final columns = math.max(1, (width / _rowColumnExtent).floor());
          final columnWidth = width / columns;
          return GridView.builder(
            padding: padding,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: AppSpacing.md,
              childAspectRatio: columnWidth / kFollowRowHeight,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) => _buildItem(items[index]),
          );
        }),
    };
  }

  /// 按当前密度渲染条目;批量模式下点击改为切换选择,长按进入批量。
  Widget _buildItem(FollowEntry entry) {
    final selected = _selectedKeys.contains(entry.key);
    void handleTap() => _batchMode ? _toggleSelect(entry.key) : _goPlay(entry);
    void handleLongPress() {
      if (!_batchMode) _enterBatch(entry.key);
    }

    return switch (_density) {
      FollowDensity.card => FollowEntryCard(
          entry: entry,
          selectMode: _batchMode,
          selected: selected,
          onTap: handleTap,
          onLongPress: handleLongPress,
          onToggleSelect: () => _toggleSelect(entry.key),
          onToggleSpecial: () =>
              ref.read(followProvider.notifier).toggleSpecial(entry.key),
          onToggleRemind: () =>
              ref.read(followProvider.notifier).toggleRemind(entry.key),
          onRemove: () => _removeEntry(entry),
          onAnchorTap: () => _goAnchor(entry),
        ),
      FollowDensity.tile => FollowEntryTile(
          entry: entry,
          selectMode: _batchMode,
          selected: selected,
          onTap: handleTap,
          onLongPress: handleLongPress,
          onToggleSelect: () => _toggleSelect(entry.key),
          onToggleSpecial: () =>
              ref.read(followProvider.notifier).toggleSpecial(entry.key),
          onToggleRemind: () =>
              ref.read(followProvider.notifier).toggleRemind(entry.key),
          onRemove: () => _removeEntry(entry),
          onAnchorTap: () => _goAnchor(entry),
        ),
      FollowDensity.row => FollowEntryRow(
          entry: entry,
          selectMode: _batchMode,
          selected: selected,
          onTap: handleTap,
          onLongPress: handleLongPress,
          onToggleSelect: () => _toggleSelect(entry.key),
          onToggleSpecial: () =>
              ref.read(followProvider.notifier).toggleSpecial(entry.key),
          onToggleRemind: () =>
              ref.read(followProvider.notifier).toggleRemind(entry.key),
          onRemove: () => _removeEntry(entry),
          onAnchorTap: () => _goAnchor(entry),
        ),
    };
  }
}
