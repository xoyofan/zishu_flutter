import 'dart:async';
import 'dart:convert';

import 'package:live_parser/live_parser.dart';
import 'package:test/test.dart';

import '../../../support/fake_soop_api.dart';

void main() {
  group('SOOP 弹幕会话(fake transport)', () {
    late FakeSoopApi http;
    late FakeDanmakuTransport transport;
    late SoopDanmakuConnector connector;

    setUp(() {
      http = FakeSoopApi()..detailResponse = soopFixture('detail_live.json');
      transport = FakeDanmakuTransport();
      connector = SoopDanmakuConnector(
        ParserHttp(client: http),
        transport: transport,
        heartbeatInterval: const Duration(milliseconds: 50),
      );
    });

    test('连接:chat 子协议 + WS 地址,握手/进房/心跳包按协议发送', () async {
      final session = await connector.connect(
        const DanmakuSessionRequest(site: 'soop', roomId: 'testbj'),
      );
      final socket = transport.sockets.single;

      expect(transport.lastUrl.toString(), 'wss://chat.sooplive.co.kr:8088/Websocket/testbj');
      expect(transport.lastProtocols, ['chat']);
      expect(
        utf8.decode(socket.sent.first),
        '\x1b\x09000100000600\x0c\x0c\x0c16\x0c',
      );

      // join 包延迟 200ms 发出:chatNo 长度 5 + 6 = 11 → 000011。
      await Future<void>.delayed(const Duration(milliseconds: 250));
      final packets = socket.sent.map(utf8.decode).toList();
      final joinPacket = packets.firstWhere(
        (packet) => packet.startsWith('\x1b\x090002'),
      );
      expect(joinPacket, startsWith('\x1b\x09000200001100\x0c12345'));
      expect(joinPacket, endsWith('\x0c\x0c\x0c\x0c\x0c'));

      // 心跳按周期发送。
      expect(packets, contains('\x1b\x09000000000100\x0c'));

      await session.close();
    });

    test('聊天帧字段归一,控制帧被过滤', () async {
      final session = await connector.connect(
        const DanmakuSessionRequest(site: 'soop', roomId: 'testbj'),
      );
      final socket = transport.sockets.single;
      final received = <DanmakuMessage>[];
      final subscription = session.messages.listen(received.add);

      socket.push(soopFrame(['\x1b\x09000100000600', 'hello', '1', '2', '3', '4', '张三']));
      socket.push(soopFrame(['\x1b\x09000100000600', '1', 'x', 'x', 'x', 'x', '系统']));
      socket.push(soopFrame(['\x1b\x09000100000600', '-1', 'x', 'x', 'x', 'x', '系统']));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(received, hasLength(1));
      expect(received.single.type, DanmakuMessageType.chat);
      expect(received.single.text, 'hello');
      expect(received.single.userName, '张三');
      expect(received.single.roomId, 'testbj');

      await subscription.cancel();
      await session.close();
    });
  });
}

List<int> soopFrame(List<String> fields) =>
    utf8.encode('${fields.join('\x0c')}\x0c');

class FakeDanmakuTransport implements DanmakuTransport {
  final sockets = <FakeDanmakuSocket>[];
  Uri? lastUrl;
  List<String>? lastProtocols;

  @override
  Future<DanmakuSocket> connect(
    Uri url, {
    List<String>? protocols,
    Map<String, String>? headers,
  }) async {
    lastUrl = url;
    lastProtocols = protocols;
    final socket = FakeDanmakuSocket();
    sockets.add(socket);
    return socket;
  }
}

class FakeDanmakuSocket implements DanmakuSocket {
  final sent = <List<int>>[];
  final _controller = StreamController<Object?>.broadcast();

  void push(List<int> frame) => _controller.add(frame);

  @override
  Stream<Object?> get data => _controller.stream;

  @override
  void send(List<int> bytes) => sent.add(bytes);

  @override
  Future<void> close() async => _controller.close();
}
