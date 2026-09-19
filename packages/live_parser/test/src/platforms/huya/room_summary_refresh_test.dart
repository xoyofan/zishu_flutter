/// 虎牙房间状态轻量刷新:只读 profileRoom(必要时补一次页面判定),不签名取流。
///
/// 关键断言:刷新路径**不得**请求播放页/签名接口 —— 关注列表定时刷新若触碰
/// anti_code 签名,会把播放链路最贵的一段搬到列表刷新里。
library;

import 'package:live_parser/live_parser.dart';
import 'package:live_parser/src/platforms/huya/huya_site.dart';
import 'package:test/test.dart';

import '../../../support/fake_huya_api.dart';

Map<String, Object?> _profile({
  required String liveStatus,
  int totalCount = 123456,
  int? activityCount,
  bool replay = false,
  bool withStream = true,
}) => {
  'status': 200,
  'data': {
    'profileInfo': {
      'nick': '虎牙主播',
      'avatar180': 'http://huyaimg.msstatic.com/avatar.jpg',
      'gameId': 1,
      'activityCount': ?activityCount,
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
      reason: '贵宾/超粉走 Tars wup 协议,轻量刷新不复刻,留空不伪造',
    );

    // 只打 mp.huya.com:没有播放页、没有签名。
    expect(
      fake.requests.every((request) => request.url.contains('mp.huya.com')),
      isTrue,
      reason: '刷新不得请求播放页/签名接口:${fake.requests.map((r) => r.url).toList()}',
    );
  });

  test('离线:online 为空串', () async {
    fake.profileRoomResponse = _profile(liveStatus: 'OFF', withStream: false);

    final summary = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'huya', roomIdOrUrl: '9528'),
    );

    expect(summary.online, '');
  });

  test('录播(replay):本仓契约无 replay,online 一律为空串', () async {
    fake.profileRoomResponse = _profile(liveStatus: 'ON', replay: true);

    final summary = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'huya', roomIdOrUrl: '9527'),
    );

    expect(
      summary.online,
      '',
      reason: 'replay 归 offline(RoomState 无 replay),不得当作在播',
    );
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
