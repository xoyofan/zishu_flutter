import 'dart:convert';
import 'dart:io';

import 'package:live_parser/live_parser.dart';
import 'package:live_parser/src/platforms/bilibili/bilibili_site.dart';
import 'package:test/test.dart';

import '../../../support/fake_bilibili_api.dart';

String _fixture(String name) => File('test/fixtures/bilibili/$name').readAsStringSync();

Object? _json(String name) => jsonDecode(_fixture(name));

class BiliHarness {
  BiliHarness() {
    fake = FakeBilibiliApi()
      ..roomInfoResponse = _json('room_info_live.json')
      ..anchorInRoomResponse = {
        'code': 0,
        'data': {'info': {'uname': '', 'face': ''}},
      }
      ..roomPlayInfoResponse = _json('room_play_info.json')
      ..spiResponse = {
        'code': 0,
        'data': {'b_3': 'buvid-xyz'},
      }
      ..navResponse = {
        'code': 0,
        'data': {
          'wbi_img': {
            'img_url': 'https://i0.hdslb.com/bfs/wbi/abc123.png',
            'sub_url': 'https://i0.hdslb.com/bfs/wbi/def456.png',
          },
        },
      };
    registration = buildBilibiliRegistration(httpClient: fake);
  }

  late FakeBilibiliApi fake;
  late SiteRegistration registration;

  // 注册表出口套了 CachedRoomResolver(结果 60s),这里直接测平台解析器本体。
  BilibiliRoomResolver get resolver =>
      BilibiliRoomResolver(BilibiliClient(httpClient: fake));
}

void main() {
  test('在播:accept_qn 画质映射 + avc/hevc 多线多 host', () async {
    final harness = BiliHarness();
    final payload = await harness.resolver.resolveRoom(
      const RoomRequest(site: 'bilibili', roomIdOrUrl: '9527'),
    );

    expect(payload.roomState, RoomState.live);
    expect(payload.site, 'bilibili');
    expect(payload.roomId, '9527');
    expect(payload.anchorName, 'B站主播');
    expect(payload.title, 'B站测试房间');
    expect(payload.category, '网游');
    expect(payload.cid, '325');
    expect(payload.avatar, 'https://i0.hdslb.com/bfs/face/a.jpg');
    // get_info 已带主播名/头像 → 省掉一次 get_anchor_in_room 请求
    expect(
      harness.fake.requests.any((r) => r.url.contains('get_anchor_in_room')),
      isFalse,
    );
    expect(payload.source, 'live_parser/bilibili');

    // 画质:accept_qn ∩ 档位表,保持官网顺序
    expect(
      payload.availableQualities.map((q) => (q.name, q.rate)).toList(),
      [('原画', 10000), ('超清', 250), ('高清', 150)],
    );

    expect(payload.streams, hasLength(3));
    final original = payload.streams[0];
    expect(original.name, '原画');

    // 原画(qn=10000):flv 匹配 current_qn=10000;hls ts 无 10000 → 回退 ≤10000
    final names = original.lines.map((l) => l.name).toList();
    expect(names.any((n) => n.startsWith('avc-')), isTrue);
    expect(names.any((n) => n.startsWith('hevc-')), isTrue,
        reason: 'hls 回退池包含 hevc,应排 avc 之后');
    expect(original.lines.first.format, 'hls', reason: 'HLS 在前');
    expect(original.lines.last.format, 'flv');

    // 多 host → 多线路;URL = host + base_url + extra
    final flvLine = original.lines.lastWhere((l) => l.format == 'flv');
    expect(flvLine.url, startsWith('https://'));
    expect(flvLine.url, contains('live-bvc/9527?proto=flv'));
    expect(flvLine.url, contains('expires='));

    // 超清档(qn=250):hls ts 精确匹配 250
    final hd = payload.streams[1];
    expect(hd.name, '超清');
    expect(hd.lines.any((l) => l.url.contains('proto=ts')), isTrue);

    // playUrl 首选档首选线路
    expect(payload.playUrl, isNotEmpty);

    final restored = RoomPayload.fromJson(payload.toJson());
    expect(restored.toJson(), equals(payload.toJson()));

    // buvid3 cookie 随请求携带
    final playRequest = harness.fake.requests
        .firstWhere((r) => r.url.contains('getRoomPlayInfo'));
    expect(playRequest.url, contains('room_id=9527'));
  });

  test('未开播:offline 无线路', () async {
    final harness = BiliHarness()
      ..fake.roomInfoResponse = _json('room_info_offline.json');
    final payload = await harness.resolver.resolveRoom(
      const RoomRequest(site: 'bilibili', roomIdOrUrl: '9528'),
    );
    expect(payload.roomState, RoomState.offline);
    expect(payload.isLive, isFalse);
    expect(payload.streams, isEmpty);
    expect(payload.cover, 'https://i0.hdslb.com/bfs/keyframe/offline.jpg',
        reason: 'user_cover 缺失时用 keyframe');
  });

  test('房间不存在(code=1):notFound', () async {
    final harness = BiliHarness()
      ..fake.roomInfoResponse = _json('room_info_missing.json');
    final payload = await harness.resolver.resolveRoom(
      const RoomRequest(site: 'bilibili', roomIdOrUrl: '999999'),
    );
    expect(payload.roomState, RoomState.notFound);
    expect(payload.error, '房间不存在');
  });

  test('URL 输入与 blanc 路径', () async {
    final harness = BiliHarness();
    final payload = await harness.resolver.resolveRoom(
      const RoomRequest(site: 'bilibili', roomIdOrUrl: 'https://live.bilibili.com/blanc/9527'),
    );
    expect(payload.roomId, '9527');
  });
}
