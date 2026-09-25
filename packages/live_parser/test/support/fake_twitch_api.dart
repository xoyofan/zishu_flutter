/// Twitch 上游 fake:按 GQL operationName 与 usher 路径路由到 fixture,全离线。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class FakeTwitchApi extends http.BaseClient {
  /// 各 operation 的 `data` 节点;null 表示未配置(返回 500 暴露路由遗漏)。
  Object? useLiveResponse;
  Object? tokenResponse;
  Object? gamesResponse;
  Object? streamsResponse;
  Object? gameResponse;
  Object? searchResponse;

  /// 按标签过滤的房间列表(`streams(tags:)`)响应。
  Object? tagStreamsResponse;

  /// usher 主播放列表内容;留空则返回空串(用于「无可用画质」用例)。
  String usherBody = '';

  /// 置为 true 时所有 GQL 返回 errors 数组。
  bool gqlErrors = false;

  final List<String> gqlOperations = [];
  final List<String> gqlQueries = [];
  final List<Map<String, Object?>> gqlVariables = [];
  final List<Uri> requests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest baseRequest) async {
    final request = baseRequest as http.Request;
    requests.add(request.url);
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
    if (url.host == 'usher.ttvnw.net') return http.Response(usherBody, 200);

    if (url.host == 'gql.twitch.tv' || url.host == 'gql.twitch.tv.') {
      final first = (jsonDecode(request.body) as List).first as Map;
      final operation = first['operationName'] as String? ?? '';
      gqlOperations.add(operation);
      gqlQueries.add(first['query']?.toString() ?? '');
      gqlVariables.add(
        Map<String, Object?>.from(first['variables'] as Map? ?? const {}),
      );
      if (gqlErrors) {
        return _json([
          {
            'errors': [
              {'message': 'fake gql error'},
            ],
          },
        ]);
      }
      return switch (operation) {
        // fixtures 已解到对应节点,fake 负责按真实响应包回外层 key。
        'UseLive' => _data({'user': useLiveResponse}),
        'PlaybackAccessToken_Template' => _data({
          'streamPlaybackAccessToken': tokenResponse,
        }),
        'BrowsePage_AllDirectories' => _data({'games': gamesResponse}),
        'BrowsePage_Popular' => _data({'streams': streamsResponse}),
        'BrowsePage_Tags' => _data({'streams': tagStreamsResponse}),
        'DirectoryPage_Game' => _data({'game': gameResponse}),
        'SearchResultsPage_SearchResults' => _data({'searchFor': searchResponse}),
        _ => http.Response('fake route missing: $operation', 500),
      };
    }
    return http.Response('fake route missing: $url', 500);
  }

  http.Response _data(Object? data) => _json([
    {'data': data},
  ]);
}

final Map<String, String> _fixtureCache = {};

/// 读取 twitch fixture 文本。
String twitchFixture(String name) => _fixtureCache.putIfAbsent(
  name,
  () => File('test/fixtures/twitch/$name').readAsStringSync(),
);

/// 读取 fixture 并解出 `data` 节点,便于按字段改造。
Map<String, dynamic> twitchFixtureData(String name) =>
    Map<String, dynamic>.from(jsonDecode(twitchFixture(name))['data'] as Map);

http.Response _json(Object payload) => http.Response.bytes(
  utf8.encode(jsonEncode(payload)),
  200,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);
