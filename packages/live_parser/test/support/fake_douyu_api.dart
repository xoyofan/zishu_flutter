/// 斗鱼上游 fake:按 URL/POST body 路由到 JSON fixture,全离线。
/// 配置缺省时返回 500,让测试在路由遗漏处立刻失败。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class RecordedRequest {
  const RecordedRequest(
    this.method,
    this.url,
    this.body, [
    this.headers = const {},
  ]);

  final String method;
  final String url;
  final String body;
  final Map<String, String> headers;

  Map<String, String> get formBody => Uri(query: body).queryParameters;

  /// 大小写无关的请求头读取。
  String? header(String name) {
    final lower = name.toLowerCase();
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == lower) return entry.value;
    }
    return null;
  }
}

class FakeDouyuApi extends http.BaseClient {
  /// betard 返回体;置为 '404' 时返回 HTTP 404。
  Object? betardResponse;

  /// 主播别名页 HTML 中的房间号;空串表示不命中(返回 404)。
  String aliasPageRid = '';

  /// 房间信息接口(m.douyu.com/api/room/info)响应;null 时返回 404。
  Object? roomInfoResponse;

  /// mixList 按 directory(如 `0_0`、`2_1`)配置;未配置返回 500。
  /// 传 'fail' 时返回 500 触发回退分支。
  final Map<String, Object?> mixListByDirectory = {};

  Object? mobileRoomListResponse;

  /// 覆盖 rate=0/hw-h5 探测响应(默认走 play_v1_probe.json fixture)。
  Object? playV1ProbeOverride;

  /// 这些画质档的所有 CDN 请求都返回上游 error,
  /// 用于验证「整档取流失败 → 该档从 streams 与 availableQualities 中整体消失」。
  final Set<String> failRates = {};

  /// 搜索接口(searchUser/searchShow)返回体;非 null 时覆盖 fixture,
  /// 用于验证上游 `error != 0` 时抛出异常而非静默返回空结果。
  Object? searchResponse;

  final List<RecordedRequest> requests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest baseRequest) async {
    final request = baseRequest as http.Request;
    requests.add(
      RecordedRequest(
        request.method,
        request.url.toString(),
        request.body,
        Map<String, String>.from(request.headers),
      ),
    );
    final response = _route(request);
    final bytes = utf8.encode(response.body);
    return http.StreamedResponse(
      Stream.value(bytes),
      response.statusCode,
      contentLength: bytes.length,
    );
  }

  http.Response _route(http.Request request) {
    final url = request.url;
    final path = url.path;

    if (path.startsWith('/betard/')) {
      if (betardResponse == '404') return http.Response('not found', 404);
      return _json(betardResponse);
    }
    if (path.contains('websec/getEncryption')) {
      return _fixture('get_encryption.json');
    }
    if (path.startsWith('/lapi/live/getH5PlayV1/')) {
      final formBody = Uri(query: request.body).queryParameters;
      final rate = formBody['rate'] ?? '0';
      final cdn = formBody['cdn'] ?? 'hw-h5';
      if (failRates.contains(rate)) {
        return _json({'error': 500, 'msg': 'rate $rate unavailable'});
      }
      if (rate == '0' && cdn == 'hw-h5' && playV1ProbeOverride != null) {
        return _json(playV1ProbeOverride);
      }
      final file = rate == '0' && cdn == 'hw-h5' ? 'play_v1_probe.json' : 'play_v1_${rate}_$cdn.json';
      return _fixture(file);
    }
    if (path.startsWith('/lapi/live/hlsH5Preview/')) {
      return _fixture('hls_preview.json');
    }
    if (url.host == 'm.douyu.com') {
      if (path == '/api/cate/list') return _fixture('cate_list.json');
      if (path == '/api/room/list') return _json(mobileRoomListResponse);
      if (path == '/api/room/info') {
        return roomInfoResponse == null
            ? http.Response('not found', 404)
            : _json(roomInfoResponse);
      }
      return http.Response('{"rid":${aliasPageRid.isEmpty ? '0' : aliasPageRid},"tt":1}', 200);
    }
    if (path.startsWith('/gapi/rkc/directory/mixList/')) {
      final directory = url.pathSegments.length > 4 ? url.pathSegments[4] : '';
      final configured = mixListByDirectory[directory];
      if (configured == null || configured == 'fail') {
        return http.Response('mix list unavailable', 500);
      }
      return _json(configured);
    }
    if (path == '/japi/search/api/searchUser') {
      if (searchResponse != null) return _json(searchResponse);
      return _fixture('search_user.json');
    }
    if (path == '/japi/search/api/searchShow') {
      if (searchResponse != null) return _json(searchResponse);
      return _fixture('search_show.json');
    }
    return http.Response('fake route missing: $url', 500);
  }
}

Map<String, String> _fixtureCache = {};

http.Response _fixture(String name) {
  final body = _fixtureCache.putIfAbsent(
    name,
    () => File('test/fixtures/douyu/$name').readAsStringSync(),
  );
  return _bytesResponse(utf8.encode(body));
}

http.Response _json(Object? payload) =>
    _bytesResponse(utf8.encode(jsonEncode(payload ?? {'error': -1})));

/// 显式 utf8:Response(String) 默认 latin1,中文 fixture 会抛 invalid characters。
http.Response _bytesResponse(List<int> bytes) => http.Response.bytes(
  bytes,
  200,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);
