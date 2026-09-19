import 'dart:convert';

import 'package:live_parser/live_parser.dart';

const ua =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

Future<void> main() async {
  // 1. 预热:拉中文分类树填 zh 表(复刻 app 预热)
  final reg = buildSoopRegistration();
  final cats = await reg.browse!.fetchCategories('soop');
  final talk = cats.groups.first.items.where((c) => c.name.contains('聊天'));
  print('聊天分类: ${talk.map((c) => '${c.cid}=${c.name}').toList()}');
  print('direct lookup 00130000 -> ${soopZhCategoryName('00130000')}');
  print('direct lookup 130000 -> ${soopZhCategoryName('130000')}');

  // 2. 聊天/秀场分类下第一个房间 → 详情链路(与播放页同路径)
  final rooms = await reg.browse!.fetchRooms(
    const RoomListRequest(site: 'soop', cid: '00130000', page: 1, limit: 3),
  );
  for (final room in rooms.rooms) {
    final http = ParserHttp(
      defaultHeaders: const {
        'Referer': 'https://www.sooplive.co.kr/',
        'Origin': 'https://www.sooplive.co.kr',
        'Accept-Language': 'zh-CN,zh;q=0.9',
      },
    );
    final payload = await fetchSoopPlayerApi(http, room.roomId);
    final ch = (jsonDecode(jsonEncode(payload)) as Map)['CHANNEL'] as Map;
    final detail = parseSoopRoomDetail(
      (jsonDecode(jsonEncode(payload)) as Map).cast<String, dynamic>(),
      room.roomId,
    );
    print('${room.roomId} CATE=${ch['CATE']} tags=${ch['CATEGORY_TAGS']}'
        ' -> parsed category=${detail.category}');
    http.close();
  }
}
