/// 真实解析 benchmark:直连各平台 live_parser,测量 fetchRooms + resolveRoom
/// 冷/热耗时,并统计返回线路数(验证多线路自动切换的数据基础)。
///
/// 用法(在 packages/live_parser 下):
///   dart pub get
///   dart run tool/bench_real_parse.dart
///
/// 结果同时打到 stdout 与 tool/bench_real_parse.md。
library;

import 'dart:io';

import 'package:live_parser/live_parser.dart';

int _median(List<int> xs) {
  if (xs.isEmpty) return 0;
  final s = [...xs]..sort();
  return s[s.length ~/ 2];
}

String _short(Object e) {
  final s = e.toString();
  return s.length > 80 ? '${s.substring(0, 80)}…' : s;
}

Future<void> main() async {
  final registry = buildSiteRegistry();
  final now = DateTime.now().toLocal();
  final buf = StringBuffer();
  buf.writeln('# 真实解析 benchmark');
  buf.writeln();
  buf.writeln('- 运行时间: $now');
  buf.writeln('- 环境: 直连各平台 live_parser(dart `http` 默认 Client,不走代理 env)');
  buf.writeln('- 方法: 每平台先 fetchRooms(limit=10)测列表耗时,取首间房间 resolveRoom 测房间解析;'
      'resolve 跑 3 次取冷/热区间与中位(失败即中止)。');
  buf.writeln();
  buf.writeln('| 平台 | browse 列表 | resolve 房间(冷/热,中位) | 线路数 | 画质档 | 状态 |');
  buf.writeln('|---|---|---|---|---|---|');

  final rows = <String>[];
  int ok = 0;
  int fail = 0;
  final swTotal = Stopwatch()..start();

  for (final site in registry.supportedSites) {
    if (site == 'cross' || site == 'all') continue; // 聚合站点,不单独 benchmark。
    final reg = registry[site]!;
    var browseCell = '—';
    var resolveCell = '—';
    var lineCell = '—';
    var qualityCell = '—';
    var status = <String>[];
    String? roomId;

    if (reg.browse != null) {
      final sw = Stopwatch()..start();
      try {
        final res = await reg.browse!.fetchRooms(
          RoomListRequest(site: site, page: 1, limit: 10),
        );
        browseCell = '${sw.elapsedMilliseconds}ms (${res.rooms.length}间)';
        status.add('browse OK');
        if (res.rooms.isNotEmpty) roomId = res.rooms.first.roomId;
      } on Exception catch (e) {
        browseCell = '${sw.elapsedMilliseconds}ms FAIL';
        status.add('browse FAIL: ${_short(e)}');
        fail++;
      }
    } else {
      browseCell = '无浏览';
    }

    if (reg.resolver != null && roomId != null) {
      final samples = <int>[];
      RoomPayload? last;
      String? err;
      for (var i = 0; i < 3; i++) {
        final sw = Stopwatch()..start();
        try {
          last = await reg.resolver!.resolveRoom(
            RoomRequest(site: site, roomIdOrUrl: roomId),
          );
          samples.add(sw.elapsedMilliseconds);
        } on Exception catch (e) {
          err = _short(e);
          break;
        }
      }
      if (samples.isNotEmpty && last != null) {
        final lines = last.streams.fold<int>(0, (s, q) => s + q.lines.length);
        final cold = samples.first;
        final hot = samples.length > 1 ? samples.skip(1).reduce((a, b) => a < b ? a : b) : samples.first;
        resolveCell = '${cold}/${hot}ms 中位${_median(samples)}';
        lineCell = '$lines';
        qualityCell = '${last.streams.length}';
        status.add('resolve OK(${last.roomState.name},${last.anchorName})');
        ok++;
      } else {
        resolveCell = 'FAIL';
        status.add('resolve FAIL: $err');
        fail++;
      }
    } else if (reg.resolver != null) {
      resolveCell = '无房间ID';
      status.add('无可用房间');
    } else {
      resolveCell = '无解析';
    }

    rows.add('| $site | $browseCell | $resolveCell | $lineCell | $qualityCell | ${status.join('; ')} |');
  }

  buf.writeln(rows.join('\n'));
  buf.writeln();
  buf.writeln('## 汇总');
  buf.writeln();
  buf.writeln('- 总耗时: ${swTotal.elapsedMilliseconds}ms(含顺序串行各平台)。');
  buf.writeln('- resolve 成功: $ok / 失败: $fail。');
  buf.writeln('- 说明: 单平台串行、无并发;海外站(Twitch/YouTube/SOOP)可能受网络/代理/地域限制失败,属预期。');
  buf.writeln('- 线路数反映「多线路自动切换」的数据基础: 线路数>1 的平台断流时可由 mpv 播放列表内部跳下一条。');

  final scriptDir = File(Platform.script.toFilePath()).parent;
  final outPath = '${scriptDir.path}/bench_real_parse.md';
  await File(outPath).writeAsString(buf.toString());
  // 同时打印到 stdout。
  stdout.writeln(buf.toString());
}
