// 探针:twitch IRC 弹幕真机验证(browse 拿在播频道 → 连 IRC 收 PRIVMSG)。
// 运行:dart run tool/_probe_twitch_irc.dart
import 'dart:async';
import 'dart:io';

import 'package:live_parser/live_parser.dart';
import 'package:live_parser/src/platforms/twitch/browse.dart';
import 'package:live_parser/src/platforms/twitch/danmaku.dart';
import 'package:live_parser/src/platforms/twitch/gql.dart';

Future<void> main() async {
  final gql = TwitchGqlClient();
  final connector = TwitchDanmakuConnector();
  try {
    final browse = TwitchBrowseRepository(gql);
    var rooms = (await browse.fetchRooms(
      const RoomListRequest(site: 'twitch', page: 1, limit: 10),
    ))
        .rooms;
    stdout.writeln('twitch browse: ${rooms.length} 个在播房间');
    if (rooms.isEmpty) {
      stdout.writeln('twitch: browse 无在播,退出');
      return;
    }
    for (final room in rooms.take(3)) {
      final login = room.roomId;
      stdout.writeln(
        'twitch: 尝试 $login「${room.anchorName}」${room.category}',
      );
      final session = await connector.connect(
        DanmakuSessionRequest(site: 'twitch', roomId: login),
      );
      var count = 0;
      final sub = session.messages.listen((message) {
        count++;
        final hasEmote = message.segments.any((s) => s.isEmoji);
        stdout.writeln(
          '  <${message.userName}> ${message.text}'
          '${hasEmote ? ' [表情段 x${message.segments.where((s) => s.isEmoji).length}]' : ''}'
          '${message.color != 0 ? ' #${message.color.toRadixString(16)}' : ''}',
        );
      });
      await Future<void>.delayed(const Duration(seconds: 15));
      stdout.writeln('twitch $login: 15s 收到 $count 条');
      await sub.cancel();
      await session.close();
      if (count > 0) return;
    }
    stdout.writeln('twitch: 前三频道均未收到消息');
  } finally {
    gql.close();
  }
}
