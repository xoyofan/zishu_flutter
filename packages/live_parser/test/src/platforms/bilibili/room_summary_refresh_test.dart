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
  String? face = 'https://i0.hdslb.com/bfs/face/a.jpg',
}) => {
  'code': 0,
  'data': {
    'room_id': 9527,
    'uid': 1234,
    'live_status': liveStatus,
    'title': title,
    'uname': uname,
    'face': ?face,
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
    // 头像取同响应 face(web follow/status.ts 的 bilibili 快照
    // `avatar: anchor.face || avatarFromRoom(info)`,本包与 resolveRoom 同口径
    // 以 get_info 的 face 优先、anchor 接口兜底)。
    expect(summary.avatar, 'https://i0.hdslb.com/bfs/face/a.jpg');
    // 粉丝数取同响应 attention(web follow/status.ts 的 bilibili 快照);
    // 勋章/大航海在 web 是额外接口且 vip 列本就为空,这里恒空。
    expect(summary.followers, '654321');
    expect(summary.vip, '');
    expect(summary.roomState, RoomState.live);

    final urls = fake.requests.map((request) => request.url).join('\n');
    expect(urls, contains('get_info'));
    expect(urls, isNot(contains('play_info')), reason: '刷新不得请求取流接口');

    // 统一记录:fromSummary 映射刷新摘要已提供的统计真值(6sol 口径)。
    final record = RoomRecord.fromSummary(summary);
    expect(record.site, 'bilibili');
    expect(record.roomId, '9527');
    expect(record.roomState, RoomState.live);
    expect(record.audience, '1.2万');
    expect(record.followers, '654321');
    expect(record.vip, isNull, reason: 'B 站 vip 列本就为空 → null');
    expect(record.svip, isNull, reason: '未请求大航海时缺值 → null');
  });

  test('头像:get_info 缺 face 时回退 anchor 接口头像(与 resolveRoom 同口径)', () async {
    fake
      ..roomInfoResponse = _roomInfo(liveStatus: 1, face: null)
      ..anchorInRoomResponse = {
        'code': 0,
        'data': {
          'info': {
            'uname': 'B站主播',
            'face': 'http://i0.hdslb.com/bfs/face/fallback.jpg',
          },
        },
      };

    final summary = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'bilibili', roomIdOrUrl: '9527'),
    );

    expect(summary.avatar, 'https://i0.hdslb.com/bfs/face/fallback.jpg');
  });

  test('大航海(diamondFans):在播时取 guardTab/topList 的 info.num', () async {
    fake
      ..roomInfoResponse = _roomInfo(liveStatus: 1, online: 12345)
      ..guardTopListResponse = {
        'code': 0,
        'data': {
          'info': {'num': 128},
          'top3': [
            {'guard_level': 1},
          ],
          'list': [
            {'guard_level': 3},
          ],
        },
      };

    final summary = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'bilibili', roomIdOrUrl: '9527'),
    );

    // web ROOM_STAT_COLUMNS.bilibili 第 3 列(tone=svip)field=guard「大航海」,
    // 本包统一由 [RoomSummary.diamondFans] 承载。
    expect(summary.diamondFans, '128');
    final urls = fake.requests.map((request) => request.url).join('\n');
    expect(urls, contains('guardTab/topList'));
    expect(urls, isNot(contains('play_info')), reason: '刷新不得请求取流接口');
    expect(
      RoomRecord.fromSummary(summary).svip,
      '128',
      reason: 'diamondFans → svip',
    );
  });

  test('大航海:离线不请求 guardTab,diamondFans 留空', () async {
    fake.roomInfoResponse = _roomInfo(liveStatus: 0, online: 9999);

    final summary = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'bilibili', roomIdOrUrl: '9528'),
    );

    expect(summary.diamondFans, '');
    expect(
      fake.requests.map((request) => request.url).join('\n'),
      isNot(contains('guardTab/topList')),
      reason: '仅播时取大航海(web 真源 state==live 门槛)',
    );
  });

  test('大航海:接口失败留空,刷新不失败(不伪造)', () async {
    fake
      ..roomInfoResponse = _roomInfo(liveStatus: 1, online: 12345)
      ..guardTopListResponse = {'code': -400, 'message': '风控'};

    final summary = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'bilibili', roomIdOrUrl: '9527'),
    );

    expect(summary.diamondFans, '');
    expect(summary.online, '1.2万', reason: '大航海失败不影响其余字段');

    final record = RoomRecord.fromSummary(summary);
    expect(record.svip, isNull, reason: '大航海失败空串 → null,不伪造');
    expect(record.audience, '1.2万');
  });

  test('离线(live_status=0):online 为空串,roomState=offline', () async {
    fake.roomInfoResponse = _roomInfo(liveStatus: 0, online: 9999);

    final summary = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'bilibili', roomIdOrUrl: '9528'),
    );

    expect(summary.online, '');
    expect(summary.roomState, RoomState.offline);

    final record = RoomRecord.fromSummary(summary);
    expect(record.roomState, RoomState.offline);
    expect(record.audience, isNull, reason: '离线热度空串 → null');
    expect(record.followers, isNull, reason: '离线未提供 attention → null');
  });

  test('轮播(live_status=2):roomState=replay,online 契约同离线为空串', () async {
    fake.roomInfoResponse = _roomInfo(liveStatus: 2, online: 9999);

    final summary = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'bilibili', roomIdOrUrl: '9529'),
    );

    // 2026-09-19 口径:轮播不再折进 offline,由 roomState 单独承载
    // 「我的关注」页的排序/标识;online 仍为空串(在播判据不变)。
    expect(summary.roomState, RoomState.replay);
    expect(summary.isLive, isFalse, reason: 'online 为空,不进侧栏在播判据');
    expect(summary.online, '');

    final record = RoomRecord.fromSummary(summary);
    expect(record.roomState, RoomState.replay);
    expect(record.isReplay, isTrue);
    expect(record.audience, isNull);
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
