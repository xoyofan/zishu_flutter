import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:live_parser/live_parser.dart';
import 'package:live_parser/src/platforms/huya/danmaku.dart';
import 'package:live_parser/src/platforms/huya/tars_codec.dart';
import 'package:test/test.dart';

import '../../../support/fake_huya_api.dart';

String _fixture(String name) => File('test/fixtures/huya/$name').readAsStringSync();

/// 构造服务端推送帧:WebSocketCommand(cmdType=7){HYPushMessage{uri, msg}}。
Uint8List _pushFrame(int uri, Uint8List msg) {
  final push = TarsWriter()
    ..writeInt(0, 0)
    ..writeInt(uri, 1)
    ..writeBytes(msg, 2);
  final frame = TarsWriter()
    ..writeInt(7, 0)
    ..writeBytes(push.takeBytes(), 1);
  return frame.takeBytes();
}

Uint8List _chatNotice({required String nick, required String content, int color = 0xff7f00}) {
  final notice = TarsWriter()
    ..writeStruct((userInfo) {
      userInfo.writeString(nick, 2);
    }, 0)
    ..writeString(content, 3)
    ..writeStruct((format) {
      format.writeInt(color, 0);
    }, 6);
  return notice.takeBytes();
}

void main() {
  late FakeHuyaApi fake;
  late FakeDanmakuTransport transport;
  late HuyaDanmakuConnector connector;

  setUp(() {
    fake = FakeHuyaApi()
      ..profileRoomResponse = jsonDecode(_fixture('profile_room_live.json'));
    transport = FakeDanmakuTransport();
    connector = HuyaDanmakuConnector(
      parserHttp: ParserHttp(client: fake),
      transport: transport,
      heartbeatInterval: const Duration(milliseconds: 50),
    );
  });

  test('连接:先取 profileRoom topSid 再入组(live:/chat: 双分组)', () async {
    final session = await connector.connect(
      const DanmakuSessionRequest(site: 'huya', roomId: '9527'),
    );

    expect(transport.lastUrl.toString(), 'wss://cdnws.api.huya.com:443');
    expect(transport.sockets, hasLength(1));

    final frame = decodeTarsCommandFrame(
      Uint8List.fromList(transport.sockets.single.rawSent.first),
    );
    expect(frame.cmdType, 16);
    final reader = TarsReader(frame.data);
    expect(reader.readStringList(0), ['live:2650134', 'chat:2650134']);
    await session.close();
  });

  test('弹幕推送 uri=1400 归一(昵称/内容/颜色);uri=8006 在线人数', () async {
    final session = await connector.connect(
      const DanmakuSessionRequest(site: 'huya', roomId: '9527'),
    );
    final socket = transport.sockets.single;
    final received = <DanmakuMessage>[];
    final sub = session.messages.listen(received.add);

    socket.pushBytes(_pushFrame(1400, _chatNotice(nick: '张三', content: '你好虎牙')));
    socket.pushBytes(
      _pushFrame(
        1400,
        _chatNotice(nick: '彩字', content: '红色弹幕', color: 0xff0000),
      ),
    );
    final online = TarsWriter()..writeInt(123456, 0);
    socket.pushBytes(_pushFrame(8006, online.takeBytes()));
    // 未知 uri 忽略
    socket.pushBytes(_pushFrame(9999, Uint8List(0)));
    // 心跳应答(cmdType=6)忽略不抛
    final ack = TarsWriter()..writeInt(6, 0);
    socket.pushBytes(ack.takeBytes());

    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(received, hasLength(3));
    expect(received[0].type, DanmakuMessageType.chat);
    expect(received[0].userName, '张三');
    expect(received[0].text, '你好虎牙');
    expect(received[0].roomId, '9527');
    expect(received[1].color, 0xff0000, reason: '正色保留');
    expect(received[2].type, DanmakuMessageType.other);
    expect(received[2].text, '123456');

    await sub.cancel();
    await session.close();
  });

  test('心跳周期发送(cmdType=5)与 close 释放', () async {
    final session = await connector.connect(
      const DanmakuSessionRequest(site: 'huya', roomId: '9527'),
    );
    final socket = transport.sockets.single;
    final states = <DanmakuSessionState>[];
    final sub = session.states.listen(states.add);

    await Future<void>.delayed(const Duration(milliseconds: 120));
    final heartbeats = socket.rawSent
        .map((bytes) => decodeTarsCommandFrame(Uint8List.fromList(bytes)))
        .where((frame) => frame.cmdType == 5)
        .length;
    expect(heartbeats, greaterThanOrEqualTo(2), reason: '50ms 间隔内应至少两次心跳');

    await session.close();
    expect(socket.closeCount, 1);
    expect(states, contains(DanmakuSessionState.disconnected));
    await sub.cancel();
  });

  test('房间未开播(无 topSid)抛 ParserHttpException', () async {
    fake.profileRoomResponse = jsonDecode(_fixture('profile_room_offline.json'));
    await expectLater(
      connector.connect(const DanmakuSessionRequest(site: 'huya', roomId: '9527')),
      throwsA(isA<ParserHttpException>()),
    );
  });
}

class FakeDanmakuTransport implements DanmakuTransport {
  final sockets = <FakeDanmakuSocket>[];
  Uri? lastUrl;

  @override
  Future<DanmakuSocket> connect(
    Uri url, {
    List<String>? protocols,
    Map<String, String>? headers,
  }) async {
    lastUrl = url;
    final socket = FakeDanmakuSocket();
    sockets.add(socket);
    return socket;
  }
}

class FakeDanmakuSocket implements DanmakuSocket {
  final rawSent = <List<int>>[];
  int closeCount = 0;

  final _controller = StreamController<Object?>.broadcast();

  void pushBytes(Uint8List bytes) => _controller.add(bytes);

  @override
  Stream<Object?> get data => _controller.stream;

  @override
  void send(List<int> bytes) => rawSent.add(List<int>.from(bytes));

  @override
  Future<void> close() async {
    closeCount++;
  }
}
