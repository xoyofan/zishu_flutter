/// YY 房间状态轻量刷新:只打 liveInfoDetail 元信息接口,不碰 stream-manager。
library;

import 'package:live_parser/live_parser.dart';
import 'package:test/test.dart';

import '../../../support/fake_yy_api.dart';

void main() {
  test('在播:totalViewer 命中即判开播,元信息正确,不请求取流接口', () async {
    final fake = FakeYyApi()..detailResponse = yyFixture('detail_live.json');
    final resolver = YyRoomResolver(YyClient(httpClient: fake));

    final summary = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'yy', roomIdOrUrl: 'https://www.yy.com/1414787909/'),
    );

    expect(summary.site, 'yy');
    expect(summary.roomId, '1414787909');
    expect(summary.title, '测试直播间');
    expect(summary.anchorName, 'YY主播');
    expect(summary.category, 'other');
    expect(summary.cid, '1414787909', reason: '与 resolveRoom 同口径:cid 取 ssid');
    expect(summary.online, '4.1万', reason: 'totalViewer 原样下发(已是格式化串)');
    expect(summary.cover, 'https://img.yy.com/cover.jpg');
    // 头像取 detail.avatar(web 快照 validImgUrl(detail.avatar) 同源)。
    expect(summary.avatar, 'https://img.yy.com/avatar.jpg');

    expect(fake.requests, hasLength(1), reason: 'totalViewer 首次命中无需重试');
    expect(
      fake.requests.every((request) => request.url.host == 'www.yy.com'),
      isTrue,
      reason: '刷新不得请求 stream-manager/interface 等取流接口',
    );

    // 统一记录:fromSummary 映射刷新摘要已提供的统计真值(6sol 口径),
    // 且状态真源 roomState 必须随真实状态赋值(平台契约:totalViewer 命中即在播)。
    final record = RoomRecord.fromSummary(summary);
    expect(record.site, 'yy');
    expect(record.roomId, '1414787909');
    expect(record.roomState, RoomState.live);
    expect(record.isLive, isTrue);
    expect(record.audience, '4.1万');
    expect(
      record.followers,
      isNull,
      reason: 'YY 上游无免登录粉丝接口 → null,不伪造 0',
    );
    expect(record.vip, isNull);
    expect(record.svip, isNull);
    expect(
      record.startedAt,
      DateTime.fromMillisecondsSinceEpoch(1788911253 * 1000),
      reason: 'detail startTime 真值透传',
    );
  });

  test('totalViewer 边缘闪变:首次缺省时重试,第二次命中判在播', () async {
    final first = Map<String, dynamic>.from(
      (yyFixture('detail_live.json') as Map)['data'] as Map,
    )..remove('totalViewer');
    final fake = FakeYyApi()
      ..detailResponseQueue.addAll([
        {'resultCode': 0, 'data': first},
        yyFixture('detail_live.json'),
      ]);
    final resolver = YyRoomResolver(YyClient(httpClient: fake));

    final summary = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'yy', roomIdOrUrl: '1414787909'),
    );

    expect(summary.online, '4.1万');
    expect(fake.requests, hasLength(2), reason: '口径对齐 web:最多连取 3 次');
    expect(summary.avatar, 'https://img.yy.com/avatar.jpg', reason: '重试保留头像');
    expect(
      RoomRecord.fromSummary(summary).audience,
      '4.1万',
      reason: '重试命中后统一记录同样拿到热度',
    );
  });

  test('未开播:data=null(合法离线响应)不重试,online 为空串', () async {
    final fake = FakeYyApi()..detailResponse = yyFixture('detail_offline.json');
    final resolver = YyRoomResolver(YyClient(httpClient: fake));

    final summary = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'yy', roomIdOrUrl: '547800'),
    );

    expect(summary.online, '');
    expect(fake.requests, hasLength(1), reason: 'data=null 直接按离线,不重试');

    final record = RoomRecord.fromSummary(summary);
    expect(record.roomState, RoomState.offline);
    expect(record.audience, isNull, reason: '离线契约空串 → null');
    expect(record.startedAt, isNull, reason: 'data=null 无开播时间,不伪造');
    expect(record.followers, isNull);
    expect(record.vip, isNull);
    expect(record.svip, isNull);
  });

  test('房间不存在:抛 ParserHttpException(不得伪造离线摘要)', () async {
    final fake = FakeYyApi()..detailResponse = yyFixture('detail_missing.json');
    final resolver = YyRoomResolver(YyClient(httpClient: fake));

    await expectLater(
      resolver.refreshRoomSummary(
        const RoomRequest(site: 'yy', roomIdOrUrl: '999999'),
      ),
      throwsA(isA<ParserHttpException>()),
    );
  });

  test('注册表包装透传刷新能力', () {
    final registration = buildYyRegistration(httpClient: FakeYyApi());
    expect(registration.resolver, isA<RoomSummaryRefresher>());
  });
}
