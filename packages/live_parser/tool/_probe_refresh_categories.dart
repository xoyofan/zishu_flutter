// 一次性探针:逐站跑 refreshRoomSummary,记录 category/cid 真实返回,
// 核对 douyin/soop/yy/kuaishou 的分类提取(真机样本显示为空)。
import 'package:live_parser/live_parser.dart';

const _sites = ['douyin', 'soop', 'yy', 'kuaishou'];

Future<void> main() async {
  final registry = buildSiteRegistry();
  for (final site in _sites) {
    final registration = registry.byId(site);
    if (registration == null || registration.browse == null) {
      // ignore: avoid_print
      print('[$site] no browse');
      continue;
    }
    try {
      final rooms = (await registration.browse!.fetchRooms(
        RoomListRequest(site: site),
      )).rooms;
      if (rooms.isEmpty) {
        // ignore: avoid_print
        print('[$site] browse empty');
        continue;
      }
      final target = rooms.first;
      final summary = await (registration.resolver as dynamic)
          .refreshRoomSummary(RoomRequest(site: site, roomIdOrUrl: target.roomId));
      // ignore: avoid_print
      print('[$site] rid=${summary.roomId} '
          'browse=${target.category} refresh=${summary.category} '
          'cid=${summary.cid} online=${summary.online}');
    } on Object catch (error) {
      // ignore: avoid_print
      print('[$site] FAILED: $error');
    }
  }
}
