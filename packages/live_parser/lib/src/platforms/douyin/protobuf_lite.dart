/// 抖音弹幕最小 protobuf 读写(无第三方依赖)。
///
/// 移植自 SFVideoLive `live-shared/src/protocol/douyin/protobuf-lite.ts` +
/// `push-frame.ts`,仅保留弹幕聊天所需字段。
library;

import 'dart:convert';
import 'dart:typed_data';

/// 一个 protobuf 字段:wire=0 时 value 为 int,wire=2 时为 [Uint8List]。
class PbField {
  const PbField(this.num, this.wire, this.value);

  final int num;
  final int wire;
  final Object value;
}

(int, int) _readVarint(Uint8List buf, int pos) {
  var result = 0;
  var shift = 0;
  var offset = pos;
  while (offset < buf.length) {
    final byte = buf[offset++];
    result |= (byte & 0x7f) << shift;
    if ((byte & 0x80) == 0) break;
    shift += 7;
    if (shift > 63) break;
  }
  return (result, offset);
}

List<PbField> decodePbFields(Uint8List buf) {
  final fields = <PbField>[];
  var pos = 0;
  while (pos < buf.length) {
    final (tag, next) = _readVarint(buf, pos);
    if (next <= pos) break;
    pos = next;
    final fieldNum = tag >>> 3;
    final wire = tag & 7;
    if (wire == 0) {
      final (value, p2) = _readVarint(buf, pos);
      if (p2 <= pos) break;
      fields.add(PbField(fieldNum, wire, value));
      pos = p2;
    } else if (wire == 2) {
      final (len, p2) = _readVarint(buf, pos);
      if (p2 <= pos) break;
      pos = p2;
      final end = pos + len;
      if (end > buf.length || end < pos) break;
      fields.add(PbField(fieldNum, wire, buf.sublist(pos, end)));
      pos = end;
    } else if (wire == 1) {
      pos += 8;
    } else if (wire == 5) {
      pos += 4;
    } else {
      break;
    }
  }
  return fields;
}

String pbFieldString(List<PbField> fields, int num) {
  for (final field in fields) {
    if (field.num != num || field.wire != 2) continue;
    return utf8.decode(field.value as Uint8List, allowMalformed: true);
  }
  return '';
}

Uint8List? pbFieldBytes(List<PbField> fields, int num) {
  for (final field in fields) {
    if (field.num != num || field.wire != 2) continue;
    return field.value as Uint8List;
  }
  return null;
}

int pbFieldUint(List<PbField> fields, int num) {
  for (final field in fields) {
    if (field.num != num || field.wire != 0) continue;
    return field.value as int;
  }
  return 0;
}

bool pbFieldBool(List<PbField> fields, int num) => pbFieldUint(fields, num) == 1;

List<Uint8List> pbRepeatedBytes(List<PbField> fields, int num) {
  final result = <Uint8List>[];
  for (final field in fields) {
    if (field.num != num || field.wire != 2) continue;
    result.add(field.value as Uint8List);
  }
  return result;
}

List<int> _writeVarint(int value) {
  final out = <int>[];
  var v = value & 0xFFFFFFFF;
  while (v >= 0x80) {
    out.add((v & 0x7f) | 0x80);
    v >>>= 7;
  }
  out.add(v);
  return out;
}

List<int> _writeTag(int fieldNum, int wireType) =>
    _writeVarint((fieldNum << 3) | wireType);

Uint8List _encodeStringField(int fieldNum, String text) {
  final bytes = utf8.encode(text);
  return Uint8List.fromList([
    ..._writeTag(fieldNum, 2),
    ..._writeVarint(bytes.length),
    ...bytes,
  ]);
}

Uint8List _encodeBytesField(int fieldNum, Uint8List payload) =>
    Uint8List.fromList([
      ..._writeTag(fieldNum, 2),
      ..._writeVarint(payload.length),
      ...payload,
    ]);

Uint8List _encodeUintField(int fieldNum, int value) =>
    Uint8List.fromList([..._writeTag(fieldNum, 0), ..._writeVarint(value)]);

/// 编码 PushFrame(客户端心跳/ack;encoding 供测试构造压缩帧)。
Uint8List encodeDouyinPushFrame({
  int logId = 0,
  String payloadType = '',
  Uint8List? payload,
  String encoding = '',
}) {
  final chunks = <List<int>>[];
  if (logId != 0) chunks.add(_encodeUintField(2, logId));
  if (encoding.isNotEmpty) chunks.add(_encodeStringField(6, encoding));
  if (payloadType.isNotEmpty) chunks.add(_encodeStringField(7, payloadType));
  if (payload != null) chunks.add(_encodeBytesField(8, payload));
  return Uint8List.fromList([for (final chunk in chunks) ...chunk]);
}

/// 归一化 Unix 时间戳到毫秒;非法/过旧返回 0。
int normalizeDouyinUnixMs(int value) {
  if (value <= 0) return 0;
  if (value > 100000000000) return value;
  if (value > 1000000000) return value * 1000;
  return 0;
}

int parsePbCommonCreateTime(Uint8List payload) {
  final commonBuf = pbFieldBytes(decodePbFields(payload), 1);
  if (commonBuf == null) return 0;
  return normalizeDouyinUnixMs(pbFieldUint(decodePbFields(commonBuf), 4));
}

/// 一条归一后的抖音聊天项。
class DouyinChatItem {
  const DouyinChatItem({
    required this.user,
    required this.userId,
    required this.text,
    required this.sentAtMs,
  });

  final String user;
  final String userId;
  final String text;
  final int sentAtMs;
}

String _parseUserName(Uint8List? userBuf) {
  if (userBuf == null) return '';
  final fields = decodePbFields(userBuf);
  final name = pbFieldString(fields, 3);
  if (name.isNotEmpty) return name;
  final alt = pbFieldString(fields, 38);
  if (alt.isNotEmpty) return alt;
  return pbFieldString(fields, 1028);
}

String _textPieceImageName(Uint8List imageBuf) {
  final imageFields = decodePbFields(imageBuf);
  final contentBuf = pbFieldBytes(imageFields, 8);
  if (contentBuf == null) return '';
  final contentFields = decodePbFields(contentBuf);
  final name = pbFieldString(contentFields, 1);
  return name.isNotEmpty ? name : pbFieldString(contentFields, 4);
}

String _parseTextPiece(Uint8List piece) {
  final pieceFields = decodePbFields(piece);
  final text = pbFieldString(pieceFields, 3);
  if (text.isNotEmpty) return text;
  final imagePieceBuf = pbFieldBytes(pieceFields, 8);
  if (imagePieceBuf != null) {
    final imageBuf = pbFieldBytes(decodePbFields(imagePieceBuf), 1);
    if (imageBuf != null) {
      final name = _textPieceImageName(imageBuf).trim();
      if (name.isNotEmpty) {
        return name.startsWith('[') && name.endsWith(']') ? name : '[$name]';
      }
    }
  }
  return '';
}

/// 解析 Text(富文本)字段:合并文本、表情名;取不到时用 field 2/1 兜底。
String _parseDouyinText(Uint8List? textBuf) {
  if (textBuf == null) return '';
  final fields = decodePbFields(textBuf);
  final fallback = pbFieldString(fields, 2).isNotEmpty
      ? pbFieldString(fields, 2)
      : pbFieldString(fields, 1);
  final pieces = pbRepeatedBytes(fields, 4);
  if (pieces.isEmpty) return fallback;
  final buffer = StringBuffer();
  for (final piece in pieces) {
    buffer.write(_parseTextPiece(piece));
  }
  final joined = buffer.toString();
  return joined.isNotEmpty ? joined : fallback;
}

/// 解析 WebcastChatMessage / WebcastEmojiChatMessage 负载。
DouyinChatItem? parseDouyinChatPayload(Uint8List payload) {
  final fields = decodePbFields(payload);
  final textBuf = pbFieldBytes(fields, 22);
  var text = textBuf != null ? _parseDouyinText(textBuf) : '';
  if (text.isEmpty) text = pbFieldString(fields, 3);
  if (text.isEmpty) text = _parseDouyinText(pbFieldBytes(fields, 4));
  if (text.isEmpty) text = pbFieldString(fields, 5);
  if (text.isEmpty) return null;

  final userBuf = pbFieldBytes(fields, 2);
  final user = _parseUserName(userBuf);
  final userId = userBuf == null
      ? ''
      : (pbFieldUint(decodePbFields(userBuf), 1) != 0
            ? '${pbFieldUint(decodePbFields(userBuf), 1)}'
            : '');
  return DouyinChatItem(
    user: user.isEmpty ? '观众' : user,
    userId: userId,
    text: text,
    sentAtMs: parsePbCommonCreateTime(payload),
  );
}

/// 一帧 push payload 的解析结果(Response 层,logId 在外层 PushFrame)。
class DouyinPushFrameResult {
  const DouyinPushFrameResult({
    required this.needAck,
    required this.internalExt,
    required this.chats,
  });

  final bool needAck;
  final String internalExt;
  final List<DouyinChatItem> chats;
}

/// 解析服务端 push 帧:payload 为 gzip 时由调用方先解压后传入。
DouyinPushFrameResult parseDouyinResponsePayload(Uint8List body) {
  final response = decodePbFields(body);
  final needAck = pbFieldBool(response, 9);
  final internalExt = pbFieldString(response, 5);
  final chats = <DouyinChatItem>[];
  for (final msgBuf in pbRepeatedBytes(response, 1)) {
    final msgFields = decodePbFields(msgBuf);
    final method = pbFieldString(msgFields, 1);
    final payload = pbFieldBytes(msgFields, 2);
    if (payload == null) continue;
    if (method == 'WebcastChatMessage' ||
        method == 'WebcastEmojiChatMessage') {
      final chat = parseDouyinChatPayload(payload);
      if (chat != null) chats.add(chat);
    }
  }
  return DouyinPushFrameResult(
    needAck: needAck,
    internalExt: internalExt,
    chats: chats,
  );
}

/// 解析外层 PushFrame:返回 (logId, encoding, payloadType, payload)。
({int logId, String encoding, String payloadType, Uint8List? payload})
parseDouyinPushFrame(Uint8List frame) {
  final fields = decodePbFields(frame);
  return (
    logId: pbFieldUint(fields, 2),
    encoding: pbFieldString(fields, 6),
    payloadType: pbFieldString(fields, 7),
    payload: pbFieldBytes(fields, 8),
  );
}
