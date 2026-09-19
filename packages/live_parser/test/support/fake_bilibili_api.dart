/// B 站上游 fake:按 URL 路径路由 JSON 响应,全离线。未配置的路径返回 500。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'fake_douyu_api.dart' show RecordedRequest;

class FakeBilibiliApi extends http.BaseClient {
  Object? roomInfoResponse;
  Object? anchorInRoomResponse;
  Object? roomPlayInfoResponse;

  /// 按请求 qn 参数路由的 playInfo 响应(懒取流用例):命中键用对应响应,
  /// 未命中回退 [roomPlayInfoResponse]。
  Map<int, Object?>? roomPlayInfoByQn;
  Object? areaListResponse;
  Object? roomListResponse;
  Object? webMainListResponse;
  Object? searchResponse;
  Object? navResponse;
  Object? spiResponse;
  Object? danmuInfoResponse;

  /// 动态路由:非 null 返回值优先于静态配置(供按请求顺序变化用例)。
  Object? Function(String path)? routeInterceptor;

  final List<RecordedRequest> requests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest baseRequest) async {
    final request = baseRequest as http.Request;
    requests.add(RecordedRequest(request.method, request.url.toString(), request.body));
    final dynamic intercepted = routeInterceptor?.call(request.url.path);
    final response = intercepted != null ? _json(intercepted) : _route(request);
    final bytes = utf8.encode(response.body);
    return http.StreamedResponse(
      Stream.value(bytes),
      response.statusCode,
      contentLength: bytes.length,
    );
  }

  http.Response _route(http.Request request) {
    final path = request.url.path;
    return switch (path) {
      '/room/v1/Room/get_info' => _json(roomInfoResponse),
      '/live_user/v1/UserInfo/get_anchor_in_room' => _json(anchorInRoomResponse),
      '/xlive/web-room/v2/index/getRoomPlayInfo' => _playInfoFor(request),
      '/room/v1/Area/getList' => _json(areaListResponse),
      '/room/v1/Area/getRoomList' => _json(roomListResponse),
      '/xlive/web-interface/v1/webMain/getList' => _json(webMainListResponse),
      '/xlive/web-room/v1/index/getDanmuInfo' => _json(danmuInfoResponse),
      '/x/web-interface/nav' => _json(navResponse),
      '/x/frontend/finger/spi' => _json(spiResponse),
      '/x/web-interface/wbi/search/type' || '/x/web-interface/search/type' => _json(searchResponse),
      _ => http.Response('fake route missing: ${request.url}', 500),
    };
  }

  http.Response _playInfoFor(http.Request request) {
    final byQn = roomPlayInfoByQn;
    final qn = int.tryParse(request.url.queryParameters['qn'] ?? '');
    if (byQn != null && qn != null && byQn.containsKey(qn)) {
      return _json(byQn[qn]);
    }
    return _json(roomPlayInfoResponse);
  }
}

http.Response _json(Object? payload) => http.Response.bytes(
  utf8.encode(jsonEncode(payload ?? {})),
  200,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

String readBilibiliFixture(String name) =>
    File('test/fixtures/bilibili/$name').readAsStringSync();
