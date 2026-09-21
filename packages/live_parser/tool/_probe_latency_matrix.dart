/// 多房间解析/取流延时实测:比较 yt-dlp 调用形态与线路首包延时。
///
/// 回答两个问题:
///  1) YouTube 的 dlp 提取能否更快(`-J` 全量 JSON vs `--print` 精简输出);
///  2) 各平台「解析 → 首个 playlist 可取」的端到端延时,以及线路抖动分布。
///
/// 运行:`dart run tool/_probe_latency_matrix.dart [rooms]`
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:live_parser/live_parser.dart';

const String kProxy = '127.0.0.1:7897';

Future<void> main(List<String> args) async {
  UpstreamProxy.configure(kProxy);
  final rooms = args.isEmpty ? 3 : int.tryParse(args.first) ?? 3;
  print('[proxy=$kProxy rooms=$rooms]');

  await _youtubeDlpVariants(rooms);
  await _platformLatency(rooms);
}

/// YouTube:同一视频、三种 yt-dlp 调用形态的耗时对比。
Future<void> _youtubeDlpVariants(int rooms) async {
  print('\n=== yt-dlp 调用形态对比(YouTube) ===');
  final registry = buildSiteRegistry();
  final list = await registry['youtube']!.browse!.fetchRooms(
    RoomListRequest(site: 'youtube', page: 1, limit: rooms),
  );
  final bin = await _dlpBin();
  if (bin == null) {
    print('  yt-dlp 不可用');
    return;
  }
  final deno = Platform.environment['LOCALAPPDATA'] == null
      ? null
      : '${Platform.environment['LOCALAPPDATA']}\\Microsoft\\WinGet\\Links\\deno.exe';

  for (final room in list.rooms) {
    print('  -- ${room.roomId} | ${room.anchorName}');
    for (final variant in [
      ('-J 全量 JSON', ['-J']),
      (
        '--print 精简',
        [
          '--print',
          '%(height)s|%(fps)s|%(protocol)s|%(url)s',
        ],
      ),
      (
        '-f m3u8 + --print',
        [
          '-f',
          'b[protocol^=m3u8]/b',
          '--print',
          '%(height)s|%(fps)s|%(protocol)s|%(url)s',
        ],
      ),
    ]) {
      final sw = Stopwatch()..start();
      final out = await _runDlp(bin, deno, room.roomId, variant.$2);
      sw.stop();
      final lines = out == null
          ? -1
          : out.split(RegExp(r'\r?\n')).where((l) => l.contains('|')).length;
      print('     ${variant.$1.padRight(16)} ${sw.elapsedMilliseconds}ms '
          'hls行=$lines');
    }
  }
}

Future<String?> _dlpBin() async {
  final r = await Process.run('where', ['yt-dlp']);
  if (r.exitCode != 0) return null;
  final first = '${r.stdout}'.split(RegExp(r'\r?\n')).first.trim();
  return first.isEmpty ? null : first;
}

Future<String?> _runDlp(
  String bin,
  String? deno,
  String videoId,
  List<String> extra,
) async {
  final args = <String>[
    'https://www.youtube.com/watch?v=$videoId',
    '--no-warnings',
    '--no-playlist',
    ...extra,
  ];
  if (deno != null && File(deno).existsSync()) {
    args.addAll(['--js-runtimes', 'deno:${deno.replaceAll(r'\', '/')}']);
  }
  try {
    final p = await Process.start(bin, args);
    final out = p.stdout.transform(utf8.decoder).join();
    final err = p.stderr.transform(utf8.decoder).join();
    final code = await p.exitCode.timeout(const Duration(seconds: 90));
    await err;
    if (code != 0) return null;
    return await out;
  } on Object {
    return null;
  }
}

/// 各平台:解析耗时 + 选中线路首包延时 + 各候选线路延时分布。
Future<void> _platformLatency(int rooms) async {
  for (final site in ['twitch', 'youtube', 'soop']) {
    print('\n=== $site 多房间延时 ===');
    final registry = buildSiteRegistry();
    final registration = registry[site]!;
    List<RoomSummary> list;
    try {
      list = (await registration.browse!.fetchRooms(
        RoomListRequest(site: site, page: 1, limit: rooms),
      )).rooms;
    } catch (e) {
      print('  列表失败: $e');
      continue;
    }
    for (final room in list) {
      final sw = Stopwatch()..start();
      RoomPayload payload;
      try {
        payload = await registration.resolver
            .resolveRoom(
              RoomRequest(site: site, roomIdOrUrl: room.roomId),
            )
            .timeout(const Duration(seconds: 60));
      } catch (e) {
        sw.stop();
        print('  ${room.roomId} 解析失败(${sw.elapsedMilliseconds}ms): $e');
        continue;
      }
      sw.stop();
      final resolveMs = sw.elapsedMilliseconds;
      final lines = [
        for (final s in payload.streams)
          for (final l in s.lines) (tier: s.name, line: l),
      ];
      final probes = await Future.wait([
        for (final item in lines.take(8)) _probeLine(item.line.url),
      ]);
      final ok = probes.where((p) => p > 0).toList()..sort();
      final summary = probes
          .map((p) => p < 0 ? 'x' : '${p}ms')
          .join(' ');
      print('  ${room.roomId} resolve=${resolveMs}ms tiers=${payload.streams.length} '
          'lines=${lines.length}');
      print('     线路首包: $summary  | 最快=${ok.isEmpty ? "-" : "${ok.first}ms"} '
          '中位=${ok.isEmpty ? "-" : "${ok[ok.length ~/ 2]}ms"}');
    }
  }
}

/// 单个线路首包延时:GET playlist 只读前若干字节即断开;失败/超时返回 -1。
Future<int> _probeLine(String url) async {
  final sw = Stopwatch()..start();
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  if (UpstreamProxy.needsProxy(Uri.tryParse(url)?.host ?? '')) {
    client.findProxy = (uri) => UpstreamProxy.findProxyFor(uri);
  }
  try {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close().timeout(const Duration(seconds: 6));
    if (response.statusCode >= 400) return -1;
    await response.first.timeout(const Duration(seconds: 6));
    sw.stop();
    return sw.elapsedMilliseconds;
  } on Object {
    return -1;
  } finally {
    client.close(force: true);
  }
}
