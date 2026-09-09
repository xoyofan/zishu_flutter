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

  Future<List<LiveRoomCandidate>> fetchRecommendedRooms({
    String site = 'douyu',
    int page = 1,
  }) async {
    final response = await _dio.get<dynamic>(
      '/api/rooms',
      queryParameters: {'site': site, 'recommend': '1', 'page': page},
    );
    final json = _jsonObject(response.data);
    final list = json['list'];
    if (json['ok'] != true || list is! List) return const [];
    return list
        .whereType<Map>()
        .map(
          (item) => LiveRoomCandidate.fromJson(Map<String, dynamic>.from(item)),
        )
        .where((room) => room.isLive && room.roomId.isNotEmpty)
        .toList(growable: false);
  }

  /// 从推荐列表逐个验证，返回当前确实在播且带播放地址的房间。
  Future<ResolvedLiveRoom> resolveRecommendedLiveRoom({
    String site = 'douyu',
    int maxAttempts = 8,
  }) async {
    final rooms = await fetchRecommendedRooms(site: site);
    Object? lastError;
    for (final room in rooms.take(maxAttempts)) {
      try {
        final resolved = await resolveRoom(site: site, roomId: room.roomId);
        if (resolved.ok && resolved.isLive && resolved.playUrl.isNotEmpty) {
          return resolved;
        }
      } catch (error) {
        lastError = error;
      }
    }
    throw StateError(
      lastError == null ? '推荐列表中没有可播放的在播房间' : '未找到可播放房间：$lastError',
    );
  }

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
    final json = _jsonObject(response.data);
    return ResolvedLiveRoom.fromJson(json);
  }

  Map<String, dynamic> _jsonObject(dynamic raw) {
    if (raw is String) {
      return jsonDecode(raw) as Map<String, dynamic>;
    }
    return Map<String, dynamic>.from(raw as Map);
  }

  void dispose() => _dio.close();
}

class LiveRoomCandidate {
  const LiveRoomCandidate({
    required this.roomId,
    required this.title,
    required this.anchorName,
    required this.isLive,
  });

  final String roomId;
  final String title;
  final String anchorName;
  final bool isLive;

  factory LiveRoomCandidate.fromJson(Map<String, dynamic> json) {
    return LiveRoomCandidate(
      roomId: json['roomId']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      anchorName: json['nickname']?.toString() ?? '',
      isLive: json['status'] == true,
    );
  }
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
