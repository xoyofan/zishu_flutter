import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:live_parser/live_parser.dart';
import 'package:live_parser/src/platforms/douyin/protobuf_lite.dart';
import 'package:test/test.dart';

import '../../../support/fake_douyin_api.dart';

void main() {
  group('抖音弹幕帧解析', () {
    test('聊天帧:文本/用户/时间归一;needAck 帧回 ack', () async {
      final fake = FakeDouyinApi()
        ..enterResponse = douyinFixture('enter_live.json');
      final transport = _FakeTransport();
      final connector = DouyinDanmakuConnector(
        DouyinClient(httpClient: fake),
        transport: transport,
        heartbeatInterval: const Duration(milliseconds: 50),
      );

      final session = await connector.connect(
        const DanmakuSessionRequest(site: 'douyin', roomId: '123456'),
      );
      final socket = transport.sockets.single;
      expect(transport.lastHeaders?['Origin'], 'https://live.douyin.com');
      expect(
        transport.lastUrl.toString(),
        contains('/webcast/im/push/v2/'),
      );

      final received = <DanmakuMessage>[];
      final subscription = session.messages.listen(received.add);

      socket.push(
        _pushFrame(
          _response(
            message: _message(
              'WebcastChatMessage',
              _chatPayload(text: '你好抖音', nick: '观众甲', userId: 10086),
            ),
            internalExt: 'ext-1',
            needAck: true,
          ),
          logId: 7,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(received, hasLength(1));
      expect(received.single.text, '你好抖音');
      expect(received.single.userName, '观众甲');
      expect(received.single.userId, '10086');
      expect(received.single.roomId, '123456');
      expect(
        received.single.sentAt,
        DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );

      // ack:payloadType=ack,logId=7,payload=internalExt
      final ackFrame = socket.sent
          .map((bytes) => parseDouyinPushFrame(Uint8List.fromList(bytes)))
          .firstWhere((frame) => frame.payloadType == 'ack');
      expect(ackFrame.logId, 7);
      expect(utf8.decode(ackFrame.payload!), 'ext-1');

      // 心跳按周期发送(50ms 间隔,等待两个周期)。
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(
        socket.sent
            .map((bytes) => parseDouyinPushFrame(Uint8List.fromList(bytes)))
            .where((frame) => frame.payloadType == 'hb'),
        isNotEmpty,
      );

      await subscription.cancel();
      await session.close();
    });

    test('gzip 压缩帧可解码', () async {
      final fake = FakeDouyinApi()
        ..enterResponse = douyinFixture('enter_live.json');
      final transport = _FakeTransport();
      final connector = DouyinDanmakuConnector(
        DouyinClient(httpClient: fake),
        transport: transport,
        heartbeatInterval: const Duration(seconds: 30),
      );
      final session = await connector.connect(
        const DanmakuSessionRequest(site: 'douyin', roomId: '123456'),
      );
      final socket = transport.sockets.single;
      final received = <DanmakuMessage>[];
      final subscription = session.messages.listen(received.add);

      final body = Uint8List.fromList(
        _response(
          message: _message(
            'WebcastChatMessage',
            _chatPayload(text: 'gzip弹幕', nick: '观众乙', userId: 1),
          ),
        ),
      );
      final frame = _pushFrame(gzip.encode(body), logId: 1, encoding: 'gzip');
      socket.push(frame);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(received.single.text, 'gzip弹幕');
      await subscription.cancel();
      await session.close();
    });
  });
}

List<int> _varint(int value) {
  final out = <int>[];
  var v = value;
  while (v >= 0x80) {
    out.add((v & 0x7f) | 0x80);
    v >>>= 7;
  }
  out.add(v);
  return out;
}

List<int> _tag(int field, int wire) => _varint((field << 3) | wire);

List<int> _pbString(int field, String text) {
  final bytes = utf8.encode(text);
  return [..._tag(field, 2), ..._varint(bytes.length), ...bytes];
}

List<int> _pbBytes(int field, List<int> bytes) =>
    [..._tag(field, 2), ..._varint(bytes.length), ...bytes];

List<int> _pbUint(int field, int value) => [..._tag(field, 0), ..._varint(value)];

List<int> _chatPayload({
  required String text,
  required String nick,
  required int userId,
}) {
  final user = [
    ..._pbUint(1, userId),
    ..._pbString(3, nick),
  ];
  final common = [..._pbUint(4, 1700000000000)];
  return [
    ..._pbBytes(1, common),
    ..._pbBytes(2, user),
    ..._pbString(3, text),
  ];
}

List<int> _message(String method, List<int> payload) => [
  ..._pbString(1, method),
  ..._pbBytes(2, payload),
];

List<int> _response({
  required List<int> message,
  String internalExt = '',
  bool needAck = false,
}) => [
  ..._pbBytes(1, message),
  if (internalExt.isNotEmpty) ..._pbString(5, internalExt),
  if (needAck) ..._pbUint(9, 1),
];

List<int> _pushFrame(
  List<int> payload, {
  required int logId,
  String encoding = '',
}) => encodeDouyinPushFrame(
  logId: logId,
  encoding: encoding,
  payloadType: 'msg',
  payload: Uint8List.fromList(payload),
);

class _FakeTransport implements DanmakuTransport {
  final sockets = <_FakeSocket>[];
  Uri? lastUrl;
  Map<String, String>? lastHeaders;

  @override
  Future<DanmakuSocket> connect(
    Uri url, {
    List<String>? protocols,
    Map<String, String>? headers,
  }) async {
    lastUrl = url;
    lastHeaders = headers;
    final socket = _FakeSocket();
    sockets.add(socket);
    return socket;
  }
}

class _FakeSocket implements DanmakuSocket {
  final sent = <List<int>>[];
  final _controller = StreamController<Object?>.broadcast();

  void push(List<int> bytes) => _controller.add(bytes);

  @override
  Stream<Object?> get data => _controller.stream;

  @override
  void send(List<int> bytes) => sent.add(bytes);

  @override
  Future<void> close() async => _controller.close();
}
