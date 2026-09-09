/// Twitch GraphQL 客户端。
///
/// - 公开 Web Client-ID:取自 twitch.tv 前端,与社区工具一致,非私有凭据。
/// - 请求与响应都是**数组**:一次可携带多个 operation,这里只发一个并取首个。
/// - `errors` 非空即失败:Twitch 经常只改字段不改状态码,必须按 errors 分类。
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../http/parser_http.dart';

/// Twitch 前端公开 Client-ID(社区工具通用,不是用户凭据)。
const String kTwitchWebClientId = 'kimne78kx3ncx6brgo4mv6wki5h1ko';

const String kTwitchGqlEndpoint = 'https://gql.twitch.tv/gql';

class TwitchGqlException implements Exception {
  const TwitchGqlException(this.message);

  final String message;

  @override
  String toString() => message;
}

class TwitchGqlClient {
  TwitchGqlClient({
    http.Client? httpClient,
    ParserHttp? parserHttp,
    this.clientId = kTwitchWebClientId,
    this.endpoint = kTwitchGqlEndpoint,
  }) : _http = parserHttp ??
           ParserHttp(
             client: httpClient,
             defaultHeaders: {'Client-ID': clientId, 'Referer': 'https://www.twitch.tv/'},
           ),
       _ownsHttp = parserHttp == null;

  final String clientId;
  final String endpoint;
  final ParserHttp _http;
  final bool _ownsHttp;

  ParserHttp get parserHttp => _http;

  /// 执行一个 operation,返回 `data` 节点;不存在时返回 null。
  Future<Object?> query({
    required String operationName,
    required String query,
    Map<String, Object?> variables = const {},
  }) async {
    final response = await _http.postJson(
      Uri.parse(endpoint),
      body: [
        {'operationName': operationName, 'variables': variables, 'query': query},
      ],
    );

    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const TwitchGqlException('GQL 返回了非法 JSON');
    }
    if (decoded is! List || decoded.isEmpty) {
      throw const TwitchGqlException('GQL 返回了非数组响应');
    }
    final first = decoded.first;
    if (first is! Map<String, dynamic>) {
      throw const TwitchGqlException('GQL 响应项不是对象');
    }
    final errors = first['errors'];
    if (errors is List && errors.isNotEmpty) {
      throw TwitchGqlException(_firstErrorMessage(errors) ?? 'GQL 查询失败');
    }
    return first['data'];
  }

  String? _firstErrorMessage(List<Object?> errors) {
    for (final error in errors) {
      if (error is Map && error['message'] is String) return error['message'] as String;
    }
    return null;
  }

  void close() {
    if (_ownsHttp) _http.close();
  }
}
