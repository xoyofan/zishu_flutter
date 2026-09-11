import 'package:live_parser/live_parser.dart';
import 'package:test/test.dart';

import '../../../support/fake_douyin_api.dart';

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
