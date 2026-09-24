/// YY 房间状态轻量刷新:只打 liveInfoDetail 元信息接口,不碰 stream-manager。
library;

import 'package:live_parser/live_parser.dart';
import 'package:test/test.dart';

import '../../../support/fake_yy_api.dart';

void main() {
  test('在播:totalViewer 命中即判开播,元信息正确,不请求取流接口', () async {
    final fake = FakeYyApi()..detailResponse = yyFixture('detail_live.json');
    final resolver = YyRoomResolver(YyClient(httpClient: fake));

    final record = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'yy', roomIdOrUrl: 'https://www.yy.com/1414787909/'),
    );

    expect(record.site, 'yy');
    expect(record.roomId, '1414787909');
    expect(record.title, '测试直播间');
    expect(record.anchorName, 'YY主播');
    expect(record.category, 'other');
    expect(record.cid, '1414787909', reason: '与 resolveRoom 同口径:cid 取 ssid');
    expect(record.audience, '4.1万', reason: 'totalViewer 原样下发(已是格式化串)');
    expect(record.cover, 'https://img.yy.com/cover.jpg');
    // 头像取 detail.avatar(web 快照 validImgUrl(detail.avatar) 同源)。
    expect(record.avatar, 'https://img.yy.com/avatar.jpg');

    expect(fake.requests, hasLength(1), reason: 'totalViewer 首次命中无需重试');
    expect(
      fake.requests.every((request) => request.url.host == 'www.yy.com'),
      isTrue,
      reason: '刷新不得请求 stream-manager/interface 等取流接口',
    );

    // 统一记录:fromSummary 映射刷新摘要已提供的统计真值(6sol 口径),
    // 且状态真源 roomState 必须随真实状态赋值(平台契约:totalViewer 命中即在播)。
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

    final record = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'yy', roomIdOrUrl: '1414787909'),
    );

    expect(record.audience, '4.1万');
    expect(fake.requests, hasLength(2), reason: '口径对齐 web:最多连取 3 次');
    expect(record.avatar, 'https://img.yy.com/avatar.jpg', reason: '重试保留头像');
    expect(
      record.audience,
      '4.1万',
      reason: '重试命中后统一记录同样拿到热度',
    );
  });

  test('三次均缺 totalViewer:状态不确定抛可诊断异常,不伪造离线', () async {
    // 6sol 裁决:resultCode=0 且 detail/data 非空但连续三次 totalViewer 均空,
    // 既无在播命中也无 data=null 离线信号 —— 必须抛可诊断异常交上层
    // 关注刷新保留旧状态,禁止将其伪造成 offline。
    final noViewer = Map<String, dynamic>.from(
      (yyFixture('detail_live.json') as Map)['data'] as Map,
    )..remove('totalViewer');
    final fake = FakeYyApi()
      ..detailResponseQueue.addAll([
        {'resultCode': 0, 'data': Map<String, dynamic>.from(noViewer)},
        {'resultCode': 0, 'data': Map<String, dynamic>.from(noViewer)},
        {'resultCode': 0, 'data': Map<String, dynamic>.from(noViewer)},
      ])
      // 第 4 次若被误发会命中在播 fixture,requests==3 断言即可暴露。
      ..detailResponse = yyFixture('detail_live.json');
    final resolver = YyRoomResolver(YyClient(httpClient: fake));

    await expectLater(
      resolver.refreshRoomSummary(
        const RoomRequest(site: 'yy', roomIdOrUrl: '1414787909'),
      ),
      throwsA(
        isA<ParserHttpException>().having(
          (error) => error.message,
          'message',
          allOf(contains('totalViewer'), contains('1414787909')),
        ),
      ),
      reason: '异常需可诊断:带 roomId 与缺失字段名',
    );
    expect(fake.requests, hasLength(3), reason: '最多连取 3 次(含首次),不再加发');
    expect(
      fake.requests.every(
        (request) =>
            request.url.host == 'www.yy.com' &&
            request.url.path.startsWith('/api/liveInfoDetail/'),
      ),
      isTrue,
      reason: '只打 liveInfoDetail 元信息,不调用取流/签名接口',
    );
    expect(
      fake.requests.any((request) => request.url.host == 'stream-manager.yy.com'),
      isFalse,
      reason: '状态不确定不得触发取流',
    );
  });

  test('重试中 data=null:明确离线立即返回,不再发起后续请求', () async {
    // 6sol 裁决第一款:data=null 是明确 offline —— 即使出现在重试响应中
    // 也按离线返回,不把旧 detail 当作“状态不确定”继续连取或抛错。
    final noViewer = Map<String, dynamic>.from(
      (yyFixture('detail_live.json') as Map)['data'] as Map,
    )..remove('totalViewer');
    final fake = FakeYyApi()
      ..detailResponseQueue.addAll([
        {'resultCode': 0, 'data': Map<String, dynamic>.from(noViewer)},
        const <String, Object?>{'resultCode': 0, 'data': null},
      ]);
    final resolver = YyRoomResolver(YyClient(httpClient: fake));

    final record = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'yy', roomIdOrUrl: '1414787909'),
    );

    expect(record.audience, isNull);
    expect(record.roomState, RoomState.offline);
    expect(fake.requests, hasLength(2), reason: 'data=null 即停,不再发起第三次');
    expect(
      record.roomState,
      RoomState.offline,
      reason: '明确离线信号经统一记录透传',
    );
  });

  test('未开播:data=null(合法离线响应)不重试,audience 为 null', () async {
    final fake = FakeYyApi()..detailResponse = yyFixture('detail_offline.json');
    final resolver = YyRoomResolver(YyClient(httpClient: fake));

    final record = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'yy', roomIdOrUrl: '547800'),
    );

    expect(record.audience, isNull);
    expect(fake.requests, hasLength(1), reason: 'data=null 直接按离线,不重试');

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
