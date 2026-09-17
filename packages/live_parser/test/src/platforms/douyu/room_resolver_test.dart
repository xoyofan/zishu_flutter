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
  // 注册表出口套了 CachedRoomResolver(结果 60s),这里直接测平台解析器本体。
  return (DouyuRoomResolver(DouyuClient(httpClient: fake)), fake);
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

      // 每档:各 CDN FLV;ali-h5 在超清档 error 被跳过。
      // HLS preview 不再插在列表头(预览流 token 寿命短,会抢走首选),仅 FLV 全灭时兜底。
      expect(payload.streams, hasLength(2));
      final blueRay = payload.streams[0];
      expect(blueRay.name, '蓝光8M');
      expect(blueRay.lines.map((l) => (l.name, l.format)).toList(), [
        ('线路1 FLV', 'flv'),
        ('线路2 FLV', 'flv'),
        ('线路3 FLV', 'flv'),
      ]);
      expect(blueRay.preferredLine?.format, 'flv',
          reason: '首选线路必须是 FLV,不得是 hlsH5Preview 预览流');
      expect(
        blueRay.preferredLine?.url,
        'https://hw-tct.douyucdn.cn/live/9527probe_0_0.flv',
      );
      // 播放请求头:参考实现同源的 Referer/Origin/UA/Cookie(缺头会被 CDN 拒/半开)
      expect(blueRay.preferredLine?.headers['referer'],
          'https://www.douyu.com/9527');
      expect(blueRay.preferredLine?.headers['user-agent'], contains('Chrome/'));
      expect(blueRay.preferredLine?.headers['cookie'], contains('dy_did='));

      final hd = payload.streams[1];
      expect(hd.lines, hasLength(2), reason: 'ali-h5 error 响应被跳过');
      expect(hd.lines.map((l) => l.name), ['线路1 FLV', '线路2 FLV']);
      expect(hd.lines[0].url, 'https://hw-tct.douyucdn.cn/live/9527hw_2_1000.flv');

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

    test('偏好档懒取流:只请求所选档,其余档空线路占位', () async {
      final (resolver, fake) = await _makeResolver(betardResponse: {
        'room': {
          'room_id': 9527,
          'nickname': '测试主播',
          'show_status': 1,
          'room_name': '斗鱼测试房间',
        },
      });

      final payload = await resolver.resolveRoom(_request('9527', quality: '超清'));

      // probe 1 次(取档位/CDN 元数据)+ 偏好档 3 CDN;不再为其余 CDN 探测 rate=0。
      final playRequests = fake.requests
          .where((r) => r.url.contains('getH5PlayV1'))
          .toList();
      expect(playRequests, hasLength(4));
      expect(
        playRequests.where((r) => r.formBody['rate'] == '2'),
        hasLength(3),
        reason: '只取超清档',
      );
      final probe = playRequests.singleWhere((r) => r.formBody['rate'] == '0');
      expect(probe.formBody['cdn'], 'hw-h5', reason: '不再为其余 CDN 发 rate=0 探测');

      expect(payload.roomState, RoomState.live);
      // 可播档放 streams 首位(playUrl / 播放侧回退直接可用)
      expect(payload.streams.first.name, '超清');
      expect(payload.streams.first.lines, isNotEmpty);
      expect(payload.playUrl, isNotEmpty);
      // 其余档位空线路占位,点击后由播放侧带该档重解析
      expect(payload.streams.last.name, '蓝光8M');
      expect(payload.streams.last.lines, isEmpty);
      expect(
        payload.availableQualities.map((q) => q.name).toList(),
        ['蓝光8M', '超清'],
        reason: 'chips 保持平台原顺序',
      );

      // 播放接口响应 60s 缓存:同一实例重复解析时,成功响应不再请求;
      // 失败 CDN(ali-h5)不缓存,会重试一次。
      final before = fake.requests.length;
      await resolver.resolveRoom(_request('9527', quality: '超清'));
      final secondRound = fake.requests
          .skip(before)
          .where((r) => r.url.contains('getH5PlayV1'))
          .toList();
      expect(
        secondRound.where((r) => r.formBody['cdn'] != 'ali-h5'),
        isEmpty,
        reason: '成功响应全部命中 60s 缓存',
      );
      expect(secondRound, hasLength(1), reason: '仅失败 CDN(ali-h5)重试');
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

  group('契约:档位与 streams 严格同源', () {
    Object betard({int showTime = 0}) => {
      'room': {
        'room_id': 9527,
        'nickname': '测试主播',
        'show_status': 1,
        'room_name': '斗鱼测试房间',
        if (showTime > 0) 'show_time': showTime,
      },
    };

    test('某档整档取流失败:该档从画质列表中整体消失(死键回归)', () async {
      final (resolver, fake) = await _makeResolver(betardResponse: betard());
      // rate=2(超清)的全部 CDN 都失败 —— 历史上该档仍留在 availableQualities 里,
      // UI 点 chip 后找不到同名 stream,表现为静默无反应的死键。
      fake.failRates.add('2');

      final payload = await resolver.resolveRoom(_request('9527'));

      expect(payload.streams.map((s) => s.name), ['蓝光8M'], reason: '超清整档失败后被丢弃');
      expect(
        payload.availableQualities.map((q) => q.name),
        payload.streams.map((s) => s.name),
        reason: '列出来的档 == 点得动的档',
      );
      // 每个 chip 都能在 streams 里精确命中同名项(qualityByName 有兜底,故比对名字)
      for (final quality in payload.availableQualities) {
        expect(payload.qualityByName(quality.name)?.name, quality.name);
      }
    });

    test('startedAt 取自 betard show_time;缺失时为 null', () async {
      final (withTime, _) = await _makeResolver(
        betardResponse: betard(showTime: 1789023402),
      );
      final live = await withTime.resolveRoom(_request('9527'));
      expect(live.startedAt, DateTime.fromMillisecondsSinceEpoch(1789023402 * 1000));

      final (noTime, _) = await _makeResolver(betardResponse: betard());
      final unknown = await noTime.resolveRoom(_request('9527'));
      expect(unknown.startedAt, isNull, reason: '平台未提供时不得伪造');
    });
  });
}
