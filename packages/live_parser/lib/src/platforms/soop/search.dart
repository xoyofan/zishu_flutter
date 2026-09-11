/// SOOP 主播/房间搜索。
library;

import '../../contracts/contracts.dart';
import '../../http/parser_http.dart';
import '../../models/models.dart';
import '../../utils/format_online.dart';
import '../../utils/search_helpers.dart';
import '../douyu/json_utils.dart';
import 'normalize.dart';
import 'room_api.dart';

class SoopSearchRepository implements SearchRepository {
  SoopSearchRepository(this._http);

  final ParserHttp _http;

  @override
  Future<SearchResult> search(SearchRequest request) async {
    final query = request.query.trim();
    final limit = request.limit.clamp(1, 50).toInt();
    if (query.isEmpty) return const SearchResult(site: kSoopSiteId, hits: []);

    final json = await _getJson(
      Uri.https('sch.sooplive.co.kr', '/api.php', {
        'l': 'DF',
        'm': 'liveSearch',
        'c': 'UTF-8',
        'w': 'webk',
        'isMobile': '0',
        'onlyParent': '1',
        'szType': 'json',
        'szOrder': 'score',
        'szKeyword': query,
        'nPageNo': '1',
        'nListCnt': '$limit',
        'tab': 'live',
        'location': 'total_search',
        'isHashSearch': '0',
        'v': '2.0',
      }),
    );
    final list = jsonListOf(json['REAL_BROAD']);
    final hits = <SearchHit>[];
    for (final raw in list) {
      final item = jsonMapOf(raw);
      final roomId = jsonText(item['user_id']).trim();
      if (roomId.isEmpty) continue;
      hits.add(
        SearchHit(
          id: roomId,
          anchor: jsonText(item['user_nick']).trim(),
          title: jsonText(item['broad_title']).trim(),
          avatar: soopMobileAvatarUrl(roomId),
          cover: httpsSoopUrl(item['broad_img']),
          state: SearchHitState.live,
          category: jsonText(item['standard_broad_cate_name']).trim(),
          online: formatOnlineCount(soopOnlineViewers(item)),
        ),
      );
      if (hits.length >= limit) break;
    }
    return SearchResult(
      site: kSoopSiteId,
      hits: sortSearchHits(query, trimSearchHits(hits, limit)),
    );
  }

  Future<Map<String, dynamic>> _getJson(Uri url) async {
    final response = await _http.get(url, headers: const {'Accept': '*/*'});
    return _http.jsonMap(response);
  }
}
