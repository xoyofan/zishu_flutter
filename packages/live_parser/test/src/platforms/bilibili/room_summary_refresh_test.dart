/// B 站房间状态轻量刷新:只读 room/get_info,不请求 room/play_info(取流)。
library;

import 'package:live_parser/live_parser.dart';
import 'package:live_parser/src/platforms/bilibili/bilibili_site.dart';
import 'package:test/test.dart';

import '../../../support/fake_bilibili_api.dart';

Map<String, Object?> _roomInfo({
  required int liveStatus,
  Object? online,
  Object? attention,
  String uname = 'B站主播',
  String title = 'B站测试房间',
}) => {
  'code': 0,
  'data': {
    'room_id': 9527,
    'uid': 1234,
    'live_status': liveStatus,
    'title': title,
    'uname': uname,
    'face': 'https://i0.hdslb.com/bfs/face/a.jpg',
    'user_cover': 'https://i0.hdslb.com/bfs/cover/b.jpg',
    'parent_area_name': '网游',
    'area_name': '英雄联盟',
    'area_id': 325,
    'online': ?online,
    'attention': ?attention,
  },
};

void main() {
  late FakeBilibiliApi fake;
  late BilibiliRoomResolver resolver;

  setUp(() {
    fake = FakeBilibiliApi()
      ..spiResponse = {
        'code': 0,
        'data': {'b_3': 'buvid-xyz'},
      };
    resolver = BilibiliRoomResolver(BilibiliClient(httpClient: fake));
  });

  test('在播:online 取格式化热度,元信息来自 get_info,且不请求 play_info', () async {
    fake.roomInfoResponse = _roomInfo(
      liveStatus: 1,
      online: 12345,
      attention: 654321,
    );

    final summary = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'bilibili', roomIdOrUrl: '9527'),
    );

    expect(summary.site, 'bilibili');
    expect(summary.roomId, '9527');
    expect(summary.title, 'B站测试房间');
    expect(summary.anchorName, 'B站主播');
    expect(summary.cid, '325');
    // 二级分区优先(web pickText(area_name, parent_area_name) 同口径)。
    expect(summary.category, '英雄联盟');
    expect(summary.online, '1.2万');
    expect(summary.cover, contains('hdslb.com'));
    // 粉丝数取同响应 attention(web follow/status.ts 的 bilibili 快照);
    // 勋章/大航海在 web 是额外接口且 vip 列本就为空,这里恒空。
    expect(summary.followers, '654321');
    expect(summary.vip, '');

    final urls = fake.requests.map((request) => request.url).join('\n');
    expect(urls, contains('get_info'));
    expect(urls, isNot(contains('play_info')), reason: '刷新不得请求取流接口');
  });

  test('离线(live_status=0):online 为空串', () async {
    fake.roomInfoResponse = _roomInfo(liveStatus: 0, online: 9999);

    final summary = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'bilibili', roomIdOrUrl: '9528'),
    );

    expect(summary.online, '');
  });

  test('轮播(live_status=2):归离线,online 为空串', () async {
    fake.roomInfoResponse = _roomInfo(liveStatus: 2, online: 9999);

    final summary = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'bilibili', roomIdOrUrl: '9529'),
    );

    expect(summary.online, '');
  });

  test('房间不存在(code=1):抛异常', () async {
    fake.roomInfoResponse = {'code': 1, 'message': '房间不存在', 'data': null};

    await expectLater(
      resolver.refreshRoomSummary(
        const RoomRequest(site: 'bilibili', roomIdOrUrl: '9527'),
      ),
      throwsA(isA<ParserHttpException>()),
    );
  });
}
