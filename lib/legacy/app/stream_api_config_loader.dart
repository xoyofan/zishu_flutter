/// Flutter 宿主配置加载器。
///
/// 核心 HTTP 客户端不读取 Flutter assets；具体宿主在 composition root 中解析配置。
library;

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../core/remote/stream_api_client.dart';

class StreamApiConfigLoader {
  StreamApiConfigLoader._();

  static Future<StreamApiConfig> resolve({String? overrideBaseUrl}) async {
    const envUrl = String.fromEnvironment('STREAM_API_URL');
    if (envUrl.isNotEmpty) {
      return StreamApiConfig(baseUrl: _normalize(envUrl));
    }
    if (overrideBaseUrl != null && overrideBaseUrl.isNotEmpty) {
      return StreamApiConfig(baseUrl: _normalize(overrideBaseUrl));
    }
    try {
      final raw = await rootBundle.loadString('assets/config/config.json');
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final url = json['streamApiBaseUrl']?.toString() ?? '';
      final timeoutMs = (json['requestTimeoutMs'] as num?)?.toInt() ?? 20000;
      return StreamApiConfig(
        baseUrl: _normalize(url),
        timeout: Duration(milliseconds: timeoutMs),
      );
    } catch (_) {
      return const StreamApiConfig(baseUrl: '');
    }
  }

  static String _normalize(String url) {
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }
}
