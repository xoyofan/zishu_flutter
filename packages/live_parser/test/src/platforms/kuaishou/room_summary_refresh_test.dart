/// 快手房间状态轻量刷新:只拉一次房间页 SSR 元信息,不解析任何播放线路。
library;

import 'package:live_parser/live_parser.dart';
import 'package:test/test.dart';

import '../../../support/fake_kuaishou_api.dart';

void main() {
  late FakeKuaishouApi fake;
  late KuaishouRoomResolver resolver;

  setUp(() {
    fake = FakeKuaishouApi()..roomPage = kuaishouFixture('room_live.html');
    resolver = KuaishouRoomResolver(KuaishouClient(httpClient: fake));
  });

  test('在播:元信息正确,且只请求房间页一次', () async {
    final summary = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'kuaishou', roomIdOrUrl: 'ks_user_1'),
    );

    expect(summary.site, 'kuaishou');
    expect(summary.roomId, 'ks_user_1');
    expect(summary.title, '今晚八点开播 不见不散');
    expect(summary.anchorName, '快手主播');
    expect(summary.category, '王者荣耀');
    expect(summary.cid, 'ks_user_1', reason: '快手无二级分类 id,cid 即房间号');
    expect(summary.online, '2.3万', reason: 'watchingCount=23456 格式化');
    expect(summary.cover, 'https://p1.kuaishou.com/poster.jpg');

    expect(fake.requests, hasLength(1), reason: '刷新只拉一次房间页');
    expect(fake.requests.single.url.host, 'live.kuaishou.com');
    expect(fake.requests.single.url.path, '/u/ks_user_1');
  });

  test('未开播:online 为空串,资料保留', () async {
    fake.roomPage = kuaishouFixture('room_offline.html');

    final summary = await resolver.refreshRoomSummary(
      const RoomRequest(site: 'kuaishou', roomIdOrUrl: 'ks_user_1'),
    );

    expect(summary.online, '', reason: '契约:online 非空即判在播,离线必须空串');
    expect(summary.anchorName, '快手主播');
  });

  test('房间不存在:抛 ParserHttpException(不得伪造离线摘要)', () async {
    fake.roomPage = kuaishouFixture('room_missing.html');

    await expectLater(
      resolver.refreshRoomSummary(
        const RoomRequest(site: 'kuaishou', roomIdOrUrl: 'ks_user_1'),
      ),
      throwsA(isA<ParserHttpException>()),
    );
  });

  test('注册表包装透传刷新能力', () {
    final registration = buildKuaishouRegistration(httpClient: fake);
    expect(registration.resolver, isA<RoomSummaryRefresher>());
  });
}
