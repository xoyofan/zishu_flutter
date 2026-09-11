import 'package:live_parser/live_parser.dart';
import 'package:test/test.dart';

import '../../../support/fake_yy_api.dart';

void main() {
  group('YY 房间解析', () {
    test('在播：详情 + stream-manager 多清晰度/多线路', () async {
      final fake = FakeYyApi()
        ..detailResponse = yyFixture('detail_live.json')
        ..streamResponse = yyFixture('stream_live.json');
      final registration = buildYyRegistration(httpClient: fake);

      final payload = await registration.resolver.resolveRoom(
        const RoomRequest(site: 'yy', roomIdOrUrl: 'https://www.yy.com/1414787909/'),
      );

      expect(payload.site, 'yy');
      expect(payload.roomId, '1414787909');
      expect(payload.sourceUrl, 'https://www.yy.com/1414787909');
      expect(payload.roomState, RoomState.live);
      expect(payload.anchorName, 'YY主播');
      expect(payload.title, '测试直播间');
      expect(payload.category, 'other');
      expect(payload.cid, '1414787909');
      expect(payload.cover, 'https://img.yy.com/cover.jpg');
      expect(payload.avatar, 'https://img.yy.com/avatar.jpg');
      expect(payload.availableQualities.map((q) => (q.name, q.rate)).toList(), [
        ('蓝光', 5),
        ('高清', 2),
        ('流畅', 1),
      ]);
      expect(payload.streams, hasLength(3));
      expect(payload.streams.first.lines.map((line) => (line.format, line.url)).toList(), [
        ('hls', 'https://stream.yy.com/blue.m3u8'),
        ('flv', 'https://stream.yy.com/blue.flv'),
      ]);
      expect(payload.playUrl, 'https://stream.yy.com/blue.m3u8');

      final streamRequest = fake.requests.firstWhere(
        (request) => request.url.host == 'stream-manager.yy.com',
      );
      expect(streamRequest.method, 'POST');
      expect(streamRequest.url.queryParameters['cid'], '1414787909');
      expect(streamRequest.url.queryParameters['sid'], '1414787909');
      expect(
        streamRequest.headers.entries.any(
          (entry) => entry.key.toLowerCase() == 'content-type' &&
              entry.value.toLowerCase().startsWith('text/plain'),
        ),
        isTrue,
        reason: 'YY stream-manager 要求 text/plain Content-Type',
      );
      final body = streamRequest.body;
      expect(body, contains('"gear":1'));
    });

    test('偏好档懒取流:只取该档,其余档空线路占位', () async {
      final fake = FakeYyApi()
        ..detailResponse = yyFixture('detail_live.json')
        ..streamResponse = yyFixture('stream_live.json');
      final registration = buildYyRegistration(httpClient: fake);

      final payload = await registration.resolver.resolveRoom(
        const RoomRequest(site: 'yy', roomIdOrUrl: '1414787909', preferredQuality: '高清'),
      );

      // 探测固定 gear=1,偏好 gear=2 再取一次,其余档位不再请求。
      expect(fake.streamGearCalls, {1: 1, 2: 1});
      expect(payload.roomState, RoomState.live);
      expect(payload.streams.first.name, '高清');
      expect(payload.streams.first.lines, isNotEmpty);
      expect(payload.playUrl, isNotEmpty);
      expect(payload.streams.skip(1).every((s) => s.lines.isEmpty), isTrue);
      expect(
        payload.availableQualities.map((q) => q.name).toList(),
        ['蓝光', '高清', '流畅'],
        reason: 'chips 保持平台原顺序',
      );
    });

    test('偏好档懒取流:命中 gear=1 时复用探测响应', () async {
      final fake = FakeYyApi()
        ..detailResponse = yyFixture('detail_live.json')
        ..streamResponse = yyFixture('stream_live.json');
      final registration = buildYyRegistration(httpClient: fake);

      final payload = await registration.resolver.resolveRoom(
        const RoomRequest(site: 'yy', roomIdOrUrl: '1414787909', preferredQuality: '流畅'),
      );

      expect(fake.streamGearCalls, {1: 1}, reason: 'gear=1 的探测响应直接复用为档位线路');
      expect(payload.streams.first.name, '流畅');
      expect(payload.streams.first.lines, isNotEmpty);
    });

    test('离线：detail data=null，返回 offline 且无线路', () async {
      final fake = FakeYyApi()..detailResponse = yyFixture('detail_offline.json');
      final registration = buildYyRegistration(httpClient: fake);

      final payload = await registration.resolver.resolveRoom(
        const RoomRequest(site: 'yy', roomIdOrUrl: '547800'),
      );

      expect(payload.roomState, RoomState.offline);
      expect(payload.isLive, isFalse);
      expect(payload.title, isEmpty);
      expect(payload.streams, isEmpty);
      expect(payload.availableQualities, isEmpty);
      expect(fake.requests, hasLength(1));
    });

    test('不存在：非零 resultCode 返回 notFound', () async {
      final fake = FakeYyApi()..detailResponse = yyFixture('detail_missing.json');
      final registration = buildYyRegistration(httpClient: fake);

      final payload = await registration.resolver.resolveRoom(
        const RoomRequest(site: 'yy', roomIdOrUrl: '999999'),
      );

      expect(payload.roomState, RoomState.notFound);
      expect(payload.error, '房间不存在');
      expect(payload.streams, isEmpty);
    });

    test('stream-manager 无流时回退移动 HLS', () async {
      final fake = FakeYyApi()
        ..detailResponse = yyFixture('detail_live.json')
        ..streamResponse = yyFixture('stream_empty.json')
        ..mobileHlsByRate['1200'] = yyFixture('mobile_hls_1200.json')
        ..mobileHlsByRate['4000'] = yyFixture('mobile_hls_4000.json');
      final registration = buildYyRegistration(httpClient: fake);

      final payload = await registration.resolver.resolveRoom(
        const RoomRequest(site: 'yy', roomIdOrUrl: '1414787909'),
      );

      expect(payload.roomState, RoomState.live);
      expect(payload.availableQualities.map((q) => q.name).toList(), ['流畅', '高清']);
      expect(payload.streams.map((stream) => stream.name).toList(), ['流畅', '高清']);
      expect(payload.streams[0].preferredLine?.url, 'https://mobile.yy.com/test-1200.m3u8');
      expect(payload.streams[1].preferredLine?.url, 'https://mobile.yy.com/test-4000.m3u8');
      expect(payload.streams.every((stream) => stream.lines.single.format == 'hls'), isTrue);
    });

    test('全部取流失败不伪报在播', () async {
      final fake = FakeYyApi()
        ..detailResponse = yyFixture('detail_live.json')
        ..streamResponse = yyFixture('stream_empty.json')
        ..mobileHlsByRate['1200'] = yyFixture('mobile_hls_empty.json')
        ..mobileHlsByRate['4000'] = yyFixture('mobile_hls_empty.json');
      final registration = buildYyRegistration(httpClient: fake);

      final payload = await registration.resolver.resolveRoom(
        const RoomRequest(site: 'yy', roomIdOrUrl: '1414787909'),
      );

      expect(payload.roomState, RoomState.offline);
      expect(payload.streams, isEmpty);
    });
  });

  test('YY 注册项声明浏览、搜索、多清晰度和多线路，无弹幕', () {
    final registration = buildYyRegistration(httpClient: FakeYyApi());

    expect(registration.id, 'yy');
    expect(registration.name, 'YY');
    expect(registration.resolver, isA<RoomResolver>());
    expect(registration.browse, isA<BrowseRepository>());
    expect(registration.search, isA<SearchRepository>());
    expect(registration.capabilities.browse, isTrue);
    expect(registration.capabilities.roomSearch, isTrue);
    expect(registration.capabilities.anchorSearch, isTrue);
    expect(registration.capabilities.multiQuality, isTrue);
    expect(registration.capabilities.multiLine, isTrue);
    expect(registration.capabilities.danmaku, isFalse);
    expect(registration.danmaku, isNull);
  });
}
