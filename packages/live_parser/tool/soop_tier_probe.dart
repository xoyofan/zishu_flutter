import 'package:live_parser/live_parser.dart';

Future<void> main() async {
  final reg = buildSoopRegistration();
  for (final quality in ['原画', '高清', '标清', '4K']) {
    try {
      final payload = await reg.resolver.resolveRoom(
        RoomRequest(site: 'soop', roomIdOrUrl: 'phonics1', preferredQuality: quality),
      );
      final tier = payload.streams.firstOrNull;
      final line = tier?.lines.firstOrNull;
      print('$quality -> state=${payload.roomState.name} '
          'tier=${tier?.name ?? "-"} lines=${tier?.lines.length ?? 0} '
          'url=${line == null ? "-" : line.url.substring(0, 55)}...');
    } catch (e) {
      print('$quality -> EXC $e');
    }
  }
}
