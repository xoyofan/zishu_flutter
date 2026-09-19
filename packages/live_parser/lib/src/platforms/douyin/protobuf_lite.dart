/// 抖音弹幕最小 protobuf 读写(无第三方依赖)。
///
/// 移植自 SFVideoLive `live-shared/src/protocol/douyin/protobuf-lite.ts` +
/// `push-frame.ts`,仅保留弹幕聊天所需字段。
library;

import 'dart:convert';
import 'dart:typed_data';

import '../../models/models.dart';

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
    this.badgeLevel = 0,
    this.userLevel = 0,
    this.segments = const [],
  });

  final String user;
  final String userId;
  final String text;
  final int sentAtMs;

  /// 粉丝团等级(协议无可靠团名,badgeName 留空 —— 对齐 web
  /// douyinTextFallback 只显示等级圆盘)。
  final int badgeLevel;

  /// 荣誉/消费等级(User.payGrade 的 field 6)。
  final int userLevel;

  /// 富文本段:仅当协议携带表情 image piece 时非空;纯文本消息保持空
  /// (UI 直接渲染 [text])。契约见 DanmakuMessage.segments。
  final List<DanmakuSegment> segments;
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

/// User badge 项(#21/#61 repeated)里的粉丝团等级:
/// 项结构 #1 = 官方 CDN 图(如 `ranklist_fansclub_pop_advanced_badge_10`),
/// #8 = 描述子消息(#3 = 等级,#4 = 名称)。荣誉等级图(`new_user_grade_level`)
/// 不是粉丝团,跳过;无子消息时回落 URL 正则(2026-09 实测字段)。
int _parseFansBadgeLevel(Uint8List badgeBuf) {
  final fields = decodePbFields(badgeBuf);
  final url = pbFieldString(fields, 1);
  if (url.isEmpty || !url.toLowerCase().contains('fansclub')) return 0;
  final desc = pbFieldBytes(fields, 8);
  if (desc != null) {
    final level = pbFieldUint(decodePbFields(desc), 3);
    if (level > 0) return level;
  }
  final match = RegExp(r'badge_(\d+)').firstMatch(url);
  return match != null ? int.tryParse(match.group(1)!) ?? 0 : 0;
}

/// User 荣誉/消费等级:payGrade(#23) 的 field 6(field 1 是钻石总数,勿混用)。
int _parseUserPayGradeLevel(Uint8List? userBuf) {
  if (userBuf == null) return 0;
  final payGrade = pbFieldBytes(decodePbFields(userBuf), 23);
  if (payGrade == null) return 0;
  return pbFieldUint(decodePbFields(payGrade), 6);
}

/// Image 字段 #1(repeated bytes)中第一个 http(s) URL(web 真源
/// parseImageUrlList,protobuf-lite.ts:149-157)。
String _firstHttpUrl(List<PbField> imageFields) {
  for (final field in imageFields) {
    if (field.num != 1 || field.wire != 2) continue;
    final url = utf8.decode(field.value as Uint8List, allowMalformed: true).trim();
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
  }
  return '';
}

/// TextPieceImage(#8.#1 = Image)里的表情:名字取 Image.#8(Content)的
/// #1/#4,图片 URL 取 Image.#1 第一个 http(s) 地址(web 真源
/// parseTextPieceImage + parseImageContentName,protobuf-lite.ts:441-461;
/// zishu 旧实现 `_textPieceImageName` 同源,这里补上 url)。
(String, String) _textPieceImage(Uint8List imageBuf) {
  final imageFields = decodePbFields(imageBuf);
  final url = _firstHttpUrl(imageFields);
  final contentBuf = pbFieldBytes(imageFields, 8);
  if (contentBuf == null) return ('', url);
  final contentFields = decodePbFields(contentBuf);
  final name = pbFieldString(contentFields, 1);
  return (name.isNotEmpty ? name : pbFieldString(contentFields, 4), url);
}

/// 单个 TextPiece:优先文本(#3),其次表情 image(#8),再次 @用户(#4);
/// 对齐 web 真源 parseDouyinTextMessage 的 piece 分支顺序
/// (protobuf-lite.ts:506-522)。返回 (拼入正文, 表情段或 null)。
(String, DanmakuSegment?) _parseTextPiece(Uint8List piece) {
  final pieceFields = decodePbFields(piece);
  final text = pbFieldString(pieceFields, 3);
  if (text.isNotEmpty) return (text, null);
  final imagePieceBuf = pbFieldBytes(pieceFields, 8);
  if (imagePieceBuf != null) {
    final imageBuf = pbFieldBytes(decodePbFields(imagePieceBuf), 1);
    if (imageBuf != null) {
      final (name, url) = _textPieceImage(imageBuf);
      final trimmed = name.trim();
      if (trimmed.isNotEmpty) {
        // formatDouyinEmojiName(protobuf-lite.ts:466-472):补 [ ] 括号。
        final display = trimmed.startsWith('[') && trimmed.endsWith(']')
            ? trimmed
            : '[$trimmed]';
        return (display, DanmakuSegment.emoji(text: display, url: url));
      }
    }
  }
  // @用户 piece(parseTextPieceUser,protobuf-lite.ts:463-471)按纯文本展开。
  final userBuf = pbFieldBytes(pieceFields, 4);
  if (userBuf != null) {
    final name = _parseUserName(userBuf);
    if (name.isNotEmpty) return ('@$name', null);
  }
  return ('', null);
}

/// 相邻文本段合并(对齐 web pushTextSegment,protobuf-lite.ts:478-491)。
void _appendTextSegment(List<DanmakuSegment> segments, String text) {
  if (text.isEmpty) return;
  final last = segments.isEmpty ? null : segments.last;
  if (last != null && !last.isEmoji) {
    segments[segments.length - 1] = DanmakuSegment.text('${last.text}$text');
    return;
  }
  segments.add(DanmakuSegment.text(text));
}

/// 解析 Text(富文本)字段:合并文本、表情名;并产出表情段。
///
/// 对齐 web 真源 parseDouyinTextMessage(protobuf-lite.ts:494-527):
/// pieces(#4 repeated)逐段展开,文本段相邻合并;无 pieces 时回退
/// #2/#1 整串文本。纯文本(无表情段)时 segments 留空 —— UI 直接渲染
/// text,与「纯文本消息 segments 保持空」契约一致。
({String text, List<DanmakuSegment> segments}) _parseDouyinText(Uint8List? textBuf) {
  if (textBuf == null) return (text: '', segments: const []);
  final fields = decodePbFields(textBuf);
  final fallback = pbFieldString(fields, 2).isNotEmpty
      ? pbFieldString(fields, 2)
      : pbFieldString(fields, 1);
  final pieces = pbRepeatedBytes(fields, 4);
  if (pieces.isEmpty) return (text: fallback, segments: const []);

  final buffer = StringBuffer();
  final segments = <DanmakuSegment>[];
  for (final piece in pieces) {
    final (text, emoji) = _parseTextPiece(piece);
    if (emoji != null) {
      buffer.write(text);
      segments.add(emoji);
      continue;
    }
    buffer.write(text);
    _appendTextSegment(segments, text);
  }
  final joined = buffer.toString();
  if (joined.isEmpty) return (text: fallback, segments: const []);
  final hasEmoji = segments.any((segment) => segment.isEmoji);
  return (
    text: joined,
    segments: hasEmoji ? List.unmodifiable(segments) : const [],
  );
}

/// 解析 WebcastChatMessage / WebcastEmojiChatMessage 负载。
DouyinChatItem? parseDouyinChatPayload(Uint8List payload) {
  final fields = decodePbFields(payload);
  // 富文本 Text(#22)优先;纯文本兜底 #3,再富文本 #4(WebcastEmojiChatMessage
  // 的 Text,web parseEmojiChatMessage 同用 parseDouyinTextMessage),最后 #5。
  var primary = _parseDouyinText(pbFieldBytes(fields, 22));
  var text = primary.text;
  var segments = primary.segments;
  if (text.isEmpty) text = pbFieldString(fields, 3);
  if (text.isEmpty) {
    primary = _parseDouyinText(pbFieldBytes(fields, 4));
    text = primary.text;
    segments = primary.segments;
  }
  if (text.isEmpty) text = pbFieldString(fields, 5);
  if (text.isEmpty) return null;

  final userBuf = pbFieldBytes(fields, 2);
  final user = _parseUserName(userBuf);
  final userId = userBuf == null
      ? ''
      : (pbFieldUint(decodePbFields(userBuf), 1) != 0
            ? '${pbFieldUint(decodePbFields(userBuf), 1)}'
            : '');

  // 徽章:粉丝团等级(#21/#61 repeated,任一命中即用)+ 荣誉等级(payGrade)。
  var badgeLevel = 0;
  var userLevel = 0;
  if (userBuf != null) {
    final userFields = decodePbFields(userBuf);
    for (final buf in [...pbRepeatedBytes(userFields, 61), ...pbRepeatedBytes(userFields, 21)]) {
      badgeLevel = _parseFansBadgeLevel(buf);
      if (badgeLevel > 0) break;
    }
    userLevel = _parseUserPayGradeLevel(userBuf);
  }
  return DouyinChatItem(
    user: user.isEmpty ? '观众' : user,
    userId: userId,
    text: text,
    sentAtMs: parsePbCommonCreateTime(payload),
    badgeLevel: badgeLevel,
    userLevel: userLevel,
    segments: segments,
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
