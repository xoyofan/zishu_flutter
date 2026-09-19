import 'package:live_parser/live_parser.dart';

Future<void> main() async {
  final reg = buildSoopRegistration();
  final payload = await reg.resolver.resolveRoom(
    const RoomRequest(site: 'soop', roomIdOrUrl: 'phonics1'),
  );
  print('state=${payload.roomState} error=${payload.error ?? "-"}');
  print('availableQualities: ${payload.availableQualities.map((q) => q.name).toList()}');
  for (final s in payload.streams) {
    print('  tier ${s.name}: lines=${s.lines.length} url=${s.lines.isEmpty ? "-" : s.lines.first.url.substring(0, 60)}...');
  }
}
