/// 虎牙上游 fake:页面 HTML、profileRoom、分类/列表/搜索 JSON 全离线路由。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'fake_douyu_api.dart' show RecordedRequest;

class FakeHuyaApi extends http.BaseClient {
  /// 数字房间页 HTML;'404' 返回 HTTP 404;null 返回 500(路由遗漏即失败)。
  String? webRoomHtml;

  /// mp.huya.com profileRoom 响应(JSON 对象)。
  Object? profileRoomResponse;

  Object? gameListResponse;
  Object? liveListResponse;
  Object? searchResponse;

  /// 别名房间页 HTML(含 ProfileRoom 数字房间号)。
  String aliasPageHtml = '';

  /// cdnws.api.huya.com wup 响应原始字节(null → HTTP 500,模拟 wup 不可达)。
  Uint8List? wupResponseBytes;

  final List<RecordedRequest> requests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest baseRequest) async {
    final request = baseRequest as http.Request;
    requests.add(RecordedRequest(request.method, request.url.toString(), _safeBody(request)));
    final response = _route(request);
    final bytes = response.bodyBytes;
    return http.StreamedResponse(
      Stream.value(bytes),
      response.statusCode,
      contentLength: bytes.length,
    );
  }

  /// wup 请求体是二进制 Tars 流(非 UTF-8 文本),解码失败时无损回退 latin1,
  /// 保证 [RecordedRequest.body] 永不抛 FormatException。
  String _safeBody(http.Request request) {
    try {
      return utf8.decode(request.bodyBytes);
    } on FormatException {
      return latin1.decode(request.bodyBytes);
    }
  }

  http.Response _route(http.Request request) {
    final url = request.url;

    if (url.host == 'www.huya.com') {
      final segment = url.pathSegments.isEmpty ? '' : url.pathSegments.first;
      if (segment == 'someanchor') {
        return _html(aliasPageHtml);
      }
      if (webRoomHtml == '404') return http.Response('not found', 404);
      if (webRoomHtml != null) return _html(webRoomHtml!);
      return http.Response('route missing', 500);
    }
    if (url.host == 'mp.huya.com') {
      if (url.queryParameters['m'] == 'Game') {
        return _json(gameListResponse);
      }
      return _json(profileRoomResponse);
    }
    if (url.host == 'live.huya.com') {
      return _json(liveListResponse);
    }
    if (url.host == 'search.cdn.huya.com') {
      return _json(searchResponse);
    }
    if (url.host == 'cdnws.api.huya.com') {
      final bytes = wupResponseBytes;
      if (bytes == null) return http.Response('wup unavailable', 500);
      return http.Response.bytes(bytes, 200);
    }
    return http.Response('fake route missing: $url', 500);
  }
}

http.Response _html(String body) => http.Response.bytes(
  utf8.encode(body),
  200,
  headers: const {'content-type': 'text/html; charset=utf-8'},
);

http.Response _json(Object? payload) => http.Response.bytes(
  utf8.encode(jsonEncode(payload ?? {})),
  200,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

String readHuyaFixture(String name) =>
    File('test/fixtures/huya/$name').readAsStringSync();
