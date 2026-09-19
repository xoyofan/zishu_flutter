/// YY 主播/房间搜索。
library;

import 'dart:convert';

import '../../contracts/contracts.dart';
import '../../http/parser_http.dart';
import '../../models/models.dart';
import '../../utils/format_online.dart';
import '../../utils/search_helpers.dart';
import '../douyu/json_utils.dart';
import 'normalize.dart';

class YySearchRepository implements SearchRepository {
  YySearchRepository(this._http);

  final ParserHttp _http;

  @override
  Future<SearchResult> search(SearchRequest request) async {
    final query = request.query.trim();
    final limit = request.limit.clamp(1, 50).toInt();
    if (query.isEmpty) return const SearchResult(site: kYySiteId, hits: []);

    // type 分流对齐 web(t=120=房间、t=1=主播,search/yy.ts searchYy*);
    // 缺省 null = 两路合并(既有混合行为,向后兼容)。
    final type = request.type;
    final List<SearchHit> merged;
    if (type == null) {
      final results = await Future.wait([
        _searchType('120', query, limit),
        _searchType('1', query, limit),
      ]);
      merged = [...results[0], ...results[1]];
    } else {
      merged = await _searchType(type == SearchType.rooms ? '120' : '1', query, limit);
    }
    return SearchResult(
      site: kYySiteId,
      hits: sortSearchHits(query, trimSearchHits(merged, limit)),
    );
  }

  Future<List<SearchHit>> _searchType(String type, String query, int limit) async {
    const pageSize = 16;
    final maxPages = 8;
    final hits = <SearchHit>[];
    final pages = ((limit / pageSize).ceil().clamp(1, maxPages)).toInt();
    for (var page = 1; page <= pages && hits.length < limit; page++) {
      final uri = Uri.https('www.yy.com', '/apiSearch/doSearch.json', {
        'q': query,
        't': type,
        'n': '$page',
      });
      final response = await _http.get(uri, headers: const {
        'Accept': 'application/json, */*',
        'Origin': 'https://www.yy.com',
        'Referer': 'https://www.yy.com/',
      });
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map) continue;
      final data = jsonMapOf(decoded['data']);
      final searchResult = jsonMapOf(data['searchResult']);
      final responseByType = jsonMapOf(searchResult['response']);
      final docs = jsonListOf(jsonMapOf(responseByType[type])['docs']);
      if (docs.isEmpty) break;
      for (final raw in docs) {
        final item = jsonMapOf(raw);
        final id = jsonText(item['sid'] ?? item['ssid']).trim();
        if (id.isEmpty) continue;
        final live = _isLive(item['liveOn']);
        if (type == '120') {
          hits.add(SearchHit(
            id: id,
            anchor: jsonText(item['name']).trim(),
            title: jsonText(item['channelName']).trim(),
            avatar: httpsYyUrl(item['headurl']),
            cover: httpsYyUrl(item['posterurl']),
            state: live ? SearchHitState.live : SearchHitState.offline,
            category: jsonText(item['biz'] ?? item['subbiz']).trim(),
            online: formatOnlineCount(item['users']),
          ));
        } else {
          final name = jsonText(item['name']).trim();
          final stageName = jsonText(item['stageName']).trim();
          hits.add(SearchHit(
            id: id,
            anchor: name.isNotEmpty ? name : stageName,
            title: stageName.isNotEmpty ? stageName : name,
            avatar: httpsYyUrl(item['headurl']),
            cover: httpsYyUrl(item['headurl']),
            state: live ? SearchHitState.live : SearchHitState.offline,
            category: '',
            online: '',
          ));
        }
        if (hits.length >= limit) break;
      }
    }
    return hits;
  }

  bool _isLive(Object? value) {
    if (value is bool) return value;
    return value?.toString() == '1' || value?.toString().toLowerCase() == 'true';
  }
}
