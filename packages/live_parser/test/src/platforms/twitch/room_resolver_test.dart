import 'package:live_parser/live_parser.dart';
import 'package:live_parser/src/platforms/twitch/gql.dart';
import 'package:live_parser/src/platforms/twitch/room_api.dart';
import 'package:live_parser/src/platforms/twitch/twitch_site.dart';
import 'package:test/test.dart';

import '../../../support/fake_twitch_api.dart';

void main() {
  late FakeTwitchApi api;

  setUp(() {
    api = FakeTwitchApi()
      ..useLiveResponse = twitchFixtureData('use_live.json')['user']
      ..tokenResponse = twitchFixtureData('playback_access_token.json')['streamPlaybackAccessToken']
      ..usherBody = twitchFixture('usher_master.m3u8');
  });

  TwitchClient clientFor() => TwitchClient(httpClient: api);

  group('输入归一', () {
    test('完整 URL / 大写 / @login 都归一为小写 login', () async {
      final resolver = TwitchRoomResolver(clientFor());
      for (final input in [
        'https://www.twitch.tv/fps_shaka',
        'https://www.twitch.tv/FPS_Shaka/',
        'twitch.tv/fps_shaka',
        '@FPS_shaka',
      ]) {
        final payload = await resolver.resolveRoom(
          RoomRequest(site: 'twitch', roomIdOrUrl: input),
        );
        expect(payload.roomId, 'fps_shaka', reason: input);
        expect(payload.sourceUrl, 'https://www.twitch.tv/fps_shaka');
      }
    });

    test('非 Twitch URL 直接失败', () async {
      final resolver = TwitchRoomResolver(clientFor());
      expect(
        resolver.resolveRoom(
          const RoomRequest(site: 'twitch', roomIdOrUrl: 'https://www.douyu.com/123'),
        ),
        throwsA(isA<ParserHttpException>()),
      );
    });
  });

  group('在播房间', () {
    test('多画质按分辨率降序,首档为原画', () async {
      final payload = await TwitchRoomResolver(clientFor()).resolveRoom(
        const RoomRequest(site: 'twitch', roomIdOrUrl: 'fps_shaka'),
      );

      expect(payload.isLive, isTrue);
      expect(payload.roomState, RoomState.live);
      expect(payload.anchorName, 'fps_shaka');
      expect(payload.title, 'SAVOGE RUST Day3');
      expect(payload.category, 'Rust');
      expect(payload.cid, '263490');
      expect(payload.source, 'live_parser/twitch');

      expect(payload.streams.map((s) => s.name).toList(), [
        '原画',
        '720p60',
        '480p',
        '360p',
        '160p',
      ]);
      expect(payload.streams.map((s) => s.rate).toList(), [1080, 720, 480, 360, 160]);
      expect(payload.availableQualities.map((q) => q.name), contains('原画'));
      expect(payload.playUrl, 'https://usher.example/v1/playlist/chunked.m3u8');
      for (final stream in payload.streams) {
        expect(stream.lines.single.format, 'hls');
        expect(stream.lines.single.headers['Referer'], 'https://www.twitch.tv/');
      }
    });

    test('封面/头像模板已填充实际尺寸', () async {
      final payload = await TwitchRoomResolver(clientFor()).resolveRoom(
        const RoomRequest(site: 'twitch', roomIdOrUrl: 'fps_shaka'),
      );
      expect(payload.cover, isNot(contains('{width}')));
      expect(payload.cover, contains('640x360'));
      expect(payload.avatar, contains('300x300'));
    });

    test('usher 请求对 token 做 URL 编码', () async {
      await TwitchRoomResolver(clientFor()).resolveRoom(
        const RoomRequest(site: 'twitch', roomIdOrUrl: 'fps_shaka'),
      );
      final usher = api.requests.firstWhere((uri) => uri.host == 'usher.ttvnw.net');
      expect(usher.path, '/api/channel/hls/fps_shaka.m3u8');
      expect(usher.queryParameters['sig'], isNotNull);
      expect(usher.query, isNot(contains('{')), reason: 'token 里的花括号必须被编码');
      expect(usher.queryParameters['token'], contains('channel'));
      expect(usher.queryParameters['client_id'], isNotEmpty);
    });

    test('GQL 返回 errors 时抛出 TwitchGqlException', () async {
      api.gqlErrors = true;
      expect(
        TwitchRoomResolver(clientFor()).resolveRoom(
          const RoomRequest(site: 'twitch', roomIdOrUrl: 'fps_shaka'),
        ),
        throwsA(isA<TwitchGqlException>()),
      );
    });

    test('主列表无可用画质时失败', () async {
      api.usherBody = '#EXTM3U\n';
      expect(
        TwitchRoomResolver(clientFor()).resolveRoom(
          const RoomRequest(site: 'twitch', roomIdOrUrl: 'fps_shaka'),
        ),
        throwsA(isA<ParserHttpException>()),
      );
    });
  });

  group('非在播状态', () {
    test('未开播:三态为 offline 且无线路', () async {
      api.useLiveResponse = twitchFixtureData('use_live_offline.json')['user'];
      final payload = await TwitchRoomResolver(clientFor()).resolveRoom(
        const RoomRequest(site: 'twitch', roomIdOrUrl: 'shroud'),
      );
      expect(payload.roomState, RoomState.offline);
      expect(payload.isLive, isFalse);
      expect(payload.streams, isEmpty);
      expect(payload.anchorName, 'shroud');
      expect(
        api.gqlOperations,
        isNot(contains('PlaybackAccessToken_Template')),
        reason: '未开播不再请求播放令牌',
      );
    });

    test('主播不存在:notFound 并带错误说明', () async {
      api.useLiveResponse = twitchFixtureData('use_live_missing.json')['user'];
      final payload = await TwitchRoomResolver(clientFor()).resolveRoom(
        const RoomRequest(site: 'twitch', roomIdOrUrl: 'nobody_zzz'),
      );
      expect(payload.roomState, RoomState.notFound);
      expect(payload.error, '主播不存在');
      expect(payload.streams, isEmpty);
    });
  });

  group('master m3u8 解析', () {
    test('丢弃 audio_only 并按分辨率降序', () {
      final streams = parseTwitchMasterPlaylist(twitchFixture('usher_master.m3u8'));
      expect(streams.length, 5);
      expect(streams.map((s) => s.rate).toList(), [1080, 720, 480, 360, 160]);
      expect(streams.any((s) => s.name.contains('audio_only')), isFalse);
    });

    test('source 档命名为原画', () {
      final streams = parseTwitchMasterPlaylist(twitchFixture('usher_master.m3u8'));
      expect(streams.first.name, '原画');
    });

    test('无 MEDIA 名称时按分辨率与帧率推导', () {
      const body = '''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=1000,RESOLUTION=1280x720,FRAME-RATE=60.000
https://example.com/720.m3u8
''';
      final streams = parseTwitchMasterPlaylist(body);
      expect(streams.single.name, '720p60');
      expect(streams.single.rate, 720);
    });
  });
}
