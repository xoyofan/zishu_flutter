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
        'dms@=100/cst@=1700000000/level@=8/bnn@=粉丝团/bl@=5/'
        'bimg@=https:@S@S@Scdn.example@Sdouyu-fans.png/bc@=16711680/',
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
      expect(message.badges.single.name, '粉丝团');
      expect(message.badges.single.level, 5);
      expect(message.badges.single.url, 'https://cdn.example/douyu-fans.png');
      expect(message.badges.single.color, 0xff0000);
      expect(message.userLevel, 8);
      expect(message.sentAt, DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000));
      expect(message.rawType, 'chatmsg');

      // 心跳按周期发送
      expect(socket.sent.where((s) => s == 'type@=mrkl/'), isNotEmpty);
      await stateSub.cancel();
      await msgSub.cancel();
      await session.close();
    });

    test('真实抓包样本(房间 252140):粉丝牌 bl/fl + diaf/cdiaf 钻粉', () async {
      // 2026-09-26 浏览器直连 wss://danmuproxy.douyu.com:8501 抓到的三条
      // 真实 chatmsg(字段按抓包原样保留):
      //   bl/fl 同值(26/26、25/25);无粉丝牌那条 bl=0 fl 空 brid=0;
      //   diaf=1 与 cdiaf=1 同时下发 → 钻粉。
      final session = await connector.connect(
        const DanmakuSessionRequest(site: 'douyu', roomId: '252140'),
      );
      final socket = transport.sockets.single;
      final received = <DanmakuMessage>[];
      final msgSub = session.messages.listen(received.add);

      socket.pushPacket(
        'type@=chatmsg/rid@=252140/uid@=1/nn@=有牌无钻粉/txt@=A/dms@=4/'
        'level@=41/sahf@=0/bnn@=金咕咕/bl@=26/brid@=252140/'
        'hc@=a076681f25802f44186cd03eef12333c/fl@=26/',
      );
      socket.pushPacket(
        'type@=chatmsg/rid@=252140/uid@=2/nn@=有牌有钻粉/txt@=B/dms@=4/'
        'level@=39/sahf@=0/bnn@=金咕咕/bl@=25/brid@=252140/'
        'hc@=a076681f25802f44186cd03eef12333c/fl@=25/'
        'diaf@=1/cdiaf@=1/dfgm@=24/ds@=1025/ail@=6065@S4144@S/tfid@=723/',
      );
      socket.pushPacket(
        'type@=chatmsg/rid@=252140/uid@=3/nn@=无牌/txt@=C/dms@=4/'
        'level@=13/sahf@=0/bnn@=/bl@=0/brid@=0/hc@=/fl@=/',
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(received, hasLength(3));
      // 样本 1：粉丝牌，钻粉/超粉都没有
      expect(received[0].badgeName, '金咕咕');
      expect(received[0].badgeLevel, 26);
      expect(received[0].badges.map((b) => b.kind), ['']);
      expect(received[0].badges.single.name, '金咕咕');
      // 粉丝牌资源字段：brid = 所属房间，hc = 徽章校验码（只入库，不做显隐闸门）
      expect(received[0].badges.single.badgeRoomId, 252140);
      expect(
        received[0].badges.single.badgeCheckCode,
        'a076681f25802f44186cd03eef12333c',
      );
      expect(received[0].superFan, isFalse);
      expect(received[0].diamondFan, isFalse);
      expect(received[0].nobleLevel, 0);
      expect(received[0].supremeLevel, 0);

      // 样本 2：粉丝牌 + 钻粉(diaf/cdiaf 任一为 1)
      expect(received[1].badges.map((b) => b.kind), ['', 'diamondfan']);
      expect(received[1].badges.last.name, '钻粉');
      expect(received[1].diamondFan, isTrue);

      // 样本 3：无团名/无等级 → 不出粉丝牌徽章（brid/hc 随之不落库）
      expect(received[2].badges, isEmpty);
      expect(received[2].badgeLevel, 0);

      await msgSub.cancel();
      await session.close();
    });

    test('fl 兜底:bl 缺失/为 0 时用同值字段 fl 当粉丝牌等级', () async {
      // 抓包里 bl 与 fl 同值，故 fl 只做兜底；bl 有值时以 bl 为准。
      final session = await connector.connect(
        const DanmakuSessionRequest(site: 'douyu', roomId: '252140'),
      );
      final socket = transport.sockets.single;
      final received = <DanmakuMessage>[];
      final msgSub = session.messages.listen(received.add);

      socket.pushPacket(
        'type@=chatmsg/rid@=252140/nn@=只有fl/txt@=A/dms@=1/'
        'bnn@=金咕咕/bl@=0/fl@=26/brid@=252140/',
      );
      socket.pushPacket(
        'type@=chatmsg/rid@=252140/nn@=bl 优先/txt@=B/dms@=1/'
        'bnn@=金咕咕/bl@=25/fl@=26/brid@=252140/',
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(received.map((m) => m.badgeLevel), [26, 25]);

      await msgSub.cancel();
      await session.close();
    });

    test('身份字段接线:ne/sl/sid/sahf/diafid 归一到 DanmakuMessage', () async {
      // 字段名来自官网 `live-next-player-aside` 的用户归一函数
      // (nobleLevel=e.ne、supremeLevel=+e.sl、supremeSid=e.sid、
      //  isShowSuperIcon=getIsShowSuperIcon(e.sahf))。
      // **取值未确证**：抓包那批弹幕里没有贵族/至尊用户，本例用构造包
      // 验证“字段名 → 模型字段”的接线，不代表官方取值域。
      final session = await connector.connect(
        const DanmakuSessionRequest(site: 'douyu', roomId: '252140'),
      );
      final socket = transport.sockets.single;
      final received = <DanmakuMessage>[];
      final msgSub = session.messages.listen(received.add);

      socket.pushPacket(
        'type@=chatmsg/rid@=252140/nn@=全身份/txt@=A/dms@=1/'
        'ne@=6/sl@=3/sid@=12/sahf@=1/diaf@=1/cdiaf@=1/diafid@=7/'
        'bnn@=金咕咕/bl@=26/fl@=26/',
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final message = received.single;
      expect(message.nobleLevel, 6);
      expect(message.supremeLevel, 3);
      expect(message.supremeSid, 12);
      expect(message.superFan, isTrue);
      expect(message.diamondFan, isTrue);
      expect(message.diamondIconId, 7);
      // 官网聊天行从左到右：粉丝牌 → 至尊 → 贵族 → 超粉 → 钻粉
      expect(
        message.badges.map((b) => b.kind),
        ['', 'supreme', 'noble', 'superfan', 'diamondfan'],
      );
      expect(message.badges[1].level, 3);
      expect(message.badges[2].level, 6);

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
  Future<DanmakuSocket> connect(
    Uri url, {
    List<String>? protocols,
    Map<String, String>? headers,
    bool sendAsText = false,
  }) async {
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
