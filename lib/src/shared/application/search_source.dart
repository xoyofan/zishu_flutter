/// 搜索数据源端口:UI 只依赖此接口;实现分为 fixture(样式开发)与 direct(真实解析)。
/// 风格对齐同目录的 browse_source.dart / parser_sources.dart。
library;

import 'package:live_parser/live_parser.dart';

import 'fixture_sources.dart';

/// 搜索数据源:平台(site)+ 关键词 + 档位 → 命中列表。
///
/// [site] 为单平台 id(如 `'douyu'` / `'huya'` / `'bilibili'`);`'all'` 表示全平台聚合
/// (并发拉取 douyu/huya/bilibili,单站失败被隔离,详见 [ParserSearchSource])。
///
/// [type] 搜索档位(主播/房间),透传给解析契约 `SearchRequest.type`;
/// 缺省 `null` = 混合(既有行为)。fixture 数据源自房间卡片、实体本身主播/
/// 房间双身份,故 [FixtureSearchSource] 忽略该参数 —— 与 web 端本地关注
/// (`matchLocalFollows`)在两档都展示的口径一致。
abstract interface class SearchSource {
  /// `site == all` 时应查询的真实站点集合。
  List<String> get aggregateSites;

  Future<List<SearchHit>> search({
    required String site,
    required String keyword,
    int limit = 20,
    SearchType? type,
  });
}

/// 真实解析实现:委托 [SiteRegistry] 中各站的 `search` 能力。
///
/// 结构照抄 parser_sources.dart 的 [ParserBrowseSource]:持有注册表,取
/// `registry[site]?.search`;未注册站点或该站不支持搜索时抛 [StateError]。
class ParserSearchSource implements SearchSource {
  ParserSearchSource({SiteRegistry? registry})
    : _registry = registry ?? buildSiteRegistry();

  final SiteRegistry _registry;

  /// 全平台聚合站点来自真实注册能力,而不是 UI fixture 目录。
  @override
  List<String> get aggregateSites => [
        for (final site in _registry.supportedSites)
          if (_registry[site]?.search != null &&
              (_registry[site]!.capabilities.roomSearch ||
                  _registry[site]!.capabilities.anchorSearch))
            site,
      ];

  @override
  Future<List<SearchHit>> search({
    required String site,
    required String keyword,
    int limit = 20,
    SearchType? type,
  }) async {
    if (site == 'all') {
      return _searchAll(keyword, limit, type);
    }
    final repo = _registry[site]?.search;
    if (repo == null) {
      throw StateError('站点 $site 不支持搜索');
    }
    final result = await repo.search(
      SearchRequest(site: site, query: keyword, limit: limit, type: type),
    );
    return result.hits;
  }

  /// 并发聚合三站,单站失败被隔离(该站本轮空缺,其余平台照常展示)。
  Future<List<SearchHit>> _searchAll(
    String keyword,
    int limit,
    SearchType? type,
  ) async {
    final results = await Future.wait([
      for (final site in aggregateSites) _searchSite(site, keyword, limit, type),
    ]);
    return results.expand((hits) => hits).toList(growable: false);
  }

  Future<List<SearchHit>> _searchSite(
    String site,
    String keyword,
    int limit,
    SearchType? type,
  ) async {
    final repo = _registry[site]?.search;
    if (repo == null) return const [];
    try {
      final result = await repo.search(
        SearchRequest(site: site, query: keyword, limit: limit, type: type),
      );
      return result.hits;
    } on Object {
      // 单站失败隔离:该站本轮空缺,整页不空白。
      return const [];
    }
  }
}

/// fixture 实现:对 [kFixtureRooms] 做大小写不敏感过滤(开关关闭时行为不变)。
///
/// 逻辑原样搬自旧 search_provider.dart 的 `_filterRooms`,保证开关关闭时
/// 搜索页表现与今天完全一致。主播/房间档位不做区分:fixture 实体为房间
/// 卡片、主播/房间双身份(同 web 端本地关注两档都展示)。
class FixtureSearchSource implements SearchSource {
  const FixtureSearchSource();

  @override
  List<String> get aggregateSites {
    final seen = <String>{};
    return [
      for (final room in kFixtureRooms)
        if (seen.add(room.site)) room.site,
    ];
  }

  @override
  Future<List<SearchHit>> search({
    required String site,
    required String keyword,
    int limit = 20,
    SearchType? type,
  }) async {
    final lower = keyword.toLowerCase();
    return [
      for (final room in kFixtureRooms)
        if ((site == 'all' || room.site == site) &&
            (room.title.toLowerCase().contains(lower) ||
                room.anchorName.toLowerCase().contains(lower) ||
                room.category.toLowerCase().contains(lower)))
          SearchHit(
            id: room.roomId,
            anchor: room.anchorName,
            title: room.title,
            // fixture 无独立头像字段,UI 端以昵称首字占位。
            avatar: '',
            cover: room.cover,
            // 约定:online 非空视为直播中,否则未开播。
            state: room.online.isEmpty
                ? SearchHitState.offline
                : SearchHitState.live,
            category: room.category,
            online: room.online,
          ),
    ];
  }
}
