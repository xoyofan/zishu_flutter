/// 播放页侧栏「相关推荐」编排:对齐 SFVideoLive web 的 `usePlayRecommend`。
///
/// **为什么重做**:旧实现只查「同平台 + 同 cid」的第一页
/// (`browseRoomsProvider(BrowseRoomQuery(site, cid))`),于是
/// - 只看得到自己平台的同分类房间(冷门分类/小平台常常整片空白),
/// - 没有热门兜底、没有分页;
/// 而参考实现(`apps/web/src/composables/usePlayRecommend.ts` +
/// `api/recommendBrowse.ts`)是**跨平台交错 + 分类映射 + 热门兜底 + 滚动加载**。
///
/// 参考实现的取数与展示规则,这里逐条复刻:
/// - 站点顺序固定 [kRecommendSiteOrder](仅取 [PlatformBrandCatalog.supportsBrowse]
///   为真的),每站 [kRecommendPerSite] 条,按站点桶**交错**合并(第 i 轮各站
///   各出一条),这样前几屏就是多平台混合而不是被单站占满;
/// - 每站取数优先级:① 房间分类能映射到该站分类 → 取该站同分类;
///   ② 映射不到 → 取该站推荐(热门,`cid == null`);③ 分类取数为空 → 回落
///   热门并记一次兜底(据此给出提示文案);④ 该站整体失败 → 本站留空、不拖垮别人;
/// - 分页:每站页号一起递增,滚动到底部触发;只剩还有更多的站点会被继续请求;
/// - 展示前统一过滤:按 `site:roomId` 去重、剔除当前房间、只保留在播。
///
/// 展示口径与参考实现的差异见 `.handoff-recommend-panel.md`(骨架占位不按站点
/// 交错插空,而是统一追加在列表尾)。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_parser/live_parser.dart';

import '../../../shared/application/browse_source.dart';
import '../../../shared/application/providers.dart';
import '../../../shared/presentation/platform_brands.dart';

/// 推荐站点顺序(与 web `api/crossBrowse.ts` 的 `BROWSE_SITES` 一致)。
///
/// 顺序即展示权重:交错合并时排在前面的站点先出现。
const List<String> kRecommendSiteOrder = <String>[
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

/// 每站每页取几条(web `RECOMMEND_PER_SITE`)。
const int kRecommendPerSite = 3;

/// 连续空页的最大重试轮数(web `RECOMMEND_MAX_EMPTY_PAGE_RETRIES`)。
///
/// 各站分页粒度不同,某一页可能整页都是已在列表里的房间;不重试就会误判
/// 「没有更多了」。
const int kRecommendEmptyPageRetries = 3;

/// 分类兜底提示文案(映射到该站分类但该分类无结果,已改用热门)。
const String kRecommendCategoryFallbackHint = '当前分类暂无推荐,已为你展示热门直播';

/// 综合兜底提示文案(分类上下文整体无结果,已改用全站热门)。
const String kRecommendMixedFallbackHint = '已展示综合推荐';

/// 当前可推荐站点:固定顺序 ∩ 支持浏览的平台(对齐 web
/// `RECOMMEND_SITE_ORDER.filter(site => site !== 'all' && supportsBrowse(site))`)。
List<String> recommendSites() => <String>[
  for (final site in kRecommendSiteOrder)
    if (PlatformBrandCatalog.supportsBrowse(site)) site,
];

/// 分类名归一:去首尾空白 + 转小写 + 去掉内部空白与常见分隔符。
///
/// 各平台分类文案大小写/间距不一(「英雄联盟」/「英雄 联盟」/「LOL」),
/// 映射必须先把噪声抹平,否则同名分类也匹配不上。
String normalizeRecommendCategory(String value) {
  final buffer = StringBuffer();
  for (final rune in value.trim().toLowerCase().runes) {
    final ch = String.fromCharCode(rune);
    if (ch.trim().isEmpty) continue;
    if (ch == '-' || ch == '_' || ch == '·' || ch == '/') continue;
    buffer.write(ch);
  }
  return buffer.toString();
}

/// 把当前房间的分类映射到 [site] 平台的分类 id。
///
/// 规则(对齐 web `findCrossCategory` + `crossCidForSite` 的意图):
/// - 同平台且房间自带 cid → 直接用房间 cid(最准,不做名字匹配);
/// - 否则按**分类名**在该平台分类索引里找:先精确匹配,再双向包含
///   (「英雄联盟」↔「英雄联盟手游」这类带后缀的档名);
/// - 找不到返回 null,由调用方走热门兜底。
String? mapRecommendCid({
  required CategoryResult? categories,
  required String category,
  required String site,
  required String contextSite,
  required String roomCid,
}) {
  final ownCid = roomCid.trim();
  if (site == contextSite && ownCid.isNotEmpty) return ownCid;
  final name = normalizeRecommendCategory(category);
  if (name.isEmpty || categories == null) return null;

  final items = <CategoryItem>[
    for (final group in categories.groups) ...group.items,
  ];
  for (final item in items) {
    if (normalizeRecommendCategory(item.name) == name) return item.cid;
  }
  for (final item in items) {
    final target = normalizeRecommendCategory(item.name);
    if (target.isEmpty) continue;
    if (target.contains(name) || name.contains(target)) return item.cid;
  }
  return null;
}

/// 能否推荐给用户:沿用全站约定「online 非空即开播」。
bool isRecommendableRoom(RoomSummary room) => room.online.trim().isNotEmpty;

/// 按站点桶交错合并出展示列表。
///
/// 逐轮(i=0,1,2…)遍历站点顺序各取第 i 条:多平台混合、且每站内部保持解析
/// 侧的相关度排序。合并时顺手做三件事 —— 跳过未开播、剔除当前房间、按
/// `site:roomId` 去重(跨站同号房间也算不同房间)。
List<RoomSummary> interleaveRecommendBuckets({
  required List<String> sites,
  required Map<String, List<RoomSummary>> buckets,
  required int perSite,
  required String currentSite,
  required String currentRoomId,
}) {
  var maxLen = perSite;
  for (final site in sites) {
    final length = buckets[site]?.length ?? 0;
    if (length > maxLen) maxLen = length;
  }
  final seen = <String>{};
  final result = <RoomSummary>[];
  for (var index = 0; index < maxLen; index++) {
    for (final site in sites) {
      final bucket = buckets[site];
      if (bucket == null || index >= bucket.length) continue;
      final room = bucket[index];
      if (!isRecommendableRoom(room)) continue;
      if (room.site == currentSite && room.roomId == currentRoomId) continue;
      if (!seen.add('${room.site}:${room.roomId}')) continue;
      result.add(room);
    }
  }
  return result;
}

/// 推荐查询参数:一条播放页(房间)对应一个推荐实例。
@immutable
class PlayRecommendArgs {
  const PlayRecommendArgs({
    required this.site,
    required this.roomId,
    required this.cid,
    required this.category,
  });

  /// 当前房间平台。
  final String site;

  /// 当前房间号(用于把当前房间从推荐里剔除)。
  final String roomId;

  /// 当前房间分类 id(可空串;解析未回填时为空)。
  final String cid;

  /// 当前房间分类名(可空串)。
  final String category;

  @override
  bool operator ==(Object other) =>
      other is PlayRecommendArgs &&
      other.site == site &&
      other.roomId == roomId &&
      other.cid == cid &&
      other.category == category;

  @override
  int get hashCode => Object.hash(site, roomId, cid, category);

  @override
  String toString() =>
      'PlayRecommendArgs(site: $site, roomId: $roomId, cid: $cid, '
      'category: $category)';
}

/// 推荐面板状态。
@immutable
class PlayRecommendState {
  const PlayRecommendState({
    this.rooms = const <RoomSummary>[],
    this.placeholderCount = 0,
    this.loading = false,
    this.loadingMore = false,
    this.hasMore = true,
    this.fallbackHint = '',
    this.error = '',
  });

  /// 已合并好的展示列表(跨站交错、已过滤)。
  final List<RoomSummary> rooms;

  /// 首屏骨架占位卡数量(>0 时面板渲染灰底占位)。
  final int placeholderCount;

  /// 首屏加载中。
  final bool loading;

  /// 追加加载中。
  final bool loadingMore;

  /// 是否还有更多(任一站点还有下一页)。
  final bool hasMore;

  /// 兜底提示文案(空串 = 不提示)。
  final String fallbackHint;

  /// 错误/空态文案(空串 = 无)。
  final String error;

  PlayRecommendState copyWith({
    List<RoomSummary>? rooms,
    int? placeholderCount,
    bool? loading,
    bool? loadingMore,
    bool? hasMore,
    String? fallbackHint,
    String? error,
  }) {
    return PlayRecommendState(
      rooms: rooms ?? this.rooms,
      placeholderCount: placeholderCount ?? this.placeholderCount,
      loading: loading ?? this.loading,
      loadingMore: loadingMore ?? this.loadingMore,
      hasMore: hasMore ?? this.hasMore,
      fallbackHint: fallbackHint ?? this.fallbackHint,
      error: error ?? this.error,
    );
  }

  @override
  String toString() =>
      'PlayRecommendState(rooms: ${rooms.length}, loading: $loading, '
      'loadingMore: $loadingMore, hasMore: $hasMore, '
      'placeholderCount: $placeholderCount, hint: $fallbackHint, '
      'error: $error)';
}

/// 单站一页的取数结果。
@immutable
class _SiteFetch {
  const _SiteFetch({
    required this.rooms,
    required this.hasMore,
    this.usedCategoryFallback = false,
    this.usedHotOnly = false,
  });

  final List<RoomSummary> rooms;
  final bool hasMore;

  /// 分类线路取数为空 → 改用该站热门(分类兜底)。
  final bool usedCategoryFallback;

  /// 该站没有分类映射,本来就走热门(有分类上下文时才需要提示)。
  final bool usedHotOnly;
}

/// 推荐编排:面板只消费状态,取数/合并/分页都在这里。
class PlayRecommendController extends Notifier<PlayRecommendState> {
  PlayRecommendController(this.args);

  /// family 参数(当前房间的平台/分类)。
  final PlayRecommendArgs args;

  /// 站点桶(原始取数结果,未过滤;展示时统一交错 + 过滤)。
  final Map<String, List<RoomSummary>> _buckets = <String, List<RoomSummary>>{};

  /// 各站是否还有下一页。
  final Map<String, bool> _siteHasMore = <String, bool>{};

  /// 命中「分类映射成功但分类无结果 → 热门兜底」的站点。
  final Set<String> _categoryFallbackSites = <String>{};

  /// 没有分类映射、直接走热门的站点(有分类上下文时用于提示)。
  final Set<String> _hotOnlySites = <String>{};

  int _page = 1;
  bool _busy = false;
  bool _forcedMixed = false;

  /// 是否有分类上下文(房间分类名或 cid 任一非空)。
  bool get _hasContext =>
      args.category.trim().isNotEmpty || args.cid.trim().isNotEmpty;

  @override
  PlayRecommendState build() => const PlayRecommendState();

  /// 首屏加载。面板在 initState 里调用一次;防重入。
  Future<void> loadFirst() async {
    if (_busy) return;
    _busy = true;
    final sites = recommendSites();
    _resetBuckets(sites);
    final placeholders = kRecommendPerSite * sites.length;
    state = PlayRecommendState(
      loading: true,
      hasMore: true,
      placeholderCount: placeholders,
    );
    try {
      await _loadPage(1, sites: sites);
      if (_display(sites).isEmpty && _hasContext) {
        // 有分类上下文却一条都没取到 → 退到「全站热门」(web 同样退到综合推荐)。
        _resetBuckets(sites);
        _forcedMixed = true;
        await _loadPage(1, sites: sites, forceHot: true);
      }
      final rooms = _display(sites);
      state = state.copyWith(
        rooms: rooms,
        loading: false,
        placeholderCount: 0,
        hasMore: rooms.isNotEmpty && _anySiteHasMore(sites),
        fallbackHint: rooms.isEmpty ? '' : _hint(sites),
        error: rooms.isEmpty ? '暂无推荐' : '',
      );
    } catch (_) {
      state = state.copyWith(
        loading: false,
        placeholderCount: 0,
        hasMore: false,
        error: '加载失败,请稍后重试',
      );
    } finally {
      _busy = false;
    }
  }

  /// 追加下一页(滚动到底部触发)。
  Future<void> loadMore() async {
    if (_busy || state.loading || state.loadingMore || !state.hasMore) return;
    _busy = true;
    final sites = recommendSites();
    final active = <String>[
      for (final site in sites)
        if (_siteHasMore[site] ?? false) site,
    ];
    state = state.copyWith(loadingMore: true);
    try {
      if (active.isEmpty) {
        state = state.copyWith(loadingMore: false, hasMore: false);
        return;
      }
      var page = _page + 1;
      var attempts = 0;
      var rooms = state.rooms;
      while (attempts < kRecommendEmptyPageRetries) {
        final before = rooms.length;
        await _loadPage(page, sites: active);
        _page = page;
        rooms = _display(sites);
        if (rooms.length > before) break;
        if (!_anySiteHasMore(sites)) break;
        attempts += 1;
        page += 1;
      }
      state = state.copyWith(
        rooms: rooms,
        hasMore: _anySiteHasMore(sites),
        fallbackHint: rooms.isEmpty ? '' : _hint(sites),
        error: rooms.isEmpty ? '暂无推荐' : '',
      );
    } catch (_) {
      // 追加失败保留已有列表,只收起「还有更多」,避免滚动时反复空转。
      state = state.copyWith(hasMore: false);
    } finally {
      _busy = false;
      state = state.copyWith(loadingMore: false);
    }
  }

  /// 按当前 args 重新拉取首屏。
  Future<void> refresh() => loadFirst();

  void _resetBuckets(List<String> sites) {
    _buckets.clear();
    _siteHasMore.clear();
    _categoryFallbackSites.clear();
    _hotOnlySites.clear();
    _forcedMixed = false;
    _page = 1;
    for (final site in sites) {
      _buckets[site] = <RoomSummary>[];
      _siteHasMore[site] = true;
    }
  }

  /// 拉取 [sites] 的 [page] 页并合并进站点桶。
  Future<void> _loadPage(
    int page, {
    required List<String> sites,
    bool forceHot = false,
  }) async {
    if (sites.isEmpty) return;
    final source = ref.read(browseSourceProvider);
    final categories = await _loadCategories(source, sites, forceHot: forceHot);
    final fetched = await Future.wait(<Future<_SiteFetch>>[
      for (final site in sites)
        _fetchSite(
          source,
          site,
          page,
          categories[site],
          forceHot: forceHot,
        ),
    ]);
    for (var index = 0; index < sites.length; index++) {
      final site = sites[index];
      final result = fetched[index];
      final bucket = _buckets.putIfAbsent(site, () => <RoomSummary>[]);
      final seen = <String>{
        for (final room in bucket) '${room.site}:${room.roomId}',
      };
      for (final room in result.rooms) {
        if (seen.add('${room.site}:${room.roomId}')) bucket.add(room);
      }
      _siteHasMore[site] = result.hasMore;
      if (result.usedCategoryFallback) {
        _categoryFallbackSites.add(site);
      } else {
        _categoryFallbackSites.remove(site);
      }
      if (result.usedHotOnly) {
        _hotOnlySites.add(site);
      } else {
        _hotOnlySites.remove(site);
      }
    }
  }

  /// 分类索引:只为「需要名字映射的站点」拉,失败按无分类处理。
  ///
  /// 同平台且房间自带 cid 时不需要映射(直接用 cid),这一类站点跳过请求 ——
  /// 侧栏推荐是次级请求,不该为它多打一轮网络。
  Future<Map<String, CategoryResult?>> _loadCategories(
    BrowseSource source,
    List<String> sites, {
    required bool forceHot,
  }) async {
    final result = <String, CategoryResult?>{};
    if (forceHot) return result;
    final targets = <String>[
      for (final site in sites)
        if (!(site == args.site && args.cid.trim().isNotEmpty)) site,
    ];
    if (targets.isEmpty || args.category.trim().isEmpty) return result;
    final fetched = await Future.wait(<Future<CategoryResult?>>[
      for (final site in targets)
        Future<CategoryResult?>(() async {
          try {
            return await source.fetchCategories(site);
          } catch (_) {
            return null;
          }
        }),
    ]);
    for (var index = 0; index < targets.length; index++) {
      result[targets[index]] = fetched[index];
    }
    return result;
  }

  /// 单站一页取数:分类线路优先,空/失败回落该站热门。
  Future<_SiteFetch> _fetchSite(
    BrowseSource source,
    String site,
    int page,
    CategoryResult? categories, {
    required bool forceHot,
  }) async {
    if (!forceHot) {
      final cid = mapRecommendCid(
        categories: categories,
        category: args.category,
        site: site,
        contextSite: args.site,
        roomCid: args.cid,
      );
      if (cid != null) {
        try {
          final related = await source.fetchRooms(
            site: site,
            cid: cid,
            page: page,
          );
          if (related.rooms.isNotEmpty) {
            return _SiteFetch(
              rooms: related.rooms,
              hasMore: related.rooms.length >= kRecommendPerSite,
            );
          }
        } catch (_) {
          // 分类线路失败 → 落到下面的热门兜底。
        }
        final hot = await _fetchHot(source, site, page);
        return _SiteFetch(
          rooms: hot.rooms,
          hasMore: hot.hasMore,
          usedCategoryFallback: hot.rooms.isNotEmpty,
        );
      }
    }
    final hot = await _fetchHot(source, site, page);
    return _SiteFetch(
      rooms: hot.rooms,
      hasMore: hot.hasMore,
      usedHotOnly: !forceHot,
    );
  }

  /// 该站推荐(热门)列表:`cid == null` 即平台默认推荐流。
  Future<_SiteFetch> _fetchHot(BrowseSource source, String site, int page) async {
    try {
      final result = await source.fetchRooms(site: site, page: page);
      return _SiteFetch(
        rooms: result.rooms,
        hasMore: result.rooms.length >= kRecommendPerSite,
      );
    } catch (_) {
      // 单站失败不影响其它站:本站留空、无更多。
      return const _SiteFetch(rooms: <RoomSummary>[], hasMore: false);
    }
  }

  List<RoomSummary> _display(List<String> sites) => interleaveRecommendBuckets(
    sites: sites,
    buckets: _buckets,
    perSite: kRecommendPerSite,
    currentSite: args.site,
    currentRoomId: args.roomId,
  );

  bool _anySiteHasMore(List<String> sites) => <String>[
    for (final site in sites)
      if (_siteHasMore[site] ?? false) site,
  ].isNotEmpty;

  /// 兜底提示:分类兜底 > 综合兜底;分类映射全部命中则不提示。
  String _hint(List<String> sites) {
    if (_categoryFallbackSites.isNotEmpty) return kRecommendCategoryFallbackHint;
    if (_forcedMixed) return kRecommendMixedFallbackHint;
    if (_hasContext && _hotOnlySites.length == sites.length) {
      return kRecommendMixedFallbackHint;
    }
    return '';
  }
}

/// 播放页「相关推荐」状态。family 参数见 [PlayRecommendArgs]。
final playRecommendProvider = NotifierProvider.autoDispose
    .family<PlayRecommendController, PlayRecommendState, PlayRecommendArgs>(
      PlayRecommendController.new,
    );
