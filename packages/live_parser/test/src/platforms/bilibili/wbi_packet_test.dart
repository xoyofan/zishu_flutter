import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:live_parser/src/platforms/bilibili/packet.dart';
import 'package:live_parser/src/platforms/bilibili/wbi.dart';
import 'package:test/test.dart';

void main() {
  group('WBI', () {
    test('mixinKey 混淆表固定向量', () {
      expect(getWbiMixinKey('abc', 'def'), 'cdfabe');
    });

    test('signWbi 固定向量(wts 固定)', () {
      final signed = signWbi(
        {'room_id': '9527', 'platform': 'web'},
        '0123456789abcdef0123456789abcdef',
        wts: 1700000000,
      );
      expect(signed['wts'], '1700000000');
      expect(signed['w_rid'], 'eaffa35d31e630c618d0be1a568353ff');
      expect(signed['room_id'], '9527');
    });

    test('含 ! 的参数被剔除', () {
      final signed = signWbi({'keyword': 'ok!', 'room_id': '1'}, 'k', wts: 1);
      expect(signed.containsKey('keyword'), isFalse);
      expect(signed['room_id'], '1');
    });
  });

  group('B 站二进制包', () {
    test('编码:头 16 字节 + body,字段按 BE', () {
      final packet = encodeBiliPacket(7, utf8.encode('{"uid":0}'));
      final view = ByteData.sublistView(packet);
      expect(view.getInt32(0, Endian.big), packet.length);
      expect(view.getInt16(4, Endian.big), 16);
      expect(view.getInt16(6, Endian.big), 0);
      expect(view.getInt32(8, Endian.big), 7);
      expect(view.getInt32(12, Endian.big), 1);
      expect(packet.length, 16 + 9);
    });

    test('一帧多包往返', () {
      final merged = BytesBuilder()
        ..add(encodeBiliPacket(8, utf8.encode('{}')))
        ..add(encodeBiliPacket(5, utf8.encode('x')));
      final packets = decodeBiliPackets(merged.toBytes());
      expect(packets.map((p) => p.operation).toList(), [8, 5]);
    });

    test('截断帧抛 BiliPacketFormatException', () {
      final packet = encodeBiliPacket(2, const []);
      expect(
        () => decodeBiliPackets(Uint8List.fromList(packet.sublist(0, 8))),
        throwsA(isA<BiliPacketFormatException>()),
      );
    });

    test('protover=2 zlib 解压;protover=3 显式不支持', () {
      final body = Uint8List.fromList(
        ZLibEncoder().convert(utf8.encode('{"cmd":"DANMU_MSG"}')),
      );
      final decoded = decompressBiliBody(body, 2);
      expect(utf8.decode(decoded), '{"cmd":"DANMU_MSG"}');
      expect(
        () => decompressBiliBody(body, 3),
        throwsA(isA<BiliPacketFormatException>()),
      );
    });
  });
}
