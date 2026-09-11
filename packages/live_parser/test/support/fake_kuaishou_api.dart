/// 快手上游 fake:房间页/列表接口/feed 轮询全部按路径路由。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class FakeKuaishouApi extends http.BaseClient {
  /// 房间页 HTML 默认值;按 id 可覆写 [roomPages]。
  String? roomPage;
  final Map<String, String> roomPages = {};
  Object? categoryResponse;
  Object? gameboardResponse;
  Object? recommendResponse;

  /// feed 响应:优先按 cursor 取,其次队列,最后兜底。
  Object? feedResponse;
  final Map<String, Object?> feedByCursor = {};
  final List<Object?> feedResponses = [];

  /// 房间页下发 Set-Cookie(验证会话透传)。
  String? setCookie;

  final List<http.Request> requests = [];

  List<http.Request> get feedRequests =>
      requests.where((request) => request.url.path == '/wap/live/feed').toList();

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
    if (url.host == 'live.kuaishou.com') {
      if (url.path.startsWith('/u/')) {
        final id = url.pathSegments.isEmpty ? '' : url.pathSegments.last;
        final html = roomPages[id] ?? roomPage;
        if (html == null) return http.Response('not found', 404);
        final headers = <String, String>{
          'content-type': 'text/html; charset=utf-8',
        };
        final cookie = setCookie;
        if (cookie != null) headers['set-cookie'] = cookie;
        return http.Response(html, 200, headers: headers);
      }
      if (url.path == '/live_api/category/data') return _json(categoryResponse);
      if (url.path == '/live_api/home/list') return _json(recommendResponse);
      if (url.path == '/live_api/gameboard/list' ||
          url.path == '/live_api/non-gameboard/list') {
        return _json(gameboardResponse);
      }
    }
    if (url.path == '/wap/live/feed') {
      final cursor = url.queryParameters['cursor'] ?? '';
      if (feedByCursor.containsKey(cursor)) return _json(feedByCursor[cursor]);
      if (feedResponses.isNotEmpty) return _json(feedResponses.removeAt(0));
      return _json(feedResponse);
    }
    return http.Response('fake route missing: $url', 500);
  }
}

http.Response _json(Object? payload, {int status = 200}) => http.Response.bytes(
  utf8.encode(jsonEncode(payload ?? {})),
  status,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

String kuaishouFixture(String name) =>
    File('test/fixtures/kuaishou/$name').readAsStringSync();

Object? kuaishouFixtureJson(String name) => jsonDecode(kuaishouFixture(name));
