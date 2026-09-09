/// 全平台聚合浏览(`site = all`):并发拉取各平台首页/分类房间后合并。
///
/// 设计要点:
/// - 单平台失败被隔离,不影响其余平台结果。
/// - 分类过滤先尝试用 cross-map 中的平台原生 cid 精确拉取,再本地按分类名兜底过滤。
/// - 默认 interleaved 混排,保证首页不被单一平台霸屏;可按 `byPopularity` 切全局热度序。
library;

import '../catalog/cross_catalog.dart';
import '../contracts/contracts.dart';
import '../models/models.dart';
import '../platforms/bilibili/room_api.dart' show kBilibiliSiteId;
import '../platforms/douyu/browse.dart' show kDouyuSiteId;
import '../platforms/huya/room_api.dart' show kHuyaSiteId;
import '../utils/format_online.dart';

/// 聚合排序方式。
enum CrossMergeMode {
  /// 各平台轮流取一条,首页多平台混排。
  interleaved,

  /// 全局按在线人数降序。
  byPopularity,
}

/// 聚合站点不提供的能力(如全平台房间解析)统一抛此错误。
class UnsupportedSiteFeature implements Exception {
  const UnsupportedSiteFeature(this.site, this.feature);

  final String site;
  final String feature;

  @override
  String toString() => '站点 $site 不支持 $feature';
}

/// 占位 resolver:聚合站点没有自己的房间接口,解析必须落到具体平台。
class UnsupportedRoomResolver implements RoomResolver {
  const UnsupportedRoomResolver(this.site);

  final String site;

  /// 异步抛出,保证调用方可以用 Future 的错误处理捕获(await / catchError)。
  @override
  Future<RoomPayload> resolveRoom(RoomRequest request) async =>
      throw UnsupportedSiteFeature(site, '房间解析');
}

/// 全平台浏览仓库。
class CrossBrowseRepository implements BrowseRepository {
  CrossBrowseRepository({
    required this.registry,
    this.siteIds = const [kDouyuSiteId, kHuyaSiteId, kBilibiliSiteId],
    this.catalog = const CrossCatalog(),
    this.mergeMode = CrossMergeMode.interleaved,
  });

  /// 聚合来源注册表;与宿主使用的实例一致时新注册站点会自动纳入。
  final SiteRegistry registry;

  /// 参与聚合的平台,顺序影响混排结果。
  final List<String> siteIds;

  final CrossCatalog catalog;

  final CrossMergeMode mergeMode;

  @override
  Future<CategoryResult> fetchCategories(String site) async =>
      catalog.toCategoryResult(site: site);

  @override
  Future<RoomListResult> fetchRooms(RoomListRequest request) async {
    final key = _effectiveKey(request.cid);
    final category = key == null ? null : catalog.byKey(key);
    final targets = siteIds.where((site) => registry[site]?.browse != null).toList();
    if (targets.isEmpty) {
      return RoomListResult(rooms: const [], page: request.page, hasMore: false);
    }

    // 分类模式放大单平台取量,过滤后仍够一页。
    final perSite = category == null
        ? request.limit
        : (request.limit * 2).clamp(request.limit, 60);

    final results = await Future.wait([
      for (final site in targets)
        _fetchSite(
          site: site,
          category: category,
          page: request.page,
          limit: perSite,
        ),
    ]);

    var hasMore = false;
    final buckets = <List<RoomSummary>>[];
    for (final result in results) {
      if (result.hasMore) hasMore = true;
      if (result.rooms.isNotEmpty) buckets.add(result.rooms);
    }
    if (buckets.isEmpty) {
      return RoomListResult(rooms: const [], page: request.page, hasMore: hasMore);
    }

    final merged = _merge(buckets);
    return RoomListResult(
      rooms: merged.length > request.limit
          ? merged.take(request.limit).toList(growable: false)
          : merged,
      page: request.page,
      hasMore: hasMore,
    );
  }

  /// `0` 与空串都表示全平台首页(不分类)。
  String? _effectiveKey(String? cid) {
    if (cid == null || cid.isEmpty || cid == '0') return null;
    return cid;
  }

  Future<_SiteRooms> _fetchSite({
    required String site,
    required CrossCategory? category,
    required int page,
    required int limit,
  }) async {
    final browse = registry[site]?.browse;
    if (browse == null) return _SiteRooms(site: site, rooms: const [], hasMore: false);

    try {
      final result = await browse.fetchRooms(
        RoomListRequest(
          site: site,
          cid: category == null ? null : _nativeCid(site, category),
          page: page,
          limit: limit,
        ),
      );
      final rooms = category == null
          ? result.rooms
          : result.rooms
                .where(
                  (room) => category.matches(
                    site: site,
                    cid: room.cid,
                    categoryName: room.category,
                  ),
                )
                .toList(growable: false);
      return _SiteRooms(site: site, rooms: rooms, hasMore: result.hasMore);
    } on Object {
      // 单平台失败隔离:该站本轮空缺,其余平台照常展示。
      return _SiteRooms(site: site, rooms: const [], hasMore: false);
    }
  }

  /// cross-map 登记的平台原生 cid;命中时用平台自身分类接口,结果更准。
  String? _nativeCid(String site, CrossCategory category) {
    final cids = category.siteCids[site];
    if (cids == null || cids.isEmpty) return null;
    return cids.first;
  }

  List<RoomSummary> _merge(List<List<RoomSummary>> buckets) {
    if (mergeMode == CrossMergeMode.byPopularity) {
      final rooms = buckets.expand((bucket) => bucket).toList();
      rooms.sort(
        (a, b) => parseOnlineCount(b.online).compareTo(parseOnlineCount(a.online)),
      );
      return rooms;
    }

    final merged = <RoomSummary>[];
    final cursors = List<int>.filled(buckets.length, 0);
    var remaining = true;
    while (remaining) {
      remaining = false;
      for (var i = 0; i < buckets.length; i++) {
        if (cursors[i] < buckets[i].length) {
          merged.add(buckets[i][cursors[i]++]);
          remaining = true;
        }
      }
    }
    return merged;
  }
}

/// 组装全平台聚合注册项。
///
/// [registry] 必须是最终使用的同一实例:聚合仓库持有它,宿主后续注册的站点
/// 只要 id 在 [siteIds] 中就会自动纳入聚合。
SiteRegistration buildCrossRegistration({
  required SiteRegistry registry,
  List<String> siteIds = const [kDouyuSiteId, kHuyaSiteId, kBilibiliSiteId],
  CrossCatalog catalog = const CrossCatalog(),
  CrossMergeMode mergeMode = CrossMergeMode.interleaved,
}) => SiteRegistration(
  id: kCrossSiteId,
  name: '全平台',
  capabilities: const SiteCapabilities(browse: true),
  resolver: const UnsupportedRoomResolver(kCrossSiteId),
  browse: CrossBrowseRepository(
    registry: registry,
    siteIds: siteIds,
    catalog: catalog,
    mergeMode: mergeMode,
  ),
);

class _SiteRooms {
  const _SiteRooms({required this.site, required this.rooms, required this.hasMore});

  final String site;
  final List<RoomSummary> rooms;
  final bool hasMore;
}
