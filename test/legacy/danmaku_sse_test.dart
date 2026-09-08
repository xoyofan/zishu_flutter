import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zishu_flutter/legacy/danmaku/danmaku_backoff.dart';
import 'package:zishu_flutter/legacy/core/models/danmaku_message.dart';
import 'package:zishu_flutter/legacy/danmaku/sse_danmaku_channel.dart';

void main() {
  group('buildSseUrl', () {
    test('拼接 base + site + room 并做 URI 编码', () {
      final url = buildSseUrl('http://127.0.0.1:8766/', 'douyin', '100 1');
      expect(
        url.toString(),
        'http://127.0.0.1:8766/api/douyin/danmaku/stream?room=100%201',
      );
      expect(url.path, '/api/douyin/danmaku/stream');
      expect(url.queryParameters['room'], '100 1');
    });

    test('容忍 base 尾部斜杠', () {
      expect(
        buildSseUrl('http://h:1', 'douyu', '9').path,
        '/api/douyu/danmaku/stream',
      );
      expect(
        buildSseUrl('http://h:1/', 'douyu', '9').path,
        '/api/douyu/danmaku/stream',
      );
    });
  });

  group('SseEventParser', () {
    test('解析 event+data 帧', () {
      final parser = SseEventParser();
      final events = parser.push(
        'event: ready\ndata: ok\n\nevent: chat\ndata: {"user":"u"}\n\n',
      );
      expect(events, hasLength(2));
      expect(events[0].event, 'ready');
      expect(events[0].data, 'ok');
      expect(events[1].event, 'chat');
      expect(events[1].data, '{"user":"u"}');
    });

    test('跨 chunk 粘包/半包', () {
      final parser = SseEventParser();
      expect(parser.push('event: chat\nda'), isEmpty);
      final events = parser.push('ta: {"text":"hi"}\n\n');
      expect(events, hasLength(1));
      expect(events.single.event, 'chat');
      expect(events.single.data, '{"text":"hi"}');
    });

    test('多行 data 以 \\n 连接，注释与空行忽略', () {
      final parser = SseEventParser();
      final events = parser.push(': keep-alive\ndata: line1\ndata: line2\n\n');
      expect(events.single.data, 'line1\nline2');
    });

    test('无 event: 前缀时默认 message', () {
      final parser = SseEventParser();
      final events = parser.push('data: ping\n\n');
      expect(events.single.event, 'message');
    });
  });

  group('parseChatJson / DanmakuMessage.fromSseJson', () {
    test('完整 payload', () {
      final message = parseChatJson(
        jsonEncode({
          'id': 'abc',
          'user': '张三',
          'text': '你好',
          'color': 0x1E87F0,
          'badge': '粉丝团 21',
          'rich': {'emoticon': 'x'},
        }),
      );
      expect(message, isNotNull);
      expect(message!.id, 'abc');
      expect(message.user, '张三');
      expect(message.text, '你好');
      expect(message.color, 0x1E87F0);
      expect(message.badge, '粉丝团 21');
      expect(message.rich, {'emoticon': 'x'});
    });

    test('color 支持 #RRGGBB 字符串', () {
      expect(DanmakuMessage.parseColor('#ff0000'), 0xFF0000);
      expect(DanmakuMessage.parseColor('00ff00'), 0x00FF00);
      expect(DanmakuMessage.parseColor(0xFFFFFF), 0xFFFFFF);
      expect(DanmakuMessage.parseColor(null), isNull);
      expect(DanmakuMessage.parseColor('nothex'), isNull);
    });

    test('缺 id 时按 room-seq 兜底', () {
      final message = parseChatJson(
        '{"user":"a","text":"b"}',
        seq: 7,
        room: '99',
      );
      expect(message!.id, '99-7');
    });

    test('非法 JSON / 非对象 / 空消息返回 null', () {
      expect(parseChatJson('not json'), isNull);
      expect(parseChatJson('[1,2]'), isNull);
      expect(parseChatJson('{}'), isNull);
      expect(parseChatJson('{"user":"","text":""}'), isNull);
    });
  });

  group('DanmakuBackoff', () {
    test('指数退避并封顶 30s', () {
      expect(DanmakuBackoff.delay(0), const Duration(seconds: 1));
      expect(DanmakuBackoff.delay(1), const Duration(seconds: 2));
      expect(DanmakuBackoff.delay(2), const Duration(seconds: 4));
      expect(DanmakuBackoff.delay(4), const Duration(seconds: 16));
      expect(DanmakuBackoff.delay(5), const Duration(seconds: 30));
      expect(DanmakuBackoff.delay(20), const Duration(seconds: 30));
      expect(DanmakuBackoff.delay(-3), const Duration(seconds: 1));
    });
  });
}
