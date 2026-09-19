import 'dart:convert';
import 'dart:io';

import 'package:live_parser/live_parser.dart';
import 'package:live_parser/src/platforms/bilibili/bilibili_site.dart';
import 'package:test/test.dart';

import '../../../support/fake_bilibili_api.dart';

String _fixture(String name) => File('test/fixtures/bilibili/$name').readAsStringSync();

Object? _json(String name) => jsonDecode(_fixture(name));

/// room_play_info 同形副本,但全部 codec 的 current_qn 统一为 [qn]
/// (真实 API 一次请求只返回单档流,所有 codec 的 current_qn 一致)。
Map<String, Object?> _playInfoWithQn(int qn) {
  final data = _json('room_play_info.json')! as Map<String, Object?>;
  void walk(Object? node) {
    if (node is Map<String, Object?>) {
      if (node.containsKey('current_qn')) node['current_qn'] = qn;
      node.values.forEach(walk);
    } else if (node is List) {
      node.forEach(walk);
    }
  }

  walk(data);
  return data;
}

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
  test('在播:accept_qn 全档列出,实给档真实线路放首位,其余档空线路占位', () async {
    final harness = BiliHarness();
    final payload = await harness.resolver.resolveRoom(
      const RoomRequest(site: 'bilibili', roomIdOrUrl: '9527'),
    );

    expect(payload.roomState, RoomState.live);
    expect(payload.site, 'bilibili');
    expect(payload.roomId, '9527');
    expect(payload.anchorName, 'B站主播');
    expect(payload.title, 'B站测试房间');
    // 二级分区优先(web pickText(area_name, parent_area_name) 同口径)。
    expect(payload.category, '英雄联盟');
    expect(payload.cid, '325');
    expect(payload.avatar, 'https://i0.hdslb.com/bfs/face/a.jpg');
    // get_info 已带主播名/头像 → 省掉一次 get_anchor_in_room 请求
    expect(
      harness.fake.requests.any((r) => r.url.contains('get_anchor_in_room')),
      isFalse,
    );
    expect(payload.source, 'live_parser/bilibili');

    // 画质:accept_qn ∩ 档位表,保持官网顺序(菜单全档可列出)
    expect(
      payload.availableQualities.map((q) => (q.name, q.rate)).toList(),
      [('原画', 10000), ('超清', 250), ('高清', 150)],
    );

    // 懒取流:一次 getRoomPlayInfo 只有 current_qn=10000 单档真实流,
    // 原画(实给档)放首位,超清/高清以空线路占位 —— 不再把同一批地址
    // 复制到多个档位(此前画质菜单「多级重复」,切档无效果)。
    expect(payload.streams, hasLength(3));
    expect(
      payload.streams.map((s) => (s.name, s.lines.length)).toList(),
      [('原画', 5), ('超清', 0), ('高清', 0)],
    );
    final original = payload.streams[0];
    expect(original.name, '原画');

    // 实给档线路:avc/hevc 双 codec,多 host 多线路;HLS 在前 FLV 在后
    final names = original.lines.map((l) => l.name).toList();
    expect(names.any((n) => n.startsWith('avc-')), isTrue);
    expect(names.any((n) => n.startsWith('hevc-')), isTrue);
    expect(original.lines.first.format, 'hls', reason: 'HLS 在前');
    expect(original.lines.last.format, 'flv');

    // 多 host → 多线路;URL = host + base_url + extra
    final flvLine = original.lines.lastWhere((l) => l.format == 'flv');
    expect(flvLine.url, startsWith('https://'));
    expect(flvLine.url, contains('live-bvc/9527?proto=flv'));
    expect(flvLine.url, contains('expires='));

    // 播放头:CDN 以 Referer/Origin 做防盗链
    expect(original.lines.first.headers['referer'], 'https://live.bilibili.com/');
    expect(original.lines.first.headers['origin'], 'https://live.bilibili.com');

    // 防重复铁律:有线路的档位唯一(实给档),不存在跨档共享 URL。
    final tiersWithLines = payload.streams.where((s) => s.lines.isNotEmpty).toList();
    expect(tiersWithLines, hasLength(1));

    // playUrl 首选档首选线路
    expect(payload.playUrl, isNotEmpty);

    // 无偏好请求 → 默认 qn=10000(原画)
    final playRequest = harness.fake.requests
        .firstWhere((r) => r.url.contains('getRoomPlayInfo'));
    expect(playRequest.url, contains('room_id=9527'));
    expect(playRequest.url, contains('qn=10000'));

    final restored = RoomPayload.fromJson(payload.toJson());
    expect(restored.toJson(), equals(payload.toJson()));
  });

  test('懒取流:preferredQuality=超清 → 请求 qn=250,超清为实给档放首位', () async {
    final harness = BiliHarness()
      ..fake.roomPlayInfoByQn = {250: _playInfoWithQn(250)};
    final payload = await harness.resolver.resolveRoom(
      const RoomRequest(
        site: 'bilibili',
        roomIdOrUrl: '9527',
        preferredQuality: '超清',
      ),
    );

    final playRequest = harness.fake.requests
        .firstWhere((r) => r.url.contains('getRoomPlayInfo'));
    expect(playRequest.url, contains('qn=250'), reason: '偏好档作为请求 qn');

    expect(
      payload.streams.map((s) => (s.name, s.lines.length)).toList(),
      [('超清', 5), ('原画', 0), ('高清', 0)],
      reason: '实给档放首位,其余档位占位',
    );
    // 超清档线路来自该次请求的 ts/fmp4 codec
    expect(payload.streams.first.lines.first.format, 'hls');
    // availableQualities 不因默认档变化,保持官网全档顺序
    expect(
      payload.availableQualities.map((q) => q.name).toList(),
      ['原画', '超清', '高清'],
    );
    expect(payload.playUrl, isNotEmpty);
  });

  test('降级:请求 qn=10000 但服务器实给 250(匿名)→ 实给档是超清而非原画', () async {
    // 响应里只有 current_qn=250 的流(未登录拿不到原画)。
    final harness = BiliHarness()..fake.roomPlayInfoResponse = _playInfoWithQn(250);
    final payload = await harness.resolver.resolveRoom(
      const RoomRequest(site: 'bilibili', roomIdOrUrl: '9527'),
    );

    expect(
      payload.streams.map((s) => (s.name, s.lines.length)).toList(),
      [('超清', 5), ('原画', 0), ('高清', 0)],
      reason: '真实线路挂 current_qn 对应档,不冒充请求档',
    );
    expect(payload.playUrl, isNotEmpty);
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

  test('轮播(live_status=2):replay 无线路(轮播流暂不接入)', () async {
    // 在播 fixture 上只改 live_status → 2:其余字段与真实响应同形。
    final info = Map<String, Object?>.of(_json('room_info_live.json')! as Map<String, Object?>);
    final data = Map<String, Object?>.of(info['data']! as Map<String, Object?>)
      ..['live_status'] = 2;
    info['data'] = data;

    final harness = BiliHarness()..fake.roomInfoResponse = info;
    final payload = await harness.resolver.resolveRoom(
      const RoomRequest(site: 'bilibili', roomIdOrUrl: '9527'),
    );
    expect(payload.roomState, RoomState.replay);
    expect(payload.isReplay, isTrue);
    expect(payload.streams, isEmpty, reason: '语义先行:不请求 play_info、不取流');
    expect(
      harness.fake.requests.any((r) => r.url.contains('play_info')),
      isFalse,
    );
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
