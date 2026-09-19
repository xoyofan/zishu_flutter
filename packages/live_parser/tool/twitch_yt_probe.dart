import 'package:live_parser/live_parser.dart';

Future<void> main(List<String> args) async {
  if (args.isNotEmpty && args[0] == 'proxy') {
    UpstreamProxy.configure('127.0.0.1:7897');
    print('[upstream proxy: 127.0.0.1:7897]');
  }
  final reg = buildSiteRegistry();

  Future<void> probeSite(String site) async {
    final r = reg[site];
    print('=== $site ===');
    if (r == null) {
      print('  NOT REGISTERED');
      return;
    }
    // 1. 房间列表(browse)
    try {
      final rooms = await r.browse!.fetchRooms(
        RoomListRequest(site: site, page: 1, limit: 5),
      );
      print('  rooms: ${rooms.rooms.length} hasMore=${rooms.hasMore}');
      for (final room in rooms.rooms.take(3)) {
        print('    ${room.roomId} | ${room.anchorName} | ${room.category} | ${room.title}');
      }
      final target = rooms.rooms.firstOrNull;
      if (target == null) return;
      // 2. 播放解析
      try {
        final payload = await r.resolver.resolveRoom(
          RoomRequest(site: site, roomIdOrUrl: target.roomId),
        );
        print('  resolve: state=${payload.roomState.name} err=${payload.error ?? "-"}');
        print('    qualities=${payload.availableQualities.map((q) => q.name).toList()}');
        for (final s in payload.streams) {
          print('    tier ${s.name}: lines=${s.lines.length}');
        }
      } catch (e) {
        print('  resolve EXC: $e');
      }
      // 3. 弹幕
      final connector = r.danmaku;
      if (connector == null || !connector.capabilities.danmaku) {
        print('  danmaku: not supported by registration');
        return;
      }
      try {
        final session = await connector
            .connect(DanmakuSessionRequest(site: site, roomId: target.roomId))
            .timeout(const Duration(seconds: 15));
        final states = <DanmakuSessionState>[];
        final msgs = <DanmakuMessage>[];
        final sub1 = session.states.listen(states.add);
        final sub2 = session.messages.listen(msgs.add);
        await Future<void>.delayed(const Duration(seconds: 12));
        print('  danmaku: states=$states msgs=${msgs.length}');
        for (final m in msgs.take(3)) {
          print('    [${m.userName}] ${m.text}');
        }
        await sub1.cancel();
        await sub2.cancel();
        await session.close();
      } catch (e) {
        print('  danmaku EXC: $e');
      }
    } catch (e) {
      print('  browse EXC: $e');
    }
  }

  await probeSite('twitch');
  await probeSite('youtube');
}
