/// 抖音上游 fake:按主机/路径返回 fixtures(签名参数不校验)。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class FakeDouyinApi extends http.BaseClient {
  Object? enterResponse;
  Object? partitionResponse;
  Object? discoverResponse;
  Object? roomSearchResponse;
  String? homeHtml;
  String? roomPageHtml;
  String? setCookie;
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
    if (url.host == 'live.douyin.com') {
      if (url.path == '/') {
        return _html(homeHtml ?? '<html></html>', setCookie: setCookie);
      }
      if (url.path.startsWith('/webcast/room/web/enter/')) {
        return _json(enterResponse);
      }
      if (url.path.startsWith('/webcast/web/partition/detail/room/v2/')) {
        return _json(partitionResponse);
      }
      return _html(roomPageHtml ?? '<html></html>');
    }
    if (url.host == 'www.douyin.com') {
      if (url.path == '/') return _html('<html></html>');
      if (url.path.contains('/discover/search/')) return _json(discoverResponse);
      return _json(roomSearchResponse);
    }
    return http.Response('fake route missing: $url', 500);
  }
}

http.Response _json(Object? payload, {int status = 200}) => http.Response.bytes(
  utf8.encode(jsonEncode(payload ?? {})),
  status,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

http.Response _html(String html, {String? setCookie}) {
  final headers = <String, String>{'content-type': 'text/html; charset=utf-8'};
  if (setCookie != null) headers['set-cookie'] = setCookie;
  return http.Response.bytes(utf8.encode(html), 200, headers: headers);
}

Object? douyinFixture(String name) =>
    jsonDecode(File('test/fixtures/douyin/$name').readAsStringSync());

String douyinHtmlFixture(String name) =>
    File('test/fixtures/douyin/$name').readAsStringSync();
