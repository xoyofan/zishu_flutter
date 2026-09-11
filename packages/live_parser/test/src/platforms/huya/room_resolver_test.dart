import 'dart:convert';
import 'dart:io';

import 'package:live_parser/live_parser.dart';
import 'package:live_parser/src/platforms/huya/huya_site.dart';
import 'package:test/test.dart';

import '../../../support/fake_huya_api.dart';

RoomRequest _request(String idOrUrl) => RoomRequest(site: 'huya', roomIdOrUrl: idOrUrl);

String _fixture(String name) => File('test/fixtures/huya/$name').readAsStringSync();

Object? _jsonFixture(String name) => jsonDecode(_fixture(name));

class HuyaHarness {
  HuyaHarness() {
    fake = FakeHuyaApi()
      ..profileRoomResponse = _jsonFixture('profile_room_live.json')
      ..gameListResponse = _jsonFixture('game_list.json')
      ..liveListResponse = _jsonFixture('live_list.json')
      ..searchResponse = _jsonFixture('search.json');
    registration = buildHuyaRegistration(httpClient: fake);
  }

  late FakeHuyaApi fake;
  late SiteRegistration registration;

  // 注册表出口套了 CachedRoomResolver(结果 60s),这里直接测平台解析器本体。
  HuyaRoomResolver get resolver =>
      HuyaRoomResolver(HuyaClient(httpClient: fake));

  void loadLiveRoom() {
    fake.webRoomHtml = _fixture('room_live.html');
  }
}

void main() {
  group('虎牙房间解析', () {
    test('在播:多 CDN 多画质 HLS/FLV 线路', () async {
      final harness = HuyaHarness()..loadLiveRoom();
      final payload = await harness.resolver.resolveRoom(_request('9527'));

      expect(payload.roomState, RoomState.live);
      expect(payload.isLive, isTrue);
      expect(payload.site, 'huya');
      expect(payload.roomId, '9527');
      expect(payload.sourceUrl, 'https://www.huya.com/9527');
      expect(payload.anchorName, '虎牙主播');
      expect(payload.title, '虎牙测试房间');
      expect(payload.category, '英雄联盟');
      expect(payload.cid, '1');
      expect(payload.avatar, 'https://huyaimg.msstatic.com/avatar.jpg');
      expect(payload.source, 'live_parser/huya');

      // 画质:vMultiStreamInfo 原序原名
      expect(
        payload.availableQualities.map((q) => (q.name, q.rate)).toList(),
        [('蓝光8M', 0), ('超清', 2000)],
      );

      // 每档:2 条 CDN 线路 × (HLS + FLV)
      expect(payload.streams, hasLength(2));
      final blueRay = payload.streams[0];
      expect(blueRay.name, '蓝光8M');
      expect(blueRay.lines.map((l) => (l.name, l.format)).toList(), [
        ('线路1 HLS', 'hls'),
        ('线路1 FLV', 'flv'),
        ('线路2 HLS', 'hls'),
        ('线路2 FLV', 'flv'),
      ]);

      // 签名地址:重新生成 wsSecret,ratio=0 时无 ratio 值
      final hlsUrl = blueRay.lines.first.url;
      expect(hlsUrl, startsWith('https://alhls.huya.com/src/9527-2650134-'));
      expect(hlsUrl, contains('.m3u8?wsSecret='));
      expect(hlsUrl, matches(RegExp(r'wsSecret=[0-9a-f]{32}')));
      expect(hlsUrl, endsWith('&ratio='));
      expect(hlsUrl, contains('ctype=huya_webh5'));

      final hdFlv = payload.streams[1].lines[1];
      expect(hdFlv.format, 'flv');
      expect(hdFlv.url, contains('&ratio=2000'));

      expect(payload.playUrl, payload.streams.first.preferredLine?.url);
      final restored = RoomPayload.fromJson(payload.toJson());
      expect(restored.toJson(), equals(payload.toJson()));
    });

    test('主播别名地址回源换数字房间号', () async {
      final harness = HuyaHarness()
        ..loadLiveRoom()
        ..fake.aliasPageHtml = _fixture('alias.html');
      final payload = await harness.resolver.resolveRoom(_request('https://www.huya.com/someanchor'));
      expect(payload.roomId, '9527');
      expect(
        harness.fake.requests.any((r) => r.url.contains('www.huya.com/someanchor')),
        isTrue,
        reason: '别名页需以小程序 UA 回源',
      );
    });

    test('页面无流但 profileRoom 在播:app API 回退单线路并替换 ctype/fs', () async {
      final harness = HuyaHarness()
        ..fake.webRoomHtml = _fixture('room_offline.html');
      final payload = await harness.resolver.resolveRoom(_request('9527'));

      expect(payload.roomState, RoomState.live);
      expect(payload.streams, hasLength(1));
      final only = payload.streams.single;
      expect(only.name, '默认');
      final flv = only.lines.firstWhere((l) => l.format == 'flv');
      expect(flv.url, startsWith('https://txflv.huya.com/src/'));
      expect(flv.url, contains('ctype=huya_webh5'), reason: 'TX 线路 ctype=tars_mp 需替换');
      expect(flv.url, contains('fs=bgct'), reason: 'TX 线路 fs=bhct 需替换');
      expect(only.lines.any((l) => l.format == 'hls'), isTrue);
    });
  });

  group('三态', () {
    test('未开播:offline 无线路', () async {
      final harness = HuyaHarness()
        ..fake.webRoomHtml = _fixture('room_offline.html')
        ..fake.profileRoomResponse = _jsonFixture('profile_room_offline.json');
      final payload = await harness.resolver.resolveRoom(_request('9527'));

      expect(payload.roomState, RoomState.offline);
      expect(payload.isLive, isFalse);
      expect(payload.streams, isEmpty);
      expect(payload.availableQualities, isEmpty);
      expect(payload.anchorName, '下播主播');
    });

    test('房间不存在(页面 404 + profile 无数据):notFound', () async {
      final harness = HuyaHarness()
        ..fake.webRoomHtml = '404'
        ..fake.profileRoomResponse = _jsonFixture('profile_room_missing.json');
      final payload = await harness.resolver.resolveRoom(_request('999999'));

      expect(payload.roomState, RoomState.notFound);
      expect(payload.streams, isEmpty);
      expect(payload.error, '房间不存在');
    });

    test('非虎牙地址抛 ParserHttpException', () async {
      final harness = HuyaHarness();
      await expectLater(
        harness.resolver.resolveRoom(_request('https://www.douyu.com/9527')),
        throwsA(isA<ParserHttpException>()),
      );
    });
  });
}
