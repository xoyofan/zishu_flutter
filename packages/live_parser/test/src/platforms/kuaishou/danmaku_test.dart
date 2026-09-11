import 'package:live_parser/live_parser.dart';
import 'package:test/test.dart';

import '../../../support/fake_kuaishou_api.dart';

void main() {
  group('快手 feed 解析', () {
    test('游标/拉取节奏/评论过滤与字段归一', () {
      final batch = parseKuaishouFeed(
        kuaishouFixtureJson('feed.json'),
        roomId: 'ks_user_1',
      );

      expect(batch.cursor, 'cursor-2');
      expect(batch.pullDelay, const Duration(seconds: 3));
      expect(batch.messages, hasLength(2), reason: 'gift 类型应被过滤');
      final message = batch.messages.first;
      expect(message.type, DanmakuMessageType.chat);
      expect(message.roomId, 'ks_user_1');
      expect(message.userName, '观众甲');
      expect(message.userId, 'u1');
      expect(message.text, '你好');
      expect(
        message.sentAt,
        DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
    });

    test('result != 1 视为请求失败', () {
      expect(() => parseKuaishouFeed({'result': 0}), throwsStateError);
    });
  });

  group('快手弹幕会话', () {
    test('首次轮询即连接,批内重复评论去重,close 后停止轮询', () async {
      final payload = kuaishouFixtureJson('feed.json');
      var calls = 0;
      final connector = KuaishouDanmakuConnector(
        ParserHttp(client: FakeKuaishouApi()),
        streamIdFetcher: (roomId) async => 'stream-123',
        feedFetcher: (liveStreamId, cursor) async {
          calls++;
          expect(liveStreamId, 'stream-123');
          expect(cursor, isEmpty);
          return payload;
        },
        minimumPollDelay: Duration.zero,
      );

      final session = await connector.connect(
        const DanmakuSessionRequest(site: 'kuaishou', roomId: 'ks_user_1'),
      );
      final messages = <DanmakuMessage>[];
      final states = <DanmakuSessionState>[];
      final messageSub = session.messages.listen(messages.add);
      final stateSub = session.states.listen(states.add);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(calls, 1);
      expect(messages, hasLength(1), reason: '同批重复评论应被去重');
      expect(messages.single.text, '你好');
      expect(
        states,
        isNot(contains(DanmakuSessionState.disconnected)),
        reason: '首轮成功后会话保持连接',
      );

      await session.close();
      expect(states.last, DanmakuSessionState.disconnected);
      final callsAfterClose = calls;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(calls, callsAfterClose, reason: 'close 后不应继续轮询');

      await messageSub.cancel();
      await stateSub.cancel();
    });

    test('首次轮询失败:进入 disconnected 并抛出', () async {
      final session = KuaishouDanmakuSession(
        'ks_user_1',
        'stream-123',
        (liveStreamId, cursor) async => throw StateError('boom'),
      );
      final states = <DanmakuSessionState>[];
      final stateSub = session.states.listen(states.add);

      await expectLater(session.start(), throwsStateError);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(states.last, DanmakuSessionState.disconnected);

      await session.close();
      await stateSub.cancel();
    });
  });
}
