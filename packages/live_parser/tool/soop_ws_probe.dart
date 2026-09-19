import 'dart:async';
import 'dart:io';

import 'package:live_parser/live_parser.dart';

Future<void> main() async {
  final reg = buildSoopRegistration();
  // 1. 从分类房间列表拿一个在播房间
  final rooms = await reg.browse!.fetchRooms(
    const RoomListRequest(site: 'soop', cid: '00040019', page: 1, limit: 5),
  );
  if (rooms.rooms.isEmpty) {
    print('no live rooms');
    return;
  }
  final roomId = rooms.rooms.first.roomId;
  print('probe room: $roomId');

  // 2. 拿弹幕参数
  final http = ParserHttp(
    defaultHeaders: const {
      'Referer': 'https://www.sooplive.co.kr/',
      'Origin': 'https://www.sooplive.co.kr',
      'Accept-Language': 'zh-CN,zh;q=0.9',
    },
  );
  final payload = await fetchSoopPlayerApi(http, roomId);
  final detail = parseSoopRoomDetail(payload, roomId);
  print('chat: no=${detail.chatNo} domain=${detail.chatDomain} port=${detail.chatPort}');

  // 3. 分别测 wss 与 ws 握手
  for (final scheme in ['wss', 'ws']) {
    final uri = Uri.parse(
      '$scheme://${detail.chatDomain}:${detail.chatPort}/Websocket/$roomId',
    );
    final sw = Stopwatch()..start();
    try {
      final socket = await WebSocket.connect(
        uri.toString(),
        protocols: const ['chat'],
      ).timeout(const Duration(seconds: 8));
      sw.stop();
      print('$scheme connect OK in ${sw.elapsedMilliseconds}ms');
      socket.close();
    } catch (e) {
      sw.stop();
      print('$scheme FAIL after ${sw.elapsedMilliseconds}ms: $e');
    }
  }
  http.close();
}
