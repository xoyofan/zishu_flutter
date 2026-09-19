/// SOOP 房间状态轻量刷新:只打一次 player_live_api(type=live),不做取流。
library;

import 'package:live_parser/live_parser.dart';
import 'package:test/test.dart';

import '../../../support/fake_soop_api.dart';

void main() {
  late FakeSoopApi fake;
  late SoopRoomResolver resolver;

  setUp(() {
    fake = FakeSoopApi()
      ..detailResponse = soopFixture('detail_live.json')
      ..dashboardResponse = {
        'upd': {'fanCnt': 23456},
        'subscription': {'total': 789},
      };
    resolver = SoopRoomResolver(SoopClient(httpClient: fake));
  });

  test('在播:元信息正确,且不触发 assign/aid 取流', () async {
    final summary = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'soop', roomIdOrUrl: 'testbj'),
    );

    expect(summary.site, 'soop');
    expect(summary.roomId, 'testbj');
    expect(summary.title, 'SOOP 测试直播间');
    expect(summary.anchorName, '测试主播');
    expect(summary.category, '英雄联盟');
    expect(summary.cid, 'testbj', reason: 'SOOP 无二级分类 id,cid 即房间号');
    expect(summary.online, '2.3万', reason: 'total_view_cnt=23456 格式化');
    expect(summary.cover, startsWith('https://liveimg.sooplive.co.kr/m/12345678'));
    // dashboard:粉丝 + 订阅(web fetchSoopDashboard 同源,upd.fanCnt /
    // subscription.total;SOOP 的 vip 列在 web 真源是「订阅」)。
    expect(summary.followers, '23456');
    expect(summary.vip, '789');

    final playerApiRequests = fake.requests
        .where((request) => request.url.path == '/afreeca/player_live_api.php')
        .toList();
    expect(playerApiRequests, hasLength(1), reason: '刷新只打一次房间信息接口');
    expect(Uri.splitQueryString(playerApiRequests.single.body)['type'], 'live');
    expect(
      fake.requests.where(
        (request) => request.url.path.endsWith('/broad_stream_assign.html'),
      ),
      isEmpty,
      reason: '刷新不得取流(assign)',
    );
    expect(
      fake.requests.where(
        (request) => request.url.path == '/afreeca/player_live_api.php' &&
            Uri.splitQueryString(request.body)['type'] == 'aid',
      ),
      isEmpty,
      reason: '刷新不得取流(aid)',
    );
  });

  test('不走 resolver 短缓存:连续两次刷新各打一次上游', () async {
    Future<void> refresh() => resolver.refreshRoomSummary(
      const RoomRequest(site: 'soop', roomIdOrUrl: 'testbj'),
    );
    await refresh();
    await refresh();

    final liveApiCount = fake.requests
        .where((request) => request.url.path == '/afreeca/player_live_api.php')
        .length;
    expect(liveApiCount, 2, reason: '契约:刷新不读也不写 60s detail 缓存');
  });

  test('未开播(RESULT=0):online 为空串', () async {
    fake.detailResponse = soopFixture('detail_offline.json');

    final summary = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'soop', roomIdOrUrl: 'testbj'),
    );

    expect(summary.online, '');
  });

  test('封禁(RESULT=-2):抛 ParserHttpException', () async {
    fake.detailResponse = soopFixture('detail_banned.json');

    await expectLater(
      resolver.refreshRoomSummary(
        const RoomRequest(site: 'soop', roomIdOrUrl: 'testbj'),
      ),
      throwsA(isA<ParserHttpException>()),
    );
  });

  test('注册表包装透传刷新能力', () {
    final registration = buildSoopRegistration(httpClient: fake);
    expect(registration.resolver, isA<RoomSummaryRefresher>());
  });
}
