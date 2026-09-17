import 'package:live_parser/live_parser.dart';
import 'package:test/test.dart';

import '../../../support/fake_youtube_api.dart';

void main() {
  group('YouTube 输入归一', () {
    test('裸 id / youtu.be / watch / live 提取', () {
      expect(extractYoutubeVideoId('dQw4w9WgXcQ'), 'dQw4w9WgXcQ');
      expect(
        extractYoutubeVideoId('https://youtu.be/dQw4w9WgXcQ'),
        'dQw4w9WgXcQ',
      );
      expect(
        extractYoutubeVideoId(
          'https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=1',
        ),
        'dQw4w9WgXcQ',
      );
      expect(
        extractYoutubeVideoId('https://www.youtube.com/live/dQw4w9WgXcQ'),
        'dQw4w9WgXcQ',
      );
      expect(extractYoutubeVideoId('short'), isNull);
    });

    test('extractJsonObjectAfter 处理字符串内括号', () {
      const html =
          'var x = {"a":"}not end{","b":{"c":1}}; trailing';
      final json = extractJsonObjectAfter(html, 'var x = ');
      expect(json, isNotNull);
      expect(json!['a'], '}not end{');
      expect((json['b'] as Map)['c'], 1);
    });

    test('master playlist:同档合并与排序', () {
      const content = '#EXTM3U\n'
          '#EXT-X-STREAM-INF:BANDWIDTH=3000,RESOLUTION=1280x720,FRAME-RATE=30\n'
          'v1.m3u8\n'
          '#EXT-X-STREAM-INF:BANDWIDTH=1000,RESOLUTION=1280x720,FRAME-RATE=30\n'
          'v2.m3u8\n';
      final qualities = parseYoutubeMasterPlaylist(
        content,
        'https://x.test/master.m3u8',
      );
      expect(qualities, hasLength(1));
      expect(qualities.single.name, '720p');
      expect(
        qualities.single.lines.map((line) => line.url).toList(),
        ['https://x.test/v1.m3u8', 'https://x.test/v2.m3u8'],
      );
      expect(qualities.single.lines.first.headers, {
        'user-agent': kYoutubeUserAgent,
        'referer': 'https://www.youtube.com/',
      });
    });

    test('yt-dlp formats 归一:仅 HLS、同名去重、按高度降序', () {
      final extract = youtubeFixtureJson('dlp.json') as Map<String, dynamic>;
      final tiers = parseYoutubeDlpTiers(extract['formats']);
      expect(tiers.map((tier) => tier.label).toList(), ['1080p60', '720p']);
      expect(tiers.first.height, 1080);
      expect(tiers.first.fps, 60);
      final qualities = youtubeDlpQualities(tiers);
      expect(qualities.first.lines.single.url, 'https://x/1080p60.m3u8');
      expect(
        qualities.first.lines.single.headers['referer'],
        'https://www.youtube.com/',
        reason: 'dlp 主路线与页面链路带同一组播放头',
      );
    });

    test('竖屏 resolution 按短边取档名(1080x1920 -> 1080p)', () {
      final tiers = parseYoutubeDlpTiers([
        {
          'url': 'https://x/portrait.m3u8',
          'resolution': '1080x1920',
          'height': 1920,
          'fps': 30,
        },
      ]);
      expect(tiers.single.label, '1080p');
      expect(tiers.single.height, 1080);
    });
  });

  group('YouTube 房间解析', () {
    late FakeYoutubeApi fake;
    late SiteRegistration registration;

    setUp(() {
      fake = FakeYoutubeApi()
        ..watchHtml = youtubeFixture('watch_live.html')
        ..masterPlaylist = youtubeFixture('master.m3u8')
        ..variantPlaylist = youtubeFixture('variant.m3u8');
      // 单测禁止真的去 spawn yt-dlp:页面链路用例显式关闭 dlp。
      registration = buildYoutubeRegistration(
        httpClient: fake,
        dlpAvailableCheck: () async => false,
      );
    });

    test('页面链路:master 预校验 + 多档位', () async {
      final payload = await registration.resolver.resolveRoom(
        const RoomRequest(
          site: 'youtube',
          roomIdOrUrl: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        ),
      );

      expect(payload.roomState, RoomState.live);
      expect(payload.roomId, 'dQw4w9WgXcQ');
      expect(payload.title, '测试直播间');
      expect(payload.anchorName, '测试频道');
      expect(
        payload.cover,
        'https://i.ytimg.com/vi/dQw4w9WgXcQ/maxresdefault.jpg',
      );
      expect(payload.availableQualities.map((q) => q.name).toList(), [
        '自动',
        '1080p60',
        '720p',
      ]);
      expect(
        payload.playUrl,
        'https://manifest.googlevideo.com/api/manifest/hls_variant/live/master.m3u8',
      );
      expect(
        fake.requests.any(
          (request) => request.headers['Range'] == 'bytes=0-2048',
        ),
        isTrue,
        reason: '应做分片 Range 预检,避免交付 403 死地址',
      );

      // '自动' master 线路就是 playUrl,必须带 googlevideo 校验头
      final masterHeaders = payload.streams.first.lines.single.headers;
      expect(masterHeaders['user-agent'], kYoutubeUserAgent);
      expect(masterHeaders['referer'], 'https://www.youtube.com/');
    });

    test('dlp 主路线:优先使用 yt-dlp 档位并做首档预校验', () async {
      final dlpRegistration = buildYoutubeRegistration(
        httpClient: fake,
        dlpAvailableCheck: () async => true,
        dlpExtractor: (videoId) async => const YoutubeDlpExtract(
          tiers: [
            YoutubeDlpTier(
              label: '720p60',
              url:
                  'https://manifest.googlevideo.com/api/manifest/hls_variant/live/dlp-720.m3u8',
              height: 720,
              fps: 60,
            ),
          ],
        ),
      );

      final payload = await dlpRegistration.resolver.resolveRoom(
        const RoomRequest(
          site: 'youtube',
          roomIdOrUrl: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        ),
      );

      expect(payload.roomState, RoomState.live);
      expect(payload.availableQualities.map((q) => q.name).toList(), ['720p60']);
      expect(payload.playUrl, contains('dlp-720.m3u8'));
    });

    test('无 player/非直播返回 offline', () async {
      fake.watchHtml = '<html><body>no player</body></html>';
      final payload = await registration.resolver.resolveRoom(
        const RoomRequest(site: 'youtube', roomIdOrUrl: 'dQw4w9WgXcQ'),
      );
      expect(payload.roomState, RoomState.offline);
    });

    test('无法解析 URL 返回 notFound', () async {
      final payload = await registration.resolver.resolveRoom(
        const RoomRequest(site: 'youtube', roomIdOrUrl: 'not a url'),
      );
      expect(payload.roomState, RoomState.notFound);
      expect(payload.error, '无法解析 YouTube URL');
    });

    test('注册项:浏览/弹幕能力,无搜索', () {
      expect(registration.id, 'youtube');
      expect(registration.name, 'YouTube');
      expect(registration.resolver, isA<RoomResolver>());
      expect(registration.browse, isA<BrowseRepository>());
      expect(registration.danmaku, isA<DanmakuConnector>());
      expect(registration.capabilities.browse, isTrue);
      expect(registration.capabilities.danmaku, isTrue);
      expect(registration.capabilities.roomSearch, isFalse);
      expect(registration.search, isNull);
    });
  });
}
