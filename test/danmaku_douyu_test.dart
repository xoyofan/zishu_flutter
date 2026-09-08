import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zishu_flutter/engine/danmaku/douyu_danmaku_codec.dart';

/// 协议常量对齐 pure_live serializeDouyu：client→server 类型 689（小端）。
void main() {
  group('serialize / deserializePackets', () {
    test('包头字段（双长度/689/加密位/保留位/结尾 0）', () {
      final body = 'type@=loginreq/roomid@=123456/';
      final bytes = DouyuDanmakuCodec.serialize(body);
      final payloadLength = utf8.encode(body).length;
      final fullLength = 4 + 4 + payloadLength + 1;

      final view = ByteData.sublistView(bytes);
      expect(view.getUint32(0, Endian.little), fullLength);
      expect(view.getUint32(4, Endian.little), fullLength);
      expect(view.getUint16(8, Endian.little), 689);
      expect(bytes[10], 0); // encrypted
      expect(bytes[11], 0); // reserved
      expect(bytes.last, 0);
      expect(utf8.decode(bytes.sublist(12, bytes.length - 1)), body);
      expect(bytes.length, 12 + payloadLength + 1);
    });

    test('单包往返', () {
      final packets = DouyuDanmakuCodec.deserializePackets(
        DouyuDanmakuCodec.serialize('type@=mrkl/'),
      );
      expect(packets, ['type@=mrkl/']);
    });

    test('一帧多包全部解出（不丢第二包起的内容）', () {
      final frame = <int>[
        ...DouyuDanmakuCodec.serialize('type@=a/'),
        ...DouyuDanmakuCodec.serialize('type@=b/'),
        ...DouyuDanmakuCodec.serialize('type@=c/'),
      ];
      expect(
        DouyuDanmakuCodec.deserializePackets(frame),
        ['type@=a/', 'type@=b/', 'type@=c/'],
      );
    });

    test('截断帧安全终止，不抛异常', () {
      final frame = DouyuDanmakuCodec.serialize('type@=chatmsg/nn@=u/');
      expect(
        DouyuDanmakuCodec.deserializePackets(frame.sublist(0, 8)),
        isEmpty,
      );
      expect(
        DouyuDanmakuCodec.deserializePackets(
            frame.sublist(0, frame.length - 1)),
        isEmpty,
      );
      expect(DouyuDanmakuCodec.deserializePackets(<int>[]), isEmpty);
    });

    test('心跳包正文为 type@=mrkl/', () {
      final packets = DouyuDanmakuCodec.deserializePackets(
        DouyuDanmakuCodec.serialize('type@=mrkl/'),
      );
      expect(packets.single, contains('type@=mrkl/'));
    });
  });

  group('sttToObject', () {
    test('键值对与分隔符', () {
      final object =
          DouyuDanmakuCodec.sttToObject('type@=chatmsg/nn@=张三/txt@=hi') as Map;
      expect(object['type'], 'chatmsg');
      expect(object['nn'], '张三');
      expect(object['txt'], 'hi');
    });

    test('@S / @A 转义反转义', () {
      expect(DouyuDanmakuCodec.unscape('a@Sb@Ac'), 'a/b@c');
      final object = DouyuDanmakuCodec.sttToObject('txt@=x@Sy') as Map;
      expect(object['txt'], 'x/y');
    });

    test('`//` 数组形态', () {
      final list = DouyuDanmakuCodec.sttToObject('a@=1//b@=2//c@=3') as List;
      expect(list, hasLength(3));
      expect(list[0], {'a': '1'});
      expect(list[1], {'b': '2'});
      expect(list[2], {'c': '3'});
    });

    test('嵌套 @A= 二次解析', () {
      // '@A' 反转义为 '@'，'u@A=x' → 'u@=x' → 再解析为嵌套 Map（对齐 pure_live 行为）。
      final object =
          DouyuDanmakuCodec.sttToObject('type@=chatmsg/nn@=u@A=x') as Map;
      expect(object['nn'], {'u': 'x'});
    });
  });

  group('chatFromStt（chatmsg 过滤与归一化）', () {
    Map<String, dynamic> chat({
      String rid = '123',
      String? dms = '100',
      String? ifFlag,
      String col = '0',
      String cst = '1700000000',
      String cid = '42',
    }) =>
        {
          'type': 'chatmsg',
          'nn': '用户',
          'txt': '弹幕内容',
          'rid': rid,
          'col': col,
          'cst': cst,
          'cid': cid,
          'dms': ?dms,
          'if': ?ifFlag,        };

    test('标准包 → DanmakuMessage', () {
      final message =
          DouyuDanmakuCodec.chatFromStt(chat(), roomId: '123');
      expect(message, isNotNull);
      expect(message!.user, '用户');
      expect(message.text, '弹幕内容');
      expect(message.color, isNull); // col=0 → 默认白
      expect(message.id, 'douyu:42');
      expect(message.ts, DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000));
    });

    test('col 颜色映射', () {
      expect(
        DouyuDanmakuCodec.chatFromStt(chat(col: '2'), roomId: '123')!.color,
        0x1E87F0,
      );
      expect(
        DouyuDanmakuCodec.chatFromStt(chat(col: '1'), roomId: '123')!.color,
        0xFF0000,
      );
      expect(DouyuDanmakuCodec.colorForCol(6), 0xFF69B4);
      expect(DouyuDanmakuCodec.colorForCol(9), isNull);
    });

    test('cst 毫秒/秒双形态', () {
      final ms = DouyuDanmakuCodec.chatFromStt(
        chat(cst: '1700000000000'),
        roomId: '123',
      )!;
      expect(ms.ts, DateTime.fromMillisecondsSinceEpoch(1700000000000));
    });

    test('无 dms 且 if!=1 的旧包丢弃；if=1 放行', () {
      expect(
        DouyuDanmakuCodec.chatFromStt(chat(dms: null, ifFlag: '0'), roomId: '123'),
        isNull,
      );
      expect(
        DouyuDanmakuCodec.chatFromStt(chat(dms: null, ifFlag: '1'), roomId: '123'),
        isNotNull,
      );
    });

    test('rid 与当前房间不一致丢弃（防串房）', () {
      expect(DouyuDanmakuCodec.chatFromStt(chat(rid: '999'), roomId: '123'),
          isNull);
      // 空房间 id 不做 rid 校验。
      expect(DouyuDanmakuCodec.chatFromStt(chat(rid: '999'), roomId: ''),
          isNotNull);
    });

    test('非 chatmsg 包返回 null', () {
      expect(
        DouyuDanmakuCodec.chatFromStt({'type': 'mrkl'}, roomId: '123'),
        isNull,
      );
    });
  });
}
