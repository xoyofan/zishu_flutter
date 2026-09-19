import 'package:live_parser/live_parser.dart';

Future<void> main(List<String> args) async {
  if (args.isNotEmpty && args[0] == 'proxy') {
    UpstreamProxy.configure('127.0.0.1:7897');
  }
  final reg = buildSiteRegistry();
  final sites = ['douyu', 'huya', 'bilibili', 'kuaishou', 'douyin', 'yy', 'twitch', 'youtube'];
  for (final site in sites) {
    final r = reg[site];
    if (r?.browse == null) continue;
    try {
      final rooms = await r!.browse!.fetchRooms(
        RoomListRequest(site: site, page: 1, limit: 4),
      );
      final cats = rooms.rooms.map((x) => x.category).toSet().toList();
      print('$site: ${cats.take(6)}');
    } catch (e) {
      print('$site: EXC ${e.runtimeType}');
    }
  }
}
