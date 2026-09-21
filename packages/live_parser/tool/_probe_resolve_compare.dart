/// 解析耗时对比探针(真网络):twitch / youtube / soop × 代理/直连 × 多轮。
///
/// 目的:回答「哪个平台解析慢、慢在哪、要不要走代理」,每个平台都用**全新
/// registry**(清空解析侧缓存)测冷解析 —— 即用户「首次进房」的真实体感;
/// 再用同一 resolver 连打第二次测热解析(缓存命中,即「切档/回房」体感)。
///
/// 运行:
///   dart run tool/_probe_resolve_compare.dart [iters]
/// 说明:ir 为每站独立注入;twitch/soop/youtube 的 roomId 取各自首页首条。
library;

import 'dart:io';

import 'package:live_parser/live_parser.dart';
import 'package:live_parser/src/platforms/twitch/room_api.dart';
import 'package:live_parser/src/platforms/twitch/twitch_site.dart';

const String kProxyHostPort = '127.0.0.1:7897';

Future<void> main(List<String> args) async {
  final iterations = args.isEmpty ? 3 : int.tryParse(args.first) ?? 3;

  for (final mode in ['proxy', 'direct']) {
    UpstreamProxy.configure(mode == 'proxy' ? kProxyHostPort : null);
    stdout.writeln('\n========== mode=$mode '
        '(proxy=${UpstreamProxy.hostPort ?? "direct"}) ==========');
    for (final site in ['twitch', 'youtube', 'soop']) {
      await _testSite(site, iterations, mode);
    }
  }
}

Future<void> _testSite(String site, int iterations, String mode) async {
  stdout.writeln('\n--- $site ($mode) ---');

  // 每轮用全新 registry,确保是「冷解析」(缓存全空)。
  final rounds = <int>[];
  var stages = '';
  var warmMs = 0;
  String note = '';

  for (var i = 0; i < iterations; i++) {
    final registry = buildSiteRegistry();
    final registration = registry[site]!;
    String roomId;
    try {
      roomId = await _pickRoom(registry, site);
    } catch (e) {
      stdout.writeln('  #${i + 1} 取房间失败: $e');
      return;
    }
    if (roomId.isEmpty) {
      stdout.writeln('  #${i + 1} 首页无在播房间,跳过');
      return;
    }

    final sw = Stopwatch()..start();
    try {
      final payload = await registration.resolver
          .resolveRoom(
            RoomRequest(site: site, roomIdOrUrl: roomId, preferredQuality: null),
          )
          .timeout(const Duration(seconds: 90));
      sw.stop();
      rounds.add(sw.elapsedMilliseconds);
      final lineCount =
          payload.streams.fold<int>(0, (a, s) => a + s.lines.length);
      note = 'state=${payload.roomState.name} tiers=${payload.streams.length} '
          'lines=$lineCount';
      if (i == iterations - 1) {
        stages = await _stages(site, roomId);
        final warm = Stopwatch()..start();
        await registration.resolver.resolveRoom(
          RoomRequest(site: site, roomIdOrUrl: roomId),
        );
        warm.stop();
        warmMs = warm.elapsedMilliseconds;
      }
    } catch (e) {
      sw.stop();
      rounds.add(sw.elapsedMilliseconds);
      note = 'EXC ${e.toString().split('\n').first}';
    }
  }

  final sorted = [...rounds]..sort();
  stdout.writeln('  冷解析 ms: ${rounds.join(", ")}  '
      '| min=${sorted.first} median=${sorted[sorted.length ~/ 2]} '
      'max=${sorted.last}');
  if (warmMs > 0) stdout.writeln('  热解析(缓存) ms: $warmMs');
  if (note.isNotEmpty) stdout.writeln('  末轮: $note');
  if (stages.isNotEmpty) stdout.writeln(stages);
}

Future<String> _pickRoom(SiteRegistry registry, String site) async {
  final rooms = await registry[site]!.browse!.fetchRooms(
    RoomListRequest(site: site, page: 1, limit: 5),
  );
  if (rooms.rooms.isEmpty) return '';
  return rooms.rooms.first.roomId;
}

/// 阶段明细:与各平台解析器内部相同的调用序列,逐条计时。
Future<String> _stages(String site, String roomId) async {
  final buffer = StringBuffer();
  switch (site) {
    case 'twitch': {
      final client = TwitchClient();
      final user = Stopwatch()..start();
      final info = await fetchTwitchUser(client.gql, roomId);
      user.stop();
      final token = Stopwatch()..start();
      final playback = await fetchTwitchPlaybackToken(client.gql, roomId);
      token.stop();
      final master = Stopwatch()..start();
      final body = await fetchTwitchMasterPlaylist(
        client.parserHttp,
        login: info?.login ?? roomId,
        token: playback,
        clientId: client.clientId,
      );
      master.stop();
      buffer.writeln('    GQL user=${user.elapsedMilliseconds}ms '
          'token=${token.elapsedMilliseconds}ms '
          'usher=${master.elapsedMilliseconds}ms '
          'tiers=${parseTwitchMasterPlaylist(body).length}');
      client.close();
    }
    case 'youtube': {
      final client = YoutubeClient();
      // 1) watch 页(与 dlp 并行发起,这里单独计时)
      final watch = Stopwatch()..start();
      Object? watchErr;
      try {
        await fetchYoutubeWatchPage(client, roomId);
      } catch (e) {
        watchErr = e;
      }
      watch.stop();
      // 2) dlp 可用性
      final dlpOk = Stopwatch()..start();
      final available = await isYoutubeDlpAvailable();
      dlpOk.stop();
      // 3) yt-dlp 提取
      final dlp = Stopwatch()..start();
      final extract = available ? await extractYoutubeViaDlp(roomId) : null;
      dlp.stop();
      // 4) 首档地址链校验(master -> variant -> 首个分片)
      var validateMs = 0;
      var validateOk = false;
      final firstUrl = extract?.tiers.firstOrNull?.url;
      if (firstUrl != null) {
        final v = Stopwatch()..start();
        validateOk = await validateYoutubeChain(client, firstUrl);
        v.stop();
        validateMs = v.elapsedMilliseconds;
      }
      buffer.writeln('    watch 页=${watch.elapsedMilliseconds}ms'
          '${watchErr == null ? '' : ' (err=$watchErr)'} '
          '| dlp 可用性=${dlpOk.elapsedMilliseconds}ms($available) '
          '| yt-dlp=${dlp.elapsedMilliseconds}ms tiers=${extract?.tiers.length ?? 0} '
          '| 首档链校验=${validateMs}ms($validateOk)');
      final total = watch.elapsedMilliseconds +
          dlp.elapsedMilliseconds +
          validateMs;
      buffer.writeln('    ⇒ 主路线小计(watch 与 dlp 并行,取较大者)='
          '${(watch.elapsedMilliseconds > dlp.elapsedMilliseconds ? watch.elapsedMilliseconds : dlp.elapsedMilliseconds) + validateMs}ms');
      client.close();
      if (total < 0) buffer.writeln('');
    }
    case 'soop': {
      final registry = buildSiteRegistry();
      final client = SoopClient();
      final detail = Stopwatch()..start();
      final raw = await fetchSoopPlayerApi(client.parserHttp, roomId);
      final parsed = parseSoopRoomDetail(raw, roomId);
      detail.stop();
      buffer.writeln('    player_live_api(type=live)=${detail.elapsedMilliseconds}ms '
          'qualities=${parsed.qualities.length} live=${parsed.isLive}');
      if (parsed.isLive && parsed.qualities.isNotEmpty) {
        final tier = Stopwatch()..start();
        final assign = await fetchSoopAssignUrl(
          client.parserHttp,
          detail: parsed,
          quality: parsed.qualities.first.rawName,
        );
        final assignMs = tier.elapsedMilliseconds;
        final aidSw = Stopwatch()..start();
        final aid = await fetchSoopStreamAid(
          client.parserHttp,
          roomId: parsed.roomId,
          bno: parsed.bno,
          quality: parsed.qualities.first.rawName,
        );
        aidSw.stop();
        tier.stop();
        buffer.writeln('    assign=${assignMs}ms aid=${aidSw.elapsedMilliseconds}ms '
            '(单档合计=${tier.elapsedMilliseconds}ms) '
            'ok=${assign.isNotEmpty && aid.isNotEmpty} 档位总数=${parsed.qualities.length}');
      }
      client.close();
      // registry 变量仅为保持与其它分支一致的形态。
      if (registry.supportedSites.isEmpty) buffer.writeln('    (registry 为空)');
    }
  }
  return buffer.toString();
}
