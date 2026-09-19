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
    test('未指定清晰度:默认 480p 高清单档,其余档空线路占位', () async {
      final payload = await TwitchRoomResolver(clientFor()).resolveRoom(
        const RoomRequest(site: 'twitch', roomIdOrUrl: 'fps_shaka'),
      );

      expect(payload.isLive, isTrue);
      expect(payload.roomState, RoomState.live);
      expect(payload.anchorName, 'fps_shaka');
      expect(payload.title, 'SAVOGE RUST Day3');
      expect(payload.category, '失控进化-RUST', reason: '详情分类经 remap 表中文化');
      expect(payload.cid, '263490');
      expect(payload.source, 'live_parser/twitch');

      // 单档收敛(对齐 web 6b4983e):进房只下发默认高清档的 media playlist。
      expect(payload.streams, hasLength(5), reason: '其余档位空占位,chips 仍全档列出');
      expect(payload.streams.first.name, '480p');
      expect(payload.streams.first.lines.single.url,
          'https://usher.example/v1/playlist/480p30.m3u8');
      expect(
        payload.streams.skip(1).every((stream) => stream.lines.isEmpty),
        isTrue,
        reason: '未选中的档位不预取线路',
      );
      expect(payload.availableQualities.map((q) => q.name).toList(), [
        '原画',
        '720p60',
        '480p',
        '360p',
        '160p',
      ]);
      expect(payload.playUrl, 'https://usher.example/v1/playlist/480p30.m3u8');
      expect(payload.streams.first.lines.single.format, 'hls');
      expect(
        payload.streams.first.lines.single.headers['Referer'],
        'https://www.twitch.tv/',
      );
    });

    test('指定偏好档:只取该档,其余档空占位', () async {
      final payload = await TwitchRoomResolver(clientFor()).resolveRoom(
        const RoomRequest(site: 'twitch', roomIdOrUrl: 'fps_shaka', preferredQuality: '原画'),
      );

      expect(payload.streams.first.name, '原画');
      expect(payload.streams.first.rate, 1080);
      expect(
        payload.streams.first.lines.single.url,
        'https://usher.example/v1/playlist/chunked.m3u8',
      );
      expect(
        payload.streams.skip(1).every((stream) => stream.lines.isEmpty),
        isTrue,
      );
      expect(payload.availableQualities.map((q) => q.name), contains('原画'));
    });

    test('偏好/默认档都不在主列表中:回退最高档', () async {
      // 仅留 720p60 及以下:480p 名仍在;改成全部无 480p 的列表。
      api.usherBody = '''
#EXTM3U
#EXT-X-MEDIA:TYPE=VIDEO,GROUP-ID="chunked",NAME="1080p60 (source)",AUTOSELECT=YES,DEFAULT=YES
#EXT-X-STREAM-INF:BANDWIDTH=6844122,RESOLUTION=1920x1080,VIDEO="chunked",FRAME-RATE=60.000
https://usher.example/v1/playlist/chunked.m3u8
#EXT-X-MEDIA:TYPE=VIDEO,GROUP-ID="720p60",NAME="720p60",AUTOSELECT=YES,DEFAULT=YES
#EXT-X-STREAM-INF:BANDWIDTH=3422999,RESOLUTION=1280x720,VIDEO="720p60",FRAME-RATE=60.000
https://usher.example/v1/playlist/720p60.m3u8
''';
      final payload = await TwitchRoomResolver(clientFor()).resolveRoom(
        const RoomRequest(site: 'twitch', roomIdOrUrl: 'fps_shaka'),
      );

      expect(payload.streams.first.name, '原画', reason: '无 480p 时回退最高档');
      expect(payload.streams.first.lines, isNotEmpty);
    });

    test('不同偏好档解析互不命中 20s 缓存(切档拿得到新档线路)', () async {
      final resolver = TwitchRoomResolver(clientFor());
      final first = await resolver.resolveRoom(
        const RoomRequest(site: 'twitch', roomIdOrUrl: 'fps_shaka'),
      );
      final second = await resolver.resolveRoom(
        const RoomRequest(site: 'twitch', roomIdOrUrl: 'fps_shaka', preferredQuality: '720p60'),
      );

      expect(first.streams.first.name, '480p');
      expect(second.streams.first.name, '720p60');
      expect(
        second.streams.first.lines.single.url,
        'https://usher.example/v1/playlist/720p60.m3u8',
        reason: '内部缓存键须含偏好档,否则切档命中上一档 payload',
      );
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
      // 元数据与 token 并行(直播房省一个 RTT);离线房多发一次 token 请求,
      // 其结果被丢弃且失败不阻塞离线资料返回。
      expect(
        api.gqlOperations,
        contains('PlaybackAccessToken_Template'),
        reason: '并行取 token;离线判定不依赖 token 结果',
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

  group('状态刷新(RoomSummaryRefresher)', () {
    test('在播:回填标题/分类/封面与观看数文案,roomId 归一为 login', () async {
      final summary = await TwitchRoomResolver(clientFor()).refreshRoomSummary(
        const RoomRequest(site: 'twitch', roomIdOrUrl: 'https://www.twitch.tv/FPS_Shaka'),
      );
      expect(summary.site, 'twitch');
      expect(summary.roomId, 'fps_shaka');
      expect(summary.anchorName, 'fps_shaka');
      expect(summary.title, 'SAVOGE RUST Day3');
      expect(summary.category, '失控进化-RUST');
      expect(summary.cid, '263490');
      expect(summary.online, '2.3万', reason: 'viewersCount 22942 过万显示 X.X万');
      expect(summary.cover, isNotEmpty);
    });

    test('未开播:online 必须为空串(宿主以 online 非空为在播判据)', () async {
      api.useLiveResponse = twitchFixtureData('use_live_offline.json')['user'];
      final summary = await TwitchRoomResolver(clientFor()).refreshRoomSummary(
        const RoomRequest(site: 'twitch', roomIdOrUrl: 'shroud'),
      );
      expect(summary.online, isEmpty);
      expect(summary.anchorName, 'shroud');
      expect(summary.title, isEmpty);
    });

    test('主播不存在:抛异常,不返回伪造资料', () async {
      api.useLiveResponse = twitchFixtureData('use_live_missing.json')['user'];
      expect(
        TwitchRoomResolver(clientFor()).refreshRoomSummary(
          const RoomRequest(site: 'twitch', roomIdOrUrl: 'nobody_zzz'),
        ),
        throwsA(isA<ParserHttpException>()),
      );
    });

    test('刷新不触发取流调用(轻查询契约)', () async {
      await TwitchRoomResolver(clientFor()).refreshRoomSummary(
        const RoomRequest(site: 'twitch', roomIdOrUrl: 'fps_shaka'),
      );
      expect(api.gqlOperations, ['UseLive'], reason: '只打元信息查询');
      expect(api.requests.any((u) => u.host == 'usher.ttvnw.net'), isFalse);
    });

    test('能力经 CachedRoomResolver 透传,注册表出口可探测', () async {
      final registration = buildTwitchRegistration(client: clientFor());
      expect(registration.resolver, isA<RoomSummaryRefresher>());
      final summary = await (registration.resolver as RoomSummaryRefresher)
          .refreshRoomSummary(
        const RoomRequest(site: 'twitch', roomIdOrUrl: 'fps_shaka'),
      );
      expect(summary.online, '2.3万');
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
