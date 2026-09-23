/// 抖音房间状态轻量刷新:只读一次房间进入数据,不构造任何播放档位/地址。
library;

import 'package:live_parser/live_parser.dart';
import 'package:test/test.dart';

import '../../../support/fake_douyin_api.dart';

Map<String, Object?> _enter({
  required int status,
  Object? online,
  Object? followerCount,
  String title = '抖音测试直播间',
  String nickname = '抖音主播',
}) => {
  'status_code': 0,
  'data': {
    'user': {'nickname': nickname},
    'data': [
      {
        'status': status,
        'id_str': '123456',
        'title': title,
        'owner': {
          'nickname': nickname,
          'id_str': '987654',
          'sec_uid': 'MS4wLjABAAAAsec',
          'avatar_thumb': {
            'url_list': ['//p3.douyinpic.com/avatar.jpg'],
          },
          if (followerCount != null)
            'follow_info': {'follower_count': followerCount},
        },
        'cover': {
          'url_list': ['//p3.douyinpic.com/cover.jpg'],
        },
        'game_data': {
          'game_tag_info': {'game_tag_name': '王者荣耀', 'game_tag_id': 1010045},
        },
        if (online != null) 'room_view_stats': {'display_value': online},
      },
    ],
  },
};

void main() {
  late FakeDouyinApi fake;
  late DouyinRoomResolver resolver;

  setUp(() {
    fake = FakeDouyinApi();
    resolver = DouyinRoomResolver(DouyinClient(httpClient: fake));
  });

  test('在播:热度格式化、元信息正确,且不请求分区/其他接口', () async {
    fake.enterResponse = _enter(
      status: 2,
      online: 32100,
      followerCount: 456789,
    );

    final summary = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'douyin', roomIdOrUrl: '123456'),
    );

    expect(summary.site, 'douyin');
    expect(summary.roomId, '123456');
    expect(summary.title, '抖音测试直播间');
    expect(summary.anchorName, '抖音主播');
    expect(summary.category, '王者荣耀');
    expect(summary.cid, '123456', reason: '抖音无二级分类 id,cid 即房间号');
    expect(summary.online, '3.2万');
    expect(summary.cover, contains('douyinpic.com'));
    // 头像取 enter 响应内 owner.avatar_thumb(web 快照同源,零额外请求)。
    expect(summary.avatar, 'https://p3.douyinpic.com/avatar.jpg');
    // 粉丝数取 enter 响应内 owner.follow_info(web 快照首选路径,零额外请求)。
    expect(summary.followers, '456789');
    expect(summary.vip, '');

    final urls = fake.requests.map((request) => request.url).join('\n');
    expect(urls, contains('enter'));
    expect(
      urls,
      isNot(contains('partition')),
      reason: '刷新不得请求分区/列表接口',
    );
  });

  test('会员(diamondFans):在播时走带签名的主播资料卡接口', () async {
    fake
      ..enterResponse = _enter(status: 2, online: 32100)
      ..anchorProfileResponse = {
        'status_code': 0,
        'data': {
          'user_profile': {
            'subscribe_info': {'member_count': 4567},
          },
        },
      };

    final summary = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'douyin', roomIdOrUrl: '123456'),
    );

    // web ROOM_STAT_COLUMNS.douyin 第 3 列(tone=svip)field=vip「会员」
    // (follow/douyin-extras.ts 的 subscribe_info.member_count);
    // 本包统一由 [RoomSummary.diamondFans] 承载。
    expect(summary.diamondFans, '4567');
    final urls = fake.requests.map((request) => request.url).join('\n');
    expect(urls, contains('/webcast/user/profile/'));
    expect(urls, contains('a_bogus='), reason: '资料卡接口需 a_bogus 签名');
    expect(urls, isNot(contains('partition')), reason: '刷新不得请求分区/列表接口');
  });

  test('会员:未开播(status=4)不请求资料卡,diamondFans 留空', () async {
    fake.enterResponse = _enter(status: 4, online: 9999);

    final summary = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'douyin', roomIdOrUrl: '123456'),
    );

    expect(summary.diamondFans, '');
    expect(
      fake.requests.map((request) => request.url).join('\n'),
      isNot(contains('/webcast/user/profile/')),
      reason: '仅播时取会员(web 真源 status==2 门槛)',
    );
  });

  test('未开播(status=4):online 为空串', () async {
    fake.enterResponse = _enter(status: 4, online: 9999);

    final summary = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'douyin', roomIdOrUrl: '123456'),
    );

    expect(summary.online, '');
  });
}
