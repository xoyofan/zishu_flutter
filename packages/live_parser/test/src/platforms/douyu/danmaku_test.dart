import 'dart:async';
import 'dart:typed_data';

import 'package:live_parser/live_parser.dart';
import 'package:live_parser/src/platforms/douyu/danmaku.dart';
import 'package:live_parser/src/platforms/douyu/douyu_site.dart';
import 'package:test/test.dart';

void main() {
  group('帧编码', () {
    test('loginreq 帧固定字节(头 12 字节 + body + \\0)', () {
      final frame = encodeDouyuFrame('type@=loginreq/roomid@=9527/');
      final body = 'type@=loginreq/roomid@=9527/'.codeUnits;
      // len = 8 + 28 + 1 = 37
      expect(frame, hasLength(12 + body.length + 1));
      expect(frame.sublist(0, 12), [0x25, 0, 0, 0, 0x25, 0, 0, 0, 0xB1, 0x02, 0, 0]);
      expect(frame.sublist(12, 12 + body.length), body);
      expect(frame.last, 0);
    });

    test('帧长字段随 body 增长', () {
      final frame = encodeDouyuFrame('type@=mrkl/');
      // len = 8 + 11 + 1 = 20
      expect(frame.sublist(0, 4), [20, 0, 0, 0]);
    });
  });

  group('帧解码', () {
    test('单包往返', () {
      const stt = 'type@=chatmsg/txt@=hello/';
      expect(decodeDouyuPackets(encodeDouyuFrame(stt)), [stt]);
    });

    test('一帧多包按各自长度迭代', () {
      final first = encodeDouyuFrame('type@=loginres/');
      final second = encodeDouyuFrame('type@=chatmsg/txt@=hi/');
      final merged = Uint8List.fromList([...first, ...second]);
      expect(decodeDouyuPackets(merged), ['type@=loginres/', 'type@=chatmsg/txt@=hi/']);
    });

    test('截断帧安全停止', () {
      final frame = encodeDouyuFrame('type@=loginres/');
      final truncated = frame.sublist(0, frame.length - 4);
      expect(decodeDouyuPackets(truncated), isEmpty);
    });
  });

  group('STT 解析', () {
    test('平铺键值 + 转义还原', () {
      final parsed = parseDouyuStt('type@=chatmsg/txt@=hello@Sworld@A2/nn@=张三/');
      expect(parsed, {
        'type': 'chatmsg',
        'txt': 'hello/world@2',
        'nn': '张三',
      });
    });

    test('数组:顶层 // 拆分为条目数组(值侧递归同路径)', () {
      expect(parseDouyuStt('a@=1//b@=2'), [
        {'a': '1'},
        {'b': '2'},
      ]);
    });

    test('纯标量', () {
      expect(parseDouyuStt('plain'), 'plain');
      expect(parseDouyuStt(''), '');
    });
  });

  group('颜色映射', () {
    test('col 1-6 与默认', () {
      expect(douyuChatColor(1), 0xff0000);
      expect(douyuChatColor(2), 0x1e87f0);
      expect(douyuChatColor(3), 0x7ac84b);
      expect(douyuChatColor(4), 0xff7f00);
      expect(douyuChatColor(5), 0x9b39f4);
      expect(douyuChatColor(6), 0xff69b4);
      expect(douyuChatColor(0), 0);
      expect(douyuChatColor(99), 0);
    });
  });

  group('会话(fake transport)', () {
    late FakeDanmakuTransport transport;
    late DouyuDanmakuConnector connector;

    setUp(() {
      transport = FakeDanmakuTransport();
      connector = DouyuDanmakuConnector(
        transport: transport,
        heartbeatInterval: const Duration(milliseconds: 50),
      );
    });

    test('连接即发 loginreq + joingroup(gid=-9999),端口池轮换', () async {
      final session = await connector.connect(
        const DanmakuSessionRequest(site: 'douyu', roomId: '9527'),
      );
      expect(transport.lastUrl.toString(), 'wss://danmuproxy.douyu.com:8501/');
      expect(transport.sockets.single.sent, [
        'type@=loginreq/roomid@=9527/',
        'type@=joingroup/rid@=9527/gid@=-9999/',
      ]);
      await session.close();

      final session2 = await connector.connect(
        const DanmakuSessionRequest(site: 'douyu', roomId: '9527'),
      );
      expect(transport.lastUrl.toString(), 'wss://danmuproxy.douyu.com:8502/');
      await session2.close();
    });

    test('loginres -> connected;chatmsg 归一字段;心跳 mrkl 周期发送', () async {
      final session = await connector.connect(
        const DanmakuSessionRequest(site: 'douyu', roomId: '9527'),
      );
      final socket = transport.sockets.single;
      final states = <DanmakuSessionState>[];
      final stateSub = session.states.listen(states.add);
      final received = <DanmakuMessage>[];
      final msgSub = session.messages.listen(received.add);

      socket.pushPacket('type@=loginres/userid@=0/');
      socket.pushPacket(
        'type@=chatmsg/rid@=9527/nn@=张三/uid@=10086/txt@=你好@S世界/col@=2/'
        'dms@=100/cst@=1700000000/level@=8/bnn@=粉丝团/bl@=5/',
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(states, contains(DanmakuSessionState.connected));
      expect(received, hasLength(1));
      final message = received.single;
      expect(message.type, DanmakuMessageType.chat);
      expect(message.userName, '张三');
      expect(message.userId, '10086');
      expect(message.text, '你好/世界');
      expect(message.color, 0x1e87f0);
      expect(message.badgeName, '粉丝团');
      expect(message.badgeLevel, 5);
      expect(message.userLevel, 8);
      expect(message.sentAt, DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000));
      expect(message.rawType, 'chatmsg');

      // 心跳按周期发送
      expect(socket.sent.where((s) => s == 'type@=mrkl/'), isNotEmpty);
      await stateSub.cancel();
      await msgSub.cancel();
      await session.close();
    });

    test('pingreq 回 pingresp;dms/if 过滤与 rid 防串房', () async {
      final session = await connector.connect(
        const DanmakuSessionRequest(site: 'douyu', roomId: '9527'),
      );
      final socket = transport.sockets.single;
      final received = <DanmakuMessage>[];
      final msgSub = session.messages.listen(received.add);

      socket.pushPacket('type@=pingreq/');
      socket.pushPacket('type@=chatmsg/rid@=9527/nn@=a/txt@=新包@S带dms/dms@=1/');
      socket.pushPacket('type@=chatmsg/rid@=9527/nn@=a/txt@=老包if1/if@=1/');
      socket.pushPacket('type@=chatmsg/rid@=9527/nn@=a/txt@=不可见弹幕被丢弃/');
      socket.pushPacket('type@=chatmsg/rid@=9999/nn@=a/txt@=串房弹幕被丢弃/');

      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(socket.sent, contains('type@=pingresp/'));
      expect(received.map((m) => m.text), ['新包/带dms', '老包if1']);
      expect(received.every((m) => m.roomId == '9527'), isTrue);

      await msgSub.cancel();
      await session.close();
      expect(socket.closeCount, 1);
      expect(socket.sent.last, 'type@=pingresp/', reason: 'close 后不再有新消息发出');
    });

    test('registry 中斗鱼声明 danmaku 能力并给出连接器', () async {
      final registration = buildDouyuRegistration(danmakuTransport: transport);
      expect(registration.capabilities.danmaku, isTrue);
      expect(registration.danmaku, isA<DanmakuConnector>());
      expect(registration.danmaku!.capabilities.danmaku, isTrue);
    });
  });
}

class FakeDanmakuTransport implements DanmakuTransport {
  final sockets = <FakeDanmakuSocket>[];
  Uri? lastUrl;

  @override
  Future<DanmakuSocket> connect(Uri url) async {
    lastUrl = url;
    final socket = FakeDanmakuSocket();
    sockets.add(socket);
    return socket;
  }
}

class FakeDanmakuSocket implements DanmakuSocket {
  final sent = <String>[];
  int closeCount = 0;

  final _controller = StreamController<Object?>.broadcast();

  void pushPacket(String stt) => _controller.add(encodeDouyuFrame(stt));

  @override
  Stream<Object?> get data => _controller.stream;

  @override
  void send(List<int> bytes) => sent.add(decodeDouyuPackets(bytes).join('|'));

  @override
  Future<void> close() async {
    closeCount++;
  }
}
