/// 全平台/平台首页:宽屏渲染「左侧栏 + 房间网格」,窄屏仅房间网格。
///
/// `site == 'all'` 仍是**单张交错混排网格**(与分区版之前的形态一致),
/// 但两件事按用户口径做了收敛:
/// - **骨架**:首屏加载中显示与真实卡等大的骨架卡,不再空白/转圈;
/// - **请求量**:按当前视口算「首屏能容纳多少张卡」(列数 × 首屏行数),
///   作为 `limit` 下发 —— `/all` 让聚合层给**每个平台**各要这么多条;
///   单平台页直接作为该站首屏刷新条数(2026-09-29 用户口径:抖音首页等
///   单平台页同样按可用宽度决定一次刷新多少个)。
///
/// 平台入口锚点 [home-platform-chip-{id}] 在左侧栏(见 [BrowseSidebar]),
/// 此处不重复渲染横向 chips 行(窄屏平台切换由 AppShell 平台条承担)。
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:live_parser/live_parser.dart';

import '../../../platforms/common/playback/playback_log.dart';
import '../../../shared/application/global_actions.dart';
import '../../../shared/presentation/design_tokens.dart';
import '../../../shared/presentation/widgets/retry_button.dart';
import '../../../shared/presentation/zishu_tokens.dart';
import '../application/browse_provider.dart';
import '../widgets/browse_sidebar.dart';
import '../widgets/room_card_skeleton.dart';
import '../widgets/room_grid.dart';

class HomeView extends ConsumerStatefulWidget {
  const HomeView({super.key, required this.site});

  /// `all` 表示全平台聚合。
  final String site;

  @override
  ConsumerState<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends ConsumerState<HomeView> {
  /// 平台切换采用 stale-while-revalidate:新平台首屏请求期间保留上一次
  /// 已渲染的网格(卡片元素继续存活),避免整块内容变成 loading 再重建。
  /// 记录 site:**只复用同一 site** 的旧数据,避免 `/all` 与平台页之间
  /// 互相污染(否则从 `/all` 切到 `/huya` 会先把全平台混排网格留在屏幕上,
  /// 或首屏被上一站数据顶掉而不显示骨架)。
  static RoomListResult? _lastVisibleRooms;
  static String? _lastVisibleSite;

  /// 仅测试用:清空静态缓存,避免跨用例泄漏。
  @visibleForTesting
  static void debugResetVisibleRooms() {
    _lastVisibleRooms = null;
    _lastVisibleSite = null;
  }

  /// F5 刷新本平台首页(浏览器式):与下拉刷新同通路(refresh 保留旧值回退)。
  void _refreshRooms() {
    unawaited(
      ref
          .read(browseRoomsProvider(_queryFor(context)).notifier)
          .refresh(),
    );
  }

  @override
  void dispose() {
    GlobalActions.unregister(GlobalActionNames.refreshHome, owner: this);
    super.dispose();
  }

  /// 首屏容量 = 列数 × 首屏行数(2026-09-29 用户口径:按**当前可用宽度**
  /// 与**单个卡片的宽高**估算一次刷新该拉多少张卡)。
  ///
  /// 三个因子与 [RoomGrid] 严格同源,否则请求量与实际能放下的卡片数不匹配:
  /// - 列数:`AppRoomGrid.columnsFor(视口宽)` —— RoomGrid 刻意让列数跟视口
  ///   断点走(对齐 CSS 媒体查询),左栏收窄只影响卡片实际宽,不影响列数;
  /// - 卡宽:**内容区真实宽**([gridConstraints],已扣除左栏与分隔线)减去
  ///   网格 padding 后按列均分(再扣列间距);
  /// - 卡高:`cardWidth * 9/16 + metaHeightFor(58)`,行数 = 内容区真实高
  ///   (扣纵向 padding)÷ 卡高,向上取整。
  static int _firstScreenCapacity(
    BuildContext context,
    BoxConstraints gridConstraints,
  ) {
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final columns = AppRoomGrid.columnsFor(viewportWidth);
    final paddingH = AppSpacing.lg * 2;
    final availableWidth = gridConstraints.maxWidth - paddingH;
    final cardWidth =
        (availableWidth - AppSpacing.gridCrossAxisSpacing * (columns - 1)) /
        columns;
    final cardHeight = cardWidth * 9 / 16 + metaHeightFor(58, context);
    final availableHeight =
        math.max(0.0, gridConstraints.maxHeight - AppSpacing.lg * 2);
    final rows = math.max(1, (availableHeight / cardHeight).ceil());
    return columns * rows;
  }

  /// 桌面首页内容区估算宽:左栏按**展开态** [BrowseSidebar.width] + 1px
  /// 分隔线扣除(首屏常态;用户收起左栏后估算卡宽偏小 ~28px/列,行数误差
  /// ≤1 行,由滚动加载兜底,不值得为此把侧栏开合态上提成共享状态)。
  /// phone(<768)无侧栏。
  static double _gridAreaWidth(double windowWidth, bool isPhone) =>
      isPhone ? windowWidth : windowWidth - BrowseSidebar.width - 1;

  /// 最近一次 build 用的查询;F5 刷新回调复用,避免窗口尺寸变化后刷新量
  /// 与屏上容量脱节。
  BrowseRoomQuery? _latestQuery;

  BrowseRoomQuery _queryFor(BuildContext context) {
    // LayoutBuilder 每次构建都会先更新 [_latestQuery];此方法只剩 F5 回调
    // 一条路径,首帧兜底用窗口估算(扣侧栏展开态)。
    final cached = _latestQuery;
    if (cached != null) return cached;
    final isPhone = MediaQuery.sizeOf(context).width < AppBreakpoints.phone;
    final window = MediaQuery.sizeOf(context);
    return _buildQuery(context, window.width, window.height, isPhone);
  }

  BrowseRoomQuery _buildQuery(
    BuildContext context,
    double width,
    double height,
    bool isPhone,
  ) {
    final capacity = _firstScreenCapacity(
      context,
      BoxConstraints(
        maxWidth: _gridAreaWidth(width, isPhone),
        maxHeight: height,
      ),
    );
    return BrowseRoomQuery(site: widget.site, limit: capacity);
  }

  @override
  Widget build(BuildContext context) {
    // 注册 F5 刷新动作(builder 层快捷键经此落地,注销随本 State dispose)。
    GlobalActions.register(
      GlobalActionNames.refreshHome,
      owner: this,
      action: _refreshRooms,
    );
    // 断点沿用 AppBreakpoints.phone(768):与旧 chips 行同档,避免 768–1365
    // 区间出现平台入口真空;左栏在此档出现,内容区不再渲染 chips。
    // <768:平台切换由 AppShell 平台条(nav-platform-strip)承担。
    final isPhone = MediaQuery.sizeOf(context).width < AppBreakpoints.phone;

    // LayoutBuilder 提供本区域**真实约束**(HomeView 嵌在 app shell 内,
    // MediaQuery 窗口尺寸会高估可用宽/高):容量按真实内容区宽高估算,
    // 窗口拖动时 limit 只在行/列边界处变化 → 换 provider 重取一次首屏。
    return LayoutBuilder(
      builder: (context, constraints) {
        final query = _buildQuery(
          context,
          constraints.maxWidth,
          constraints.maxHeight,
          isPhone,
        );
        _latestQuery = query;
        return _buildBody(context, query, isPhone);
      },
    );
  }

  Widget _buildBody(BuildContext context, BrowseRoomQuery query, bool isPhone) {
    final roomsAsync = ref.watch(browseRoomsProvider(query));
    final controller = ref.read(browseRoomsProvider(query).notifier);
    final tokens = context.tokens;

    // 房间网格主体(下拉刷新 + 滚动加载 + 空态/错误)。切平台时新 provider
    // 先进入 loading,继续显示旧网格;新数据到达后只替换 RoomRecord。
    final Widget body;
    final sameSite = _lastVisibleSite == widget.site;
    switch (roomsAsync) {
      case AsyncValue(value: final value?):
        _lastVisibleRooms = value;
        _lastVisibleSite = widget.site;
        body = _body(
          context,
          rooms: value.rooms,
          hasMore: value.hasMore,
        );
      case AsyncValue(error: final _)
          when sameSite && _lastVisibleRooms != null:
        // 有旧数据时静默保留旧网格(继续展示),错误由下一次成功刷新覆盖。
        body = _body(
          context,
          rooms: _lastVisibleRooms!.rooms,
          hasMore: _lastVisibleRooms!.hasMore,
        );
      case AsyncValue(error: final error?):
        body = _ErrorRetry(
          message: '房间列表加载失败：$error',
          onRetry: controller.refresh,
        );
      // 首屏无旧数据:显示与真实卡等大的骨架卡(数量=首屏容量),
      // 而不是整块转圈,避免加载完成时布局跳动。
      default:
        body = _skeletonBody(context, count: query.limit ?? 12);
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!isPhone) BrowseSidebar(site: widget.site),
        if (!isPhone) Container(width: 1, color: tokens.border),
        Expanded(child: body),
      ],
    );
  }

  /// 骨架网格:列数/间距/格高与 [RoomGrid] 严格同源,数量=首屏容量。
  Widget _skeletonBody(BuildContext context, {required int count}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = MediaQuery.sizeOf(context).width;
        final columns = AppRoomGrid.columnsFor(viewportWidth);
        final available = constraints.maxWidth - AppSpacing.lg * 2;
        final cardWidth =
            (available - AppSpacing.gridCrossAxisSpacing * (columns - 1)) /
            columns;
        return GridView.builder(
          key: const Key('home-skeleton-grid'),
          padding: const EdgeInsets.all(AppSpacing.lg),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: AppSpacing.gridMainAxisSpacing,
            crossAxisSpacing: AppSpacing.gridCrossAxisSpacing,
            childAspectRatio:
                cardWidth / (cardWidth * 9 / 16 + metaHeightFor(58, context)),
          ),
          itemCount: count,
          itemBuilder: (context, index) => RoomCardSkeleton(
            key: Key('home-skeleton-$index'),
          ),
        );
      },
    );
  }

  /// 有数据(含刷新中)时的网格主体:下拉刷新 + 滚动加载 + 空态。
  Widget _body(
    BuildContext context, {
    required List<RoomRecord> rooms,
    required bool hasMore,
  }) {
    final query = _queryFor(context);
    final controller = ref.read(browseRoomsProvider(query).notifier);
    if (rooms.isEmpty) {
      return RefreshIndicator(
        onRefresh: controller.refresh,
        color: context.tokens.accent,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: AppSpacing.xxl * 6),
            Icon(
              Icons.live_tv_rounded,
              size: 48,
              color: context.tokens.textSecondary,
            ),
            const SizedBox(height: AppSpacing.md),
            Center(
              child: Text('暂无直播间,下拉刷新试试', style: context.textSecondary),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: controller.refresh,
      color: context.tokens.accent,
      child: RoomGrid(
        rooms: rooms,
        hasMore: hasMore,
        onLoadMore: controller.loadMore,
        onRoomTap: (room) {
          PlaybackLog.logRoomNav(
            source: 'home_grid',
            site: room.site,
            roomId: room.roomId,
          );
          context.push('/${room.site}/play/${room.roomId}');
        },
      ),
    );
  }
}

/// 错误占位:错误说明 + 重试按钮。
class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 40,
            color: context.tokens.error,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(message, style: context.textSecondary),
          const SizedBox(height: AppSpacing.lg),
          RetryButton(onRetry: onRetry),
        ],
      ),
    );
  }
}

/// 仅测试用:清空 HomeView 的静态可见缓存,避免跨用例泄漏。
@visibleForTesting
void debugResetHomeVisibleRooms() => _HomeViewState.debugResetVisibleRooms();
