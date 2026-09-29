import 'package:live_parser/live_parser.dart';
import 'package:test/test.dart';

import '../../../support/fake_xhs_api.dart';

/// 统一站点出口:注册项(含 CachedRoomResolver 包装)装配进 [SiteRegistry]
/// 后,经 `registry.site('xhs')` 验证 LiveSite 适配层的 RoomRecord 映射。
LiveSite _liveSite(FakeXhsApi fake) {
  final registry = SiteRegistry()
    ..register(buildXhsRegistration(httpClient: fake));
  return registry.site('xhs')!;
}

void main() {
  late FakeXhsApi fake;
  late SiteRegistration registration;

  setUp(() {
    fake = FakeXhsApi()..roomPage = xhsFixture('room_live.html');
    registration = buildXhsRegistration(httpClient: fake);
  });

  group('小红书房间解析', () {
    test('在播:iOS UA 直抓页面,原画/高清两档 + pullConfig 多线路', () async {
      final payload = await registration.resolver.resolveRoom(
        const RoomRequest(
          site: 'xhs',
          roomIdOrUrl: 'https://www.xiaohongshu.com/livestream/1736648088123456789',
        ),
      );

      expect(payload.site, 'xhs');
      expect(payload.roomId, '1736648088123456789');
      expect(payload.sourceUrl, 'https://www.xiaohongshu.com/livestream/1736648088123456789');
      expect(payload.roomState, RoomState.live);
      expect(payload.anchorName, '小红主播');
      expect(payload.title, '今晚八点翻唱会');
      expect(payload.cover, 'https://sns-cover.xhscdn.com/cover1.jpg');
      expect(payload.avatar, 'https://sns-avatar.xhscdn.com/avatar1.jpg');

      // 直连页抓取不需要签名,用 iOS App UA。
      final pageRequest = fake.requests.last;
      expect(pageRequest.url.host, 'www.xiaohongshu.com');
      expect(pageRequest.headers['User-Agent'], startsWith('ios/'));

      // 画质两档:原画(原链)+ 高清(_hcv520 派生)。
      expect(
        payload.availableQualities.map((q) => q.name).toList(),
        ['原画', '高清'],
      );
      expect(payload.streams, hasLength(2));

      final original = payload.streams.first;
      expect(original.name, '原画');
      // h265 重复的 flv 直链按 URL 去重,仍为两条线路。
      expect(original.lines.map((line) => line.name).toList(), [
        '主线路·FLV',
        '华为线路·HLS',
      ]);
      expect(original.lines.map((line) => line.url).toList(), [
        'https://live-source-play.xhscdn.com/live/room1.flv',
        'https://live-source-play-hw.xhscdn.com/live/room1.m3u8',
      ]);
      expect(original.preferredLine?.format, 'hls');

      final hd = payload.streams.last;
      expect(hd.name, '高清');
      expect(hd.lines.map((line) => line.url).toList(), [
        'https://live-source-play.xhscdn.com/live/room1_hcv520.flv',
        'https://live-source-play-hw.xhscdn.com/live/room1_hcv520.m3u8',
      ]);
      expect(payload.playUrl, 'https://live-source-play-hw.xhscdn.com/live/room1.m3u8');
    });

    test('离线:roomId=0 回退入参,主播名走 deeplink 兜底并 URL 解码', () async {
      fake.roomPage = xhsFixture('room_offline.html');

      final payload = await registration.resolver.resolveRoom(
        const RoomRequest(site: 'xhs', roomIdOrUrl: '660200000000000010'),
      );

      expect(payload.roomState, RoomState.offline);
      expect(payload.roomId, '660200000000000010', reason: 'roomInfo.roomId=0 回退入参');
      expect(payload.anchorName, '离线主播', reason: 'hostInfo 缺失回退 deeplink host_nickname');
      expect(payload.title, '主播还没开播');
      expect(payload.error, '未开播');
      expect(payload.streams, isEmpty);
      expect(payload.availableQualities, isEmpty);
    });

    test('「回放」标题按离线处理:即使 liveStatus=success 且带 pullConfig', () async {
      fake.roomPage = xhsFixture('room_replay.html');

      final payload = await registration.resolver.resolveRoom(
        const RoomRequest(site: 'xhs', roomIdOrUrl: '1736648088123456001'),
      );

      expect(payload.roomState, RoomState.offline);
      expect(payload.error, '回放');
      expect(payload.anchorName, '回放机器');
      expect(payload.streams, isEmpty);
      expect(payload.availableQualities, isEmpty);
    });

    test('未找到直播间(pageStatus=error)→ notFound', () async {
      fake.roomPage = xhsFixture('room_missing.html');

      final payload = await registration.resolver.resolveRoom(
        const RoomRequest(site: 'xhs', roomIdOrUrl: '660300000000000020'),
      );

      expect(payload.roomState, RoomState.notFound);
      expect(payload.error, '未找到直播间');
      expect(payload.streams, isEmpty);
    });

    test('页面缺少 __INITIAL_STATE__ → notFound', () async {
      fake.roomPage = '<html><body>no state</body></html>';

      final payload = await registration.resolver.resolveRoom(
        const RoomRequest(site: 'xhs', roomIdOrUrl: '660300000000000021'),
      );

      expect(payload.roomState, RoomState.notFound);
      expect(payload.error, '未获取到房间数据');
    });

    test('xhslink 短链:302 跟随到 /livestream/ 后复用常规链路', () async {
      fake
        ..shortLinks['/x1'] =
            'https://www.xiaohongshu.com/livestream/1736648088123456789?from=share'
        ..roomPages['1736648088123456789'] = xhsFixture('room_live.html');

      final payload = await registration.resolver.resolveRoom(
        const RoomRequest(site: 'xhs', roomIdOrUrl: 'https://xhslink.com/x1'),
      );

      expect(payload.roomState, RoomState.live);
      expect(payload.roomId, '1736648088123456789');
      expect(fake.requests, hasLength(2));
      expect(fake.requests.first.url.host, endsWith('xhslink.com'));
      expect(fake.requests.last.url.path, '/livestream/1736648088123456789');
    });

    test('xhslink 短链落主播主页:只回主播名,按离线处理', () async {
      fake
        ..shortLinks['/u2'] =
            'https://www.xiaohongshu.com/user/profile/5ff0e6410000000001008a12'
        ..profilePage = '<html><title>@主页主播 的个人主页</title></html>';

      final payload = await registration.resolver.resolveRoom(
        const RoomRequest(site: 'xhs', roomIdOrUrl: 'xhslink.com/u2'),
      );

      expect(payload.roomState, RoomState.offline);
      expect(payload.anchorName, '主页主播');
      expect(payload.streams, isEmpty);
    });

    test('输入归一:纯数字 / 直链(含 query)/ 短链透传', () {
      expect(normalizeXhsRoomId('1736648088123456789'), '1736648088123456789');
      expect(
        normalizeXhsRoomId(
          'https://www.xiaohongshu.com/livestream/1736648088123456789?x=1',
        ),
        '1736648088123456789',
      );
      expect(
        normalizeXhsRoomId('https://xhslink.com/x1'),
        'https://xhslink.com/x1',
      );
    });
  });

  group('LiveSite 统一出口:registry.site(xhs).resolveRoom → RoomRecord', () {
    test('在播:线路/画质透传;详情出口统计为 null(RoomPayload 无观众字段)', () async {
      final room = await _liveSite(fake).resolveRoom(
        const RoomRequest(site: 'xhs', roomIdOrUrl: '1736648088123456789'),
      );

      expect(room, isA<RoomRecord>());
      expect(room.site, 'xhs');
      expect(room.roomState, RoomState.live);
      expect(room.isLive, isTrue);
      expect(room.title, '今晚八点翻唱会');
      expect(room.anchorName, '小红主播');
      expect(room.cover, 'https://sns-cover.xhscdn.com/cover1.jpg');
      expect(room.sourceUrl, 'https://www.xiaohongshu.com/livestream/1736648088123456789');
      expect(room.cid, '1736648088123456789');
      expect(room.streams, hasLength(2));
      expect(room.playUrl, 'https://live-source-play-hw.xhscdn.com/live/room1.m3u8');
      expect(room.audience, isNull, reason: '6sol 口径:详情出口统计必须为 null');
    });

    test('refresher:轻量刷新只回元信息;观众数取上游格式化字符串', () async {
      final site = _liveSite(fake);

      final fresh = await site.refresher!.refreshRoomSummary(
        const RoomRequest(site: 'xhs', roomIdOrUrl: '1736648088123456789'),
      );
      expect(fresh.roomState, RoomState.live);
      expect(fresh.audience, '1万+', reason: 'displayViewerCount 原样保留');
      expect(fresh.title, '今晚八点翻唱会');
      expect(fresh.anchorName, '小红主播');
      expect(fresh.streams, isEmpty, reason: '轻量刷新不构造播放线路');

      fake.roomPage = xhsFixture('room_offline.html');
      final offline = await site.refresher!.refreshRoomSummary(
        const RoomRequest(site: 'xhs', roomIdOrUrl: '660200000000000010'),
      );
      expect(offline.roomState, RoomState.offline);
      expect(offline.audience, isNull);
    });

    test('refresher:房间不存在抛异常,不返回伪造空记录', () async {
      fake.roomPage = xhsFixture('room_missing.html');

      await expectLater(
        _liveSite(fake).refresher!.refreshRoomSummary(
          const RoomRequest(site: 'xhs', roomIdOrUrl: '660300000000000020'),
        ),
        throwsA(isA<ParserHttpException>()),
      );
    });
  });

  test('小红书注册项:浏览开启、搜索/弹幕不暴露、声明需要 Cookie', () {
    expect(registration.id, 'xhs');
    expect(registration.name, '小红书');
    expect(registration.capabilities.browse, isTrue);
    expect(registration.capabilities.roomSearch, isFalse);
    expect(registration.capabilities.anchorSearch, isFalse);
    expect(registration.capabilities.danmaku, isFalse);
    expect(registration.capabilities.multiQuality, isTrue);
    expect(registration.capabilities.multiLine, isTrue);
    expect(registration.capabilities.requiresCookie, isTrue);
    expect(registration.browse, isA<BrowseRepository>());
    expect(registration.search, isNull);
    expect(registration.danmaku, isNull);

    final registry = SiteRegistry()
      ..register(buildXhsRegistration(httpClient: fake));
    final site = registry.site('xhs')!;
    expect(site.refresher, isNotNull, reason: '内层实现 RoomSummaryRefresher');
    expect(site.recovery, isNotNull, reason: '短缓存包装实现恢复');
    expect(site.search, isNull);
    expect(site.danmaku, isNull);
  });
}
