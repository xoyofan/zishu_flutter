// 一次性探针:实测 B 站列表接口(全站 Area/getRoomList + 首页推荐
// webMain/getList)条目里有没有「卡片角标 / 特色标签」类字段
// (对应斗鱼的 icv3 / roomLabel),以及大航海/舰长等 vip 系字段。
//
// 用法:cd packages/live_parser && dart run tool/_probe_bili_cards.dart
import 'dart:convert';

import 'package:live_parser/live_parser.dart';
import 'package:live_parser/src/platforms/bilibili/room_api.dart';
import 'package:live_parser/src/platforms/bilibili/wbi.dart';

Map<String, dynamic> _map(Object? v) =>
    v is Map<String, dynamic> ? v : <String, dynamic>{};

List<Object?> _list(Object? v) => v is List ? v : const [];

Future<void> main() async {
  final http = ParserHttp();
  final credentials = BilibiliCredentials();

  // 先拿真实分区 id(area_id=9 实测 404)。
  final areas = await bilibiliFetchJson(
    http,
    credentials,
    Uri.parse('https://api.live.bilibili.com/room/v1/Area/getList'),
  );
  final groups = _list(_map(_map(areas)['data'])['list']).isNotEmpty
      ? _list(_map(_map(areas)['data'])['list'])
      : _list(areas);
  final areaIds = <String>[];
  for (final g in groups.whereType<Map<String, dynamic>>()) {
    for (final item in _list(g['list']).whereType<Map<String, dynamic>>()) {
      final id = '${item['id'] ?? ''}';
      if (id.isNotEmpty) areaIds.add(id);
      if (areaIds.length >= 2) break;
    }
    if (areaIds.length >= 2) break;
  }
  // ignore: avoid_print
  print('=== 真实分区 id 样本: $areaIds');

  await _scan(
    http,
    credentials,
    'https://api.live.bilibili.com/room/v1/Area/getRoomList',
    {'page': '1', 'page_size': '30'},
  );
  await _scan(
    http,
    credentials,
    'https://api.live.bilibili.com/xlive/web-interface/v1/webMain/getList',
    {'platform': 'web', 'page': '1', 'page_size': '12'},
  );
  for (final id in areaIds.take(1)) {
    await _scan(
      http,
      credentials,
      'https://api.live.bilibili.com/room/v1/Area/getRoomList',
      {'page': '1', 'page_size': '30', 'area_id': id},
    );
  }
  // room/get_info:看是否直接带粉丝勋章/大航海数(决定要不要额外请求)。
  for (final rid in ['1', '22908869', '1919216529']) {
    try {
      final data = await bilibiliFetchJson(
        http,
        credentials,
        Uri.parse('https://api.live.bilibili.com/xlive/web-room/v1/index/getInfoByRoom'),
        roomId: rid,
      );
      final info = _map(_map(data)['data']);
      // ignore: avoid_print
      print('=== getInfoByRoom rid=$rid');
      final keys = info.keys.toList()..sort();
      for (final k in keys) {
        final v = info[k];
        final s = v is Map || v is List ? jsonEncode(v) : '$v';
        if (s.isEmpty || s == '0' || s == 'false' || s == 'null') continue;
        if (s.length > 120) continue;
        // ignore: avoid_print
        print('  $k = $s');
      }
    } on Object catch (e) {
      // ignore: avoid_print
      print('=== getInfoByRoom rid=$rid FAILED: $e');
    }
  }
}

/// 与 browse.dart `_roomListFromPayload` 同口径取条目数组。
List<Map<String, dynamic>> _rooms(Object? data) {
  if (data is List) return data.whereType<Map<String, dynamic>>().toList();
  final record = _map(data);
  for (final key in ['recommend_room_list', 'list', 'rooms']) {
    final list = _list(record[key]).whereType<Map<String, dynamic>>().toList();
    if (list.isNotEmpty) return list;
  }
  return const [];
}

/// 打印条目全字段(跳过空值),并单独汇总「非空字段名 + 出现次数」。
Future<void> _scan(
  ParserHttp http,
  BilibiliCredentials credentials,
  String url,
  Map<String, String> params,
) async {
  try {
    final data = await bilibiliFetchJson(
      http,
      credentials,
      Uri.parse(url),
      params: params,
    );
    final rooms = _rooms(data);
    // ignore: avoid_print
    print('=== $url $params -> ${rooms.length} items');
    for (final item in rooms.take(2)) {
      // ignore: avoid_print
      print('--- room ${item['roomid']}');
      final keys = item.keys.toList()..sort();
      for (final k in keys) {
        final v = item[k];
        final s = v is Map || v is List ? jsonEncode(v) : '$v';
        if (s.isEmpty || s == '0' || s == 'false' || s == 'null') continue;
        if (s.length > 200) continue;
        // ignore: avoid_print
        print('  $k = $s');
      }
    }
    // 字段出现频次:一眼看出哪些是「每条都有」的结构字段。
    final freq = <String, int>{};
    for (final item in rooms) {
      for (final k in item.keys) {
        final v = item[k];
        final s = v is Map || v is List ? jsonEncode(v) : '$v';
        if (s.isEmpty || s == '0' || s == 'false' || s == 'null') continue;
        freq[k] = (freq[k] ?? 0) + 1;
      }
    }
    final common = freq.entries.where((e) => e.value >= rooms.length * 0.5).toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    // ignore: avoid_print
    print('  -- 高频字段: ${common.map((e) => '${e.key}(${e.value})').join(' ')}');
  } on Object catch (e) {
    // ignore: avoid_print
    print('=== $url FAILED: $e');
  }
}
