/// douyu 弹幕 WS 协议编解码（纯逻辑，可测）。
///
/// 从 pure_live lib/core/danmaku/douyu_danmaku.dart 移植（AGPL-3.0，随本仓库传染）：
/// 包格式（小端）：[len(4)][len(4)][type=689(2)][encrypted(1)][reserved(1)][body(utf8)][0(1)]，
/// len = body 长度 + 9；一个 WS 帧可能粘连多个完整包，按各自长度迭代解包。
/// 正文是 douyu STT 格式（`@=` 键值、`/` 分隔、`//` 数组、`@A`/`@S` 转义）。
library;

import 'dart:convert';
import 'dart:typed_data';

import '../core/models/danmaku_message.dart';

class DouyuDanmakuCodec {
  /// 客户端→服务器包类型。
  static const int clientSendToServer = 689;

  /// 浏览器直连的弹幕网关（与 pure_live serverUrl 一致）。
  static const String defaultServerUrl = 'wss://danmuproxy.douyu.com:8506';

  /// 构造一个完整 douyu 包（含 8 字节双长度头 + 2 字节类型 + 2 字节标志 + 正文 + 结尾 0）。
  static Uint8List serialize(String body) {
    final payload = utf8.encode(body);
    final fullMsgLength = 4 + 4 + payload.length + 1;
    final bytes = BytesBuilder();
    final header = ByteData(12);
    header.setUint32(0, fullMsgLength, Endian.little);
    header.setUint32(4, fullMsgLength, Endian.little);
    header.setUint16(8, clientSendToServer, Endian.little);
    header.setUint8(10, 0); // encrypted
    header.setUint8(11, 0); // reserved
    bytes.add(header.buffer.asUint8List());
    bytes.add(payload);
    bytes.addByte(0);
    return bytes.toBytes();
  }

  /// 解包：一个 WS 帧里的所有完整包正文（STT 文本）。
  ///
  /// 长度非法或帧不完整时按规范终止迭代，不抛异常。
  static List<String> deserializePackets(List<int> buffer) {
    final packets = <String>[];
    try {
      final bytes = Uint8List.fromList(buffer);
      var offset = 0;
      while (offset + 12 <= bytes.length) {
        final header = ByteData.sublistView(bytes, offset, offset + 4);
        final fullMsgLength = header.getUint32(0, Endian.little);
        final frameLength = fullMsgLength + 4;
        final bodyLength = fullMsgLength - 9;
        if (fullMsgLength < 9 ||
            bodyLength < 0 ||
            offset + frameLength > bytes.length) {
          break;
        }
        final bodyStart = offset + 12;
        packets.add(
          utf8.decode(
            bytes.sublist(bodyStart, bodyStart + bodyLength),
            allowMalformed: true,
          ),
        );
        offset += frameLength;
      }
    } catch (_) {
      // 脏帧：返回已解出的部分。
    }
    return packets;
  }

  /// douyu STT 文本 → JSON 风格结构（Map/List/String）。
  static dynamic sttToObject(String str) {
    if (str.contains('//')) {
      return [
        for (final field in str.split('//'))
          if (field.isNotEmpty) sttToObject(field),
      ];
    }
    if (str.contains('@=')) {
      final result = <String, dynamic>{};
      for (final field in str.split('/')) {
        if (field.isEmpty) continue;
        final separator = field.indexOf('@=');
        if (separator <= 0) continue;
        final key = field.substring(0, separator);
        final value = unscape(field.substring(separator + 2));
        result[key] = sttToObject(value);
      }
      return result;
    } else if (str.contains('@A=')) {
      return sttToObject(unscape(str));
    }
    return unscape(str);
  }

  /// 反转义：`@S` → `/`，`@A` → `@`。
  static String unscape(String str) =>
      str.replaceAll('@S', '/').replaceAll('@A', '@');

  /// douyu `col` 颜色码 → 0xRRGGBB（0/其他 → null 即默认白）。
  static int? colorForCol(int type) {
    switch (type) {
      case 1:
        return 0xFF0000;
      case 2:
        return 0x1E87F0;
      case 3:
        return 0x7AC84B;
      case 4:
        return 0xFF7F00;
      case 5:
        return 0x9B39F4;
      case 6:
        return 0xFF69B4;
      default:
        return null;
    }
  }

  /// `chatmsg` 包 → [DanmakuMessage]；非聊天包或被过滤规则剔除时返回 null。
  ///
  /// 过滤规则（移植自 pure_live）：
  /// - 新包以 `dms` 标记可见聊天，旧包以粉丝旗标 `if=1` 标记——两者皆无则丢弃；
  /// - `rid` 与当前房间不一致时丢弃（防串房）。
  static DanmakuMessage? chatFromStt(
    Map<String, dynamic> stt, {
    required String roomId,
  }) {
    if (stt['type']?.toString() != 'chatmsg') return null;
    // 见上：不能仅凭 `if!=1` 丢弃——合并 super-chat 后的普通观众包没有 `if`。
    if (stt['dms'] == null && stt['if']?.toString() != '1') return null;
    final packetRoomId = stt['rid']?.toString() ?? '';
    if (packetRoomId.isNotEmpty &&
        roomId.isNotEmpty &&
        packetRoomId != roomId) {
      return null;
    }
    final col = int.tryParse(stt['col']?.toString() ?? '') ?? 0;
    final rawTimestamp = int.tryParse(stt['cst']?.toString() ?? '');
    final ts = rawTimestamp == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            rawTimestamp > 100000000000 ? rawTimestamp : rawTimestamp * 1000,
          );
    final cid = stt['cid']?.toString() ?? '';
    return DanmakuMessage(
      user: stt['nn']?.toString() ?? '',
      text: stt['txt']?.toString() ?? '',
      color: colorForCol(col),
      ts: ts,
      id: cid.isEmpty ? null : 'douyu:$cid',
    );
  }
}
