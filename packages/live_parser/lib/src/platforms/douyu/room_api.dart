/// 房间基础信息:房间号解析(含别名房)、betard 拉取、封面/头像归一。
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../http/parser_http.dart';
import 'json_utils.dart';
import 'normalize.dart';

/// 房间不存在(betard 无数据)——由 resolver 转为 [RoomState.notFound]。
class RoomNotFoundException implements Exception {
  const RoomNotFoundException(this.roomId);

  final String roomId;

  @override
  String toString() => '斗鱼房间不存在: $roomId';
}

/// betard 房间字段(只取解析链路需要的部分)。
class BetardRoom {
  const BetardRoom({
    required this.roomId,
    required this.nickname,
    required this.showStatus,
    required this.roomName,
    required this.cover,
    required this.avatar,
    required this.videoLoop,
    required this.cateId,
    required this.cateName,
    required this.showTime,
  });

  final String roomId;
  final String nickname;

  /// 1 = 在播,其余(典型 2)= 未开播。
  final int showStatus;
  final String roomName;
  final String cover;
  final String avatar;
  final int videoLoop;
  final String cateId;
  final String cateName;

  /// 本场开播时间(betard `show_time`,秒级 Unix 时间戳)。0 / 缺失 = 未知。
  final int showTime;

  /// 开播时间;未知时为 null(UI 侧以占位符呈现,不伪造)。
  DateTime? get startedAt => showTime <= 0
      ? null
      : DateTime.fromMillisecondsSinceEpoch(showTime * 1000);

  static BetardRoom fromJson(Map<String, dynamic> json) {
    return BetardRoom(
      roomId: jsonText(json['room_id']),
      nickname: jsonText(json['nickname']),
      showStatus: jsonInt(json['show_status']),
      roomName: jsonText(json['room_name']),
      cover: _coverFromJson(json),
      avatar: _avatarFromJson(json['avatar']),
      videoLoop: jsonInt(json['videoLoop']),
      cateId: jsonText(json['cate_id']),
      cateName: jsonText(json['cate_name']),
      showTime: jsonInt(json['show_time']),
    );
  }

  static String _coverFromJson(Map<String, dynamic> json) {
    var cover = jsonText(json['room_pic'] ?? json['coverSrc']).trim();
    if (cover.isEmpty) {
      final src = jsonText(json['room_src']).trim();
      if (src.startsWith('//')) {
        cover = 'https:$src';
      } else if (src.startsWith('http')) {
        cover = src;
      } else if (src.isNotEmpty) {
        cover = 'https://rpic.douyucdn.cn/${src.replaceFirst(RegExp('^/'), '')}';
      }
    } else if (cover.startsWith('//')) {
      cover = 'https:$cover';
    }
    return cover;
  }

  /// betard 的 avatar 可能是字符串或 {big, middle, small} 对象。
  static String _avatarFromJson(Object? raw) {
    String pick(Map<String, dynamic> obj) =>
        httpsUrl(jsonText(obj['big'] ?? obj['middle'] ?? obj['small']));
    if (raw is Map<String, dynamic>) return pick(raw);
    return httpsUrl(jsonText(raw));
  }
}

/// `https://`、`//`、`http://` 头像与封面统一归一为 https。
String httpsUrl(String text) {
  final value = text.trim();
  if (value.isEmpty) return '';
  if (value.startsWith('//')) return 'https:$value';
  if (value.startsWith('http://')) return 'https://${value.substring(7)}';
  return value;
}

const Map<String, String> _douyuWebHeaders = {
  'Referer': 'https://www.douyu.com/',
};

/// 解析房间号:数字/URL 直接提取;主播别名地址回源 HTML 提取 `"rid":(\d+)`。
Future<String> resolveRoomId(ParserHttp http, String url) async {
  final rid = douyuRidFromUrl(url);
  if (rid.isNotEmpty) return rid;

  final parts = url.split('douyu.com/');
  final path = parts.length > 1 ? parts[1].split('?').first.split('/').first : '';
  if (path.isEmpty) {
    throw ParserHttpException('无效的斗鱼地址: $url');
  }
  final response = await http.get(
    Uri.parse('https://m.douyu.com/$path'),
    headers: _douyuWebHeaders,
  );
  final match = RegExp(r'"rid":(\d+)').firstMatch(utf8.decode(response.bodyBytes));
  if (match == null) {
    throw ParserHttpException('无法解析房间号: $url');
  }
  return match.group(1)!;
}

/// 拉取 betard 房间信息;HTTP 404 或空 room 视为房间不存在。
Future<BetardRoom> fetchBetard(ParserHttp parserHttp, String rid) async {
  final http.Response response;
  try {
    response = await parserHttp.get(
      Uri.parse('https://www.douyu.com/betard/$rid'),
      headers: _douyuWebHeaders,
    );
  } on ParserHttpException catch (error) {
    if (error.statusCode == 404) throw RoomNotFoundException(rid);
    rethrow;
  }
  final decoded = jsonDecode(utf8.decode(response.bodyBytes));
  if (decoded is! Map<String, dynamic>) {
    throw ParserHttpException('betard 返回了非对象 JSON');
  }
  final room = decoded['room'];
  if (room is! Map<String, dynamic> || jsonText(room['room_id']).isEmpty) {
    throw RoomNotFoundException(rid);
  }
  return BetardRoom.fromJson(room);
}

/// betard 头像缺失时回退 m.douyu.com 房间信息接口。
Future<String> fetchRoomAvatarFallback(ParserHttp http, String rid) async {
  final roomInfo = await fetchDouyuMobileRoomInfo(http, rid);
  return httpsUrl(jsonText(roomInfo['avatar']));
}

/// m.douyu.com 房间信息(只取 roomInfo 块)。
///
/// 与 [fetchRoomAvatarFallback] 打同一个端点,区别是**保留整块元信息**:
/// 轻量刷新需要 `hn`(已人类可读的热度文案,web 侧 `follow/status.ts` 的
/// douyu 快照也用它)、`roomName`/`nickname` 与 `showTime`。
///
/// 失败一律返回空 map(而非抛错):热度只是展示增强,不能让本身已拿到
/// betard 状态的刷新整体失败。
Future<Map<String, dynamic>> fetchDouyuMobileRoomInfo(
  ParserHttp http,
  String rid,
) async {
  try {
    final response = await http.get(
      Uri.parse('https://m.douyu.com/api/room/info?rid=$rid'),
      headers: {
        ..._douyuWebHeaders,
        'Origin': 'https://www.douyu.com',
        'Client-Type': 'web',
      },
    );
    final payload = jsonMapOf(jsonDecode(utf8.decode(response.bodyBytes)));
    if (jsonInt(payload['code']) != 0) return const {};
    final data = jsonMapOf(payload['data']);
    return jsonMapOf(data['roomInfo']);
  } on ParserHttpException {
    return const {};
  }
}
