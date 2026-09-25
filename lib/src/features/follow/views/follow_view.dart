/// 我的关注页(U7):平台筛选 + 排序 + 两档视图 + 批量管理。
/// 对齐 SFVideoLive FollowView 的信息结构(Flutter 重写;用户口径
/// 2026-09-20:只保留 卡片/列表 两档,不提供「紧凑」):
/// 业务状态收敛在 FollowController,本页只持有筛选/视图/选择等视图状态。
/// 列表铺陈交给共享组件 [FollowRoomList](与播放页侧栏「关注」同一套视图)。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/presentation/design_tokens.dart';
import '../../../shared/presentation/zishu_tokens.dart';
import '../../../shared/application/browse_source.dart';
import '../../../shared/application/providers.dart';
import '../application/follow_provider.dart';
import '../application/follow_sort.dart';
import '../widgets/follow_empty_state.dart';
import '../widgets/follow_platform_filter.dart';
import '../widgets/follow_room_list.dart';

class FollowView extends ConsumerStatefulWidget {
  const FollowView({super.key});

  @override
  ConsumerState<FollowView> createState() => _FollowViewState();
}

class _FollowViewState extends ConsumerState<FollowView> {
  String _siteFilter = 'all';
  FollowDensity _density = FollowDensity.card;
  bool _batchMode = false;
  bool _refreshing = false;
  bool _importing = false;
  bool _importingLive = false;
  final Set<String> _selectedKeys = {};

  /// 平台筛选 + 排序(纯视图计算,不改动 controller 状态)。
  ///
  /// 排序口径见 [visibleFollowEntries]:**超关 → 开播 → 轮播 → 未直播**,
  /// 档内按观看数倒序、缺失沉底、平局回退关注时间倒序。
  /// 抽到 follow_sort.dart 是为了与播放页侧栏关注面板共用同一口径;
  /// 排序方式已固定(无下拉,用户口径 2026-09-22),走默认 liveFirst。
  List<FollowEntry> _visible(List<FollowEntry> entries) =>
      visibleFollowEntries(entries, site: _siteFilter);

  /// 刷新封面与状态:真实解析源走 [FollowController.refreshStatuses],
  /// fixture / 未开真实解析保持原「模拟耗时」反馈,不产生任何网络调用。
  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    final refresher = ref.read(roomRefresherProvider);
    if (refresher == null) {
      await Future<void>.delayed(const Duration(milliseconds: 600));
    } else {
      // 用户主动刷新 → 全量(定时轮询走分批,见 follow_status_poller.dart)。
      final refreshed = await ref
          .read(followProvider.notifier)
          .refreshStatuses();
      if (mounted && refreshed == 0) {
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(const SnackBar(content: Text('状态刷新失败,请稍后再试')));
      }
    }
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
          onPressed: () => ref
              .read(followProvider.notifier)
              .addFromRoom(
                entry.room,
                isSpecial: entry.isSpecial,
                remindOn: entry.remindOn,
                followedAt: entry.followedAt,
              ),
        ),
      ),
    );
  }

  Future<void> _importDouyin() async {
    if (_importing) return;
    setState(() => _importing = true);
    final progress = ValueNotifier(const FollowImportProgress(page: 0, imported: 0));
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ValueListenableBuilder<FollowImportProgress>(
          valueListenable: progress,
          builder: (context, value, _) => AlertDialog(
            title: const Text('正在导入抖音关注'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const LinearProgressIndicator(),
                const SizedBox(height: AppSpacing.md),
                Text(
                  value.refreshing
                      ? '正在批量刷新当前直播状态…'
                      : '第 ${value.page} 页 · 已发现 ${value.imported}${value.total > 0 ? ' / ${value.total}' : ''} 个关注',
                ),
              ],
            ),
          ),
        ),
      ),
    );
    try {
      final notifier = ref.read(followProvider.notifier);
      final added = await notifier.importDouyinFollows(
        onProgress: (value) => progress.value = value,
      );
      progress.value = FollowImportProgress(
        page: progress.value.page,
        imported: added,
        total: progress.value.total,
        refreshing: true,
      );
      await notifier.refreshStatuses();
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      _toast(added == 0 ? '没有新增抖音关注,已刷新直播状态' : '已导入 $added 个抖音关注并刷新状态');
    } catch (_) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      if (mounted) _toast('抖音关注导入失败,请检查登录 Cookie');
    } finally {
      progress.dispose();
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _importLive() async {
    if (_importingLive) return;
    setState(() => _importingLive = true);
    try {
      final added = await ref
          .read(followProvider.notifier)
          .importDouyinLiveFollows();
      if (!mounted) return;
      _toast(added == 0 ? '没有发现新的直播关注' : '已导入 $added 个直播关注');
    } catch (_) {
      if (mounted) _toast('直播关注导入失败,请稍后重试');
    } finally {
      if (mounted) setState(() => _importingLive = false);
    }
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
          Text('我的关注', style: context.textTitle.copyWith(fontSize: AppFontSize.headline)),
          const Spacer(),
          Flexible(
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (_siteFilter == 'douyin') ...[
                  if (_importingLive)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    TextButton.icon(
                      onPressed: _importLive,
                      icon: Icon(
                        Icons.podcasts_rounded,
                        size: 16,
                        color: tokens.liveBadge,
                      ),
                      label: Text(
                        '导入直播中',
                        style: context.textBody.copyWith(
                          color: tokens.liveBadge,
                        ),
                      ),
                    ),
                  if (_importing)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    TextButton.icon(
                      onPressed: _importDouyin,
                      icon: Icon(
                        Icons.download_rounded,
                        size: 16,
                        color: tokens.textSecondary,
                      ),
                      label: Text(
                        '导入抖音关注',
                        style: context.textBody.copyWith(
                          color: tokens.textSecondary,
                        ),
                      ),
                    ),
                ],
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
                    icon: Icon(
                      Icons.refresh_rounded,
                      size: 20,
                      color: tokens.textSecondary,
                    ),
                  ),
                if (_batchMode) ...[
                  TextButton(
                    onPressed: _exitBatch,
                    child: Text(
                      '取消',
                      style: context.textBody.copyWith(
                        color: tokens.textSecondary,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _toggleSelectAll(items),
                    child: Text(
                      _allSelected(items) ? '全不选' : '全选',
                      style: context.textBody,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _selectedKeys.isEmpty ? null : _deleteSelected,
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      size: 16,
                      color: tokens.error,
                    ),
                    label: Text(
                      '删除所选 (${_selectedKeys.length})',
                      style: context.textBody.copyWith(color: tokens.error),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _selectedKeys.isEmpty
                        ? null
                        : () => _setRemindSelected(true),
                    icon: Icon(
                      Icons.notifications_active_rounded,
                      size: 16,
                      color: tokens.accent,
                    ),
                    label: Text(
                      '开提醒 (${_selectedKeys.length})',
                      style: context.textBody.copyWith(color: tokens.accent),
                    ),
                  ),
                  TextButton(
                    onPressed: _selectedKeys.isEmpty
                        ? null
                        : () => _setRemindSelected(false),
                    child: Text(
                      '关提醒',
                      style: context.textBody.copyWith(
                        color: tokens.textSecondary,
                      ),
                    ),
                  ),
                ] else
                  TextButton.icon(
                    onPressed: () => _enterBatch(),
                    icon: Icon(
                      Icons.checklist_rounded,
                      size: 16,
                      color: tokens.textSecondary,
                    ),
                    label: Text(
                      '批量管理',
                      style: context.textBody.copyWith(
                        color: tokens.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 筛选行:平台 chips + 视图切换(卡片/列表)。
  ///
  /// 原「排序方式」下拉(开播优先/最近关注)已随口径固定一并移除 ——
  /// 排序唯一口径见 follow_sort.dart,不再向用户提供选项。
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
          SegmentedButton<FollowDensity>(
            segments: [
              // ButtonSegment 本身无 key 参数,锚点落在各段的 label 上,
              // 点击 label 与点击整段等价(follow-density-card/row)。
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
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? tokens.accent.withValues(alpha: 0.18)
                    : tokens.surface,
              ),
              foregroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? tokens.accent
                    : tokens.textSecondary,
              ),
              side: WidgetStatePropertyAll(BorderSide(color: tokens.border)),
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(borderRadius: AppRadius.allSm),
              ),
              textStyle: WidgetStatePropertyAll(
                context.textBody.copyWith(
                  fontSize: AppFontSize.bodySecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _densityIcon(FollowDensity density) => switch (density) {
    FollowDensity.card => Icons.grid_view_rounded,
    FollowDensity.row => Icons.format_list_bulleted_rounded,
  };

  Widget _buildList(List<FollowEntry> items) {
    if (items.isEmpty) {
      return FollowEmptyState(onBrowse: () => context.go('/all'));
    }
    return FollowRoomList(
      entries: items,
      density: _density,
      selectMode: _batchMode,
      selectedKeys: _selectedKeys,
      // 批量模式下点击改为切换选择,长按进入批量;否则进播放页。
      onTap: (entry) => _batchMode ? _toggleSelect(entry.key) : _goPlay(entry),
      onLongPress: (entry) {
        if (!_batchMode) _enterBatch(entry.key);
      },
      onToggleSelect: _toggleSelect,
      onToggleSpecial: (entry) =>
          ref.read(followProvider.notifier).toggleSpecial(entry.key),
      onToggleRemind: (entry) =>
          ref.read(followProvider.notifier).toggleRemind(entry.key),
      onRemove: _removeEntry,
      onAnchorTap: _goAnchor,
    );
  }
}
