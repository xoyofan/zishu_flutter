import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:live_parser/live_parser.dart';
import 'package:live_parser/src/platforms/bilibili/danmaku.dart';
import 'package:live_parser/src/platforms/bilibili/packet.dart';
import 'package:live_parser/src/platforms/douyu/json_utils.dart';
import 'package:test/test.dart';

import '../../../support/fake_bilibili_api.dart';

String _fixture(String name) => File('test/fixtures/bilibili/$name').readAsStringSync();

Uint8List _danmuFrame({
  required String cmd,
  required String userName,
  required String text,
  List<Object?>? medalInfo,
  List<Object?>? ulInfo,
  Map<String, Object?>? metaUser, // 新协议 info[0][15].user
}) {
  final meta = <Object?>[0, 16, 999, 0xff7f00, 1700000000];
  if (metaUser != null) {
    while (meta.length < 15) {
      meta.add(null);
    }
    meta.add({'user': metaUser});
  }
  final message = jsonEncode({
    'cmd': cmd,
    'info': [
      meta,
      text,
      [6900, userName],
      ?medalInfo,
      ?ulInfo,
    ],
  });
  // 真实协议:op=5 body 解压后仍是完整包流(内层 protover=0 op=5 body=JSON)
  final inner = encodeBiliPacket(BiliPacketOp.message, utf8.encode(message));
  final compressed = Uint8List.fromList(ZLibEncoder().convert(inner));
  return encodeBiliPacket(BiliPacketOp.message, compressed, protocolVersion: 2);
}

void main() {
  late FakeBilibiliApi fake;
  late FakeDanmakuTransport transport;
  late BilibiliDanmakuConnector connector;

  setUp(() {
    fake = FakeBilibiliApi()
      ..danmuInfoResponse = jsonDecode(_fixture('danmu_info.json'))
      ..spiResponse = {
        'code': 0,
        'data': {'b_3': 'buvid-xyz'},
      };
    transport = FakeDanmakuTransport();
    connector = BilibiliDanmakuConnector(
      parserHttp: ParserHttp(client: fake),
      transport: transport,
      heartbeatInterval: const Duration(milliseconds: 50),
    );
  });

  test('连接:getDanmuInfo 取 token/host,发送 auth(op=7, protover=2)', () async {
    final session = await connector.connect(
      const DanmakuSessionRequest(site: 'bilibili', roomId: '9527'),
    );

    expect(transport.lastUrl.toString(), 'wss://broadcastlv-chat-1.bilivideo.com/sub');

    // 首帧应为 auth 包
    final authPacket =
        decodeBiliPackets(Uint8List.fromList(transport.sockets.single.rawSent.first)).single;
    expect(authPacket.operation, BiliPacketOp.auth);
    expect(authPacket.protocolVersion, 0);
    final auth = jsonMapOf(jsonDecode(utf8.decode(authPacket.body)));
    expect(auth['roomid'], 9527);
    expect(auth['protover'], 2, reason: '无 brotli 依赖,固定 zlib');
    expect(auth['key'], 'danmaku-token-abc');
    expect(auth['buvid'], 'buvid-xyz');
    expect(auth['uid'], 0, reason: '带 buvid 时 uid 固定 0');
    await session.close();
  });

  test('authAck(op=8) → connected;DANMU_MSG(zlib)归一;op=3 人气', () async {
    final session = await connector.connect(
      const DanmakuSessionRequest(site: 'bilibili', roomId: '9527'),
    );
    final socket = transport.sockets.single;
    final received = <DanmakuMessage>[];
    final states = <DanmakuSessionState>[];
    final subMessages = session.messages.listen(received.add);
    final subStates = session.states.listen(states.add);

    // 认证应答
    socket.pushBytes(encodeBiliPacket(BiliPacketOp.authAck, utf8.encode('{"code":0}')));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(states, contains(DanmakuSessionState.connected));
    expect(
      socket.rawSent
          .map((bytes) => decodeBiliPackets(Uint8List.fromList(bytes)).single.operation)
          .toList(),
      contains(BiliPacketOp.heartbeat),
      reason: '认证确认后立即发送首次心跳',
    );

    // zlib 压缩的 DANMU_MSG
    socket.pushBytes(_danmuFrame(cmd: 'DANMU_MSG:4:0:2:2:2:0', userName: '张三', text: '你好B站'));
    // op=3 人气
    final popularity = ByteData(4)..setInt32(0, 654321, Endian.big);
    socket.pushBytes(encodeBiliPacket(BiliPacketOp.heartbeatAck, popularity.buffer.asUint8List()));

    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(received, hasLength(2));
    expect(received[0].type, DanmakuMessageType.chat);
    expect(received[0].userName, '张三');
    expect(received[0].text, '你好B站');
    expect(received[0].color, 0xff7f00);
    expect(received[1].rawType, 'bilibili:popularity');
    expect(received[1].text, '654321');

    await subMessages.cancel();
    await subStates.cancel();
    await session.close();
  });

  test('DANMU_MSG 协议重推去重:user+text 兜底 key(对齐 web bilibiliDanmakuDedup)', () async {
    final session = await connector.connect(
      const DanmakuSessionRequest(site: 'bilibili', roomId: '9527'),
    );
    final socket = transport.sockets.single;
    final received = <DanmakuMessage>[];
    final sub = session.messages.listen(received.add);
    socket.pushBytes(encodeBiliPacket(BiliPacketOp.authAck, utf8.encode('{"code":0}')));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    socket.pushBytes(_danmuFrame(cmd: 'DANMU_MSG:4:0:2:2:2:0', userName: '张三', text: '你好B站'));
    // SSE/代理链路对同一条的重复推送(用户+正文完全相同)。
    socket.pushBytes(_danmuFrame(cmd: 'DANMU_MSG:4:0:2:2:2:0', userName: '张三', text: '你好B站'));
    // 不同用户同正文:不是重推,应保留。
    socket.pushBytes(_danmuFrame(cmd: 'DANMU_MSG:4:0:2:2:2:0', userName: '李四', text: '你好B站'));
    // 同用户不同正文:应保留。
    socket.pushBytes(_danmuFrame(cmd: 'DANMU_MSG:4:0:2:2:2:0', userName: '张三', text: '换一条'));
    // 人气(op=3)不属于 chat 域,不受去重影响。
    final popularity = ByteData(4)..setInt32(0, 654321, Endian.big);
    socket.pushBytes(encodeBiliPacket(BiliPacketOp.heartbeatAck, popularity.buffer.asUint8List()));

    await Future<void>.delayed(const Duration(milliseconds: 10));

    final chats = received.where((m) => m.type == DanmakuMessageType.chat).toList();
    expect(chats, hasLength(3), reason: '协议重推(用户+正文同)应被滤掉,其余保留');
    expect(
      received.where((m) => m.rawType == 'bilibili:popularity'),
      hasLength(1),
      reason: '人气消息不参与 chat 去重',
    );

    await sub.cancel();
    await session.close();
  });

  test('DANMU_MSG 徽章提取:粉丝牌(info[3])+ 用户等级 UL(info[4])', () async {
    final session = await connector.connect(
      const DanmakuSessionRequest(site: 'bilibili', roomId: '9527'),
    );
    final socket = transport.sockets.single;
    final received = <DanmakuMessage>[];
    final sub = session.messages.listen(received.add);
    socket.pushBytes(encodeBiliPacket(BiliPacketOp.authAck, utf8.encode('{"code":0}')));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    socket.pushBytes(_danmuFrame(
      cmd: 'DANMU_MSG:4:0:2:2:2:0',
      userName: '张三',
      text: '带徽章',
      medalInfo: [12, '提督骑士团', 12, 0xffffff, 0xaa00aa, 0x00ffff, 0, 0, 0xbb00bb, 0xcc00cc],
      ulInfo: [31, 0, -1],
    ));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final m = received.single;
    expect(m.badgeName, '提督骑士团');
    expect(m.badgeLevel, 12);
    expect(m.userLevel, 31);
    // 老结构十进制色:web 口径 [8]=start/[9]=end/[5]=border;老结构无
    // text/level 色(web 同样只在 v2 新协议取),应为 0。
    expect(m.badgeColorStart, 0xbb00bb);
    expect(m.badgeColorEnd, 0xcc00cc);
    expect(m.badgeColorBorder, 0x00ffff);
    expect(m.badgeTextColor, 0);
    expect(m.badgeColorLevel, 0);

    await sub.cancel();
    await session.close();
  });

  test('DANMU_MSG 徽章提取:新协议 info[0][15].user.medal 优先;无徽章时字段为空', () async {
    final session = await connector.connect(
      const DanmakuSessionRequest(site: 'bilibili', roomId: '9527'),
    );
    final socket = transport.sockets.single;
    final received = <DanmakuMessage>[];
    final sub = session.messages.listen(received.add);
    socket.pushBytes(encodeBiliPacket(BiliPacketOp.authAck, utf8.encode('{"code":0}')));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    // 新协议:meta[15].user.medal 与老 info[3] 同时存在 → 新结构优先。
    socket.pushBytes(_danmuFrame(
      cmd: 'DANMU_MSG:4:0:2:2:2:0',
      userName: '李四',
      text: '新结构',
      metaUser: {
        'medal': {
          'name': '新结构牌',
          'level': 8,
          'guard_level': 3,
          'v2_medal_color_start': '#BB00BB',
          'v2_medal_color_end': '#CC00CC',
          'v2_medal_color_border': '#00FFFF',
          'v2_medal_color_text': '#EDEDED',
          'v2_medal_color_level': '#FFFFFF',
        },
      },
      medalInfo: [12, '老结构牌', 12],
      ulInfo: [20, 0, -1],
    ));
    // 无任何徽章字段:三字段应为空/0。
    socket.pushBytes(_danmuFrame(cmd: 'DANMU_MSG:4:0:2:2:2:0', userName: '王五', text: '无徽章'));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(received, hasLength(2));
    expect(received[0].badgeName, '新结构牌');
    expect(received[0].badgeLevel, 8);
    expect(received[0].userLevel, 20);
    // 新协议 hex 色解析(对齐 web medalFieldsFromObj)。
    expect(received[0].badgeColorStart, 0xbb00bb);
    expect(received[0].badgeColorEnd, 0xcc00cc);
    expect(received[0].badgeColorBorder, 0x00ffff);
    // 文字色/等级数字色 = v2_medal_color_text/level(web bilibili.ts:121-141)。
    expect(received[0].badgeTextColor, 0xededed);
    expect(received[0].badgeColorLevel, 0xffffff);
    expect(received[1].badgeName, isEmpty);
    expect(received[1].badgeLevel, 0);
    expect(received[1].userLevel, 0);

    await sub.cancel();
    await session.close();
  });

  test('authAck code!=0 → disconnected', () async {
    final session = await connector.connect(
      const DanmakuSessionRequest(site: 'bilibili', roomId: '9527'),
    );
    final states = <DanmakuSessionState>[];
    final sub = session.states.listen(states.add);
    transport.sockets.single
        .pushBytes(encodeBiliPacket(BiliPacketOp.authAck, utf8.encode('{"code":-101}')));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(states, contains(DanmakuSessionState.disconnected));
    await sub.cancel();
    await session.close();
  });

  test('getDanmuInfo 失败降级 getConf', () async {
    fake.routeInterceptor = (path) {
      if (path.contains('getDanmuInfo')) {
        return {'code': -412, 'message': '请求被拦截'};
      }
      if (path.contains('Danmu/getConf')) {
        return {
          'code': 0,
          'data': {
            'token': 'conf-token',
            'host': 'broadcastlv.chat.bilibili.com',
            'port': 2245,
          },
        };
      }
      return null;
    };

    final session = await connector.connect(
      const DanmakuSessionRequest(site: 'bilibili', roomId: '9527'),
    );
    expect(transport.lastUrl.toString(), 'wss://broadcastlv.chat.bilibili.com/sub');
    final authPacket =
        decodeBiliPackets(Uint8List.fromList(transport.sockets.single.rawSent.first)).single;
    final auth = jsonMapOf(jsonDecode(utf8.decode(authPacket.body)));
    expect(auth['key'], 'conf-token');
    await session.close();
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
