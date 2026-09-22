part of '../play_side_panel.dart';

/// 侧栏「关注」tab:对齐 SFVideoLive `PlayFollowRecommendTabs.vue` ——
/// 顶部视图切换(封面网格 / 紧凑列表)+ 平台筛选 chips,下方用预览网格呈现关注,
/// 开播优先排序。空态提示与「我的关注」标题文案保持不变(测试锚点)。
class _FollowPanel extends ConsumerStatefulWidget {
  const _FollowPanel();

  @override
  ConsumerState<_FollowPanel> createState() => _FollowPanelState();
}

class _FollowPanelState extends ConsumerState<_FollowPanel> {
  /// true = 封面网格,false = 紧凑列表(每条一行)。
  /// **默认列表**是用户口径(2026-09-19:「默认用列表显示 列表显示每个
  /// 是一行」);web 真源默认封面预览(`previewCover: true`),此处有意偏离。
  /// 取值与变更都会写进会话级偏好 —— 切房重建后不丢。
  bool get _grid => ref.watch(playSidePanelPrefsProvider).followGrid;
  set _grid(bool value) =>
      ref.read(playSidePanelPrefsProvider.notifier).update(followGrid: value);

  String get _siteFilter => ref.watch(playSidePanelPrefsProvider).followSite;
  set _siteFilter(String value) =>
      ref.read(playSidePanelPrefsProvider.notifier).update(followSite: value);

  /// 已展示条数(分页窗口)。对齐 web `PLAY_FOLLOW_PAGE_SIZE = 48`:
  /// 首屏只放 48 条,滚到底再放一页,底部提示「向下滚动加载更多…」。
  int _visibleCount = _kFollowPageSize;

  /// 距底部多少像素内视为「滚到底」(触发下一页加载)。
  static const double _kLoadMoreTriggerExtent = 96;

  /// 单页条数(web `PLAY_FOLLOW_PAGE_SIZE`)。
  static const int _kFollowPageSize = 48;

  /// 本轮待渲染的可见条目总数(由 build 写入,供滚动回调判定还有没有下一页)。
  int _visibleTotal = 0;

  /// 侧栏可见性口径:**只显在播**(用户口径 2026-09-19:「不用显示没开播
  /// 的」)。排序 = 超关在播 → 普通在播(follow_sort 统一档位,未开播档
  /// 自然为空)。
  ///
  /// 口径沿革:2026-09-18 曾对齐 web `isPlayFollowVisible` 保留离线超关
  /// (当时为修「关注没显示」),随后被本口径覆盖 —— web 真源的离线超关
  /// 分支为有意偏离,见 follow_sort.dart 注释。
  List<FollowEntry> _visible(List<FollowEntry> entries) =>
      playSidebarFollowEntries(entries, site: _siteFilter);

  /// 滚动到底附近再放一页(web 的哨兵/scroll 触发)。
  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical ||
        _visibleTotal <= _visibleCount) {
      return false;
    }
    if (notification.metrics.maxScrollExtent - notification.metrics.pixels <=
        _kLoadMoreTriggerExtent) {
      setState(() => _visibleCount += _kFollowPageSize);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final entries = _visible(ref.watch(followProvider));
    _visibleTotal = entries.length;
    final hasMore = entries.length > _visibleCount;
    final windowed = hasMore ? entries.sublist(0, _visibleCount) : entries;
    return Column(
      key: const Key('play-side-follow-panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 无「我的关注」标题(用户口径 2026-09-19:顶部不要标题);
        // 视图切换按钮挪进平台筛选行,对齐 web `follow-tab-toolbar`
        // (list 按钮 + 筛选 chips 同一行)。
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(width: AppSpacing.sm),
            Tooltip(
              message: _grid ? '切换为列表视图' : '切换为封面预览',
              child: IconButton(
                key: const Key('play-side-follow-view-toggle'),
                onPressed: () => setState(() => _grid = !_grid),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                icon: Icon(
                  // 卡片态显示「列表」入口、列表态显示「网格」入口(点击即切)。
                  _grid ? Icons.view_list_rounded : Icons.grid_view_rounded,
                  size: 18,
                  color: _grid ? tokens.textSecondary : tokens.accent,
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                // 与「我的关注」页共用同一 [FollowPlatformFilter](web 两处
                // 同为 FollowPlatformFilter.vue):侧栏紧凑 + 6 列等宽,
                // chips 放不下自动换到第二排。
                child: FollowPlatformFilter(
                  value: _siteFilter,
                  onChanged: (site) => setState(() {
                    _siteFilter = site;
                    // 换平台等于换列表:分页窗口回到首屏(否则一换平台就直接铺满 48×n)。
                    _visibleCount = _kFollowPageSize;
                  }),
                  compact: true,
                  columns: 6,
                  chipKey: (id) => Key('play-side-follow-site-$id'),
                ),
              ),
            ),
          ],
        ),
        Expanded(
          child: entries.isEmpty
              ? const _PanelHint(
                  icon: Icons.star_border_rounded,
                  title: '我的关注',
                  text: '暂无在播关注',
                )
              : NotificationListener<ScrollNotification>(
                  onNotification: _onScroll,
                  // 与「我的关注」页共用同一 [FollowRoomList]:侧栏走 compact
                  // (卡片隐藏操作/统计、固定 2 列),两档 = 封面卡 / 列表。
                  // 列表是每主播一行的单行表格,侧栏窄列下左右 padding 再
                  // 收一档(用户口径 2026-09-20)。
                  child: FollowRoomList(
                    entries: windowed,
                    density: _grid ? FollowDensity.card : FollowDensity.row,
                    compact: true,
                    cardColumns: 2,
                    padding: EdgeInsets.fromLTRB(
                      _grid ? AppSpacing.sm : AppSpacing.xs,
                      0,
                      _grid ? AppSpacing.sm : AppSpacing.xs,
                      AppSpacing.sm,
                    ),
                    onTap: (entry) => _goRoom(entry.room),
                  ),
                ),
        ),
        if (hasMore) const _FollowMoreHint(),
      ],
    );
  }

  /// 切房：用 pushReplacement（只替换栈顶播放页）而非 go。
  ///
  /// - push：旧播放页连同其 media-kit 会话被压在栈下继续存活 → 切房泄漏；
  /// - go：整条历史栈被重置（go_router 会把壳层页也换掉）→ 播放页左上角
  ///   「返回」无栈可回，抛 `GoError: There is nothing to pop`，表现为点了没反应；
  /// - pushReplacement：旧播放页被卸载（会话随 autoDispose 收干净），
  ///   下层浏览页保留为返回目标 —— 两者兼得。
  void _goRoom(RoomSummary room) =>
      context.pushReplacement('/${room.site}/play/${room.roomId}');
}

/// 侧栏关注列表底部提示:还有更多时引导滚动。
///
/// 对齐 web `.follow-recommend__more-hint`(「向下滚动加载更多…」) —— 列表
/// 滚到底部会自动再放一页,这行提示是给用户的可见信号。
class _FollowMoreHint extends StatelessWidget {
  const _FollowMoreHint();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(
        '向下滚动加载更多…',
        textAlign: TextAlign.center,
        style: context.textCaption,
      ),
    );
  }
}

/// 自绘迷你开关(对齐 web el-switch 密度:轨道 30×16、圆角 8、滑块 12)。
///
/// 选中轨道品牌紫(tokens.accent);未选中透明底 + #3a3a3a 描边。
/// 保留 Material Switch 的 value/onChanged/Semantics(toggled) 语义,
/// 只是视觉收敛为侧栏密度尺寸。
class _PanelHint extends StatelessWidget {
  const _PanelHint({
    required this.icon,
    required this.title,
    required this.text,
  });

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 30, color: tokens.surfaceRaised),
            const SizedBox(height: AppSpacing.sm),
            Text(
              title,
              style: TextStyle(
                fontSize: AppFontSize.bodySecondary,
                fontWeight: FontWeight.w600,
                color: tokens.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(text, textAlign: TextAlign.center, style: context.textCaption),
          ],
        ),
      ),
    );
  }
}
