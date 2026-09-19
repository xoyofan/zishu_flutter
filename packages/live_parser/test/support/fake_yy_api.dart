/// YY 上游 fake：按主机/路径返回离线 fixtures。
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class FakeYyApi extends http.BaseClient {
  Object? detailResponse;
  int detailStatus = 200;

  /// 按次出队的 detail 响应(优先于 [detailResponse]);用于边缘节点闪变
  /// 这类「同一接口连打多次、响应不同」的用例。耗尽后回落 detailResponse。
  final ListQueue<Object?> detailResponseQueue = ListQueue<Object?>();
  Object? streamResponse;
  int streamStatus = 200;
  final Map<int, Object?> streamResponsesByGear = {};
  final Map<int, int> streamGearCalls = {};
  final Map<String, Object?> mobileHlsByRate = {};
  Object? headerResponse;
  final Map<String, Object?> categoryResponses = {};
  final Map<String, String> categoryPages = {};
  Object? recommendResponse;
  Object? searchResponse;
  final Map<String, Object?> searchResponses = {};
  final List<http.Request> requests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest baseRequest) async {
    final request = baseRequest as http.Request;
    requests.add(request);
    final response = _route(request);
    final bytes = utf8.encode(response.body);
    return http.StreamedResponse(Stream.value(bytes), response.statusCode, contentLength: bytes.length);
  }

  http.Response _route(http.Request request) {
    final url = request.url;
    if (url.host == 'www.yy.com') {
      if (url.path.startsWith('/api/liveInfoDetail/')) {
        return _json(
          detailResponseQueue.isNotEmpty
              ? detailResponseQueue.removeFirst()
              : detailResponse,
          status: detailStatus,
        );
      }
      if (url.path == '/yyweb/module/data/header') return _json(headerResponse);
      if (url.path == '/c/yycom/category/getCategory.action') {
        return _json(categoryResponses[url.queryParameters['parentId']]);
      }
      if (url.path == '/more/page.action') return _json(recommendResponse);
      if (url.path == '/apiSearch/doSearch.json') {
        final type = url.queryParameters['t'] ?? '';
        return _json(searchResponses[type] ?? searchResponse);
      }
      final page = categoryPages[url.toString()];
      if (page != null) return http.Response(page, 200, headers: const {'content-type': 'text/html'});
    }
    if (url.host == 'stream-manager.yy.com') {
      var gear = 0;
      try {
        final body = jsonDecode(request.body);
        gear = ((body as Map)['avp_parameter'] as Map)['gear'] as int? ?? 0;
      } on Object {
        // malformed request falls through to the default response
      }
      streamGearCalls[gear] = (streamGearCalls[gear] ?? 0) + 1;
      final payload = streamResponsesByGear[gear] ?? streamResponse;
      return _json(payload, status: streamStatus);
    }
    if (url.host == 'interface.yy.com') {
      final rate = url.pathSegments.isEmpty ? '' : url.pathSegments.last;
      return _json(mobileHlsByRate[rate]);
    }
    return http.Response('fake route missing: $url', 500);
  }
}

http.Response _json(Object? payload, {int status = 200}) => http.Response.bytes(
      utf8.encode(jsonEncode(payload ?? {})),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

dynamic yyFixture(String name) => jsonDecode(File('test/fixtures/yy/$name').readAsStringSync());
