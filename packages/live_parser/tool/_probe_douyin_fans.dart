// 一次性探针:抓抖音真实弹幕,统计粉丝团徽章协议 URL 的模板分布,
// 判断我们渲染的是哪一款(advanced_badge 60×48 / new_badge 90×48 /
// level_v6 150×48 / 灰图),并打印每款的真实像素尺寸。
//
// 用法:cd packages/live_parser && dart run tool/_probe_douyin_fans.dart
import 'dart:io';

import 'package:live_parser/live_parser.dart';

Future<void> main() async {
  final target = buildSiteRegistry()['douyin']!;
  final room = await _pickRoom();
  stdout.writeln('== 房间 $room ==');
  final sub = await target.danmaku!.connect(
    DanmakuSessionRequest(site: 'douyin', roomId: room),
  );
  final seen = <String, int>{};
  try {
    await for (final m in sub.messages.timeout(const Duration(seconds: 40)).take(600)) {
      if (m.type != DanmakuMessageType.chat) continue;
      final url = m.badgeUrl;
      if (url.isEmpty) continue;
      final tpl = RegExp(r'(fansclub[_a-z0-9]*?)(?:_)?(\d+)').firstMatch(url);
      final key = tpl != null ? tpl.group(1)! : url.split('/').last.replaceAll(RegExp(r'\d+'), 'N');
      seen[key] = (seen[key] ?? 0) + 1;
      if (seen.length <= 6 && (seen[key] == 1)) {
        stdout.writeln('  lv=${m.badges.isEmpty ? "-" : m.badges.first.level} '
            'name="${m.badgeName}" url=$url');
      }
    }
  } on Object catch (e) {
    stdout.writeln('(结束 $e)');
  }
  await sub.close();
  stdout.writeln('== 模板分布 ==');
  seen.forEach((k, v) => stdout.writeln('  $k × $v'));
}

Future<String> _pickRoom() async {
  final browse = DouyinBrowseRepository(DouyinClient());
  final rooms = await browse.fetchRooms(const RoomListRequest(site: 'douyin', limit: 5));
  return rooms.rooms.first.roomId;
}
