// 探针:真机验证 soop / twitch 弹幕链路(收 N 条消息或超时)。
// 运行:dart run tool/_probe_danmaku_live.dart
import 'dart:async';
import 'dart:io';

import 'package:live_parser/live_parser.dart';
import 'package:live_parser/src/platforms/soop/danmaku.dart' as soop_danmaku;
import 'package:live_parser/src/platforms/twitch/danmaku.dart';
import 'package:live_parser/src/platforms/twitch/gql.dart';
import 'package:live_parser/src/platforms/twitch/room_api.dart';

Future<void> main() async {
  stdout.writeln('== soop 弹幕探针 ==');
  await _probeSoop();

  stdout.writeln('== twitch 弹幕探针 ==');
  await _probeTwitch();

  stdout.writeln('== done ==');
}

Future<void> _probeSoop() async {
  final client = SoopClient();
  try {
    // 推荐列表拿一个在播房间。
    final browse = SoopBrowseRepository(client.parserHttp);
    final rooms = await browse.fetchRooms(
      const RoomListRequest(site: 'soop', page: 1, limit: 5),
    );
    if (rooms.rooms.isEmpty) {
      stdout.writeln('soop: 推荐列表为空,跳过');
      return;
    }
    for (final room in rooms.rooms.take(3)) {
      stdout.writeln(
        'soop: 房间 ${room.roomId}「${room.anchorName}」分类=${room.category}',
      );
      final connector = soop_danmaku.SoopDanmakuConnector(client.parserHttp);
      try {
        final session = await connector.connect(
          DanmakuSessionRequest(site: 'soop', roomId: room.roomId),
        );
        final done = Completer<int>();
        var count = 0;
        final sub = session.messages.listen((message) {
          count++;
          stdout.writeln(
            '  soop<${message.userName}>: ${message.text}'
            '${message.color != 0 ? ' [色#${message.color.toRadixString(16)}]' : ''}',
          );
          if (count >= 3 && !done.isCompleted) done.complete(count);
        });
        await Future.any([
          done.future,
          Future<void>.delayed(const Duration(seconds: 15)),
        ]);
        stdout.writeln('soop: 收到 $count 条');
        await sub.cancel();
        await session.close();
        if (count > 0) return;
      } catch (error) {
        stdout.writeln('  soop 连接失败: $error');
      }
    }
  } finally {
    client.close();
  }
}

Future<void> _probeTwitch() async {
  final gql = TwitchGqlClient();
  final connector = TwitchDanmakuConnector();
  try {
    for (final login in ['kaicenat', 'xqc', 'zackrawrr', 'jynxzi', 'loltyler1']) {
      // 先确认在播(不在播的频道 IRC 无消息)。
      TwitchUser? user;
      try {
        user = await fetchTwitchUser(gql, login);
      } on Object catch (error) {
        stdout.writeln('twitch: $login 查询失败 $error');
        continue;
      }
      if (user == null || !user.isLive) {
        stdout.writeln('twitch: $login 未在播,跳过');
        continue;
      }
      stdout.writeln(
        'twitch: 频道 $login 在播「${user.stream!.gameName}」',
      );
      final session = await connector.connect(
        DanmakuSessionRequest(site: 'twitch', roomId: login),
      );
      var count = 0;
      final sub = session.messages.listen((message) {
        count++;
        stdout.writeln(
          '  twitch<${message.userName}>: ${message.text}'
          '${message.segments.any((s) => s.isEmoji) ? ' [含表情段]' : ''}',
        );
        if (count >= 3) {}
      });
      await Future<void>.delayed(const Duration(seconds: 15));
      stdout.writeln('twitch: 15s 收到 $count 条');
      await sub.cancel();
      await session.close();
      if (count > 0) return;
    }
  } finally {
    gql.close();
  }
}
