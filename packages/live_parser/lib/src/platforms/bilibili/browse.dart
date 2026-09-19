/// B 站浏览:Area/getList 分类 + Area/getRoomList 列表 + webMain 推荐合并。
library;


import '../../http/parser_http.dart';
import '../../utils/format_online.dart';
import '../../contracts/contracts.dart';
import '../../models/models.dart';
import '../../registry/category_cache.dart';
import '../douyu/json_utils.dart';
import 'promo_tag.dart';
import 'room_api.dart';
import 'wbi.dart';

class BilibiliBrowseRepository implements BrowseRepository {
  BilibiliBrowseRepository(this._http, this._credentials);

  final ParserHttp _http;
  final BilibiliCredentials _credentials;

  List<CategoryGroup>? _categoryCache;

  @override
  Future<CategoryResult> fetchCategories(String site) async {
    final cached = _categoryCache;
    // 空壳分组(有分组无子项)按未命中处理,作废重拉(web e389570 同款校验)。
    if (hasRealCategoryGroups(cached)) {
      return CategoryResult(site: kBilibiliSiteId, groups: cached!);
    }

    final parents = jsonListOf(
      await bilibiliFetchJson(
        _http,
        _credentials,
        Uri.parse('https://api.live.bilibili.com/room/v1/Area/getList'),
      ),
    );
    final groups = <CategoryGroup>[];
    for (final parent in jsonListOf(parents).whereType<Map<String, dynamic>>()) {
      final items = jsonListOf(parent['list'])
          .whereType<Map<String, dynamic>>()
          .map(
            (item) => CategoryItem(
              cid: jsonText(item['id']),
              name: jsonText(item['name']),
              pic: _normalizeCover(jsonText(item['pic'])),
            ),
          )
          .toList();
      if (items.isEmpty) continue;
      groups.add(
        CategoryGroup(id: jsonText(parent['id']), name: jsonText(parent['name']), items: items),
      );
    }
    // 空壳分组不落缓存,避免上游异常响应霸占缓存(web e389570 同款语义)。
    if (hasRealCategoryGroups(groups)) _categoryCache = groups;
    return CategoryResult(site: kBilibiliSiteId, groups: groups);
  }

  @override
  Future<RoomListResult> fetchRooms(RoomListRequest request) async {
    final page = request.page;
    final cid = request.cid;
    if (cid != null && cid.isNotEmpty && cid != '0') {
      return _fetchCategoryRooms(cid: cid, page: page, limit: request.limit);
    }

    final data = await bilibiliFetchJson(
      _http,
      _credentials,
      Uri.parse('https://api.live.bilibili.com/room/v1/Area/getRoomList'),
      params: {'page': '$page', 'page_size': '${request.limit}'},
    );
    final broadItems = _roomListFromPayload(data);

    // 首页第 1 页并入官方推荐位(webMain),去重
    final items = [...broadItems];
    if (page == 1) {
      try {
        final curated = await bilibiliFetchJson(
          _http,
          _credentials,
          Uri.parse('https://api.live.bilibili.com/xlive/web-interface/v1/webMain/getList'),
          params: {'platform': 'web', 'page': '1', 'page_size': '12'},
        );
        final seen = <String>{
          for (final item in items) jsonText(item['roomid'] ?? item['room_id']),
        };
        for (final item in _roomListFromPayload(curated)) {
          final id = jsonText(item['roomid'] ?? item['room_id']);
          if (id.isEmpty || !seen.add(id)) continue;
          items.add(item);
        }
      } on BilibiliApiException {
        // 推荐位失败时仍展示全站列表。
      }
    }

    final rooms = <RoomSummary>[
      for (final item in items)
        if (_normalizeRoom(item).roomId.isNotEmpty) _normalizeRoom(item),
    ];
    return RoomListResult(rooms: rooms, page: page, hasMore: broadItems.length >= request.limit);
  }

  Future<RoomListResult> _fetchCategoryRooms({
    required String cid,
    required int page,
    required int limit,
  }) async {
    final data = await bilibiliFetchJson(
      _http,
      _credentials,
      Uri.parse('https://api.live.bilibili.com/room/v1/Area/getRoomList'),
      params: {
        'page': '$page',
        'page_size': '$limit',
        'area_id': cid,
      },
    );
    final rooms = <RoomSummary>[
      for (final item in _roomListFromPayload(data))
        if (_normalizeRoom(item).roomId.isNotEmpty) _normalizeRoom(item),
    ];
    return RoomListResult(rooms: rooms, page: page, hasMore: rooms.length >= limit);
  }

  List<Map<String, dynamic>> _roomListFromPayload(Object? data) {
    if (data is List) {
      return data.whereType<Map<String, dynamic>>().toList();
    }
    final record = jsonMapOf(data);
    for (final key in ['recommend_room_list', 'list', 'rooms']) {
      final list = jsonListOf(record[key]).whereType<Map<String, dynamic>>().toList();
      if (list.isNotEmpty) return list;
    }
    return const [];
  }

  RoomSummary _normalizeRoom(Map<String, dynamic> item) {
    final cover = _normalizeCover(
      jsonText(item['user_cover'] ?? item['cover'] ?? item['keyframe']),
    );
    return RoomSummary(
      site: kBilibiliSiteId,
      roomId: jsonText(item['roomid'] ?? item['room_id']),
      title: jsonText(item['title']),
      anchorName: jsonText(item['uname']),
      cid: jsonText(item['area_id'] ?? item['area_v2_id']),
      category: jsonText(
        item['area_name'] ??
            item['area_v2_name'] ??
            item['parent_area_name'] ??
            item['area_v2_parent_name'],
      ),
      online: formatOnlineCount(item['online']),
      cover: cover,
      promoTag: pickBilibiliPromoTag(item),
    );
  }

  static String _normalizeCover(String value) {
    final text = value.trim();
    if (text.isEmpty) return '';
    if (text.startsWith('//')) return 'https:$text';
    return text;
  }
}
