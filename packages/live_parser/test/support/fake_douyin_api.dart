/// 抖音上游 fake:按主机/路径返回 fixtures(签名参数不校验)。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class FakeDouyinApi extends http.BaseClient {
  Object? enterResponse;

  /// 主播资料卡(/webcast/user/profile/,签名请求)。
  Object? anchorProfileResponse;

  /// 用户信息(/webcast/user/?target_uid=,签名请求;关注数回退路径)。
  Object? userProfileResponse;
  Object? partitionResponse;
  Object? feedResponse;
  Object? feedNextResponse;
  Object? followLiveResponse;
  Object? followLiveNextResponse;
  Object? selfProfileResponse;
  Object? followingResponse;
  Object? followingNextResponse;
  Object? discoverResponse;
  Object? roomSearchResponse;
  String? homeHtml;
  String? roomPageHtml;
  String? setCookie;
  final List<http.Request> requests = [];
  int _feedCalls = 0;
  int _followLiveCalls = 0;
  int _followingCalls = 0;

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
      if (url.path.startsWith('/webcast/user/profile/')) {
        return _json(anchorProfileResponse);
      }
      if (url.path == '/webcast/user/') {
        return _json(userProfileResponse);
      }
      if (url.path == '/webcast/feed/') {
        return _json(_feedCalls++ == 0 ? feedResponse : feedNextResponse);
      }
      if (url.path == '/webcast/feed/follow_top/') {
        return _json(
          _followLiveCalls++ == 0 ? followLiveResponse : followLiveNextResponse,
        );
      }
      if (url.path.startsWith('/webcast/web/partition/detail/room/v2/')) {
        return _json(partitionResponse);
      }
      return _html(roomPageHtml ?? '<html></html>');
    }
    if (url.host == 'www.douyin.com') {
      if (url.path == '/') return _html('<html></html>');
      if (url.path == '/aweme/v1/web/user/profile/self/') {
        return _json(selfProfileResponse);
      }
      if (url.path == '/aweme/v1/web/user/following/list/') {
        return _json(
          _followingCalls++ == 0 ? followingResponse : followingNextResponse,
        );
      }
      if (url.path.contains('/discover/search/')) {
        return _json(discoverResponse);
      }
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
