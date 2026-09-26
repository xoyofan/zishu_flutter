// 一次性探针:走正规 resolver 路径看 B 站统计槽(vip/svip/followers)实际取值,
// 并列出 web 真源用到的两个额外接口(粉丝勋章数 / 大航海)在我们的可达性。
//
// 用法:cd packages/live_parser && dart run tool/_probe_bili_stats.dart
import 'package:live_parser/live_parser.dart';

Future<void> main() async {
  final bili = buildSiteRegistry().byId('bilibili')!;
  final rooms = (await bili.browse!.fetchRooms(
    const RoomListRequest(site: 'bilibili', limit: 5),
  )).rooms;
  for (final r in rooms.take(3)) {
    // ignore: avoid_print
    print('[browse] rid=${r.roomId} cat=${r.category} '
        'aud=${r.audience} followers=${r.followers} vip=${r.vip} svip=${r.svip} '
        'promo=${r.promoTag} identity=${r.identityLabel} chips=${r.chips.length}');
  }
  for (final r in rooms.take(2)) {
    try {
      final fresh = await (bili.resolver as RoomSummaryRefresher).refreshRoomSummary(
        RoomRequest(site: 'bilibili', roomIdOrUrl: r.roomId),
      );
      // ignore: avoid_print
      print('[refresh] rid=${fresh.roomId} aud=${fresh.audience} '
          'followers=${fresh.followers} vip=${fresh.vip} svip=${fresh.svip} '
          'state=${fresh.roomState.name}');
    } on Object catch (e) {
      // ignore: avoid_print
      print('[refresh] rid=${r.roomId} FAILED: $e');
    }
  }
  // ignore: avoid_print
}
