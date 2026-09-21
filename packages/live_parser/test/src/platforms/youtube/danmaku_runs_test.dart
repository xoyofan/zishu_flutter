/// YouTube 弹幕 runs → 展示文本的单测。
///
/// 重点覆盖「自定义频道 emoji」:协议里它的 `emojiId` 是不透明标识符
/// (形如 `UCxxxx/…`),直接写进正文即用户看到的「弹幕乱码」。
library;

import 'package:live_parser/src/platforms/youtube/danmaku.dart';
import 'package:test/test.dart';

void main() {
  group('youtubeRunsToText', () {
    test('纯文本 run 原样拼接', () {
      expect(
        youtubeRunsToText([
          {'text': 'hello '},
          {'text': '世界'},
        ]),
        'hello 世界',
      );
    });

    test('普通 emoji:emojiId 即 Unicode,直接使用', () {
      expect(
        youtubeRunsToText([
          {'text': 'nice '},
          {
            'emoji': {'emojiId': '😀'},
          },
        ]),
        'nice 😀',
      );
    });

    test('自定义频道 emoji:走 shortcuts,绝不输出不透明 emojiId', () {
      final text = youtubeRunsToText([
        {
          'emoji': {
            'emojiId': 'UCkszU2WH9gy6-EjuTYAytuA/gKQl9haVOQ',
            'shortcuts': [':_wave:'],
          },
        },
        {'text': ' hi'},
      ]);
      expect(text, isNot(contains('UCkszU2WH9gy6')));
      expect(text, ':_wave: hi');
    });

    test('已知短名替换为 Unicode;未知短名保留原文(不伪造)', () {
      expect(
        youtubeRunsToText([
          {
            'emoji': {
              'emojiId': 'UCxxx/custom',
              'shortcuts': [':smile:'],
            },
          },
        ]),
        '😄',
      );
    });

    test('无 shortcuts 且 emojiId 含 / 时丢弃(宁缺勿乱码)', () {
      expect(
        youtubeRunsToText([
          {
            'emoji': {'emojiId': 'UCxxx/custom'},
          },
        ]),
        '',
      );
    });
  });
}
