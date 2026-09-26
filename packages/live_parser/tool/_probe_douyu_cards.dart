// 一次性探针:对比斗鱼旧列表接口(gapi/rkc/directory/mixList)与新列表接口
// (gapi/rknc/directory/mixListV1)的条目数与字段差异,确认后者是否带
// 卡片左上角标 icv3(页面上的「段位LV4」),以及哪些 cid2 有数据。
//
// 2026-09-26 实测:icv3[i].cfgRich.text = 角标文案;icv3 只在游戏目录
// (如 2_2 炉石传说)出现,首页 0_0 为 null。
//
// 用法:cd packages/live_parser && dart run tool/_probe_douyu_cards.dart
import 'dart:convert';

import 'package:live_parser/live_parser.dart';

const _headers = {'Referer': 'https://www.douyu.com/'};

Map<String, dynamic> _map(Object? v) => v is Map<String, dynamic> ? v : <String, dynamic>{};

List<Object?> _list(Object? v) => v is List ? v : const [];

Future<void> main() async {
  final http = ParserHttp();
  for (final cid in ['0_0', '2_2', '2_181', '2_3', '2_270', '2_3351']) {
    await _probe(http, cid);
  }
  await _rawIcv3(http, '0_0');
  await _rawIcv3(http, '2_2');
  await _cover(http, '2_2');
  await _paging(http, '0_0');
}

/// 打印旧/新接口同房间的封面字段,并 HEAD 校验图片可加载。
Future<void> _cover(ParserHttp http, String cid) async {
  final old = await _fetch(http, 'gapi/rkc/directory/mixList/$cid/1');
  final v1 = await _fetch(http, 'gapi/rknc/directory/mixListV1/$cid/1');
  for (final item in v1.take(2)) {
    final rid = item['rid'];
    final same = old.where((e) => e['rid'] == rid).firstOrNull;
    // ignore: avoid_print
    print('### cover rid=$rid');
    // ignore: avoid_print
    print('   v1  rs16=${item['rs16']} rs1=${item['rs1']} rs_ext=${jsonEncode(item['rs_ext'])}');
    // ignore: avoid_print
    print('   old rs16=${same?['rs16']} rs1=${same?['rs1']}');
    for (final url in ['${item['rs16']}', '${item['rs16']}/dy1']) {
      if (url.isEmpty || url == 'null') continue;
      try {
        final res = await http.get(Uri.parse(url));
        // ignore: avoid_print
        print('   GET $url -> ${res.statusCode} bytes=${res.bodyBytes.length}');
      } on Object catch (e) {
        // ignore: avoid_print
        print('   GET $url -> FAIL $e');
      }
    }
  }
}

/// 翻页校验:V1 第 2 页是否给新房间。
Future<void> _paging(ParserHttp http, String cid) async {
  final p1 = await _fetch(http, 'gapi/rknc/directory/mixListV1/$cid/1');
  final p2 = await _fetch(http, 'gapi/rknc/directory/mixListV1/$cid/2');
  final p3 = await _fetch(http, 'gapi/rknc/directory/mixListV1/$cid/3');
  final ids1 = p1.map((e) => '${e['rid']}').toSet();
  // ignore: avoid_print
  print('### paging $cid p1=${p1.length} p2=${p2.length} p3=${p3.length} '
      'p2overlap=${ids1.intersection(p2.map((e) => '${e['rid']}').toSet()).length}');
}

/// 原样打印若干条 icv3 原文,看清全部形态(text 型 / 图片型 / 多条)。
Future<void> _rawIcv3(ParserHttp http, String cid) async {
  final v1 = await _fetch(http, 'gapi/rknc/directory/mixListV1/$cid/1');
  // ignore: avoid_print
  print('### raw icv3 $cid');
  var shown = 0;
  for (final item in v1) {
    if (_list(item['icv3']).isEmpty) continue;
    // ignore: avoid_print
    print('  rid=${item['rid']} ${jsonEncode(item['icv3'])}');
    if (++shown >= 6) break;
  }
}

Future<void> _probe(ParserHttp http, String cid) async {
  final old = await _fetch(http, 'gapi/rkc/directory/mixList/$cid/1');
  final v1 = await _fetch(http, 'gapi/rknc/directory/mixListV1/$cid/1');
  // ignore: avoid_print
  print('=== cid=$cid  old=${old.length}  v1=${v1.length}');
  final shapes = <String, int>{};
  final texts = <String, int>{};
  for (final item in v1) {
    final icv3 = _list(item['icv3']);
    final kinds = icv3.map((e) => '${_map(e)['cfgType']}').join('+');
    shapes['cfgType=$kinds'] = (shapes['cfgType=$kinds'] ?? 0) + 1;
    for (final e in icv3) {
      final t = '${_map(_map(e)['cfgRich'])['text']}';
      if (t.isNotEmpty) texts[t] = (texts[t] ?? 0) + 1;
    }
  }
  // ignore: avoid_print
  print('   v1 icv3 shapes: $shapes');
  // ignore: avoid_print
  print('   v1 icv3 texts : $texts');
  // ignore: avoid_print
  print('   v1 label 样例: ${v1.take(3).map((e) => jsonEncode(_list(e['roomLabel']))).toList()}');
  // ignore: avoid_print
  print('   v1 gametag 样例: ${v1.take(3).map((e) => e['gametag']).toList()}');
}

Future<List<Map<String, dynamic>>> _fetch(ParserHttp http, String path) async {
  try {
    final res = await http.get(
      Uri.parse('https://www.douyu.com/$path'),
      headers: _headers,
    );
    final data = _map(_map(jsonDecode(utf8.decode(res.bodyBytes)))['data']);
    return _list(data['rl']).whereType<Map<String, dynamic>>().toList();
  } on Object catch (e) {
    // ignore: avoid_print
    print('   FETCH $path FAILED: $e');
    return const [];
  }
}
