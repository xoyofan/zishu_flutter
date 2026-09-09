/// B 站弹幕二进制包:16 字节头(BE)+ body;一帧可含多包。
///
/// packetLength(4) | headerLength(2)=16 | protocolVersion(2) | operation(4) | sequence(4)。
/// protocolVersion:0=JSON 文本,1=Int32 人气,2=zlib,3=brotli(本实现不支持)。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const int kBiliPacketHeaderLength = 16;

/// 操作码。
abstract final class BiliPacketOp {
  static const int heartbeat = 2;
  static const int heartbeatAck = 3;
  static const int message = 5;
  static const int auth = 7;
  static const int authAck = 8;
}

/// 编码一个完整包。
Uint8List encodeBiliPacket(int operation, List<int> body, {int protocolVersion = 0}) {
  final packetLength = kBiliPacketHeaderLength + body.length;
  final buffer = Uint8List(packetLength);
  final view = ByteData.view(buffer.buffer);
  view.setInt32(0, packetLength, Endian.big);
  view.setInt16(4, kBiliPacketHeaderLength, Endian.big);
  view.setInt16(6, protocolVersion, Endian.big);
  view.setInt32(8, operation, Endian.big);
  view.setInt32(12, 1, Endian.big);
  buffer.setAll(kBiliPacketHeaderLength, body);
  return buffer;
}

class BiliPacket {
  const BiliPacket({
    required this.protocolVersion,
    required this.operation,
    required this.body,
  });

  final int protocolVersion;
  final int operation;
  final Uint8List body;
}

class BiliPacketFormatException implements Exception {
  const BiliPacketFormatException(this.message);

  final String message;

  @override
  String toString() => 'BiliPacketFormatException: $message';
}

/// 解析一帧内的完整包序列;截断/非法长度抛 [BiliPacketFormatException]。
List<BiliPacket> decodeBiliPackets(Uint8List data) {
  final packets = <BiliPacket>[];
  var offset = 0;
  while (offset + kBiliPacketHeaderLength <= data.length) {
    final view = ByteData.sublistView(data, offset);
    final packetLength = view.getInt32(0, Endian.big);
    final headerLength = view.getInt16(4, Endian.big);
    final protocolVersion = view.getInt16(6, Endian.big);
    final operation = view.getInt32(8, Endian.big);

    if (headerLength < kBiliPacketHeaderLength ||
        packetLength < headerLength ||
        offset + packetLength > data.length) {
      throw BiliPacketFormatException(
        'invalid frame: offset=$offset packet=$packetLength header=$headerLength total=${data.length}',
      );
    }

    packets.add(
      BiliPacket(
        protocolVersion: protocolVersion,
        operation: operation,
        body: Uint8List.sublistView(data, offset + headerLength, offset + packetLength),
      ),
    );
    offset += packetLength;
  }
  if (offset != data.length) {
    throw BiliPacketFormatException('trailing bytes: parsed=$offset total=${data.length}');
  }
  return packets;
}

/// 解压 op=5 的 body(protover=2 zlib;protover=3 brotli 不支持,显式报错)。
Uint8List decompressBiliBody(Uint8List body, int protocolVersion) {
  switch (protocolVersion) {
    case 2:
      return Uint8List.fromList(ZLibDecoder().convert(body));
    default:
      throw BiliPacketFormatException('unsupported protocol version: $protocolVersion');
  }
}

String decodeUtf8(List<int> bytes) => utf8.decode(bytes, allowMalformed: true);
