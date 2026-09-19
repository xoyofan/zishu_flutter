import 'package:live_parser/live_parser.dart';

Future<void> main() async {
  final reg = buildSiteRegistry();
  final yy = reg['yy']!;
  // 1. 预热分类树(填 biz→中文名)
  final cats = await yy.browse!.fetchCategories('yy');
  print('分类树: ${cats.groups.expand((g) => g.items).take(5).map((i) => i.name).toList()}...');
  // 2. 首页推荐流(原 other)
  final rooms = await yy.browse!.fetchRooms(
    const RoomListRequest(site: 'yy', page: 1, limit: 3),
  );
  print('首页推荐 category: ${rooms.rooms.map((r) => r.category).toSet().toList()}');
  // 3. 真实房间解析
  if (rooms.rooms.isNotEmpty) {
    final payload = await yy.resolver.resolveRoom(
      RoomRequest(site: 'yy', roomIdOrUrl: rooms.rooms.first.roomId),
    );
    print('resolve(${rooms.rooms.first.roomId}): category=${payload.category}'
        ' state=${payload.roomState.name}');
  }
}
