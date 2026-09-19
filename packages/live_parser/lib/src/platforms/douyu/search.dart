/// 斗鱼搜索:japi/search/api/searchUser(主播)+ searchShow(房间)合并归一。
library;

import 'dart:convert';
import 'dart:math';

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

/// 斗鱼搜索接口要求携带设备标识 cookie `dy_did`。
///
/// 实测:不带该 cookie 时 `japi/search/api/searchShow` 与 `searchUser` 一律返回
/// `{"data":{},"error":9,"msg":"搜索过于频繁，请稍后再试"}` —— 文案像是限流,
/// 实际是缺设备标识;补一个**随机 32 位十六进制**的 `dy_did` 即可稳定拿到真实结果。
/// 进程内生成一次并复用,保持同一「设备」身份。
final String _douyuDid = _randomDouyuDid();

String _randomDouyuDid() {
  final random = Random.secure();
  final buffer = StringBuffer();
  for (var i = 0; i < 16; i++) {
    buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

Map<String, String> get _searchHeaders => {
  ..._douyuWebHeaders,
  'Cookie': 'dy_did=$_douyuDid',
};

class DouyuSearchRepository implements SearchRepository {
  DouyuSearchRepository(this._http);

  final ParserHttp _http;

  @override
  Future<SearchResult> search(SearchRequest request) async {
    final query = request.query.trim();
    if (query.isEmpty) return const SearchResult(site: kDouyuSiteId, hits: []);

    // type 分流对齐 web(SFVideoLive search/douyu.ts:searchUser=主播、
    // searchShow=房间);缺省 null = 两路合并(既有混合行为,向后兼容)。
    final type = request.type;
    final List<SearchHit> merged;
    if (type == SearchType.anchors) {
      merged = await searchAnchors(query, request.limit);
    } else if (type == SearchType.rooms) {
      merged = await searchRooms(query, request.limit);
    } else {
      final results = await Future.wait([
        searchAnchors(query, request.limit),
        searchRooms(query, request.limit),
      ]);
      merged = [...results[0], ...results[1]];
    }
    final hits = sortSearchHits(query, trimSearchHits(merged, request.limit));
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
      headers: _searchHeaders,
    );
    final data = _searchData(response.bodyBytes);

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
      headers: _searchHeaders,
    );
    final data = _searchData(response.bodyBytes);

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

/// 解析 japi 响应体并取出 `data`;上游 `error != 0` 时抛出带 msg 的异常。
///
/// 不抛异常的话,缺失设备标识 / 真限流时上游会返回 `data` 为空的响应,
/// 调用方只会看到「搜索到 0 条」——语义完全不同的假绿。这里显式失败,
/// 让上层能区分「没搜到」与「搜索接口不可用」。
Map<String, dynamic> _searchData(List<int> bodyBytes) {
  final payload = jsonMapOf(jsonDecode(utf8.decode(bodyBytes)));
  final error = jsonInt(payload['error']);
  if (error != 0) {
    final msg = jsonText(payload['msg']).trim();
    throw ParserHttpException(msg.isEmpty ? '斗鱼搜索上游错误($error)' : msg);
  }
  return jsonMapOf(payload['data']);
}
