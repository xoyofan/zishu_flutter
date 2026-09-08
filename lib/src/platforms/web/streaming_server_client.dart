import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

/// 新 Web 端解析 adapter：只通过 streaming-server HTTP API 获取解析结果。
class StreamingServerClient {
  StreamingServerClient({this.baseUrl = 'http://106.14.46.209:8080', Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(seconds: 60),
              responseType: ResponseType.json,
            ),
          );

  final String baseUrl;
  final Dio _dio;

  Future<ResolvedLiveRoom> resolveRoom({
    required String site,
    required String roomId,
  }) async {
    final response = await _dio.get<dynamic>(
      '/api/room',
      queryParameters: {
        'site': site,
        'room': roomId,
        'source': 'local',
        'mode': 'lazy',
      },
    );
    final raw = response.data;
    final json = raw is String
        ? jsonDecode(raw) as Map<String, dynamic>
        : Map<String, dynamic>.from(raw as Map);
    return ResolvedLiveRoom.fromJson(json);
  }

  void dispose() => _dio.close();
}

class ResolvedLiveRoom {
  const ResolvedLiveRoom({
    required this.ok,
    required this.site,
    required this.roomId,
    required this.title,
    required this.anchorName,
    required this.isLive,
    required this.playUrl,
    required this.error,
  });

  final bool ok;
  final String site;
  final String roomId;
  final String title;
  final String anchorName;
  final bool isLive;
  final String playUrl;
  final String error;

  factory ResolvedLiveRoom.fromJson(Map<String, dynamic> json) {
    String text(String key) => json[key]?.toString() ?? '';
    return ResolvedLiveRoom(
      ok: json['ok'] == true,
      site: text('site'),
      roomId: text('room_id'),
      title: text('title'),
      anchorName: text('anchor_name'),
      isLive: json['is_live'] == true,
      playUrl: text('m3u8_url').isNotEmpty
          ? text('m3u8_url')
          : text('play_url'),
      error: text('error'),
    );
  }
}
