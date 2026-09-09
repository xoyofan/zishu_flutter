import 'package:live_parser/live_parser.dart';
import 'package:live_parser/src/platforms/douyu/douyu_site.dart';
import 'package:test/test.dart';

import '../../../support/fake_douyu_api.dart';

const _probeErrorJson = {'error': 1200, 'msg': 'room offline'};

RoomRequest _request(String idOrUrl, {String? quality}) =>
    RoomRequest(site: 'douyu', roomIdOrUrl: idOrUrl, preferredQuality: quality);

Future<(DouyuRoomResolver, FakeDouyuApi)> _makeResolver({
  Object? betardResponse,
  Object? probeOverride,
}) async {
  final fake = FakeDouyuApi()
    ..betardResponse = betardResponse
    ..playV1ProbeOverride = probeOverride;
  final registration = buildDouyuRegistration(httpClient: fake);
  return (registration.resolver as DouyuRoomResolver, fake);
}

void main() {
  group('在播房间解析', () {
    test('数字房间号:多 CDN 多画质 + HLS 线路', () async {
      final (resolver, fake) = await _makeResolver(betardResponse: {
        'room': {
          'room_id': 9527,
          'nickname': '测试主播',
          'show_status': 1,
          'room_name': '斗鱼测试房间',
          'room_pic': 'https://rpic.douyucdn.cn/live_cover/240x135.jpg',
          'cate_id': 1,
          'cate_name': '英雄联盟',
          'avatar': {'big': '//shf1-ali-douyucdn.cn/avatar/big.jpg'},
        },
      });

      final payload = await resolver.resolveRoom(_request('9527'));

      expect(payload.roomState, RoomState.live);
      expect(payload.isLive, isTrue);
      expect(payload.site, 'douyu');
      expect(payload.roomId, '9527');
      expect(payload.sourceUrl, 'https://www.douyu.com/9527');
      expect(payload.anchorName, '测试主播');
      expect(payload.title, '斗鱼测试房间');
      expect(payload.category, '英雄联盟');
      expect(payload.cid, '1');
      expect(payload.avatar, 'https://shf1-ali-douyucdn.cn/avatar/big.jpg');
      expect(payload.source, 'live_parser/douyu');

      // 画质映射:multirates 顺序与原名,不补档不重排
      expect(
        payload.availableQualities.map((q) => (q.name, q.rate)).toList(),
        [('蓝光8M', 0), ('超清', 2)],
      );

      // 每档:HLS 在前 + 各 CDN FLV;ali-h5 在超清档 error 被跳过
      expect(payload.streams, hasLength(2));
      final blueRay = payload.streams[0];
      expect(blueRay.name, '蓝光8M');
      expect(blueRay.lines.map((l) => (l.name, l.format)).toList(), [
        ('HLS', 'hls'),
        ('线路1 FLV', 'flv'),
        ('线路2 FLV', 'flv'),
        ('线路3 FLV', 'flv'),
      ]);
      expect(blueRay.preferredLine?.format, 'hls');
      expect(
        blueRay.preferredLine?.url,
        'https://hw-tct.douyucdn.cn/live/9527probe_0_0.m3u8?wsSecret=abc123&wsTime=1700000000',
      );

      final hd = payload.streams[1];
      expect(hd.lines, hasLength(3), reason: 'ali-h5 error 响应被跳过');
      expect(hd.lines.map((l) => l.name), ['HLS', '线路1 FLV', '线路2 FLV']);
      expect(hd.lines[1].url, 'https://hw-tct.douyucdn.cn/live/9527hw_2_1000.flv');

      // playUrl = 首选画质首选线路
      expect(payload.playUrl, blueRay.preferredLine?.url);

      // rate=0 复用探测缓存:probe 1 + 其余 CDN 2 + rate2 3 = 6 次播放请求
      final playRequests = fake.requests
          .where((r) => r.url.contains('getH5PlayV1'))
          .toList();
      expect(playRequests, hasLength(6));

      // 签名字段随请求携带
      final probeBody = playRequests.first.formBody;
      expect(probeBody['rid'], '9527');
      expect(probeBody['cdn'], 'hw-h5');
      expect(probeBody['ver'], '219032101');
      expect(probeBody['enc_data'], 'encDataToken');
      expect(probeBody['auth'], hasLength(32));
    });

    test('画质选择:qualityByName 命中与回退', () async {
      final (resolver, _) = await _makeResolver(betardResponse: {
        'room': {
          'room_id': 9527,
          'nickname': '测试主播',
          'show_status': 1,
          'room_name': '斗鱼测试房间',
        },
      });
      final payload = await resolver.resolveRoom(_request('9527'));

      expect(payload.qualityByName('超清')?.name, '超清');
      expect(payload.qualityByName('不存在')?.name, '蓝光8M', reason: '未命中回退首选档');
      expect(payload.qualityByName(null)?.name, '蓝光8M');
    });

    test('RoomPayload 序列化 round-trip', () async {
      final (resolver, _) = await _makeResolver(betardResponse: {
        'room': {
          'room_id': 9527,
          'nickname': '测试主播',
          'show_status': 1,
          'room_name': '斗鱼测试房间',
        },
      });
      final payload = await resolver.resolveRoom(_request('9527'));

      final restored = RoomPayload.fromJson(payload.toJson());
      expect(restored.toJson(), equals(payload.toJson()));
      expect(restored.encode(), payload.encode());
    });
  });

  group('输入归一', () {
    Future<String> roomIdOf(String input) async {
      final (resolver, _) = await _makeResolver(betardResponse: {
        'room': {'room_id': 9527, 'show_status': 1, 'nickname': 'x'},
      });
      return (await resolver.resolveRoom(_request(input))).roomId;
    }

    test('完整 URL', () async {
      expect(await roomIdOf('https://www.douyu.com/9527'), '9527');
    });

    test('缺协议 URL', () async {
      expect(await roomIdOf('www.douyu.com/9527'), '9527');
    });

    test('URL 带 rid 参数', () async {
      expect(await roomIdOf('https://www.douyu.com/topic/rhz?rid=9527&tt=1'), '9527');
    });

    test('主播别名地址回源 HTML 提取 rid', () async {
      final (resolver, fake) = await _makeResolver(betardResponse: {
        'room': {'room_id': 9527, 'show_status': 1, 'nickname': 'x'},
      });
      fake.aliasPageRid = '9527';
      final payload = await resolver.resolveRoom(_request('https://www.douyu.com/someanchor'));
      expect(payload.roomId, '9527');
      expect(
        fake.requests.any((r) => r.url.startsWith('https://m.douyu.com/someanchor')),
        isTrue,
      );
    });

    test('非斗鱼地址抛 ParserHttpException', () async {
      final (resolver, _) = await _makeResolver();
      await expectLater(
        resolver.resolveRoom(_request('https://huya.com/123')),
        throwsA(isA<ParserHttpException>()),
      );
    });
  });

  group('三态', () {
    test('未开播:offline 且无线路', () async {
      final (resolver, _) = await _makeResolver(betardResponse: {
        'room': {
          'room_id': 9528,
          'nickname': '下播主播',
          'show_status': 2,
          'room_name': '下播中的房间',
          'room_src': 'live_cover/offline_240x135.jpg',
          'avatar': 'http://shf1-ali-douyucdn.cn/avatar/offline.jpg',
        },
      });
      final payload = await resolver.resolveRoom(_request('9528'));
      expect(payload.roomState, RoomState.offline);
      expect(payload.isLive, isFalse);
      expect(payload.streams, isEmpty);
      expect(payload.availableQualities, isEmpty);
      expect(payload.playUrl, isEmpty);
      // room_src 相对路径补 rpic 域名;avatar http 转 https
      expect(payload.cover, 'https://rpic.douyucdn.cn/live_cover/offline_240x135.jpg');
      expect(payload.avatar, 'https://shf1-ali-douyucdn.cn/avatar/offline.jpg');
    });

    test('房间不存在(betard 404):notFound', () async {
      final (resolver, _) = await _makeResolver(betardResponse: '404');
      final payload = await resolver.resolveRoom(_request('999999'));
      expect(payload.roomState, RoomState.notFound);
      expect(payload.streams, isEmpty);
      expect(payload.error, '房间不存在');
      expect(payload.anchorName, isEmpty);
    });

    test('在播但播放接口报错:抛出上游 msg', () async {
      final (resolver, _) = await _makeResolver(
        betardResponse: {
          'room': {'room_id': 9527, 'show_status': 1, 'nickname': 'x'},
        },
        probeOverride: _probeErrorJson,
      );
      await expectLater(
        resolver.resolveRoom(_request('9527')),
        throwsA(
          isA<ParserHttpException>().having((e) => e.message, 'message', 'room offline'),
        ),
      );
    });
  });
}
