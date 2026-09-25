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

    final record = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'douyin', roomIdOrUrl: '123456'),
    );

    expect(record.site, 'douyin');
    expect(record.roomId, '123456');
    expect(record.title, '抖音测试直播间');
    expect(record.anchorName, '抖音主播');
    expect(record.category, '王者荣耀');
    expect(record.cid, '123456', reason: '抖音无二级分类 id,cid 即房间号');
    expect(record.audience, '3.2万');
    expect(record.cover, contains('douyinpic.com'));
    // 头像取 enter 响应内 owner.avatar_thumb(web 快照同源,零额外请求)。
    expect(record.avatar, 'https://p3.douyinpic.com/avatar.jpg');
    // 粉丝数取 enter 响应内 owner.follow_info(web 快照首选路径,零额外请求)。
    expect(record.followers, '456789');
    expect(record.vip, isNull);

    final urls = fake.requests.map((request) => request.url).join('\n');
    expect(urls, contains('enter'));
    expect(
      urls,
      isNot(contains('partition')),
      reason: '刷新不得请求分区/列表接口',
    );

    // 统一记录:fromSummary 映射刷新摘要已提供的统计真值(6sol 口径),
    // 且状态真源 roomState 必须随真实状态赋值(平台契约:status != 4 即在播)。
    expect(record.site, 'douyin');
    expect(record.roomId, '123456');
    expect(record.roomState, RoomState.live);
    expect(record.isLive, isTrue);
    expect(record.audience, '3.2万');
    expect(record.followers, '456789');
    expect(record.vip, isNull, reason: '粉丝团列未取 → null,不伪造 0');
    expect(record.svip, isNull, reason: '本用例未给资料卡,会员缺值 → null');
  });

  test('关注数:enter 的 owner.follow_info 缺 follower_count 时回退用户资料接口', () async {
    // 实连 dump 2026-09-25:抖音 enter 响应的 owner.follow_info **只有
    // follow_status**,没有 follower_count → 此前关注数恒「—」。
    // web 真源 fetchDouyinSnapshot 的回退路径:owner.id_str 存在时打
    // /webcast/user/?target_uid=,取 data.follow_info.follower_count。
    fake
      ..enterResponse = _enter(status: 2, online: 32100)
      ..userProfileResponse = {
        'status_code': 0,
        'data': {
          'follow_info': {
            'following_count': 3575,
            'follower_count': 4911564,
            'follower_count_str': '0',
          },
        },
      };

    final record = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'douyin', roomIdOrUrl: '123456'),
    );

    expect(record.followers, '4911564');
    final urls = fake.requests.map((request) => request.url).join('\n');
    expect(urls, contains('/webcast/user/'), reason: '必须走 web 同款回退接口');
    expect(urls, contains('a_bogus='), reason: '回退接口同样需签名');
  });

  test('关注数:enter 已有 follower_count 时不额外请求用户资料接口', () async {
    fake
      ..enterResponse = _enter(status: 2, online: 32100, followerCount: 456789)
      ..userProfileResponse = null;

    final record = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'douyin', roomIdOrUrl: '123456'),
    );

    expect(record.followers, '456789');
    final urls = fake.requests.map((request) => request.url).join('\n');
    expect(
      urls,
      isNot(contains('/webcast/user/?')),
      reason: 'enter 已带 follower_count 时零额外请求',
    );
  });

  test('粉丝团(vip 列):在播时取资料卡 fans_club.total_fans_count', () async {
    // web 真源 ROOM_STAT_COLUMNS.douyin 第 2 列 field=fanGroup「粉丝团」,
    // 取自同一份 /webcast/user/profile/ 响应的 fans_club.total_fans_count
    // (SFVideoLive fetchDouyinAnchorProfileCounts 的 fanGroup 分支)。
    // 回归:此前只取 subscribe_info.member_count 填第 3 列,
    // 第 2 列恒空 → 播放页「粉丝团」永远显示「—」。
    fake
      ..enterResponse = _enter(status: 2, online: 32100)
      ..anchorProfileResponse = {
        'status_code': 0,
        'data': {
          'user_profile': {
            'fans_club': {
              'total_fans_count': 718512,
              'total_fans_count_str': '71.9',
              'total_fans_count_substr': '万',
            },
            'subscribe_info': {'member_count': 3259},
          },
        },
      };

    final record = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'douyin', roomIdOrUrl: '123456'),
    );

    expect(
      record.vip,
      '718512',
      reason: '粉丝团列取 fans_club.total_fans_count(web formatPlainCount 整数口径)',
    );
    expect(record.svip, '3259', reason: '第 3 列会员仍取 member_count');
  });

  test('粉丝团:资料卡原始零留空,不伪造 0', () async {
    fake
      ..enterResponse = _enter(status: 2, online: 32100)
      ..anchorProfileResponse = {
        'status_code': 0,
        'data': {
          'user_profile': {
            'fans_club': {'total_fans_count': 0, 'total_fans_count_str': ''},
          },
        },
      };

    final record = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'douyin', roomIdOrUrl: '123456'),
    );

    expect(record.vip, isNull, reason: '协议原始零不可信,不落伪造的 0');
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

    final record = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'douyin', roomIdOrUrl: '123456'),
    );

    // web ROOM_STAT_COLUMNS.douyin 第 3 列(tone=svip)field=vip「会员」
    // (follow/douyin-extras.ts 的 subscribe_info.member_count);
    // 摘要由 [RoomSummary.diamondFans] 承载,统一记录出口为 [RoomRecord.svip]。
    expect(record.svip, '4567');
    final urls = fake.requests.map((request) => request.url).join('\n');
    expect(urls, contains('/webcast/user/profile/'));
    expect(urls, contains('a_bogus='), reason: '资料卡接口需 a_bogus 签名');
    expect(urls, isNot(contains('partition')), reason: '刷新不得请求分区/列表接口');

    // diamondFans → svip:会员列真值经统一记录透传。
    expect(record.svip, '4567');
  });

  test('会员:资料卡协议原始零按平台契约留空,diamondFans 不伪造 0', () async {
    fake
      ..enterResponse = _enter(status: 2, online: 32100)
      ..anchorProfileResponse = {
        'status_code': 0,
        'data': {
          'user_profile': {
            'subscribe_info': {'member_count': 0},
          },
        },
      };

    final record = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'douyin', roomIdOrUrl: '123456'),
    );

    expect(record.svip, isNull);
    expect(record.svip, isNull, reason: '协议原始零不可信,统一记录不落伪造的 0');
    expect(record.audience, '3.2万', reason: '零值不影响其余统计');
  });

  test('会员:未开播(status=4)不请求资料卡,diamondFans 留空', () async {
    fake.enterResponse = _enter(status: 4, online: 9999);

    final record = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'douyin', roomIdOrUrl: '123456'),
    );

    expect(record.svip, isNull);
    expect(
      fake.requests.map((request) => request.url).join('\n'),
      isNot(contains('/webcast/user/profile/')),
      reason: '仅播时取会员(web 真源 status==2 门槛)',
    );
  });

  test('未开播(status=4):audience 为 null', () async {
    fake.enterResponse = _enter(status: 4, online: 9999);

    final record = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'douyin', roomIdOrUrl: '123456'),
    );

    expect(record.audience, isNull);

    expect(record.roomState, RoomState.offline);
    expect(
      record.audience,
      isNull,
      reason: '未开播热度不采纳(协议原值 9999 被契约清空)',
    );
    expect(record.followers, isNull);
    expect(record.svip, isNull);
  });
}
