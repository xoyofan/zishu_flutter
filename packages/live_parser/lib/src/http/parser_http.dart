/// 统一 HTTP 基础设施:默认 UA、Referer、超时与 JSON 解码。
/// 每个站点持有独立实例,保证 header/Cookie 隔离;可注入 [http.Client] 便于 fixture 单测。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'upstream_proxy.dart';

/// 站点解析默认 UA(SFVideoLive 同款)。
const String kDefaultParserUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

class ParserHttpException implements Exception {
  const ParserHttpException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() =>
      statusCode == null ? message : '$message (HTTP $statusCode)';
}

class ParserHttp {
  ParserHttp({
    http.Client? client,
    Map<String, String> defaultHeaders = const {},
    this.defaultTimeout = const Duration(seconds: 20),
  }) : _client = client ?? _buildDefaultClient(),
       _ownsClient = client == null,
       defaultHeaders = {
         'User-Agent': kDefaultParserUserAgent,
         ...defaultHeaders,
       };

  /// 自建 client 时接上游代理(宿主经 [UpstreamProxy.configure] 配置);
  /// 外部注入的 client 由注入方自行决定代理行为(fixture 测试不受影响)。
  static http.Client _buildDefaultClient() {
    if (!UpstreamProxy.enabled) return http.Client();
    final inner = HttpClient()
      ..findProxy = (uri) => UpstreamProxy.findProxyValue;
    return IOClient(inner);
  }

  final Map<String, String> defaultHeaders;
  final Duration defaultTimeout;
  final http.Client _client;
  final bool _ownsClient;

  Map<String, String> _merge(Map<String, String>? headers) => {
    ...defaultHeaders,
    ...?headers,
  };

  Future<http.Response> get(
    Uri url, {
    Map<String, String>? headers,
    Duration? timeout,
  }) async {
    try {
      final response = await _client
          .get(url, headers: _merge(headers))
          .timeout(timeout ?? defaultTimeout);
      _ensureOk(response);
      return response;
    } on TimeoutException {
      throw ParserHttpException('请求超时: ${url.host}');
    }
  }

  Future<http.Response> postForm(
    Uri url, {
    required Map<String, String> body,
    Map<String, String>? headers,
    Duration? timeout,
  }) async {
    try {
      final response = await _client
          .post(
            url,
            headers: _merge({
              'Content-Type': 'application/x-www-form-urlencoded',
              ...?headers,
            }),
            body: body,
            encoding: utf8,
          )
          .timeout(timeout ?? defaultTimeout);
      _ensureOk(response);
      return response;
    } on TimeoutException {
      throw ParserHttpException('请求超时: ${url.host}');
    }
  }

  /// JSON POST:GraphQL 类接口使用(GQL 请求体是数组)。
  Future<http.Response> postJson(
    Uri url, {
    required Object body,
    Map<String, String>? headers,
    Duration? timeout,
  }) async {
    try {
      final response = await _client
          .post(
            url,
            headers: _merge({
              'Content-Type': 'application/json; charset=utf-8',
              'Accept': 'application/json',
              ...?headers,
            }),
            body: jsonEncode(body),
            encoding: utf8,
          )
          .timeout(timeout ?? defaultTimeout);
      _ensureOk(response);
      return response;
    } on TimeoutException {
      throw ParserHttpException('请求超时: ${url.host}');
    }
  }

  void _ensureOk(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ParserHttpException(
        '上游响应异常',
        statusCode: response.statusCode,
      );
    }
  }

  Map<String, dynamic> jsonMap(http.Response response) {
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw const ParserHttpException('上游返回了非对象 JSON');
    }
    return decoded;
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}
