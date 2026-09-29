/// 小红书上游 fake:直播间页(www.xiaohongshu.com/livestream)、xhslink
/// 短链 302、主页壳页与 live-room 分类/列表接口全部按路径路由。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:live_parser/src/platforms/xhs/signing.dart' as xhs_signing;

/// 桩签名器:签名算法由并行轨移植(signing.dart),本桩只验证
/// 「签名头接入请求」的接线,不计算真实签名值。
class StubXhsSigner extends xhs_signing.XhsSigner {
  StubXhsSigner()
    : super(
        a1: 'a1test',
        webSession: 'wstest',
        cookieHeader: 'a1=a1test; web_session=wstest',
      );

  @override
  Map<String, String> signedHeaders(
    String method,
    String uri, {
    Map<String, Object?> params = const {},
  }) => {
    'User-Agent': xhs_signing.XhsSigner.webUserAgent,
    'Cookie': cookieHeader,
  };
}

class FakeXhsApi extends http.BaseClient {
  /// 直播间页 HTML 默认值;按 roomId 可覆写 [roomPages]。
  String? roomPage;
  final Map<String, String> roomPages = {};

  /// xhslink 短链:path → 302 Location(如 `/x1` → livestream 直链)。
  final Map<String, String> shortLinks = {};

  /// 主页壳页 HTML(短链落 /user/profile 时使用)。
  String? profilePage;

  Object? categoryResponse;
  Object? squarefeedResponse;

  /// squarefeed 按 cursorScore 路由(验证链式翻页),未命中回退
  /// [squarefeedResponse]。
  final Map<String, Object?> squarefeedByCursor = {};

  final List<http.Request> requests = [];

  /// squarefeed 请求(验证链式游标顺序)。
  List<http.Request> get squarefeedRequests =>
      requests
          .where(
            (request) =>
                request.url.host == 'live-room.xiaohongshu.com' &&
                request.url.path == '/api/sns/red/live/web/feed/v1/squarefeed',
          )
          .toList();

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
    if (url.host.endsWith('xhslink.com')) {
      final location = shortLinks[url.path];
      if (location == null) return http.Response('not found', 404);
      return http.Response('', 302, headers: {'location': location});
    }
    if (url.host == 'www.xiaohongshu.com') {
      if (url.path.startsWith('/livestream/')) {
        final id = url.pathSegments.isEmpty ? '' : url.pathSegments.last;
        final html = roomPages[id] ?? roomPage;
        if (html == null) return http.Response('not found', 404);
        return _html(html);
      }
      if (url.path.startsWith('/user/profile/')) {
        final html = profilePage;
        if (html == null) return http.Response('not found', 404);
        return _html(html);
      }
    }
    if (url.host == 'live-room.xiaohongshu.com') {
      if (url.path == '/api/sns/red/live/web/feed/category') {
        return _json(categoryResponse);
      }
      if (url.path == '/api/sns/red/live/web/feed/v1/squarefeed') {
        final cursor = url.queryParameters['cursorScore'] ?? '';
        if (squarefeedByCursor.containsKey(cursor)) {
          return _json(squarefeedByCursor[cursor]);
        }
        return _json(squarefeedResponse);
      }
    }
    return http.Response('fake route missing: $url', 500);
  }
}

http.Response _html(String body) => http.Response(
  body,
  200,
  headers: const {'content-type': 'text/html; charset=utf-8'},
);

http.Response _json(Object? payload, {int status = 200}) => http.Response.bytes(
  utf8.encode(jsonEncode(payload ?? {})),
  status,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

String xhsFixture(String name) =>
    File('test/fixtures/xhs/$name').readAsStringSync();

Object? xhsFixtureJson(String name) => jsonDecode(xhsFixture(name));
