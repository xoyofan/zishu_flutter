/// SOOP 主播信息探针:头像 / 粉丝 / 订阅(VIP)三字段可用性验证。
///
/// 对多个真实房间对比:
/// 1. `player_live_api(type=live)` CHANNEL 里与主播资料相关字段;
/// 2. `api-channel.sooplive.co.kr/v1.1/channel/{id}/dashboard` 原始响应;
/// 3. 构造的 station LOGO 头像 URL 是否真实存在(HTTP 状态码);
/// 4. `refreshRoomSummary` 归一后的 followers/vip 结果。
library;

import 'dart:convert';
import 'dart:io';

import 'package:live_parser/live_parser.dart';

Future<void> main(List<String> args) async {
  UpstreamProxy.configure('127.0.0.1:7897');
  final client = SoopClient();
  final reg = buildSoopRegistration(client: client);
  final resolver = SoopRoomResolver(client);

  // 取推荐列表房间作为样本;命令行可追加指定房间号。
  final roomIds = <String>[...args];
  if (roomIds.isEmpty) {
    final rooms = await reg.browse!.fetchRooms(
      const RoomListRequest(site: 'soop', page: 1, limit: 10),
    );
    roomIds.addAll(rooms.rooms.take(6).map((r) => r.roomId));
  }
  print('样本房间: $roomIds\n');

  final http = ParserHttp(
    defaultHeaders: const {
      'Referer': 'https://www.sooplive.co.kr/',
      'Origin': 'https://www.sooplive.co.kr',
      'Accept-Language': 'zh-CN,zh;q=0.9',
    },
  );

  for (final roomId in roomIds) {
    print('===== $roomId =====');
    // 1. player_live_api 原始 CHANNEL
    try {
      final payload = await fetchSoopPlayerApi(http, roomId);
      final rawChannel = payload['CHANNEL'];
      final channel = rawChannel is Map
          ? Map<String, dynamic>.from(rawChannel)
          : <String, dynamic>{};
      final keys = channel.keys.toList()..sort();
      print('CHANNEL keys: $keys');
      for (final key in [
        'BJID',
        'BJNICK',
        'PROFILE_IMAGE',
        'BJIMG',
        'STATION_IMG',
        'USER_IMG',
        'PHOTO',
        'PROFILE',
      ]) {
        if (channel[key] != null) print('  $key = ${channel[key]}');
      }
    } on Object catch (e) {
      print('player_live_api EXC: $e');
    }

    // 2. dashboard 原始响应(与 fetchSoopDashboard 相同 headers)
    try {
      final uri = Uri.https(
        'api-channel.sooplive.co.kr',
        '/v1.1/channel/$roomId/dashboard',
      );
      final response = await http.get(
        uri,
        headers: const {
          'Accept': 'application/json',
          'Referer': 'https://www.sooplive.com/',
          'Origin': 'https://www.sooplive.com',
        },
      );
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      print('dashboard HTTP ${response.statusCode}: '
          '${jsonEncode(data).substring(0, jsonEncode(data).length.clamp(0, 800))}');
    } on Object catch (e) {
      print('dashboard EXC: $e');
    }

    // 3. 构造的 station LOGO 头像 URL 存在性
    final avatarUrl = soopAvatarUrl(roomId);
    try {
      final client = HttpClient();
      client.findProxy = (uri) => 'PROXY 127.0.0.1:7897';
      final request = await client.headUrl(Uri.parse(avatarUrl));
      request.headers.set('User-Agent', kDefaultParserUserAgent);
      final resp = await request.close();
      await resp.drain<void>();
      print('avatar $avatarUrl -> HTTP ${resp.statusCode}');
      client.close();
    } on Object catch (e) {
      print('avatar EXC: $e');
    }

    // 4. 归一后的 refreshRoomSummary
    try {
      final summary = await resolver.refreshRoomSummary(
        RoomRequest(site: 'soop', roomIdOrUrl: roomId),
      );
      print('summary: followers="${summary.followers}" vip="${summary.vip}" '
          'online="${summary.online}"');
    } on Object catch (e) {
      print('refreshRoom EXC: $e');
    }
    print('');
  }
  http.close();
  client.close();
}
