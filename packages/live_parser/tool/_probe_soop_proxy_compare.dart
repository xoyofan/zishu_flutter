// 探针:对比「直连 vs 系统代理」下 soop 聊天域名下发与弹幕连接。
// 运行:dart run tool/_probe_soop_proxy_compare.dart
import 'dart:async';
import 'dart:io';

import 'package:live_parser/live_parser.dart';
import 'package:live_parser/src/http/danmaku_transport.dart';
import 'package:live_parser/src/http/upstream_proxy.dart';
import 'package:live_parser/src/platforms/soop/danmaku.dart';

const String _roomId = 'devil0108';

Future<void> main() async {
  stdout.writeln('======== 直连 ========');
  await run(enabled: false);
  stdout.writeln('======== 系统代理 127.0.0.1:7897 ========');
  await run(enabled: true);
  stdout.writeln('== done ==');
  exit(0);
}

Future<void> run({required bool enabled}) async {
  UpstreamProxy.configure(enabled ? '127.0.0.1:7897' : null);
  final client = SoopClient();
  try {
    final payload = await fetchSoopPlayerApi(client.parserHttp, _roomId);
    final ch = (payload['CHANNEL'] as Map?) ?? const {};
    stdout.writeln(
      '聊天参数: CHATNO=${ch['CHATNO']} CHDOMAIN=${ch['CHDOMAIN']} '
      'CHPT=${ch['CHPT']} geo=${ch['geo_cc']}',
    );
    final connector = SoopDanmakuConnector(
      client.parserHttp,
      transport: IoDanmakuTransport(connectTimeout: const Duration(seconds: 6)),
    );
    final session = await connector.connect(
      DanmakuSessionRequest(site: 'soop', roomId: _roomId),
    );
    var count = 0;
    final sub = session.messages.listen((_) => count++);
    await Future<void>.delayed(const Duration(seconds: 10));
    stdout.writeln('10s 收到 $count 条');
    await sub.cancel();
    await session.close();
  } on Object catch (error) {
    stdout.writeln('失败: $error');
  } finally {
    client.close();
  }
}
