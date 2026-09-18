/// 抖音房间状态轻量刷新:只读一次房间进入数据,不构造任何播放档位/地址。
library;

import 'package:live_parser/live_parser.dart';
import 'package:test/test.dart';

import '../../../support/fake_douyin_api.dart';

Map<String, Object?> _enter({
  required int status,
  Object? online,
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
          'avatar_thumb': {
            'url_list': ['//p3.douyinpic.com/avatar.jpg'],
          },
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
    fake.enterResponse = _enter(status: 2, online: 32100);

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

    final urls = fake.requests.map((request) => request.url).join('\n');
    expect(urls, contains('enter'));
    expect(
      urls,
      isNot(contains('partition')),
      reason: '刷新不得请求分区/列表接口',
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
