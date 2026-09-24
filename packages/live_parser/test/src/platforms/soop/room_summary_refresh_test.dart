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
    final record = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'soop', roomIdOrUrl: 'testbj'),
    );

    expect(record.site, 'soop');
    expect(record.roomId, 'testbj');
    expect(record.title, 'SOOP 测试直播间');
    expect(record.anchorName, '测试主播');
    expect(record.category, '英雄联盟');
    expect(record.cid, 'testbj', reason: 'SOOP 无二级分类 id,cid 即房间号');
    expect(record.audience, '2.3万', reason: '分类列表 view_cnt=23456 格式化');
    expect(record.roomState, RoomState.live);
    expect(record.cover, startsWith('https://liveimg.sooplive.co.kr/m/12345678'));
    // 头像:station LOGO 确定性 URL(web fetchSoopRoomStats 同源,零额外请求)。
    expect(record.avatar, 'https://stimg.sooplive.co.kr/LOGO/te/testbj/testbj.jpg');
    // dashboard:粉丝 + 订阅(web fetchSoopDashboard 同源,upd.fanCnt /
    // subscription.total;SOOP 的 vip 列在 web 真源是「订阅」;fixture 里
    // total 是字符串形态,一并覆盖数值解析)。
    expect(record.followers, '434898');
    expect(record.vip, '235');
    expect(record.startedAt, DateTime.parse('2026-09-20 18:01:42'));

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

    // 统一记录:fromSummary 映射刷新摘要已提供的 fixture 真值;SOOP 无
    // diamondFans 上游 → svip null,不编造数字。
    expect(record.site, 'soop');
    expect(record.roomId, 'testbj');
    expect(record.audience, '2.3万', reason: 'view_cnt=23456 → audience 透传');
    expect(record.followers, '434898');
    expect(record.vip, '235');
    expect(record.svip, isNull);
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

    final record = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'soop', roomIdOrUrl: 'testbj'),
    );

    expect(record.roomState, RoomState.live);
    expect(
      record.audience,
      kSoopLiveOnlineFallback,
      reason: '在播判据是 roomState;占位文案经 fromSummary 透传',
    );

    // 关键口径:「直播中」是占位文案不是数字——fromSummary 原样透传该
    // 常量,且绝不等于 '0'(不把占位当有效观看数,交给展示层过滤)。
    expect(record.audience, kSoopLiveOnlineFallback);
    expect(record.audience, isNot('0'));
    expect(record.followers, '434898');
    expect(record.vip, '235');
    expect(record.svip, isNull);
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

  test('未开播(RESULT=0):audience 为 null + 离线,不查分类列表观看数', () async {
    fake.detailResponse = soopFixture('detail_offline.json');

    final record = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'soop', roomIdOrUrl: 'testbj'),
    );

    expect(record.audience, isNull);
    expect(record.roomState, RoomState.offline);

    // 离线协议 total_view_cnt:"0" 按平台契约 online 空串 → audience
    // null(0 不是有效观看数);dashboard 真值照常透传,svip 缺项 null。
    expect(record.audience, isNull);
    expect(record.followers, '434898');
    expect(record.vip, '235');
    expect(record.svip, isNull);
    expect(
      record.avatar,
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
    expect(record.followers, '434898');
    expect(record.vip, '235');
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

    final record = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'soop', roomIdOrUrl: 'testbj'),
    );

    expect(record.followers, '434898');
    expect(record.vip, '235');
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

    final record = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'soop', roomIdOrUrl: 'testbj'),
    );

    expect(record.roomState, RoomState.live);
    expect(record.followers, isNull);
    expect(record.vip, isNull);

    expect(record.followers, isNull);
    expect(record.vip, isNull);
    expect(record.svip, isNull);
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
