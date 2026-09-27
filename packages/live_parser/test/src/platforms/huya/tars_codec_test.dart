import 'dart:convert';
import 'dart:typed_data';

import 'package:live_parser/src/platforms/huya/tars_codec.dart';
import 'package:live_parser/src/platforms/huya/tars_exception.dart';
import 'package:test/test.dart';

void main() {
  group('TarsWriter 固定字节', () {
    test('小整数 int8', () {
      final w = TarsWriter()..writeInt(5, 0);
      expect(w.takeBytes(), [0, 5]);
    });

    test('零值 zeroTag 单字节', () {
      final w = TarsWriter()..writeInt(0, 0);
      expect(w.takeBytes(), [12]);
    });

    test('字符串 string1', () {
      final w = TarsWriter()..writeString('AB', 0);
      expect(w.takeBytes(), [6, 2, 65, 66]);
    });

    test('扩展 tag(tag=16 走第二字节)', () {
      final w = TarsWriter()..writeInt(3, 16);
      expect(w.takeBytes(), [240, 16, 3]);
    });

    test('joinGroup 请求体结构', () {
      final w = TarsWriter()
        ..writeStringList(['live:1', 'chat:1'], 0)
        ..writeString('', 1);
      expect(w.takeBytes(), [
        9, 0, 2, // list head, int8 head, size=2
        6, 6, 108, 105, 118, 101, 58, 49, // 'live:1'
        6, 6, 99, 104, 97, 116, 58, 49, // 'chat:1'
        22, 0, // token: string1 head(tag1), len 0
      ]);
    });

    test('命令帧(cmdType + bytes)', () {
      final w = TarsWriter()
        ..writeInt(16, 0)
        ..writeBytes(Uint8List.fromList([9, 9]), 1);
      expect(w.takeBytes(), [0, 16, 29, 0, 0, 2, 9, 9]);
    });
  });

  group('TarsReader 往返', () {
    test('整数自适应宽度', () {
      for (final value in [0, 5, 127, -128, 32767, -32768, 70000, -70000, 5000000000]) {
        final w = TarsWriter()..writeInt(value, 3);
        final r = TarsReader(w.takeBytes());
        expect(r.readInt(3), value);
      }
    });

    test('字符串与转义内容', () {
      final w = TarsWriter()..writeString('弹幕@内容/', 0);
      expect(TarsReader(w.takeBytes()).readString(0), '弹幕@内容/');

      // STRING1 长度是**无符号单字节**:128-255 字符的串(官网模板 URL 常见,
      // 如 biz12 定制牌 NewFloor 模板 139 字符)曾按有符号读成负数 → 误判
      // out of range。回归:139 字符(≥128)必须原样读回。
      final longUrl = 'https://fileserver.cdn.huya.com/web_admin_badgeNewFloorResource/'
          '5f84f95775344a1aa5c5ff4903f85818/<size>_<ua>_<status>_<sfmark>_<level>.webp';
      expect(longUrl.length, greaterThan(128));
      final w2 = TarsWriter()..writeString(longUrl, 0);
      expect(TarsReader(w2.takeBytes()).readString(0), longUrl);
    });

    test('bytes(SimpleList)', () {
      final payload = Uint8List.fromList([1, 2, 3, 250]);
      final w = TarsWriter()..writeBytes(payload, 1);
      expect(TarsReader(w.takeBytes()).readBytes(1), payload);
    });

    test('嵌套结构读取', () {
      final w = TarsWriter()
        ..writeStruct((inner) {
          inner.writeString('张三', 2);
        }, 0)
        ..writeString('你好', 3)
        ..writeStruct((format) {
          format.writeInt(0xff7f00, 0);
        }, 6);
      final r = TarsReader(w.takeBytes());
      var nick = '';
      r.readStruct(0, (userInfo) {
        nick = userInfo.readString(2);
      });
      expect(r.readString(3), '你好');
      var color = 0;
      r.readStruct(6, (format) {
        color = format.readInt(0);
      });
      expect(nick, '张三');
      expect(color, 0xff7f00);
    });

    test('缺失字段返回 fallback', () {
      final w = TarsWriter()..writeString('only', 0);
      final r = TarsReader(w.takeBytes());
      expect(r.readString(5, fallback: 'fallback'), 'fallback');
      expect(r.readInt(9, fallback: 42), 42);
    });

    test('坏数据抛 TarsDecodeException', () {
      final r = TarsReader(Uint8List.fromList([0x06, 200]));
      expect(() => r.readString(0), throwsA(isA<TarsDecodeException>()));
    });
  });

  group('decodeTarsCommandFrame', () {
    test('解析 cmdType 与 data', () {
      final data = Uint8List.fromList(utf8.encode('payload'));
      final w = TarsWriter()
        ..writeInt(7, 0)
        ..writeBytes(data, 1);
      final frame = decodeTarsCommandFrame(w.takeBytes());
      expect(frame.cmdType, 7);
      expect(frame.data, data);
    });
  });
}
