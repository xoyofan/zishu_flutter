/// 虎牙房间状态轻量刷新:只读 profileRoom(必要时补一次页面判定)+ 在播时的
/// wup 贵宾查询,不签名取流。
///
/// 关键断言:刷新路径**不得**请求播放页/签名接口 —— 关注列表定时刷新若触碰
/// anti_code 签名,会把播放链路最贵的一段搬到列表刷新里。
library;

import 'package:live_parser/live_parser.dart';
import 'package:live_parser/src/platforms/huya/huya_site.dart';
import 'package:test/test.dart';

import '../../../support/fake_huya_api.dart';
import 'huya_wup_test.dart' show buildFakeVipResponse;

Map<String, Object?> _profile({
  required String liveStatus,
  int totalCount = 123456,
  int? activityCount,
  bool replay = false,
  bool withStream = true,
  int uid = 1394575534,
  int liveChannel = 1394575534,
}) => {
  'status': 200,
  'data': {
    'profileInfo': {
      'nick': '虎牙主播',
      'avatar180': 'http://huyaimg.msstatic.com/avatar.jpg',
      'gameId': 1,
      'activityCount': ?activityCount,
      'uid': uid,
    },
    'liveStatus': liveStatus,
    'realLiveStatus': liveStatus,
    'liveData': {
      'introduction': '虎牙测试房间',
      'roomName': '房间名',
      'screenshot': 'https://cover.huya.com/cover.jpg',
      'totalCount': totalCount,
      'sGameFullName': '英雄联盟',
      'gid': 1,
      'liveChannel': liveChannel,
      if (replay) 'isReplay': 1,
    },
    'stream': {
      'baseSteamInfoList': [
        if (withStream) {'lChannelId': 1},
      ],
    },
  },
};

void main() {
  late FakeHuyaApi fake;
  late HuyaRoomResolver resolver;

  setUp(() {
    fake = FakeHuyaApi();
    resolver = HuyaRoomResolver(HuyaClient(httpClient: fake));
  });

  test('在播:online 取 totalCount 格式化,元信息来自 profileRoom,且不请求播放页', () async {
    fake.profileRoomResponse = _profile(liveStatus: 'ON', activityCount: 98765);

    final summary = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'huya', roomIdOrUrl: '9527'),
    );

    expect(summary.site, 'huya');
    expect(summary.roomId, '9527');
    expect(summary.title, '虎牙测试房间');
    expect(summary.anchorName, '虎牙主播');
    expect(summary.category, '英雄联盟');
    expect(summary.cid, '1');
    expect(summary.online, '12.3万');
    expect(summary.cover, 'https://cover.huya.com/cover.jpg');
    // 粉丝数取同响应 activityCount(web follow/status.ts 的 huya 快照)。
    expect(summary.followers, '98765', reason: 'web formatCount 口径:完整数字');
    expect(
      summary.vip,
      '',
      reason: 'wup 不可达(fake 未配置响应)时静默留空,不伪造',
    );
    expect(summary.roomState, RoomState.live);

    // 只打 mp.huya.com 元信息与 wup 贵宾网关:没有播放页、没有签名。
    expect(
      fake.requests.every(
        (request) =>
            request.url.contains('mp.huya.com') ||
            request.url.contains('cdnws.api.huya.com'),
      ),
      isTrue,
      reason: '刷新不得请求播放页/签名接口:${fake.requests.map((r) => r.url).toList()}',
    );
  });

  test('在播且 wup 可用:vip 取 getVipBarList 的贵宾总数', () async {
    fake.profileRoomResponse = _profile(liveStatus: 'ON', activityCount: 98765);
    fake.wupResponseBytes = buildFakeVipResponse(total: 75, totalNum: 75);

    final summary = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'huya', roomIdOrUrl: '9527'),
    );

    expect(summary.vip, '75', reason: 'SideHeader「贵宾」行 = iTotalNum');
    expect(
      fake.requests.where((r) => r.url.contains('cdnws.api.huya.com')),
      hasLength(1),
      reason: '在播时恰好一次 wup 查询',
    );
  });

  test('在播但贵宾为 0:vip 留空(web formatCount(0) 同口径)', () async {
    fake.profileRoomResponse = _profile(liveStatus: 'ON');
    fake.wupResponseBytes = buildFakeVipResponse(total: 0, totalNum: 0);

    final summary = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'huya', roomIdOrUrl: '9527'),
    );

    expect(summary.vip, '');
  });

  test('分类/cid:真实形态 gameFullName + gid(gameId=0 不可信)', () async {
    // 2026-09 真实探针(tool/_probe_huya_cid.dart)实证:profileRoom 的
    // liveData 已不再下发 `sGameFullName`,中文名在 `gameFullName`,
    // `gameHostName` 是缩写;`gameId` 不是分区 id(取值 0/IntegerId),
    // 分区 id 是 `gid`(与 browse 一致,lol=1)。归一(缩写 → 中文)由
    // 宿主 app 侧 displayCategoryName 完成。
    final raw = _profile(liveStatus: 'ON');
    final data = Map<String, Object?>.of(raw['data']! as Map<String, Object?>);
    final liveData = Map<String, Object?>.of(
      data['liveData']! as Map<String, Object?>,
    )
      ..remove('sGameFullName')
      ..addAll(const {
        'gameFullName': '英雄联盟',
        'gameHostName': 'lol',
        'gameId': 0, // 上游用 0 表示无此 id,不得取走作 cid。
      });
    data['liveData'] = liveData;
    raw['data'] = data;

    fake.profileRoomResponse = raw;
    final summary = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'huya', roomIdOrUrl: '9527'),
    );

    expect(summary.category, '英雄联盟');
    expect(summary.cid, '1', reason: 'gid 优先,gameId=0 视为缺失');
  });

  test('离线:online 为空串,且不发起 wup 贵宾查询', () async {
    fake.profileRoomResponse = _profile(liveStatus: 'OFF', withStream: false);

    final summary = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'huya', roomIdOrUrl: '9528'),
    );

    expect(summary.online, '');
    expect(summary.vip, '');
    expect(
      fake.requests.where((request) => request.url.contains('cdnws.api.huya.com')),
      isEmpty,
      reason: 'web fetchHuyaSnapshot 仅 isLive 时查询贵宾',
    );
  });

  test('录播(replay):roomState=replay,online 契约同离线为空串', () async {
    fake.profileRoomResponse = _profile(liveStatus: 'ON', replay: true);

    final summary = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'huya', roomIdOrUrl: '9527'),
    );

    // 2026-09-19 口径:huyaRoomState 的 replay 不再折进 offline,由
    // roomState 单独承载;online 仍为空串(在播判据不变)。
    expect(summary.roomState, RoomState.replay);
    expect(summary.isLive, isFalse);
    expect(
      summary.online,
      '',
      reason: '轮播不是实时直播,不得当作在播',
    );
  });

  test('离线补 roomState:OFF 且无流时 roomState=offline', () async {
    fake.profileRoomResponse = _profile(liveStatus: 'OFF', withStream: false);

    final summary = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'huya', roomIdOrUrl: '9528'),
    );

    expect(summary.roomState, RoomState.offline);
  });

  test('房间不存在(profileRoom 无 data):抛异常', () async {
    fake.profileRoomResponse = null;

    await expectLater(
      resolver.refreshRoomSummary(
        const RoomRequest(site: 'huya', roomIdOrUrl: '9527'),
      ),
      throwsA(isA<ParserHttpException>()),
    );
  });
}
