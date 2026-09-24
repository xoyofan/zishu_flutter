/// 虎牙房间状态轻量刷新:只读 profileRoom(必要时补一次页面判定)+ 在播时的
/// wup 贵宾/超粉查询,不签名取流。
///
/// 关键断言:刷新路径**不得**请求播放页/签名接口 —— 关注列表定时刷新若触碰
/// anti_code 签名,会把播放链路最贵的一段搬到列表刷新里。
library;

import 'package:live_parser/live_parser.dart';
import 'package:live_parser/src/platforms/huya/huya_site.dart';
import 'package:test/test.dart';

import '../../../support/fake_huya_api.dart';
import 'huya_wup_test.dart'
    show
        buildFakeSuperFansInfoResponse,
        buildFakeSuperFansRankPanelResponse,
        buildFakeVipResponse;

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

  test('在播:audience 取 totalCount 格式化,元信息来自 profileRoom,且不请求播放页', () async {
    fake.profileRoomResponse = _profile(liveStatus: 'ON', activityCount: 98765);

    final record = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'huya', roomIdOrUrl: '9527'),
    );

    expect(record.site, 'huya');
    expect(record.roomId, '9527');
    expect(record.title, '虎牙测试房间');
    expect(record.anchorName, '虎牙主播');
    expect(record.category, '英雄联盟');
    expect(record.cid, '1');
    expect(record.audience, '12.3万');
    expect(record.cover, 'https://cover.huya.com/cover.jpg');
    // 头像取 data.profileInfo.avatar180(web avatarFromHuya 同源);
    // 真源探针实证:顶层 data 下没有 avatar180/avatar,只存在于 profileInfo。
    expect(record.avatar, 'https://huyaimg.msstatic.com/avatar.jpg');
    // 粉丝数取同响应 activityCount(web follow/status.ts 的 huya 快照)。
    expect(record.followers, '98765', reason: 'web formatCount 口径:完整数字');
    expect(
      record.vip,
      isNull,
      reason: 'wup 不可达(fake 未配置响应)时静默留空,不伪造',
    );
    expect(
      record.svip,
      isNull,
      reason: '超粉同口径:wup 不可达留空,不回填 0',
    );
    expect(record.roomState, RoomState.live);

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

    expect(record.site, 'huya');
    expect(record.roomId, '9527');
    expect(record.roomState, RoomState.live);
    expect(record.audience, '12.3万');
    expect(record.followers, '98765');
    expect(record.vip, isNull, reason: 'wup 不可达空串 → null,不伪造 0');
    expect(record.svip, isNull);
  });

  test('在播且 wup 可用:vip 取 getVipBarList 的贵宾总数', () async {
    fake.profileRoomResponse = _profile(liveStatus: 'ON', activityCount: 98765);
    fake.wupResponseBytes = buildFakeVipResponse(total: 75, totalNum: 75);

    final record = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'huya', roomIdOrUrl: '9527'),
    );

    expect(record.vip, '75', reason: 'SideHeader「贵宾」行 = iTotalNum');
    expect(
      fake.wupFuncNames.where((name) => name == 'getVipBarList'),
      hasLength(1),
      reason: '在播时恰好一次贵宾查询',
    );
    expect(record.vip, '75');
    expect(
      fake.wupFuncNames,
      unorderedEquals(<String>[
        'getVipBarList',
        'getSuperFansInfo',
        'getSuperFansRankPanel',
      ]),
      reason: 'web fetchHuyaSnapshot:仅 isLive 时并发发 3 个 wup,不重复也不额外',
    );
  });

  test('在播且 wup 可用:diamondFans 取超粉人数(第 3 列 svip tone「超粉」)', () async {
    fake.profileRoomResponse = _profile(liveStatus: 'ON');
    fake.wupResponseBytes = buildFakeVipResponse(total: 75, totalNum: 75);
    fake.wupResponseByFunc['getSuperFansInfo'] =
        buildFakeSuperFansInfoResponse(superFansNum: 1288, yearSuperFansNum: 12);
    fake.wupResponseByFunc['getSuperFansRankPanel'] =
        buildFakeSuperFansRankPanelResponse(num: 999, plusNum: 0);

    final record = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'huya', roomIdOrUrl: '9527'),
    );

    expect(
      record.svip,
      '1300',
      reason: 'iSuperFansNum + iYearSuperFansNum(info 优先,web formatCount 同口径)',
    );
    expect(record.vip, '75');
    expect(record.toJson()['diamondFans'], '1300');

    expect(record.vip, '75');
    expect(record.svip, '1300', reason: 'diamondFans → svip');
  });

  // 6sol 裁决:Huya WUP 返回的原始 0 被 huya_wup.dart
  // isPlausibleHuyaSuperFanCount(>0) 判为不可信 —— 协议未保证它是有效
  // 计数,故留空才是正确行为,禁止改成显示 0。
  test('在播但超粉原始零不可信，合并仍留空', () async {
    fake.profileRoomResponse = _profile(liveStatus: 'ON');
    fake.wupResponseBytes = buildFakeVipResponse(total: 75, totalNum: 75);
    fake.wupResponseByFunc['getSuperFansInfo'] =
        buildFakeSuperFansInfoResponse(superFansNum: 0, yearSuperFansNum: 0);
    fake.wupResponseByFunc['getSuperFansRankPanel'] =
        buildFakeSuperFansRankPanelResponse(num: 0, plusNum: 0);

    final record = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'huya', roomIdOrUrl: '9527'),
    );

    expect(record.svip, isNull);
    expect(record.toJson().containsKey('diamondFans'), isFalse, reason: '空串不写 JSON');
    expect(
      record.svip,
      isNull,
      reason: '超粉原始零不可信，合并仍留空',
    );
  });

  test('在播但超粉接口只给 panel 时:diamondFans 回退 rankPanel', () async {
    fake.profileRoomResponse = _profile(liveStatus: 'ON');
    fake.wupResponseBytes = buildFakeVipResponse(total: 75, totalNum: 75);
    fake.wupResponseByFunc['getSuperFansInfo'] =
        buildFakeSuperFansInfoResponse(superFansNum: 0, yearSuperFansNum: 0);
    fake.wupResponseByFunc['getSuperFansRankPanel'] =
        buildFakeSuperFansRankPanelResponse(num: 61, plusNum: 1);

    final record = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'huya', roomIdOrUrl: '9527'),
    );

    expect(record.svip, '62', reason: 'iNum + iPlusNum');
  });

  test('在播但贵宾为 0:vip 留空(web formatCount(0) 同口径)', () async {
    fake.profileRoomResponse = _profile(liveStatus: 'ON');
    fake.wupResponseBytes = buildFakeVipResponse(total: 0, totalNum: 0);

    final record = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'huya', roomIdOrUrl: '9527'),
    );

    expect(record.vip, isNull);
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
    final record = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'huya', roomIdOrUrl: '9527'),
    );

    expect(record.category, '英雄联盟');
    expect(record.cid, '1', reason: 'gid 优先,gameId=0 视为缺失');
  });

  test('离线:audience 为 null,且不发起 wup 贵宾查询', () async {
    fake.profileRoomResponse = _profile(liveStatus: 'OFF', withStream: false);

    final record = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'huya', roomIdOrUrl: '9528'),
    );

    expect(record.audience, isNull);
    expect(record.vip, isNull);
    expect(record.svip, isNull);
    expect(
      fake.requests.where((request) => request.url.contains('cdnws.api.huya.com')),
      isEmpty,
      reason: 'web fetchHuyaSnapshot 仅 isLive 时查询贵宾/超粉',
    );
    expect(fake.wupFuncNames, isEmpty);

    expect(record.roomState, RoomState.offline);
    expect(record.audience, isNull);
    expect(record.vip, isNull);
    expect(record.svip, isNull);
  });

  test('录播(replay):roomState=replay,audience 同离线为 null', () async {
    fake.profileRoomResponse = _profile(liveStatus: 'ON', replay: true);

    final record = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'huya', roomIdOrUrl: '9527'),
    );

    // 2026-09-19 口径:huyaRoomState 的 replay 不再折进 offline,由
    // roomState 单独承载;audience 空串在转换边界归 null。
    expect(record.roomState, RoomState.replay);
    expect(record.isLive, isFalse);
    expect(
      record.audience,
      isNull,
      reason: '轮播不是实时直播,不得当作在播',
    );
    expect(
      record.svip,
      isNull,
      reason: '轮播同样不查 wup(仅 isLive)',
    );
    expect(fake.wupFuncNames, isEmpty);

    expect(record.roomState, RoomState.replay);
    expect(record.isReplay, isTrue);
    expect(record.audience, isNull);
  });

  test('离线补 roomState:OFF 且无流时 roomState=offline', () async {
    fake.profileRoomResponse = _profile(liveStatus: 'OFF', withStream: false);

    final record = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'huya', roomIdOrUrl: '9528'),
    );

    expect(record.roomState, RoomState.offline);
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
