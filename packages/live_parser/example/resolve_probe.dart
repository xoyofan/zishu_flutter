// 斗鱼解析探测脚本:直接调用解析包,绕过 app UI,把真实错误/耗时打出来。
// 用法: dart run example/resolve_probe.dart [roomId]
import 'dart:io';
import 'package:live_parser/live_parser.dart';

Future<void> main(List<String> args) async {
  final room = args.isNotEmpty ? args[0] : '9999';
  UpstreamProxy.configure('127.0.0.1:7897'); // 模拟 app 的系统代理探测结果
  final registry = buildSiteRegistry();
  final site = registry['douyu'];
  if (site == null) {
    print('no douyu site in registry');
    exit(1);
  }
  final sw = Stopwatch()..start();
  try {
    final payload = await site.resolver
        .resolveRoom(RoomRequest(site: 'douyu', roomIdOrUrl: room))
        .timeout(const Duration(seconds: 30));
    sw.stop();
    print('RESOLVE_OK ${sw.elapsedMilliseconds}ms room=$room '
        'title=${payload.title} anchor=${payload.anchorName} '
        'state=${payload.roomState}');
    for (final q in payload.streams) {
      print('  quality=${q.name} lines=${q.lines.length}');
      for (final l in q.lines.take(3)) {
        print('    ${l.format} ${Uri.tryParse(l.url)?.host} expire='
            '${Uri.tryParse(l.url)?.queryParameters['expire']}');
      }
    }
  } catch (e, s) {
    sw.stop();
    print('RESOLVE_FAIL ${sw.elapsedMilliseconds}ms: $e');
    print(s.toString().split('\n').take(8).join('\n'));
  }
  exit(0);
}
