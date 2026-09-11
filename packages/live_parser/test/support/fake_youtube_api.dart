/// YouTube 上游 fake:watch 页 / HLS 清单 / live_chat 轮询。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class FakeYoutubeApi extends http.BaseClient {
  String? watchHtml;
  String? browseHtml;
  String? masterPlaylist;
  String? variantPlaylist;
  Object? playerResponse;
  Object? chatResponse;

  final List<Object?> chatResponses = [];
  final List<http.Request> requests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest baseRequest) async {
    final request = baseRequest as http.Request;
    requests.add(request);
    final response = _route(request);
    final bytes = response.bodyBytes;
    return http.StreamedResponse(
      Stream.value(bytes),
      response.statusCode,
      contentLength: bytes.length,
      headers: response.headers,
    );
  }

  http.Response _route(http.Request request) {
    final url = request.url;
    // HLS 地址在 googlevideo 域,按路径优先路由。
    if (url.path.contains('/hls_variant/live/master.m3u8')) {
      return _text(masterPlaylist ?? '#EXTM3U\n');
    }
    if (url.path.contains('/hls_variant/live/')) {
      return _text(variantPlaylist ?? '#EXTM3U\n#EXTINF:4.0,\nseg-1.ts\n');
    }
    if (url.path.contains('seg-1.ts')) {
      return http.Response.bytes(const [0, 1, 2, 3], 200);
    }
    if (url.host == 'www.youtube.com') {
      if (url.path == '/watch') return _text(watchHtml ?? '<html></html>');
      if (url.path == '/live' ||
          url.path == '/gaming' ||
          url.path == '/music' ||
          url.path == '/news') {
        return _text(browseHtml ?? '<html></html>');
      }
      if (url.path == '/youtubei/v1/player') {
        return _json(playerResponse);
      }
      if (url.path == '/youtubei/v1/live_chat/get_live_chat') {
        if (chatResponses.isNotEmpty) return _json(chatResponses.removeAt(0));
        return _json(chatResponse);
      }
      return http.Response('fake route missing: $url', 500);
    }
    return http.Response('fake route missing: $url', 500);
  }
}

http.Response _json(Object? payload) => http.Response.bytes(
  utf8.encode(jsonEncode(payload ?? {})),
  200,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

http.Response _text(String text) => http.Response.bytes(
  utf8.encode(text),
  200,
  headers: const {'content-type': 'text/plain; charset=utf-8'},
);

String youtubeFixture(String name) =>
    File('test/fixtures/youtube/$name').readAsStringSync();

Object? youtubeFixtureJson(String name) => jsonDecode(youtubeFixture(name));
