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
    if (jsonInt(payload['code']) != 0) return '';
    final data = jsonMapOf(payload['data']);
    final roomInfo = jsonMapOf(data['roomInfo']);
    return httpsUrl(jsonText(roomInfo['avatar']));
  } on ParserHttpException {
    return '';
  }
}
