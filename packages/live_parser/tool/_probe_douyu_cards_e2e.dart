// 一次性端到端校验:走真实 DouyuBrowseRepository(不注入 fake),
// 打印首页/分类列表的 identityLabel + chips + promoTag,确认 mixListV1 接线生效。
//
// 用法:cd packages/live_parser && dart run tool/_probe_douyu_cards_e2e.dart
import 'package:live_parser/live_parser.dart';
import 'package:live_parser/src/platforms/douyu/browse.dart';

Future<void> main() async {
  final browse = DouyuBrowseRepository(ParserHttp());
  for (final (label, request) in [
    ('首页 0_0', const RoomListRequest(site: 'douyu', limit: 12)),
    ('炉石 2_2', const RoomListRequest(site: 'douyu', cid: '2', limit: 12)),
    ('DNF 2_4', const RoomListRequest(site: 'douyu', cid: '4', limit: 12)),
  ]) {
    try {
      final result = await browse.fetchRooms(request);
      // ignore: avoid_print
      print('=== $label -> ${result.rooms.length} 房 hasMore=${result.hasMore}');
      for (final room in result.rooms.take(6)) {
        // ignore: avoid_print
        print('  rid=${room.roomId} cat=${room.category} '
            'identity=${room.identityLabel} promo=${room.promoTag} '
            'chips=${room.chips.map((c) => c.name).toList()}');
      }
    } on Object catch (e) {
      // ignore: avoid_print
      print('=== $label FAILED: $e');
    }
  }
}
