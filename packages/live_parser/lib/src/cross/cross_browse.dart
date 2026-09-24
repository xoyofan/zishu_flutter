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

/// 聚合浏览本轮所有实际请求的来源都全部失败时抛出。
///
/// 用于区分「确实没有房间」的空结果与「请求全挂了」的错误态:
/// 至少一站成功(即使成功结果为空)时不抛,部分失败继续隔离。
class CrossBrowseAllSourcesFailed implements Exception {
  const CrossBrowseAllSourcesFailed(this.failures);

  /// 站点 id -> 该站本轮的原始失败原因,便于逐站诊断。
  final Map<String, Object> failures;

  @override
  String toString() =>
      '全平台浏览失败: ${failures.length} 个来源本轮全部失败; '
      '${failures.entries.map((e) => '${e.key}: ${e.value}').join('; ')}';
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
const List<String> _canonicalCrossSiteOrder = [
  'douyu',
  'huya',
  'bilibili',
  'douyin',
  'kuaishou',
  'yy',
  'twitch',
  'soop',
  'youtube',
];

List<String> eligibleCrossBrowseSites(SiteRegistry registry) {
  bool eligible(String site) {
    if (site == kCrossSiteId) return false;
    final registration = registry[site];
    return registration?.capabilities.browse == true &&
        registration?.browse != null;
  }

  final result = <String>[
    for (final site in _canonicalCrossSiteOrder)
      if (eligible(site)) site,
  ];
  for (final site in registry.supportedSites) {
    if (eligible(site) && !result.contains(site)) result.add(site);
  }
  return List.unmodifiable(result);
}

class CrossBrowseRepository implements BrowseRepository {
  CrossBrowseRepository({
    required this.registry,
    List<String>? siteIds,
    this.catalog = const CrossCatalog(),
    this.mergeMode = CrossMergeMode.interleaved,
  }) : siteIds = siteIds ?? eligibleCrossBrowseSites(registry);

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

    final results = <_SiteRooms>[];
    // 控制跨平台请求并发,避免 all 首页同时打出全部平台请求。
    for (var offset = 0; offset < targets.length; offset += 4) {
      final chunk = targets.skip(offset).take(4);
      results.addAll(
        await Future.wait([
          for (final site in chunk)
            _fetchSite(
              site: site,
              category: category,
              page: request.page,
              limit: perSite,
            ),
        ]),
      );
    }

    // 本轮所有实际请求的来源都失败时抛聚合错,不能伪装成成功空列表。
    final failures = <String, Object>{
      for (final result in results)
        if (result.error != null) result.site: result.error!,
    };
    if (failures.length == targets.length) {
      throw CrossBrowseAllSourcesFailed(Map.unmodifiable(failures));
    }

    var hasMore = false;
    final buckets = <List<RoomSummary>>[];
    for (final result in results) {
      if (result.error != null) continue; // 部分失败隔离:失败站本轮空缺。
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
    } on Object catch (error) {
      // 单平台失败隔离:记录原始错误,该站本轮空缺,其余平台照常展示;
      // 若全部来源都失败,由 fetchRooms 统一抛出。
      return _SiteRooms(site: site, rooms: const [], hasMore: false, error: error);
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
  List<String>? siteIds,
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
  const _SiteRooms({
    required this.site,
    required this.rooms,
    required this.hasMore,
    this.error,
  });

  final String site;
  final List<RoomSummary> rooms;
  final bool hasMore;

  /// 该站本轮的原始失败原因;非 null 表示请求失败而非空结果。
  final Object? error;
}
