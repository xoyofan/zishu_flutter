/// 字幕行缓冲:多句并存 + 定长存活(用户口径 5s)。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:zishu_flutter/src/features/play/application/caption_lines.dart';

void main() {
  DateTime t0() => DateTime(2026, 9, 21, 12);

  group('CaptionLineBuffer 定长存活', () {
    test('新句追加在尾部,顺序即上屏顺序', () {
      final buffer = CaptionLineBuffer();
      buffer.add('第一句', t0());
      buffer.add('第二句', t0().add(const Duration(seconds: 1)));

      expect(buffer.lines.map((l) => l.text).toList(), ['第一句', '第二句']);
    });

    test('存活 5s:未到点保留,到点删除', () {
      final buffer = CaptionLineBuffer();
      buffer.add('你好', t0());

      expect(buffer.prune(t0().add(const Duration(seconds: 4))), isFalse);
      expect(buffer.lines, hasLength(1));

      expect(buffer.prune(t0().add(const Duration(seconds: 5))), isTrue);
      expect(buffer.lines, isEmpty);
    });

    test('各句独立计时:先来的先消失,后来的继续显示', () {
      final buffer = CaptionLineBuffer();
      buffer.add('早', t0());
      buffer.add('晚', t0().add(const Duration(seconds: 3)));

      buffer.prune(t0().add(const Duration(seconds: 5)));
      expect(buffer.lines.map((l) => l.text).toList(), ['晚']);
    });

    test('nextExpiryIn 指向最早到期的一句;空缓冲返回 null', () {
      final buffer = CaptionLineBuffer();
      expect(buffer.nextExpiryIn(t0()), isNull);

      buffer.add('早', t0());
      buffer.add('晚', t0().add(const Duration(seconds: 2)));
      expect(buffer.nextExpiryIn(t0()), const Duration(seconds: 5));
      expect(
        buffer.nextExpiryIn(t0().add(const Duration(seconds: 3))),
        const Duration(seconds: 2),
      );
    });

    test('已达到期时刻时剩余为 0(不出现负值)', () {
      final buffer = CaptionLineBuffer();
      buffer.add('x', t0());
      expect(
        buffer.nextExpiryIn(t0().add(const Duration(seconds: 9))),
        Duration.zero,
      );
    });

    test('超上限丢最旧,不无限累积', () {
      final buffer = CaptionLineBuffer();
      for (var i = 0; i < CaptionLineBuffer.maxLines + 3; i++) {
        buffer.add('句$i', t0());
      }
      expect(buffer.lines, hasLength(CaptionLineBuffer.maxLines));
      expect(buffer.lines.first.text, '句3');
    });
  });
}
