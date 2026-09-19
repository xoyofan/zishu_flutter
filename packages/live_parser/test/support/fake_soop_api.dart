/// SOOP 上游 fake:按主机/路径与表单 type 返回 fixtures。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class FakeSoopApi extends http.BaseClient {
  Object? detailResponse;
  int detailStatus = 200;
  Object? aidResponse;
  Object? assignResponse;
  Object? categoryListResponse;
  Object? categoryRoomsResponse;
  Object? recommendResponse;
  Object? searchResponse;

  /// 频道 dashboard(api-channel.sooplive.co.kr)响应;null 时 404
  /// (refreshRoomSummary 侧按 best-effort 静默为 0,不破坏刷新)。
  Object? dashboardResponse;
  final List<http.Request> requests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest baseRequest) async {
    final request = baseRequest as http.Request;
    requests.add(request);
    final response = _route(request);
    final bytes = utf8.encode(response.body);
    return http.StreamedResponse(
      Stream.value(bytes),
      response.statusCode,
      contentLength: bytes.length,
      headers: response.headers,
    );
  }

  http.Response _route(http.Request request) {
    final url = request.url;
    if (url.host == 'sch.sooplive.co.kr') {
      switch (url.queryParameters['m']) {
        case 'categoryList':
          return _json(categoryListResponse);
        case 'categoryContentsList':
          return _json(categoryRoomsResponse);
        case 'liveSearch':
          return _json(searchResponse);
      }
    }
    if (url.host == 'live.sooplive.co.kr' &&
        url.path == '/api/main_broad_list_api.php') {
      return _json(recommendResponse);
    }
    if (url.host == 'live.sooplive.co.kr' &&
        url.path == '/afreeca/player_live_api.php') {
      final body = Uri.splitQueryString(request.body);
      if (body['type'] == 'aid') return _json(aidResponse);
      return _json(detailResponse, status: detailStatus);
    }
    if (url.host == 'api-channel.sooplive.co.kr' &&
        url.path.startsWith('/v1.1/channel/')) {
      if (dashboardResponse == null) {
        return http.Response('fake route missing: $url', 404);
      }
      return _json(dashboardResponse);
    }
    if (url.path.endsWith('/broad_stream_assign.html')) {
      return _json(assignResponse);
    }
    return http.Response('fake route missing: $url', 500);
  }
}

http.Response _json(Object? payload, {int status = 200}) => http.Response.bytes(
  utf8.encode(jsonEncode(payload ?? {})),
  status,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

dynamic soopFixture(String name) =>
    jsonDecode(File('test/fixtures/soop/$name').readAsStringSync());
