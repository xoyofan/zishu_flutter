/// streaming-server HTTP 客户端。
///
/// 端点与参数严格对齐 SFVideoLive web/src/api/{room,browse,search}.ts 的调用方式。
library;

import 'dart:convert';
import 'dart:async';

import 'package:dio/dio.dart';

import '../contracts/room_models.dart';
import '../contracts/browse_models.dart';

/// 解析服务连接配置。配置来源由 app composition root 负责。
class StreamApiConfig {
  final String baseUrl;
  final Duration timeout;

  const StreamApiConfig({
    required this.baseUrl,
    this.timeout = const Duration(seconds: 20),
  });

  bool get isConfigured => baseUrl.isNotEmpty;
}

/// streaming-server API 客户端。
class StreamApiClient {
  final Dio _dio;
  final StreamApiConfig config;

  StreamApiClient({required this.config})
    : _dio = Dio(
        BaseOptions(
          baseUrl: config.baseUrl,
          connectTimeout: config.timeout,
          receiveTimeout: config.timeout,
          responseType: ResponseType.json,
        ),
      );

  bool get isConfigured => config.isConfigured;

  /// GET /api/room?site=&room=&source=local&mode=lazy[&quality=][&force=1]
  Future<RoomPayload> fetchRoom({
    required String site,
    required String room,
    String mode = 'lazy',
    String? quality,
    bool force = false,
  }) async {
    final params = <String, dynamic>{
      'site': site,
      'room': room,
      'source': 'local',
      'mode': mode,
      if (quality != null && quality.isNotEmpty) 'quality': quality,
      if (force) 'force': '1',
    };
    final data = await _getJson('/api/room', params);
    return RoomPayload.fromJson(data);
  }

  /// GET /api/categories?site=
  Future<CategoriesResponse> fetchCategories(String site) async {
    final data = await _getJson('/api/categories', {'site': site});
    return CategoriesResponse.fromJson(data);
  }

  /// GET /api/rooms?site=&recommend=1&page=
  Future<RoomsResponse> fetchRecommendRooms(String site, {int page = 1}) async {
    final data = await _getJson('/api/rooms', {
      'site': site,
      'recommend': '1',
      'page': '$page',
    });
    return RoomsResponse.fromJson(data);
  }

  /// GET /api/rooms?site=&cid=&page=[&pid=][&kw=][&quality=][&country=]
  Future<RoomsResponse> fetchCategoryRooms(
    String site, {
    required String cid,
    int page = 1,
    String? pid,
    String? kw,
    String? quality,
    String? country,
  }) async {
    final data = await _getJson('/api/rooms', {
      'site': site,
      'cid': cid,
      'page': '$page',
      if (pid != null && pid.isNotEmpty) 'pid': pid,
      if (kw != null && kw.isNotEmpty) 'kw': kw,
      if (quality != null && quality.isNotEmpty) 'quality': quality,
      if (country != null && country.isNotEmpty) 'country': country,
    });
    return RoomsResponse.fromJson(data);
  }

  /// GET /api/search?site=&q=&limit=[&type=anchors|rooms]
  Future<SearchResponse> search({
    required String site,
    required String q,
    int limit = 10,
    String? type,
  }) async {
    final data = await _getJson('/api/search', {
      'site': site,
      'q': q,
      'limit': '$limit',
      if (type != null && type.isNotEmpty) 'type': type,
    });
    return SearchResponse.fromJson(data);
  }

  /// GET /api/hot-categories（跨平台热门分类）
  Future<dynamic> hotCategories() => _getJson('/api/hot-categories', null);

  /// GET /api/config/playback（弹幕通道矩阵等运行时配置）
  Future<dynamic> playbackConfig() => _getJson('/api/config/playback', null);

  /// GET /api/health
  Future<bool> health() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/api/health');
      return res.data?['ok'] == true;
    } on DioException {
      return false;
    }
  }

  Future<Map<String, dynamic>> _getJson(
    String path,
    Map<String, dynamic>? query,
  ) async {
    if (!isConfigured) {
      throw StateError(
        'streaming-server base URL 未配置（assets/config/config.json 或 --dart-define=STREAM_API_URL）',
      );
    }
    final res = await _dio.get<dynamic>(path, queryParameters: query);
    final data = res.data;
    if (data is Map<String, dynamic>) return data;
    if (data is String) return jsonDecode(data) as Map<String, dynamic>;
    throw StateError('响应不是 JSON 对象: $path');
  }

  void dispose() => _dio.close();
}
