import 'package:live_parser/live_parser.dart';
import 'package:test/test.dart';

import '../../../support/fake_youtube_api.dart';

void main() {
  late FakeYoutubeApi fake;

  setUp(() {
    fake = FakeYoutubeApi()
      ..browseHtml = youtubeFixture('live.html')
      ..watchHtml = youtubeFixture('watch_live.html');
  });

  test('浏览:/live 页提取 videoId、标题与列表封面变体', () async {
    final browse = YoutubeBrowseRepository(ParserHttp(client: fake));
    final result = await browse.fetchRooms(
      const RoomListRequest(site: 'youtube', page: 1, limit: 10),
    );

    expect(result.rooms, hasLength(2));
    expect(result.rooms.first.roomId, 'AAAAAAAAAAA');
    expect(result.rooms.first.title, '房间一');
    // 列表卡片固定用 16:9 原生的 mqdefault(320×180,实测 11.8KB):
    // ytInitialData 的 hq720 是 1280×720/170KB,而卡片实宽仅 226~320px。
    expect(
      result.rooms.first.cover,
      'https://i.ytimg.com/vi/AAAAAAAAAAA/mqdefault.jpg',
      reason: '列表封面应改用小变体,不得直接用 ytInitialData 的大图 URL',
    );
    expect(result.rooms[1].cover, 'https://i.ytimg.com/vi/BBBBBBBBBBB/mqdefault.jpg');
    expect(result.rooms.first.category, '正在直播');
    expect(result.hasMore, isFalse);

    final categories = await browse.fetchCategories('youtube');
    expect(
      categories.groups.single.items.map((item) => item.name).toList(),
      ['正在直播', '游戏', '音乐', '新闻'],
    );
  });

  test('弹幕:continuation token + 轮询消息归一', () async {
    final connector = YoutubeDanmakuConnector(
      ParserHttp(client: fake),
      fetcher: (continuation) async {
        expect(continuation, 'TOKEN-1');
        return {
          'continuationContents': {
            'liveChatContinuation': {
              'actions': [
                {
                  'addChatItemAction': {
                    'item': {
                      'liveChatTextMessageRenderer': {
                        'id': 'm1',
                        'authorName': {'simpleText': '观众甲'},
                        'message': {
                          'runs': [
                            {'text': '你好'},
                            {
                              'emoji': {
                                'shortcuts': [':)'],
                              },
                            },
                          ],
                        },
                        'timestampUsec': '1700000000000000',
                      },
                    },
                  },
                },
              ],
              'continuations': [
                {
                  'timedContinuationData': {
                    'continuation': 'TOKEN-2',
                    'timeoutMs': 2000,
                  },
                },
              ],
            },
          },
        };
      },
      minimumPollDelay: Duration.zero,
    );

    final session = await connector.connect(
      const DanmakuSessionRequest(site: 'youtube', roomId: 'dQw4w9WgXcQ'),
    );
    final messages = <DanmakuMessage>[];
    final states = <DanmakuSessionState>[];
    final messageSub = session.messages.listen(messages.add);
    final stateSub = session.states.listen(states.add);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(messages, hasLength(1));
    expect(messages.single.text, '你好:)');
    expect(messages.single.userName, '观众甲');
    expect(
      messages.single.sentAt,
      DateTime.fromMillisecondsSinceEpoch(1700000000000),
    );
    expect(states, isNot(contains(DanmakuSessionState.disconnected)));

    await session.close();
    expect(states.last, DanmakuSessionState.disconnected);
    await messageSub.cancel();
    await stateSub.cancel();
  });

  test('弹幕:emoji run 短代码归一,emojiId Unicode 优先,未知名保留', () async {
    final connector = YoutubeDanmakuConnector(
      ParserHttp(client: fake),
      fetcher: (continuation) async {
        expect(continuation, 'TOKEN-1');
        return {
          'continuationContents': {
            'liveChatContinuation': {
              'actions': [
                {
                  'addChatItemAction': {
                    'item': {
                      'liveChatTextMessageRenderer': {
                        'id': 'e1',
                        'authorName': {'simpleText': '观众乙'},
                        'message': {
                          'runs': [
                            {'text': '来了'},
                            // 真机证据形态(2026-09-20):emojiId 为短代码 →
                            // shortcut 过映射表(:crossed_flags: → 🎌)。
                            {
                              'emoji': {
                                'emojiId': ':crossed_flags:',
                                'shortcuts': [':crossed_flags:'],
                              },
                            },
                            {
                              'emoji': {
                                'emojiId': ':grinning_face_with_sweat:',
                                'shortcuts': [':grinning_face_with_sweat:'],
                              },
                            },
                            // emojiId 已是 Unicode → 直接采用,不查表。
                            {
                              'emoji': {
                                'emojiId': '🔥',
                                'shortcuts': [':fire:'],
                              },
                            },
                            // 表外未知名 → 原文保留(数据诚实)。
                            {
                              'emoji': {
                                'shortcuts': [':totally_unknown_code:'],
                              },
                            },
                          ],
                        },
                        'timestampUsec': '1700000000000000',
                      },
                    },
                  },
                },
              ],
              'continuations': [
                {
                  'timedContinuationData': {
                    'continuation': 'TOKEN-2',
                    'timeoutMs': 2000,
                  },
                },
              ],
            },
          },
        };
      },
      minimumPollDelay: Duration.zero,
    );

    final session = await connector.connect(
      const DanmakuSessionRequest(site: 'youtube', roomId: 'dQw4w9WgXcQ'),
    );
    final messages = <DanmakuMessage>[];
    final sub = session.messages.listen(messages.add);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(messages, hasLength(1));
    expect(messages.single.text, '来了🎌😅🔥:totally_unknown_code:');

    await session.close();
    await sub.cancel();
  });

  test('未开播(无 conversationBar)抛错', () async {
    fake.watchHtml = '<html><body>no chat</body></html>';
    final connector = YoutubeDanmakuConnector(ParserHttp(client: fake));
    await expectLater(
      connector.connect(
        const DanmakuSessionRequest(site: 'youtube', roomId: 'dQw4w9WgXcQ'),
      ),
      throwsA(isA<ParserHttpException>()),
    );
  });
}
