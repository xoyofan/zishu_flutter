/// browse feature 状态层:controller 持有数据与分页逻辑,Widget 只负责渲染。
/// Riverpod 3 惯用法:AsyncNotifier + family(notifier 构造函数接收参数)。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_parser/live_parser.dart';

import '../../../shared/application/providers.dart';

/// 房间列表查询参数:(site, cid) 唯一确定一个分页列表实例。
class BrowseRoomQuery {
  const BrowseRoomQuery({required this.site, this.cid, this.limit});

  /// `all` 表示全平台聚合。
  final String site;

  /// 子分类 id;空表示不按分类过滤。
  final String? cid;

  /// 首屏条数上限:由首页按「当前列数 × 首屏行数」(可用宽度→列数)算出。
  /// `/all` 让聚合层给**每个平台**各要这么多条;单平台页作为该站首屏刷新
  /// 条数。loadMore 不带 limit(抖音 feed 加载更多恒 8,官方 load_more 契约)。
  final int? limit;

  @override
  bool operator ==(Object other) =>
      other is BrowseRoomQuery &&
      other.site == site &&
      other.cid == cid &&
      other.limit == limit;

  @override
  int get hashCode => Object.hash(site, cid, limit);

  @override
  String toString() =>
      'BrowseRoomQuery(site: $site, cid: $cid, limit: $limit)';
}

/// 房间列表 controller:按 (site, cid) 拉取第一页,支持分页追加与刷新。
class BrowseRoomController extends AsyncNotifier<RoomListResult> {
  BrowseRoomController(this.query);

  /// family 参数,由 [browseRoomsProvider] 创建实例时注入。
  final BrowseRoomQuery query;

  bool _loadingMore = false;

  @override
  Future<RoomListResult> build() async {
    // watch 数据源端口:G1 换 direct 实现时自动重建。
    final source = ref.watch(browseSourceProvider);
    return source.fetchRooms(
      site: query.site,
      cid: query.cid,
      page: 1,
      limit: query.limit,
    );
  }

  /// 加载下一页并把结果追加到现有列表;防重入,无更多时为空操作。
  Future<void> loadMore() async {
    final current = state.value;
    if (_loadingMore || current == null || !current.hasMore) return;
    _loadingMore = true;
    try {
      final next = await ref.read(browseSourceProvider).fetchRooms(
            site: query.site,
            cid: query.cid,
            page: current.page + 1,
          );
      state = AsyncData(
        RoomListResult(
          rooms: [...current.rooms, ...next.rooms],
          page: next.page,
          hasMore: next.hasMore,
        ),
      );
    } catch (_) {
      // 追加失败保留当前数据,下次滚动到底部会再次尝试。
    } finally {
      _loadingMore = false;
    }
  }

  /// 回到第一页重新拉取;失败时回退旧数据,避免把已有列表刷成错误态。
  Future<void> refresh() async {
    final previous = state.value;
    state = AsyncLoading<RoomListResult>();
    try {
      // 刷新与首屏同容量:F5/下拉刷新的条数 = 当前视口算出的首屏容量
      // (否则刷新一回来条数漂移,首屏可能多/空一截)。
      final result = await ref.read(browseSourceProvider).fetchRooms(
            site: query.site,
            cid: query.cid,
            page: 1,
            limit: query.limit,
          );
      state = AsyncData(result);
    } catch (error, stackTrace) {
      state =
          previous != null ? AsyncData(previous) : AsyncError(error, stackTrace);
    }
  }
}

/// (site, cid) -> 房间分页列表。
final browseRoomsProvider = AsyncNotifierProvider.family<
    BrowseRoomController, RoomListResult, BrowseRoomQuery>(
  BrowseRoomController.new,
);

/// 分类索引 controller:按 site 拉取大类分组与子分类。
class CategoryController extends AsyncNotifier<CategoryResult> {
  CategoryController(this.site);

  /// family 参数(站点 id),由 [browseCategoriesProvider] 注入。
  final String site;

  @override
  Future<CategoryResult> build() {
    return ref.watch(browseSourceProvider).fetchCategories(site);
  }

  /// 重新拉取分类索引。
  Future<void> refresh() async {
    state = AsyncLoading<CategoryResult>();
    try {
      state =
          AsyncData(await ref.read(browseSourceProvider).fetchCategories(site));
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }
}

/// site -> 分类索引。
final browseCategoriesProvider =
    AsyncNotifierProvider.family<CategoryController, CategoryResult, String>(
  CategoryController.new,
);
