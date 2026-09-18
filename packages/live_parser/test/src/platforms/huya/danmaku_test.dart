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

Uint8List _chatNotice({
  required String nick,
  required String content,
  int color = 0xff7f00,
  Map<int, List<Uint8List>>? decorations,
}) {
  final notice = TarsWriter()
    ..writeStruct((userInfo) {
      userInfo.writeString(nick, 2);
    }, 0)
    ..writeString(content, 3)
    ..writeStruct((format) {
      format.writeInt(color, 0);
    }, 6);
  if (decorations == null || decorations.isEmpty) {
    return notice.takeBytes();
  }
  // 装饰 tag(8/9/12/15)大于已有字段,按 Tars tag 升序直接追加
  // (向量字节自带 LIST 头,故用裸字节拼接而非 writeBytes 二次包装)。
  final out = BytesBuilder()..add(notice.takeBytes());
  for (final tag in decorations.keys.toList()..sort()) {
    out.add(_decorationVector(tag, decorations[tag]!));
  }
  return out.takeBytes();
}

/// BadgeInfo{sBadgeName@3, iBadgeLevel@4} 结构体字节。
/// 依据 web 真源 parseOfficialBadgeInfo(apps/web/src/utils/danmaku/huyaJce.ts:350-361)。
Uint8List _fansBadgeInfo({required String name, required int level}) =>
    (TarsWriter()..writeString(name, 3)..writeInt(level, 4)).takeBytes();

/// ConsumeLevelBadgeInfo{iLevel@1, iBadgeStyle@2, iIsPolished@3} 结构体字节。
/// 依据 web 真源 parseOfficialConsumeLevel(huyaJce.ts:362-373)。
Uint8List _consumeLevelInfo({required int level, int style = 0, int polished = 0}) =>
    (TarsWriter()
          ..writeInt(level, 1)
          ..writeInt(style, 2)
          ..writeInt(polished, 3))
        .takeBytes();

/// DecorationInfo{appId@0, data@2} 结构体字节(huyaJce.ts:326-332)。
Uint8List _decorationInfo(int appId, Uint8List data) =>
    (TarsWriter()..writeInt(appId, 0)..writeBytes(data, 2)).takeBytes();

/// `LIST<DecorationInfo>` 字段字节:LIST 头字节手写(TarsWriter 未暴露裸
/// LIST 头),头编码与 TarsWriter._writeHead 同款——tag<15 单字节,tag>=15
/// 走 `(15<<4)|9` + tag 字节双字节扩展;其后为元素个数与各元素(tag0 结构头
/// + 原始字段 + 结构尾),与 TarsReader.readStructList 的读取方式对称。
Uint8List _decorationVector(int tag, List<Uint8List> items) {
  final sizes = TarsWriter()..writeInt(items.length, 0);
  final out = BytesBuilder();
  if (tag < 15) {
    out.add([(tag << 4) | 9]);
  } else {
    out.add([(15 << 4) | 9, tag]);
  }
  out.add(sizes.takeBytes());
  for (final item in items) {
    out
      ..add(const [0x0a]) // STRUCT_BEGIN(tag 0)
      ..add(item)
      ..add(const [0x0b]); // STRUCT_END(tag 0)
  }
  return out.takeBytes();
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

  test('徽章/等级:DecorationInfo(10400 粉丝牌/11200 消费等级)提取', () async {
    final session = await connector.connect(
      const DanmakuSessionRequest(site: 'huya', roomId: '9527'),
    );
    final socket = transport.sockets.single;
    final received = <DanmakuMessage>[];
    final sub = session.messages.listen(received.add);

    // 装饰结构依据 web 真源 huyaJce.ts:HUYA_DECO_APP{FANS:10400,
    // CONSUME_LEVEL_BADGE:11200}(306-309 行),向量挂在 MessageNotice tag 8。
    socket.pushBytes(
      _pushFrame(
        1400,
        _chatNotice(
          nick: '牌哥',
          content: '带牌发言',
          decorations: {
            8: [
              _decorationInfo(10400, _fansBadgeInfo(name: '铁粉', level: 13)),
              _decorationInfo(11200, _consumeLevelInfo(level: 25, style: 1)),
            ],
          },
        ),
      ),
    );

    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(received, hasLength(1));
    expect(received.single.userName, '牌哥');
    expect(received.single.text, '带牌发言');
    expect(received.single.badgeName, '铁粉');
    expect(received.single.badgeLevel, 13);
    expect(received.single.userLevel, 25);
    // 虎牙粉丝牌渐变走 UI 端 HUYA_BAR_GRADIENTS 7 档分档,不填 B 站专属三色。
    expect(received.single.badgeColorStart, 0);
    expect(received.single.badgeColorEnd, 0);
    expect(received.single.badgeColorBorder, 0);

    await sub.cancel();
    await session.close();
  });

  test('无装饰消息徽章/等级为默认值(UI 不渲染)', () async {
    final session = await connector.connect(
      const DanmakuSessionRequest(site: 'huya', roomId: '9527'),
    );
    final socket = transport.sockets.single;
    final received = <DanmakuMessage>[];
    final sub = session.messages.listen(received.add);

    socket.pushBytes(_pushFrame(1400, _chatNotice(nick: '路人', content: '无牌发言')));

    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(received, hasLength(1));
    expect(received.single.badgeName, '');
    expect(received.single.badgeLevel, 0);
    expect(received.single.userLevel, 0);

    await sub.cancel();
    await session.close();
  });

  test('徽章:level<=0 无效不覆盖;多 tag 累积后写覆盖(对齐 applyDecorations)', () async {
    final session = await connector.connect(
      const DanmakuSessionRequest(site: 'huya', roomId: '9527'),
    );
    final socket = transport.sockets.single;
    final received = <DanmakuMessage>[];
    final sub = session.messages.listen(received.add);

    // level<=0 视为无牌/无等级(normalizeHuyaBadge fanBadges/huya.ts:112、
    // normalizeHuyaUserLevel userLevels/huya.ts:12);tag 8/12/15 累积读取,
    // 同 appId 后写覆盖先写(huyaJce.ts:374-390)。
    socket.pushBytes(
      _pushFrame(
        1400,
        _chatNotice(
          nick: '多牌',
          content: '多 tag 装饰',
          decorations: {
            8: [_decorationInfo(10400, _fansBadgeInfo(name: '甲团', level: 5))],
            12: [
              _decorationInfo(10400, _fansBadgeInfo(name: '乙团', level: 0)),
              _decorationInfo(10400, _fansBadgeInfo(name: '丙团', level: 9)),
              _decorationInfo(11200, _consumeLevelInfo(level: 0)),
            ],
            15: [_decorationInfo(11200, _consumeLevelInfo(level: 7))],
          },
        ),
      ),
    );

    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(received, hasLength(1));
    expect(received.single.badgeName, '丙团', reason: 'level=0 的乙团不覆盖,丙团后写覆盖甲团');
    expect(received.single.badgeLevel, 9);
    expect(received.single.userLevel, 7, reason: 'level=0 的消费等级不生效,tag15 后写覆盖');

    await sub.cancel();
    await session.close();
  });

  test('装饰数据残缺只丢徽章不丢正文', () async {
    final session = await connector.connect(
      const DanmakuSessionRequest(site: 'huya', roomId: '9527'),
    );
    final socket = transport.sockets.single;
    final received = <DanmakuMessage>[];
    final sub = session.messages.listen(received.add);

    // 非法 Tars 字节:string1 头(0x36)声明长度 200 但无负载,解析必抛。
    socket.pushBytes(
      _pushFrame(
        1400,
        _chatNotice(
          nick: '坏牌',
          content: '正文要保留',
          decorations: {
            8: [_decorationInfo(10400, Uint8List.fromList([0x36, 0xc8]))],
          },
        ),
      ),
    );

    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(received, hasLength(1), reason: '装饰残缺不应吞掉整条弹幕');
    expect(received.single.text, '正文要保留');
    expect(received.single.badgeName, '');
    expect(received.single.badgeLevel, 0);
    expect(received.single.userLevel, 0);

    await sub.cancel();
    await session.close();
  });

  test('chat 协议重推去重:user+text 兜底 key(对齐 web huyaDanmakuDedup)', () async {
    final session = await connector.connect(
      const DanmakuSessionRequest(site: 'huya', roomId: '9527'),
    );
    final socket = transport.sockets.single;
    final received = <DanmakuMessage>[];
    final sub = session.messages.listen(received.add);

    socket.pushBytes(_pushFrame(1400, _chatNotice(nick: '张三', content: '你好虎牙')));
    // WS 对同一条的重复推送(用户+正文完全相同)。
    socket.pushBytes(_pushFrame(1400, _chatNotice(nick: '张三', content: '你好虎牙')));
    // 不同用户同正文:保留。
    socket.pushBytes(_pushFrame(1400, _chatNotice(nick: '李四', content: '你好虎牙')));
    // 同用户不同正文:保留。
    socket.pushBytes(_pushFrame(1400, _chatNotice(nick: '张三', content: '换一条')));
    // 在线人数(8006)不属于 chat 域,不受去重影响。
    final online = TarsWriter()..writeInt(123456, 0);
    socket.pushBytes(_pushFrame(8006, online.takeBytes()));

    await Future<void>.delayed(const Duration(milliseconds: 10));

    final chats = received.where((m) => m.type == DanmakuMessageType.chat).toList();
    expect(chats, hasLength(3), reason: '协议重推(用户+正文同)应被滤掉,其余保留');
    expect(
      received.where((m) => m.type == DanmakuMessageType.other),
      hasLength(1),
      reason: '在线人数不参与 chat 去重',
    );

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
