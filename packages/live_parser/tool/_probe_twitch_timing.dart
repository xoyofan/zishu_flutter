/// Twitch 解析耗时分解探针(真网络)。
///
/// 目的:把 `resolveRoom` 的冷解析拆成可归因的阶段,回答「Twitch 解析为何慢」:
///   watch?   —— 房间列表(可选,默认跳过)
///   user     —— GQL 元信息(UseLive)
///   token    —— GQL PlaybackAccessToken
///   playlist —— usher master m3u8
///   chain    —— 广告过滤代理的 playlist 包装
/// 运行:`dart run tool/_probe_twitch_timing.dart [login]`(默认走 7897 代理)
library;

import 'package:http/http.dart' as http;
import 'package:live_parser/live_parser.dart';
import 'package:live_parser/src/platforms/twitch/room_api.dart';
import 'package:live_parser/src/platforms/twitch/twitch_site.dart';

Future<void> main(List<String> args) async {
  UpstreamProxy.configure('127.0.0.1:7897');
  print('[upstream proxy: 127.0.0.1:7897]');

  final registry = buildSiteRegistry();
  final twitch = registry['twitch']!;
  final client = TwitchClient(httpClient: http.Client());

  String login = args.isNotEmpty ? args.first : '';
  if (login.isEmpty) {
    final sw = Stopwatch()..start();
    final rooms = await twitch.browse!.fetchRooms(
      const RoomListRequest(site: 'twitch', page: 1, limit: 5),
    );
    sw.stop();
    print('browse(首页 list): ${sw.elapsedMilliseconds}ms rooms=${rooms.rooms.length}');
    if (rooms.rooms.isEmpty) return;
    login = rooms.rooms.first.roomId;
  }
  print('target=$login');

  // 逐阶段计时(与 TwitchRoomResolver._resolve 相同的调用序列)。
  final user = Stopwatch()..start();
  final info = await fetchTwitchUser(client.gql, login);
  user.stop();
  print('GQL user(UseLive)            : ${user.elapsedMilliseconds}ms '
      'live=${info?.isLive} viewers=${info?.stream?.viewers}');

  final token = Stopwatch()..start();
  final playback = await fetchTwitchPlaybackToken(client.gql, login);
  token.stop();
  print('GQL PlaybackAccessToken      : ${token.elapsedMilliseconds}ms');

  final master = Stopwatch()..start();
  final playlist = await fetchTwitchMasterPlaylist(
    client.parserHttp,
    login: login,
    token: playback,
    clientId: client.clientId,
  );
  master.stop();
  final qualities = parseTwitchMasterPlaylist(playlist);
  print('usher master m3u8            : ${master.elapsedMilliseconds}ms '
      '(${playlist.length} bytes, ${qualities.length} 档)');
  for (final q in qualities) {
    print('   ${q.name.padRight(10)} rate=${q.rate} lines=${q.lines.length}');
  }

  // 冷解析整体(含 CachedRoomResolver 包装)与热解析对比。
  final cold = Stopwatch()..start();
  final payload = await twitch.resolver.resolveRoom(
    RoomRequest(site: 'twitch', roomIdOrUrl: login, preferredQuality: '原画'),
  );
  cold.stop();
  final warm = Stopwatch()..start();
  await twitch.resolver.resolveRoom(
    RoomRequest(site: 'twitch', roomIdOrUrl: login, preferredQuality: '原画'),
  );
  warm.stop();
  print('resolveRoom 冷(含缓存包装)   : ${cold.elapsedMilliseconds}ms '
      'state=${payload.roomState.name} tiers=${payload.streams.length} '
      '总线路=${payload.streams.fold(0, (a, s) => a + s.lines.length)}');
  print('resolveRoom 热(60s 缓存)     : ${warm.elapsedMilliseconds}ms');

  client.close();
}
