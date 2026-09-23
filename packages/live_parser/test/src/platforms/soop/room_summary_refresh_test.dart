/// SOOP 房间状态轻量刷新:RESULT==1 即在播,观看数取分类列表 API。
library;

import 'package:http/http.dart' as http;
import 'package:live_parser/live_parser.dart';
import 'package:test/test.dart';

import '../../../support/fake_soop_api.dart';

void main() {
  late FakeSoopApi fake;
  late SoopRoomResolver resolver;

  setUp(() {
    fake = FakeSoopApi()
      // 真实 player_live_api 已不下发观看数字段(fixture 镜像现状),
      // 观看数走分类列表 API(fetchSoopCategoryViewers)。
      ..detailResponse = soopFixture('detail_live.json')
      ..categoryRoomsResponse = {
        'data': {
          'list': [
            {'user_id': 'otherbj', 'view_cnt': '99999'},
            {'user_id': 'testbj', 'view_cnt': '23456'},
          ],
        },
      }
      // dashboard fixture 镜像真实响应结构(2026-09 探针),字符串型
      // subscription.total 一并覆盖。
      ..dashboardResponse = soopFixture('dashboard_live.json');
    resolver = SoopRoomResolver(SoopClient(httpClient: fake));
  });

  test('在播:元信息正确,观看数取自分类列表,且不触发 assign/aid 取流', () async {
    final summary = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'soop', roomIdOrUrl: 'testbj'),
    );

    expect(summary.site, 'soop');
    expect(summary.roomId, 'testbj');
    expect(summary.title, 'SOOP 测试直播间');
    expect(summary.anchorName, '测试主播');
    expect(summary.category, '英雄联盟');
    expect(summary.cid, 'testbj', reason: 'SOOP 无二级分类 id,cid 即房间号');
    expect(summary.online, '2.3万', reason: '分类列表 view_cnt=23456 格式化');
    expect(summary.roomState, RoomState.live);
    expect(summary.cover, startsWith('https://liveimg.sooplive.co.kr/m/12345678'));
    // 头像:station LOGO 确定性 URL(web fetchSoopRoomStats 同源,零额外请求)。
    expect(summary.avatar, 'https://stimg.sooplive.co.kr/LOGO/te/testbj/testbj.jpg');
    // dashboard:粉丝 + 订阅(web fetchSoopDashboard 同源,upd.fanCnt /
    // subscription.total;SOOP 的 vip 列在 web 真源是「订阅」;fixture 里
    // total 是字符串形态,一并覆盖数值解析)。
    expect(summary.followers, '434898');
    expect(summary.vip, '235');

    final playerApiRequests = fake.requests
        .where((request) => request.url.path == '/afreeca/player_live_api.php')
        .toList();
    expect(playerApiRequests, hasLength(1), reason: '刷新只打一次房间信息接口');
    expect(Uri.splitQueryString(playerApiRequests.single.body)['type'], 'live');
    // 观看数按房间分类号查分类在播列表(web fetchSoopCategoryViewers 同参)。
    final viewerRequests = fake.requests
        .where(
          (request) =>
              request.url.host == 'sch.sooplive.co.kr' &&
              request.url.queryParameters['m'] == 'categoryContentsList',
        )
        .toList();
    expect(viewerRequests, hasLength(1));
    expect(viewerRequests.single.url.queryParameters['szCateNo'], '00040066');
    expect(viewerRequests.single.url.queryParameters['szOrder'], 'view_cnt_desc');
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

  test('在播但分类列表未命中:回退「直播中」文案,不得刷成离线', () async {
    fake.categoryRoomsResponse = {
      'data': {
        'list': [
          {'user_id': 'otherbj', 'view_cnt': '99999'},
        ],
      },
    };

    final summary = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'soop', roomIdOrUrl: 'testbj'),
    );

    expect(summary.roomState, RoomState.live);
    expect(
      summary.online,
      kSoopLiveOnlineFallback,
      reason: '宿主以 online 非空为在播判据,空串会把在播房间判成离线',
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

  test('未开播(RESULT=0):online 空串 + 离线,不查分类列表观看数', () async {
    fake.detailResponse = soopFixture('detail_offline.json');

    final summary = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'soop', roomIdOrUrl: 'testbj'),
    );

    expect(summary.online, '');
    expect(summary.roomState, RoomState.offline);
    expect(
      summary.avatar,
      'https://stimg.sooplive.co.kr/LOGO/te/testbj/testbj.jpg',
      reason: '离线房间同样有 LOGO 头像',
    );
    // 离线房间无观看数语义:分类列表观看数只在在播时补。
    expect(
      fake.requests.where(
        (request) =>
            request.url.host == 'sch.sooplive.co.kr' &&
            request.url.queryParameters['m'] == 'categoryContentsList',
      ),
      isEmpty,
    );
    // 粉丝/订阅与开播状态无关:离线也照常取 dashboard(2026-09 探针实测
    // 离线房间 dashboard 照常 200 且字段齐全),播放页主播卡离线也展示。
    expect(summary.followers, '434898');
    expect(summary.vip, '235');
    expect(
      fake.requests.where(
        (request) => request.url.host == 'api-channel.sooplive.co.kr',
      ),
      hasLength(1),
    );
  });

  test('dashboard 瞬时失败:重试第二次成功,粉丝/订阅不丢', () async {
    fake.dashboardResponseQueue.addAll([
      http.Response('upstream 503', 503),
      soopFixture('dashboard_live.json'),
    ]);

    final summary = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'soop', roomIdOrUrl: 'testbj'),
    );

    expect(summary.followers, '434898');
    expect(summary.vip, '235');
    expect(
      fake.requests.where(
        (request) => request.url.host == 'api-channel.sooplive.co.kr',
      ),
      hasLength(2),
      reason: '第一次非 2xx 触发轻量重试,共两次请求',
    );
  });

  test('dashboard 连续失败:followers/vip 留空,刷新不失败(不伪造)', () async {
    fake.dashboardResponseQueue.addAll([
      http.Response('upstream 503', 503),
      http.Response('upstream 429', 429),
    ]);

    final summary = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'soop', roomIdOrUrl: 'testbj'),
    );

    expect(summary.roomState, RoomState.live);
    expect(summary.followers, '');
    expect(summary.vip, '');
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
