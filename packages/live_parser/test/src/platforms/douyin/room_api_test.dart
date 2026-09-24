import 'package:live_parser/live_parser.dart';
import 'package:test/test.dart';

import '../../../support/fake_douyin_api.dart';

/// 统一站点出口:注册项(含 CachedRoomResolver 包装)装配进 [SiteRegistry]
/// 后,经 `registry.site('douyin')` 验证 LiveSite 适配层的 RoomRecord 映射。
LiveSite _liveSite(FakeDouyinApi fake) {
  final registry = SiteRegistry()
    ..register(buildDouyinRegistration(httpClient: fake));
  return registry.site('douyin')!;
}

void main() {
  late FakeDouyinApi fake;
  late SiteRegistration registration;

  setUp(() {
    fake = FakeDouyinApi()
      ..enterResponse = douyinFixture('enter_live.json')
      ..roomPageHtml = douyinHtmlFixture('room_page.html');
    registration = buildDouyinRegistration(httpClient: fake);
  });

  group('抖音房间解析', () {
    test('enter 在播:多画质/线路,HLS 优先,分类与头像归一', () async {
      final payload = await registration.resolver.resolveRoom(
        const RoomRequest(site: 'douyin', roomIdOrUrl: 'https://live.douyin.com/123456'),
      );

      expect(payload.site, 'douyin');
      expect(payload.roomId, '123456');
      expect(payload.roomState, RoomState.live);
      expect(payload.anchorName, '测试主播');
      expect(payload.title, '测试直播间');
      expect(payload.category, '王者荣耀');
      expect(payload.cover, 'https://p3.douyinpic.com/cover.jpg');
      expect(payload.avatar, 'https://p3.douyinpic.com/avatar.jpg');
      expect(payload.availableQualities.map((q) => q.name).toList(), ['原画', '超清']);
      expect(payload.streams, hasLength(2));
      expect(payload.playUrl, 'https://pull-hls.douyin.com/origin.m3u8');
      final origin = payload.streams.first;
      expect(origin.lines.map((line) => line.format).toList(), ['hls', 'flv']);
      expect(
        origin.lines.first.headers['Referer'],
        'https://live.douyin.com/',
      );
    });

    test('离线:status=4 返回 offline 且无线路', () async {
      fake.enterResponse = douyinFixture('enter_offline.json');

      final payload = await registration.resolver.resolveRoom(
        const RoomRequest(site: 'douyin', roomIdOrUrl: '123456'),
      );

      expect(payload.roomState, RoomState.offline);
      expect(payload.streams, isEmpty);
    });

    test('enter 失败回退房间页:解析转义 JSON 与 URL 反转义', () async {
      fake.enterResponse = const <String, Object?>{};

      final payload = await registration.resolver.resolveRoom(
        const RoomRequest(site: 'douyin', roomIdOrUrl: '123456'),
      );

      expect(payload.roomState, RoomState.live);
      expect(payload.title, '页面房间标题');
      expect(payload.anchorName, '页面主播');
      expect(payload.category, '和平精英');
      expect(
        payload.playUrl,
        'https://pull-hls.douyin.com/origin.m3u8',
      );
      final flvLine = payload.streams.first.lines
          .firstWhere((line) => line.format == 'flv');
      expect(
        flvLine.url,
        'https://pull-flv.douyin.com/origin.flv?x=1&y=2',
        reason: '\\u0026 应还原为 &',
      );
    });
  });

  group('LiveSite 统一出口:registry.site(douyin).resolveRoom → RoomRecord', () {
    test('在播:类型/身份/线路稳定段与 headers 透传;统计字段为 null', () async {
      final fake = FakeDouyinApi()
        ..enterResponse = douyinFixture('enter_live.json')
        ..roomPageHtml = douyinHtmlFixture('room_page.html');

      final room = await _liveSite(fake).resolveRoom(
        const RoomRequest(
          site: 'douyin',
          roomIdOrUrl: 'https://live.douyin.com/123456',
        ),
      );

      expect(room, isA<RoomRecord>());
      expect(room.site, 'douyin');
      expect(room.roomId, '123456');
      expect(room.sourceUrl, 'https://live.douyin.com/123456');
      expect(room.roomState, RoomState.live);
      expect(room.isLive, isTrue);
      expect(room.title, '测试直播间');
      expect(room.anchorName, '测试主播');
      expect(room.category, '王者荣耀');
      expect(room.cover, 'https://p3.douyinpic.com/cover.jpg');
      expect(room.avatar, 'https://p3.douyinpic.com/avatar.jpg');

      // 线路与播放请求头经统一记录透传(CDN 防盗链 Referer)。
      expect(room.streams, isNotEmpty);
      final origin = room.streams.first;
      expect(origin.name, '原画');
      // P2:锁定既有 fixture enter_live.json 真值的稳定 URL,
      // 防止适配层把线路整体换成别的非空值仍通过。
      expect(
        origin.lines.map((line) => (line.format, line.url)).toList(),
        [
          ('hls', 'https://pull-hls.douyin.com/origin.m3u8'),
          ('flv', 'https://pull-flv.douyin.com/origin.flv'),
        ],
      );
      expect(origin.lines.first.headers['Referer'], 'https://live.douyin.com/');
      expect(room.playUrl, 'https://pull-hls.douyin.com/origin.m3u8');
      expect(room.playUrl, origin.preferredLine?.url);

      // 6sol 口径:RoomPayload 没有统计字段,详情出口统计必须为
      // null,不伪造 0/空串。
      expect(room.audience, isNull);
      expect(room.followers, isNull);
      expect(room.vip, isNull);
      expect(room.svip, isNull);
    });

    test('未开播:status=4 → offline、无线路、统计 null,资料保留', () async {
      final fake = FakeDouyinApi()..enterResponse = douyinFixture('enter_offline.json');

      final room = await _liveSite(fake).resolveRoom(
        const RoomRequest(site: 'douyin', roomIdOrUrl: '123456'),
      );

      expect(room, isA<RoomRecord>());
      expect(room.roomState, RoomState.offline);
      expect(room.isLive, isFalse);
      expect(room.title, '测试直播间');
      expect(room.anchorName, '测试主播');
      expect(room.streams, isEmpty);
      expect(room.availableQualities, isEmpty);
      expect(room.playUrl, isEmpty);
      expect(room.audience, isNull);
      expect(room.followers, isNull);
      expect(room.vip, isNull);
      expect(room.svip, isNull);
    });
  });

  test('抖音注册项声明浏览/搜索/弹幕与多线路', () {
    expect(registration.id, 'douyin');
    expect(registration.name, '抖音');
    expect(registration.capabilities.browse, isTrue);
    expect(registration.capabilities.roomSearch, isTrue);
    expect(registration.capabilities.danmaku, isTrue);
    expect(registration.capabilities.multiQuality, isTrue);
    expect(registration.capabilities.multiLine, isTrue);
  });

  group('抖音输入归一', () {
    test('裸 id / 直播 URL / 分享 URL', () {
      expect(normalizeDouyinRoomId('123456'), '123456');
      expect(
        normalizeDouyinRoomId('https://live.douyin.com/123456?foo=1'),
        '123456',
      );
      expect(normalizeDouyinRoomId('live.douyin.com/abcDEF123'), 'abcDEF123');
    });
  });
}
