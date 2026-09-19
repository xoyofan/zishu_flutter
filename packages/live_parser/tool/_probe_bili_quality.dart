// 一次性探针:拉 bilibili 真实房间 resolve,打印画质档位与线路。
import 'package:live_parser/live_parser.dart';

Future<void> main() async {
  final bili = buildSiteRegistry().byId('bilibili')!;
  final browse = await bili.browse!.fetchRooms(
    const RoomListRequest(site: 'bilibili'),
  );
  final first = browse.rooms.first;
  // ignore: avoid_print
  print('[browse] first=${first.roomId} category=${first.category} '
      'online=${first.online}');
  final payload = await bili.resolver.resolveRoom(
    RoomRequest(site: 'bilibili', roomIdOrUrl: first.roomId),
  );
  // ignore: avoid_print
  print('[resolve] qualities=${payload.availableQualities.map((q) => q.name).toList()}');
  for (final q in payload.streams) {
    // ignore: avoid_print
    print('[stream] ${q.name} rate=${q.rate} lines=${q.lines.length} '
        'formats=${q.lines.map((l) => l.format).toSet().toList()}');
  }
}
