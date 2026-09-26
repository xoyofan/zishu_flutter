// 一次性探针:验证 B 站「大航海」(guardTab/topList info.num) 在真实房间
// 能否取到非 0,判断 B 站第 3 列是「真没数据」还是「取数方式不对」;
// 顺带统计 get_info 的 tags(逗号分隔多标签)覆盖率。
//
// 用法:cd packages/live_parser && dart run tool/_probe_bili_guard.dart
import 'package:live_parser/live_parser.dart';
import 'package:live_parser/src/platforms/bilibili/room_api.dart';
import 'package:live_parser/src/platforms/bilibili/wbi.dart';

Map<String, dynamic> _map(Object? v) =>
    v is Map<String, dynamic> ? v : <String, dynamic>{};

Future<void> main() async {
  final http = ParserHttp();
  final credentials = BilibiliCredentials();

  // 走正规 browse 拿房间(它有回退链,比裸调分区接口稳)。
  final browse = buildSiteRegistry().byId('bilibili')!.browse!;
  final roomIds = <String>[];
  for (final req in [
    const RoomListRequest(site: 'bilibili', limit: 30),
    const RoomListRequest(site: 'bilibili', cid: '86', limit: 30),
    const RoomListRequest(site: 'bilibili', cid: '214', limit: 30),
  ]) {
    try {
      for (final r in (await browse.fetchRooms(req)).rooms) {
        if (!roomIds.contains(r.roomId)) roomIds.add(r.roomId);
      }
    } on Object catch (e) {
      // ignore: avoid_print
      print('browse $req FAILED: $e');
    }
  }
  // ignore: avoid_print
  print('样本房间数: ${roomIds.length}');

  var nonZero = 0;
  var tagged = 0;
  var checked = 0;
  for (final rid in roomIds.take(40)) {
    final info = await fetchBilibiliRoomInfo(http, credentials, rid);
    final tags = '${info['tags'] ?? ''}'.trim();
    final uid = (info['uid'] as int?) ?? 0;
    checked++;
    if (tags.isNotEmpty) tagged++;
    var num = -1;
    try {
      final data = await bilibiliFetchJson(
        http,
        credentials,
        Uri.parse(
          'https://api.live.bilibili.com/xlive/app-room/v2/guardTab/topList',
        ),
        params: {
          'roomid': rid,
          'ruid': '$uid',
          'page': '1',
          'page_size': '10',
        },
        roomId: rid,
      );
      num = (_map(_map(data)['info'])['num'] as int?) ?? -1;
    } on Object catch (e) {
      // ignore: avoid_print
      print('rid=$rid guardTab FAILED: $e');
    }
    if (num > 0) nonZero++;
    // ignore: avoid_print
    print(
      'rid=$rid uid=$uid guard=$num live=${info['live_status']} tags="$tags"',
    );
  }
  // ignore: avoid_print
  print('=== $checked 间样本:大航海非 0 = $nonZero,带 tags = $tagged');
}
