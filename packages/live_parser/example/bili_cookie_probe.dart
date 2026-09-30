// CLI probe: bilibili login-cookie tier unlock verification.
import 'package:live_parser/live_parser.dart';

Future<void> main(List<String> args) async {
  final cookie = args.isEmpty ? '' : args.first;
  final registry = buildSiteRegistry(bilibiliCookie: cookie);
  final registration = registry['bilibili']!;
  final payload = await registration.resolver.resolveRoom(
    RoomRequest(site: 'bilibili', roomIdOrUrl: '6', preferredQuality: 'worst'),
  );
  print('qualities=${payload.availableQualities.map((q) => q.name).join(",")}');
  for (final s in payload.streams) {
    final qn = s.lines.isEmpty
        ? ''
        : RegExp(r'qn=(\d+)').firstMatch(s.lines.first.url)?.group(1);
    print('tier=${s.name} lines=${s.lines.length} url_qn=$qn');
  }
}
