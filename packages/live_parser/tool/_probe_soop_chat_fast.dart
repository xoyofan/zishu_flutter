// 快速探针:soop 弹幕真连验证(单房间、5s 握手超时、收 1 条即止)。
// 运行:dart run tool/_probe_soop_chat_fast.dart
import 'dart:async';
import 'dart:io';

import 'package:live_parser/live_parser.dart';
import 'package:live_parser/src/http/danmaku_transport.dart';
import 'package:live_parser/src/platforms/soop/danmaku.dart';

Future<void> main() async {
  final client = SoopClient();
  try {
    final browse = SoopBrowseRepository(client.parserHttp);
    final rooms = await browse.fetchRooms(
      const RoomListRequest(site: 'soop', page: 1, limit: 3),
    );
    stdout.writeln('在播房间: ${[for (final r in rooms.rooms) r.roomId]}');
    for (final room in rooms.rooms.take(1)) {
      stdout.writeln('== 连接 ${room.roomId}「${room.anchorName}」 ==');
      final connector = SoopDanmakuConnector(
        client.parserHttp,
        transport: IoDanmakuTransport(connectTimeout: const Duration(seconds: 5)),
      );
      final session = await connector.connect(
        DanmakuSessionRequest(site: 'soop', roomId: room.roomId),
      );
      stdout.writeln('握手成功');
      var count = 0;
      final sub = session.messages.listen((message) {
        count++;
        stdout.writeln('  <${message.userName}> ${message.text}');
      });
      await Future<void>.delayed(const Duration(seconds: 12));
      stdout.writeln('12s 收到 $count 条');
      await sub.cancel();
      await session.close();
    }
    stdout.writeln('== done ==');
    exit(0);
  } on Object catch (error) {
    stdout.writeln('失败: $error');
    exit(1);
  } finally {
    client.close();
  }
}
