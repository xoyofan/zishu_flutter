/// 斗鱼搜索:japi/search/api/searchUser(主播)+ searchShow(房间)合并归一。
library;

import 'dart:convert';

import '../../http/parser_http.dart';
import '../../utils/format_online.dart';
import '../../contracts/contracts.dart';
import '../../models/models.dart';
import '../../utils/search_helpers.dart';
export '../../utils/search_helpers.dart';
import 'browse.dart';
import 'json_utils.dart';
import 'room_api.dart';

const Map<String, String> _douyuWebHeaders = {
  'Referer': 'https://www.douyu.com/',
};

class DouyuSearchRepository implements SearchRepository {
  DouyuSearchRepository(this._http);

  final ParserHttp _http;

  @override
  Future<SearchResult> search(SearchRequest request) async {
    final query = request.query.trim();
    if (query.isEmpty) return const SearchResult(site: kDouyuSiteId, hits: []);

    final results = await Future.wait([
      searchAnchors(query, request.limit),
      searchRooms(query, request.limit),
    ]);
    final hits = sortSearchHits(query, trimSearchHits([...results[0], ...results[1]], request.limit));
    return SearchResult(site: kDouyuSiteId, hits: hits);
  }

  /// 主播搜索:searchUser;pageSize 收敛在 5-20。
  Future<List<SearchHit>> searchAnchors(String query, int limit) async {
    final kw = query.trim();
    if (kw.isEmpty) return const [];
    final pageSize = limit.clamp(5, 20);
    final response = await _http.get(
      Uri.parse(
        'https://www.douyu.com/japi/search/api/searchUser'
        '?kw=${Uri.encodeQueryComponent(kw)}&page=1&pageSize=$pageSize',
      ),
      headers: _douyuWebHeaders,
    );
    final payload = jsonMapOf(jsonDecode(utf8.decode(response.bodyBytes)));
    final data = jsonMapOf(payload['data']);

    final hits = <SearchHit>[];
    for (final item in jsonListOf(data['relateUser']).whereType<Map<String, dynamic>>()) {
      final info = jsonMapOf(item['anchorInfo']);
      final id = jsonText(info['rid']).trim();
      if (id.isEmpty) continue;
      final state = jsonInt(info['isLive']) == 1
          ? (jsonInt(info['videoLoop']) == 1 || jsonInt(info['isLoop']) == 1
                ? SearchHitState.replay
                : SearchHitState.live)
          : SearchHitState.offline;
      hits.add(
        SearchHit(
          id: id,
          anchor: jsonText(info['nickName']).trim(),
          title: jsonText(info['room_name'] ?? info['nickName']).trim(),
          avatar: httpsUrl(jsonText(info['avatar'])),
          cover: httpsUrl(jsonText(info['roomSrc'])),
          state: state,
          category: jsonText(info['cateName']).trim(),
          online: '',
          fans: jsonText(info['followerCount'] ?? info['fansNumStr']).trim(),
        ),
      );
    }
    return hits;
  }

  /// 房间搜索:searchShow。
  Future<List<SearchHit>> searchRooms(String query, int limit) async {
    final kw = query.trim();
    if (kw.isEmpty) return const [];
    final response = await _http.get(
      Uri.parse(
        'https://www.douyu.com/japi/search/api/searchShow'
        '?kw=${Uri.encodeQueryComponent(kw)}&page=1&pageSize=$limit',
      ),
      headers: _douyuWebHeaders,
    );
    final payload = jsonMapOf(jsonDecode(utf8.decode(response.bodyBytes)));
    final data = jsonMapOf(payload['data']);

    final hits = <SearchHit>[];
    for (final item in jsonListOf(data['relateShow']).whereType<Map<String, dynamic>>()) {
      final id = jsonText(item['rid']).trim();
      if (id.isEmpty) continue;
      hits.add(
        SearchHit(
          id: id,
          anchor: jsonText(item['nickName']).trim(),
          title: jsonText(item['roomName']).trim(),
          avatar: httpsUrl(jsonText(item['avatar'])),
          cover: httpsUrl(jsonText(item['roomSrc'])),
          state: jsonInt(item['isLive']) == 1 ? SearchHitState.live : SearchHitState.offline,
          category: jsonText(item['cateName']).trim(),
          online: formatOnlineCount(item['hot']),
        ),
      );
    }
    return hits;
  }
}

