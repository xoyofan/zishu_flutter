import 'package:live_parser/live_parser.dart';
import 'package:test/test.dart';

import '../../../support/fake_douyin_api.dart';

void main() {
  test('分页导入抖音关注并转换为离线房间摘要', () async {
    final fake = FakeDouyinApi()
      ..selfProfileResponse = {
        'user': {'sec_uid': 'MS4wLjABAAAA-test-sec-uid'},
      }
      ..followingResponse = douyinFixture('following_page_1.json')
      ..followingNextResponse = douyinFixture('following_page_2.json');
    final rooms = await fetchDouyinFollowingAnchors(
      DouyinClient(
        httpClient: fake,
        cookieOverride: 'sessionid=import-session; msToken=import-token',
      ),
    );

    expect(rooms, hasLength(3));
    expect(rooms.first.roomId, 'room-1');
    expect(rooms.first.anchorName, '导入主播一');
    expect(rooms.first.roomState, RoomState.offline);
    expect(rooms.first.category, '关注');
    expect(rooms.first.avatar, 'https://p3.douyinpic.com/import-avatar-1.jpg');

    final selfRequest = fake.requests.firstWhere(
      (request) => request.url.path == '/aweme/v1/web/user/profile/self/',
    );
    final followingRequest = fake.requests.firstWhere(
      (request) => request.url.path == '/aweme/v1/web/user/following/list/',
    );
    expect(selfRequest.url.host, 'www.douyin.com');
    expect(followingRequest.url.queryParameters['sec_user_id'],
        'MS4wLjABAAAA-test-sec-uid');
    expect(followingRequest.url.queryParameters['count'], '50');
    expect(followingRequest.url.queryParameters['source_type'], '2');
    expect(followingRequest.headers['Cookie'], contains('sessionid=import-session'));
    expect(
      fake.requests
          .where((request) => request.url.path == '/aweme/v1/web/user/following/list/')
          .map((request) => request.url.queryParameters['offset'])
          .toList(),
      ['0', '20'],
    );
  });
}
