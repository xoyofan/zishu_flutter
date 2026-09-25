/// 首页「按平台独立区块」数据层:每个可浏览平台一个独立分页 controller,
/// 互不阻塞 —— 单平台失败/变慢只影响自己的区块,其它平台照常渲染。
///
/// 与单平台页的 [browseRoomsProvider] 分开:
/// - 单平台页(/twitch 等)保持旧的单请求路径不变;
/// - `site == 'all'` 首页改走这里的按平台 family(见 `HomeSections`)。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_parser/live_parser.dart';

import '../../../shared/application/browse_source.dart';
import '../../../shared/application/providers.dart';
import '../../../shared/presentation/platform_brands.dart';

/// 首页区块的平台清单:与侧栏/顶栏平台切换同一口径
/// ([PlatformBrandCatalog.navigationPlatforms],fixture 构建为全量目录,
/// 真实解析构建按注册表 browse 能力裁剪),去掉「全平台」自身。
List<PlatformBrand> get homeSectionBrands => [
  for (final brand in PlatformBrandCatalog.navigationPlatforms)
    if (brand.id != 'all') brand,
];

/// 平台区块房间查询参数:(site, limit) 唯一确定一个区块实例。
///
/// [limit] 是**首屏请求条数 = 当前网格列数**(`AppRoomGrid.columnsFor`):
/// 窗口宽度跨断点 → 列数变化 → family key 变化 → 新 key 按新 limit
/// 重新拉取(旧 key 随之失联释放),不需要在 controller 里做补齐逻辑。
class PlatformRoomsQuery {
  const PlatformRoomsQuery({required this.site, required this.limit});

  /// 平台 id(不含 `all`)。
  final String site;

  /// 首屏请求条数(当前网格列数)。
  final int limit;

  @override
  bool operator ==(Object other) =>
      other is PlatformRoomsQuery && other.site == site && other.limit == limit;

  @override
  int get hashCode => Object.hash(site, limit);

  @override
  String toString() => 'PlatformRoomsQuery(site: $site, limit: $limit)';
}

/// 单平台区块 controller:按 (site, limit) 拉第一页,支持追加分页与刷新。
///
/// 与 [BrowseRoomController] 同构,差异只有三点:
/// 1. 首屏下发 [PlatformRoomsQuery.limit](单平台页旧路径不指定 limit);
/// 2. 结果按 [PlatformRoomsQuery.site] 过滤 —— 真实解析源按 site 拉取天然
///    同平台,fixture 源不按 site 过滤(单平台页「渲染全部样例」契约),
///    区块层兜底保证「区块 = 平台」不变量;
/// 3. 各实例互相独立:某平台抛错只把自己的 state 置为 AsyncError。
class PlatformRoomsController extends AsyncNotifier<RoomListResult> {
  PlatformRoomsController(this.query);

  /// family 参数,由 [platformRoomsProvider] 创建实例时注入。
  final PlatformRoomsQuery query;

  bool _loadingMore = false;

  @override
  Future<RoomListResult> build() async {
    // watch 数据源端口:换实现时自动重建。
    final source = ref.watch(browseSourceProvider);
    return _firstPage(source);
  }

  Future<RoomListResult> _firstPage(BrowseSource source) async {
    final result = await source.fetchRooms(
      site: query.site,
      page: 1,
      limit: query.limit,
    );
    return _platformOnly(result);
  }

  /// 区块只渲染本平台房间(见类注释第 2 点)。
  RoomListResult _platformOnly(RoomListResult result) => RoomListResult(
    rooms: [
      for (final room in result.rooms)
        if (room.site == query.site) room,
    ],
    page: result.page,
    hasMore: result.hasMore,
  );

  /// 加载下一页并追加到现有列表;防重入,无更多时为空操作。
  Future<void> loadMore() async {
    final current = state.value;
    if (_loadingMore || current == null || !current.hasMore) return;
    _loadingMore = true;
    try {
      final next = await ref
          .read(browseSourceProvider)
          .fetchRooms(
            site: query.site,
            page: current.page + 1,
            limit: query.limit,
          );
      state = AsyncData(
        RoomListResult(
          rooms: [...current.rooms, ..._platformOnly(next).rooms],
          page: next.page,
          hasMore: next.hasMore,
        ),
      );
    } catch (_) {
      // 追加失败保留当前数据,下次触发会再试。
    } finally {
      _loadingMore = false;
    }
  }

  /// 回到第一页重新拉取;失败时回退旧数据,避免把已有列表刷成错误态。
  Future<void> refresh() async {
    final previous = state.value;
    state = AsyncLoading<RoomListResult>();
    try {
      state = AsyncData(await _firstPage(ref.read(browseSourceProvider)));
    } catch (error, stackTrace) {
      state = previous != null
          ? AsyncData(previous)
          : AsyncError(error, stackTrace);
    }
  }
}

/// (site, limit) -> 该平台首屏房间分页列表。
final platformRoomsProvider =
    AsyncNotifierProvider.family<
      PlatformRoomsController,
      RoomListResult,
      PlatformRoomsQuery
    >(PlatformRoomsController.new);
