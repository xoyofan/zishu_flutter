import 'package:live_parser/live_parser.dart';
import 'package:test/test.dart';

import '../../../support/fake_youtube_api.dart';

/// 统一站点出口:注册项(含 CachedRoomResolver 包装)装配进 [SiteRegistry]
/// 后,经 `registry.site('youtube')` 验证 LiveSite 适配层的 RoomRecord 映射。
///
/// 路线选择:页面链 fixture 全齐(watch_live.html + master/variant.m3u8),
/// 按既有 fixture 选页面链为可用路线;单测显式关闭 dlp,不伪造
/// dlp/yt-dlp 子进程。
LiveSite _liveSite(FakeYoutubeApi fake) {
  final registry = SiteRegistry()
    ..register(
      buildYoutubeRegistration(
        httpClient: fake,
        dlpAvailableCheck: () async => false,
      ),
    );
  return registry.site('youtube')!;
}

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
          liveStartAtSec: 1788911253,
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
      expect(
        payload.startedAt,
        DateTime.fromMillisecondsSinceEpoch(1788911253 * 1000),
      );
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

    test('注册项:未实现刷新,但带 CachedRoomResolver 装饰器时内省仍如实判 null', () {
      // 装饰器恒 is RoomSummaryRefresher(内层未实现时运行期抛
      // UnsupportedError),必须按 RefreshCapabilityProbe 上报真实能力。
      final resolver = registration.resolver;
      expect(resolver, isA<RoomSummaryRefresher>());
      expect(
        (resolver as RefreshCapabilityProbe).innerRefreshSupported,
        isFalse,
        reason: 'YoutubeRoomResolver 未实现刷新',
      );
    });
  });

  group('LiveSite 统一出口:registry.site(youtube).resolveRoom → RoomRecord', () {
    late FakeYoutubeApi fake;

    setUp(() {
      fake = FakeYoutubeApi()
        ..watchHtml = youtubeFixture('watch_live.html')
        ..masterPlaylist = youtubeFixture('master.m3u8')
        ..variantPlaylist = youtubeFixture('variant.m3u8');
    });

    test('在播:类型/身份/线路稳定段与 headers 透传;统计四项 null', () async {
      final room = await _liveSite(fake).resolveRoom(
        const RoomRequest(
          site: 'youtube',
          roomIdOrUrl: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        ),
      );

      expect(room, isA<RoomRecord>());
      expect(room.site, 'youtube');
      expect(room.roomId, 'dQw4w9WgXcQ');
      expect(
        room.sourceUrl,
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      );
      expect(room.roomState, RoomState.live);
      expect(room.isLive, isTrue);
      expect(room.title, '测试直播间');
      expect(room.anchorName, '测试频道');
      expect(
        room.cover,
        'https://i.ytimg.com/vi/dQw4w9WgXcQ/maxresdefault.jpg',
      );
      expect(room.cid, 'dQw4w9WgXcQ');
      expect(room.source, 'live_parser/youtube');
      expect(room.error, isNull);

      // 线路:锁定 fixture master.m3u8 真值的稳定 URL 段与播放头,
      // 防止适配层把线路换成别的非空值仍通过。
      expect(room.streams, hasLength(3));
      expect(room.streams.first.name, '自动');
      expect(
        room.playUrl,
        'https://manifest.googlevideo.com/api/manifest/hls_variant/live/'
        'master.m3u8',
        reason: '页面链主路线就是 watch 页 fixture 的 hlsManifestUrl',
      );
      expect(
        room.streams.skip(1).map((stream) => stream.name).toList(),
        ['1080p60', '720p'],
        reason: 'master.m3u8 fixture 的两个变体档位保留',
      );
      final headers = room.streams.first.preferredLine?.headers ?? {};
      expect(headers['user-agent'], kYoutubeUserAgent);
      expect(headers['referer'], 'https://www.youtube.com/');

      // 6sol 口径:RoomPayload 没有统计字段,详情出口统计必须为
      // null,不伪造 0/空串。
      expect(room.audience, isNull);
      expect(room.followers, isNull);
      expect(room.vip, isNull);
      expect(room.svip, isNull);
    });

    test('未开播:offline、无线路、缺字段 null、统计 null', () async {
      fake.watchHtml = '<html><body>no player</body></html>';

      final room = await _liveSite(fake).resolveRoom(
        const RoomRequest(site: 'youtube', roomIdOrUrl: 'dQw4w9WgXcQ'),
      );

      expect(room, isA<RoomRecord>());
      expect(room.site, 'youtube');
      expect(room.roomId, 'dQw4w9WgXcQ');
      expect(room.roomState, RoomState.offline);
      expect(room.isLive, isFalse);
      expect(
        room.title,
        isNull,
        reason: 'RoomPayload 空串经统一记录归一为 null',
      );
      expect(room.anchorName, isNull);
      expect(room.error, isNull);
      expect(room.streams, isEmpty);
      expect(room.playUrl, isEmpty);
      expect(room.audience, isNull);
      expect(room.followers, isNull);
      expect(room.vip, isNull);
      expect(room.svip, isNull);
    });

    test('无法解析 URL:notFound 语义、统计 null', () async {
      final room = await _liveSite(fake).resolveRoom(
        const RoomRequest(site: 'youtube', roomIdOrUrl: 'not a url'),
      );

      expect(room, isA<RoomRecord>());
      expect(room.roomState, RoomState.notFound);
      expect(room.error, '无法解析 YouTube URL');
      expect(
        room.title,
        '无法解析 YouTube URL',
        reason: '既有 payload 把诊断文案同时落在 title,原样透传',
      );
      expect(room.streams, isEmpty);
      expect(room.audience, isNull);
      expect(room.followers, isNull);
      expect(room.vip, isNull);
      expect(room.svip, isNull);
    });

    test('refresh 不可用:YouTube 无 RoomSummaryRefresher,refresher 为 null', () {
      // 契约:不支持的能力部件必须是 null(不是空占位);CachedRoomResolver
      // 装饰器恒 is RoomSummaryRefresher,靠 RefreshCapabilityProbe 如实上报
      // 内层未实现刷新。
      expect(_liveSite(fake).refresher, isNull);
    });
  });

  group('YouTube 恢复重解析(绕开 20s/60s 播放缓存)', () {
    late FakeYoutubeApi fake;
    late SiteRegistration registration;

    const request = RoomRequest(
      site: 'youtube',
      roomIdOrUrl: 'dQw4w9WgXcQ',
    );

    setUp(() {
      fake = FakeYoutubeApi()
        ..watchHtml = youtubeFixture('watch_live.html')
        ..masterPlaylist = youtubeFixture('master.m3u8')
        ..variantPlaylist = youtubeFixture('variant.m3u8');
      registration = buildYoutubeRegistration(
        httpClient: fake,
        dlpAvailableCheck: () async => false,
      );
    });

    test('普通连续解析 20s 内只请求一次;恢复重新拉页并返回新地址', () async {
      expect(
        registration.resolver,
        isA<RoomRecoveryResolver>(),
        reason: 'YouTube 内层自带播放缓存,必须实现恢复接口,否则恢复会复用旧线路',
      );
      final resolver = registration.resolver;
      final recovery = resolver as RoomRecoveryResolver;

      final first = await resolver.resolveRoom(request);
      expect(first.roomState, RoomState.live);
      final requestsAfterFirst = fake.requests.length;

      final second = await resolver.resolveRoom(request);
      expect(
        fake.requests.length,
        requestsAfterFirst,
        reason: '普通解析应命中 20s 短缓存,0 新请求(保留短缓存性能)',
      );
      expect(second.playUrl, first.playUrl);

      // 上游地址刷新:watch 页里的 manifest 换新链接(带 query 不改路由路径)。
      fake.watchHtml = fake.watchHtml!.replaceFirst(
        'live/master.m3u8',
        'live/master.m3u8?expire=9999',
      );

      final recovered = await recovery.recoverRoom(request);
      expect(
        fake.requests.length,
        greaterThan(requestsAfterFirst),
        reason: '恢复必须重新拉页获取地址,不能命中 20s 内层缓存',
      );
      expect(recovered.roomState, RoomState.live);
      expect(
        recovered.playUrl,
        contains('expire=9999'),
        reason: '恢复必须返回新地址,不得复用缓存里的旧线路',
      );
      expect(recovered.playUrl, isNot(first.playUrl));

      // 恢复后的新结果重新进入短缓存:后续普通解析不再发请求。
      final third = await resolver.resolveRoom(request);
      expect(third.playUrl, recovered.playUrl);
      expect(fake.requests.length, greaterThanOrEqualTo(requestsAfterFirst));
      final requestsAfterRecovery = fake.requests.length;
      final fourth = await resolver.resolveRoom(request);
      expect(fourth.playUrl, recovered.playUrl);
      expect(fake.requests.length, requestsAfterRecovery);
    });

    test('dlp 路线:普通解析 20s 内只提取一次,恢复再次提取并拿到新线路', () async {
      var dlpCalls = 0;
      final dlpRegistration = buildYoutubeRegistration(
        httpClient: fake,
        dlpAvailableCheck: () async => true,
        dlpExtractor: (videoId) async {
          dlpCalls++;
          return YoutubeDlpExtract(
            tiers: [
              YoutubeDlpTier(
                label: '720p60',
                // 指向可路由的 master(带 query 区分新旧),后台链校验可确定性通过。
                url:
                    'https://manifest.googlevideo.com/api/manifest/'
                    'hls_variant/live/master.m3u8?dlp=$dlpCalls',
                height: 720,
                fps: 60,
              ),
            ],
            liveStartAtSec: 1788911253,
          );
        },
      );
      final resolver = dlpRegistration.resolver;
      final recovery = resolver as RoomRecoveryResolver;

      final first = await resolver.resolveRoom(request);
      expect(first.roomState, RoomState.live);
      expect(first.playUrl, contains('dlp=1'));
      expect(dlpCalls, 1);

      final second = await resolver.resolveRoom(request);
      expect(dlpCalls, 1, reason: '20s 内普通解析命中缓存,不再跑 dlp');
      expect(second.playUrl, first.playUrl);

      final recovered = await recovery.recoverRoom(request);
      expect(dlpCalls, 2, reason: '恢复必须重新执行 dlp 提取,不能复用 60s dlp 缓存');
      expect(
        recovered.playUrl,
        contains('dlp=2'),
        reason: '恢复必须拿到新线路',
      );
    });

    test('无效 ID 恢复不崩溃,返回 notFound', () async {
      final recovery = registration.resolver as RoomRecoveryResolver;
      final payload = await recovery.recoverRoom(
        const RoomRequest(site: 'youtube', roomIdOrUrl: 'not a url'),
      );
      expect(payload.roomState, RoomState.notFound);
      expect(payload.error, '无法解析 YouTube URL');
    });
  });

  group('InnerTube ANDROID_VR 兜底(2026-09-22 实测修复)', () {
    test('必须下发 X-Goog-Visitor-Id,否则上游固定返回 LOGIN_REQUIRED', () async {
      // 真机实测:不带头 → status=LOGIN_REQUIRED(reason "Sign in to confirm you're not a bot")、
      // hlsManifestUrl 空;补上后曾出现 status=OK + 6 档 HLS + 分片 200。
      // 该头是必要条件(IP 未被挑战时可用),但上游会按 IP 状态重新发起挑战 ——
      // 因此本改动只是让兜底不再必然失败,不构成可靠主路径。
      // 此前 WEB 分支发了这个头,ANDROID_VR 分支漏发 —— 于是兜底形同虚设。
      final fake = FakeYoutubeApi()..playerResponse = {'streamingData': <String, Object?>{}};
      final client = YoutubeClient(httpClient: fake);
      final context = YoutubePageContext(
        innertubeContext: const {
          'client': {'clientName': 'WEB', 'visitorData': 'VISITOR_ABC_123'},
        },
        apiKey: 'TEST_KEY',
      );

      // 两个分支都拿不到 hls(WEB 已 SABR-only,ANDROID_VR 拿到空),但请求得发出去。
      final hls = await resolveYoutubeInnerTubeHls(client, context, 'vid12345678');
      expect(hls, isEmpty);

      final playerRequests = fake.requests
          .where((request) => request.url.path == '/youtubei/v1/player')
          .toList();
      expect(playerRequests, hasLength(2), reason: '先 WEB 再 ANDROID_VR 兜底');
      final fallback = playerRequests.last;
      expect(fallback.headers['X-Youtube-Client-Name'], '28');
      expect(
        fallback.headers['X-Goog-Visitor-Id'],
        'VISITOR_ABC_123',
        reason: 'ANDROID_VR 缺此头会被上游判 LOGIN_REQUIRED,兜底永远拿不到地址',
      );
      client.close();
    });
  });
}
