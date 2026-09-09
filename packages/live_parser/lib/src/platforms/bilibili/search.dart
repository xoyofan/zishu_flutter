/// B 站搜索:wbi/search/type(bili_user 主播 + live 房间)。
library;


import '../../http/parser_http.dart';
import '../../utils/format_online.dart';
import '../../utils/search_helpers.dart';
import '../../contracts/contracts.dart';
import '../../models/models.dart';
import '../douyu/json_utils.dart';
import 'room_api.dart';
import 'wbi.dart';

class BilibiliSearchRepository implements SearchRepository {
  BilibiliSearchRepository(this._http, this._credentials);

  final ParserHttp _http;
  final BilibiliCredentials _credentials;

  @override
  Future<SearchResult> search(SearchRequest request) async {
    final query = request.query.trim();
    if (query.isEmpty) return const SearchResult(site: kBilibiliSiteId, hits: []);

    final results = await Future.wait([
      _searchAnchors(query, request.limit),
      _searchRooms(query, request.limit),
    ]);
    final hits = sortSearchHits(
      query,
      trimSearchHits([...results[0], ...results[1]], request.limit),
    );
    return SearchResult(site: kBilibiliSiteId, hits: hits);
  }

  Future<List<SearchHit>> _searchAnchors(String query, int limit) async {
    final data = await _searchType({
      'search_type': 'bili_user',
      'keyword': query,
      'page': '1',
    });
    final hits = <SearchHit>[];
    for (final item in jsonListOf(data['result']).whereType<Map<String, dynamic>>()) {
      if (jsonText(item['type']) != 'bili_user') continue;
      final roomId = jsonInt(item['room_id']);
      if (roomId == 0) continue;
      final live = jsonInt(item['is_live']) == 1;
      hits.add(
        SearchHit(
          id: '$roomId',
          anchor: jsonText(item['uname']).trim(),
          title: (jsonText(item['usign'] ?? item['uname'])).trim(),
          avatar: httpsBilibiliUrl(jsonText(item['upic'])),
          cover: '',
          state: live ? SearchHitState.live : SearchHitState.offline,
          category: '',
          online: '',
          fans: formatExactCount(item['fans']),
        ),
      );
    }
    return hits;
  }

  Future<List<SearchHit>> _searchRooms(String query, int limit) async {
    final data = await _searchType({
      'search_type': 'live',
      'cover_type': 'user_cover',
      'keyword': query,
      'order': '',
      'category_id': '',
      'highlight': '0',
      'single_column': '0',
      'page': '1',
      'page_size': '${limit.clamp(1, 50)}',
    });
    final result = jsonMapOf(data['result']);
    var roomsRaw = jsonListOf(result['live_room']);
    if (roomsRaw.isEmpty) {
      final nested = jsonMapOf(jsonMapOf(data['data'])['result']);
      roomsRaw = jsonListOf(nested['live_room']);
    }
    final rooms = roomsRaw.whereType<Map<String, dynamic>>();

    final hits = <SearchHit>[];
    for (final item in rooms) {
      final id = jsonText(item['roomid']).trim();
      if (id.isEmpty) continue;
      final live = jsonInt(item['live_status']) == 1;
      hits.add(
        SearchHit(
          id: id,
          anchor: jsonText(item['uname']).trim(),
          title: _stripEmTags(jsonText(item['title'])),
          avatar: httpsBilibiliUrl(jsonText(item['uface'])),
          cover: httpsBilibiliUrl(jsonText(item['cover'])),
          state: live ? SearchHitState.live : SearchHitState.offline,
          category: _stripEmTags(jsonText(item['cate_name'])),
          online: formatOnlineCount(item['online']),
        ),
      );
    }
    return hits;
  }

  Future<Map<String, dynamic>> _searchType(Map<String, String> params) async {
    try {
      return jsonMapOf(
        await bilibiliFetchJson(
          _http,
          _credentials,
          Uri.parse('https://api.bilibili.com/x/web-interface/wbi/search/type'),
          params: params,
        ),
      );
    } on BilibiliApiException catch (error) {
      // wbi 接口被风控时回落到旧入口(签名 best-effort 同样适用)。
      if (error.code == -412 || error.code == -401) {
        return jsonMapOf(
          await bilibiliFetchJson(
            _http,
            _credentials,
            Uri.parse('https://api.bilibili.com/x/web-interface/search/type'),
            params: params,
          ),
        );
      }
      rethrow;
    }
  }

  static String _stripEmTags(String text) =>
      text.replaceAll(RegExp(r'<.*?em.*?>'), '').trim();
}
