/// 虎牙搜索:search.cdn.huya.com,typ=-5;v=1 主播(分区1)+ 在播房间(分区3),
/// v=4 仅在播房间 —— 按 `SearchRequest.type` 分流,对齐 web search/huya.ts。
library;

import 'dart:convert';

import '../../http/parser_http.dart';
import '../../utils/format_online.dart';
import '../../utils/search_helpers.dart';
import '../../contracts/contracts.dart';
import '../../models/models.dart';
import '../douyu/json_utils.dart';
import 'room_api.dart';

const Map<String, String> _huyaSearchHeaders = {
  'Referer': 'https://www.huya.com/search/',
  'Origin': 'https://www.huya.com',
};

class HuyaSearchRepository implements SearchRepository {
  HuyaSearchRepository(this._http);

  final ParserHttp _http;

  @override
  Future<SearchResult> search(SearchRequest request) async {
    final query = request.query.trim();
    if (query.isEmpty) return const SearchResult(site: kHuyaSiteId, hits: []);

    // type 分流对齐 web(search/huya.ts:anchors=v1 主播分区1+在播房间分区3、
    // rooms=v4 仅在播房间分区3);缺省 null 沿用 anchors 口径(既有混合行为)。
    final hits = request.type == SearchType.rooms
        ? await _searchRoomDocs(query, request.limit)
        : await _searchDocs(query, request.limit, v: '1');
    return SearchResult(
      site: kHuyaSiteId,
      hits: sortSearchHits(query, trimSearchHits(hits, request.limit)),
    );
  }

  /// 请求 search.cdn.huya.com 并返回 `response` 分区映射。
  Future<Map<String, dynamic>> _fetchResponse(String query, int rows, {required String v}) async {
    final encoded = Uri.encodeQueryComponent(query);
    final response = await _http.get(
      Uri.parse(
        'https://search.cdn.huya.com/?m=Search&do=getSearchContent&q=$encoded'
        '&uid=0&v=$v&typ=-5&livestate=0&rows=$rows&start=0',
      ),
      headers: _huyaSearchHeaders,
    );
    final payload = jsonMapOf(jsonDecode(utf8.decode(response.bodyBytes)));
    return jsonMapOf(payload['response']);
  }

  /// v=1:主播分区(1)+ 在播房间分区(3)合并;去重后统一排序。
  Future<List<SearchHit>> _searchDocs(String query, int limit, {required String v}) async {
    final rows = limit.clamp(5, 20);
    final responseMap = await _fetchResponse(query, rows, v: v);

    final hits = <SearchHit>[];
    for (final doc in _docsOf(responseMap, '1')) {
      final hit = _mapAnchorDoc(doc);
      if (hit != null) hits.add(hit);
    }
    for (final doc in _docsOf(responseMap, '3')) {
      final id = jsonText(doc['room_id']).trim();
      if (id.isEmpty || hits.any((h) => h.id == id)) continue;
      hits.add(
        SearchHit(
          id: id,
          anchor: jsonText(doc['game_nick']).trim(),
          title: jsonText(doc['game_introduction'] ?? doc['game_nick']).trim(),
          avatar: httpsHuyaUrl(jsonText(doc['game_imgUrl'])),
          cover: httpsHuyaUrl(jsonText(doc['game_screenshot'])),
          state: SearchHitState.live,
          category: jsonText(doc['gameName'] ?? doc['game_name']).trim(),
          online: formatOnlineCount(doc['game_total_count']),
        ),
      );
    }
    return hits;
  }

  /// v=4:仅在播房间分区(3),标题口径 `game_roomName` —— 与 web
  /// `searchHuyaRooms` 同参同源(主播档 v=1 里的分区3 走 `game_introduction`)。
  Future<List<SearchHit>> _searchRoomDocs(String query, int limit) async {
    final rows = limit.clamp(1, 20);
    final responseMap = await _fetchResponse(query, rows, v: '4');

    final hits = <SearchHit>[];
    for (final doc in _docsOf(responseMap, '3')) {
      final id = jsonText(doc['room_id']).trim();
      if (id.isEmpty) continue;
      hits.add(
        SearchHit(
          id: id,
          anchor: jsonText(doc['game_nick']).trim(),
          title: jsonText(doc['game_roomName']).trim(),
          avatar: httpsHuyaUrl(jsonText(doc['game_screenshot'])),
          cover: httpsHuyaUrl(jsonText(doc['game_screenshot'])),
          state: SearchHitState.live,
          category: jsonText(doc['gameName']).trim(),
          online: formatOnlineCount(doc['game_total_count']),
        ),
      );
    }
    return hits;
  }

  SearchHit? _mapAnchorDoc(Map<String, dynamic> doc) {
    final id = jsonText(doc['room_id']).trim();
    if (id.isEmpty) return null;
    final live = doc['gameLiveOn'] == true;
    return SearchHit(
      id: id,
      anchor: jsonText(doc['game_nick']).trim(),
      title: jsonText(doc['live_intro'] ?? doc['game_nick']).trim(),
      avatar: httpsHuyaUrl(jsonText(doc['game_avatarUrl180'])),
      cover: httpsHuyaUrl(jsonText(doc['game_screenshot'])),
      state: live ? SearchHitState.live : SearchHitState.offline,
      category: jsonText(doc['game_name']).trim(),
      online: live ? formatOnlineCount(doc['game_total_count']) : '',
      fans: formatOnlineCount(doc['game_activityCount']),
    );
  }

  static List<Map<String, dynamic>> _docsOf(Map<String, dynamic> responseMap, String key) =>
      jsonListOf(jsonMapOf(responseMap[key])['docs']).whereType<Map<String, dynamic>>().toList();
}
