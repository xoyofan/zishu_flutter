import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:live_parser/live_parser.dart';
import 'package:live_parser/src/platforms/huya/danmaku.dart';
import 'package:live_parser/src/platforms/huya/huya_wup.dart';
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
Uint8List _fansBadgeInfo({
  required String name,
  required int level,
  int vFlag = 0,
  String vLogo = '',
  int badgeType = 0,
}) =>
    (TarsWriter()
          ..writeString(name, 3)
          ..writeInt(level, 4)
          ..writeInt(vFlag, 12)
          ..writeString(vLogo, 13)
          ..writeInt(badgeType, 17))
        .takeBytes();

/// BadgeInfo 完整字段字节(官网 `assets/modules/taf/structs/FansServant.js`
/// 的 `SimpleBadgeInfo`):tag3/4/12/13/17 之外补读 18/19/22/25/26。
Uint8List _fansBadgeInfoFull({
  required String name,
  required int level,
  int vFlag = 0,
  String vLogo = '',
  int badgeType = 0,
  int superFansFlag = 0,
  int customBadgeFlag = 0,
  int fansIdentity = 0,
  int badgeSize = 0,
  int extinguished = 0,
}) =>
    (TarsWriter()
          ..writeString(name, 3)
          ..writeInt(level, 4)
          ..writeInt(vFlag, 12)
          ..writeString(vLogo, 13)
          ..writeInt(badgeType, 17)
          ..writeStruct((_) {}, 18) // tFaithInfo:不消费,读掉保持偏移
          ..writeStruct((sf) => sf.writeInt(superFansFlag, 1), 19)
          ..writeInt(customBadgeFlag, 22)
          ..writeStruct((external) {
            external.writeInt(fansIdentity, 1);
            external.writeInt(badgeSize, 2);
          }, 25)
          ..writeInt(extinguished, 26))
        .takeBytes();

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

/// 拼一个 wup 响应包(4 字节大端包长 + ResponsePacket),sBuffer 内放 `tRsp`。
Uint8List _wupResponse(String servant, String func, Uint8List tRsp) {
  final sBuffer = TarsWriter()..writeBytesMap({'tRsp': tRsp}, 0);
  final payload = (TarsWriter()
        ..writeInt(3, 1)
        ..writeInt(0, 2)
        ..writeInt(0, 3)
        ..writeInt(1, 4)
        ..writeString(servant, 5)
        ..writeString(func, 6)
        ..writeBytes(sBuffer.takeBytes(), 7)
        ..writeInt(0, 8)
        ..writeStringMap(const {}, 9)
        ..writeStringMap(const {}, 10))
      .takeBytes();
  final total = payload.length + 4;
  return Uint8List.fromList([
    (total >> 24) & 0xff,
    (total >> 16) & 0xff,
    (total >> 8) & 0xff,
    total & 0xff,
    ...payload,
  ]);
}

/// `LIST<struct>` 字段字节(LIST 头手写,同 `_decorationVector` 的做法)。
Uint8List _structListField(int tag, List<Uint8List> elements) {
  final sizes = TarsWriter()..writeInt(elements.length, 0);
  final out = BytesBuilder();
  if (tag < 15) {
    out.add([(tag << 4) | 9]);
  } else {
    out.add([(15 << 4) | 9, tag]);
  }
  out.add(sizes.takeBytes());
  for (final element in elements) {
    out
      ..add(const [0x0a])
      ..add(element)
      ..add(const [0x0b]);
  }
  return out.takeBytes();
}

Uint8List _structOf(List<Uint8List> fields) {
  final out = BytesBuilder()..add(const [0x0a]);
  for (final field in fields) {
    out.add(field);
  }
  return (out..add(const [0x0b])).takeBytes();
}

/// `GetResourceInfoRsp` 里只带一条 `CommonFansBadgeSplit`(bizType/type=14)。
Uint8List _resourceInfoTars({
  required String floorUrl,
  required String identityUrl,
  int maxLevel = 52,
}) {
  final payload = (TarsWriter()
        ..writeStruct((resource) {
          resource.writeInt(maxLevel, 0);
          resource.writeStruct((common) {
            common.writeString(floorUrl, 0);
            common.writeString(identityUrl, 1);
          }, 1);
        }, 0))
      .takeBytes();
  final item = (TarsWriter()
        ..writeString('commonFansBadgeSplit', 0)
        ..writeInt(14, 1)
        ..writeBytes(payload, 2)
        ..writeInt(0, 3))
      .takeBytes();
  final resourceFields = (BytesBuilder()
        ..add((TarsWriter()..writeInt(14, 0)).takeBytes())
        ..add(_structListField(1, [item])))
      .takeBytes();
  return _structOf([_structListField(0, [resourceFields])]);
}

const String _kFloorTemplate =
    'https://fileserver.cdn.huya.com/web_admin_badgeDefaultFloorUrl/'
    '73b846b6b8684ce9b1793d50824a3d4d/<size>_<ua>_<dark>_<level>.name';
const String _kIdentityTemplate =
    'https://fileserver.cdn.huya.com/web_admin_badgeDefaultIdentityUrl/'
    'b42f4df0d47540c28e11b1b10b57e870/<ua>_<dark>_<identity>.name';

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
              _decorationInfo(
                10400,
                _fansBadgeInfo(
                  name: '铁粉',
                  level: 13,
                  vFlag: 1,
                  vLogo: 'https://cdn.example/huya-v.png',
                  badgeType: 2,
                ),
              ),
              _decorationInfo(
                11200,
                _consumeLevelInfo(level: 25, style: 1, polished: 1),
              ),
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
    expect(received.single.badges.single.vFlag, 1);
    expect(received.single.badges.single.vLogo, 'https://cdn.example/huya-v.png');
    expect(received.single.userLevel, 25);
    expect(received.single.userLevelBadgeStyle, 1);
    expect(received.single.userLevelIsPolished, 1);
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

  test('表情:真源 MessageNotice 无表情段,正文括号表情保持纯文本(segments 恒空)', () async {
    final session = await connector.connect(
      const DanmakuSessionRequest(site: 'huya', roomId: '9527'),
    );
    final socket = transport.sockets.single;
    final received = <DanmakuMessage>[];
    final sub = session.messages.listen(received.add);

    // 虎牙协议(web 真源 huyaJce.ts parseMessageNotice 391-435 行)不存在
    // 表情段;正文 `[表情名]` 括号是纯文本的一部分,web 端 emoji 映射表仅
    // douyin 加载、虎牙不图片化。解析侧不拆段,segments 恒空。
    socket.pushBytes(
      _pushFrame(1400, _chatNotice(nick: '表情哥', content: '[微笑]你好[传送]')),
    );

    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(received, hasLength(1));
    expect(received.single.text, '[微笑]你好[传送]', reason: '括号表情保持原文,不改写不拆段');
    expect(received.single.segments, isEmpty);

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

  test('BadgeInfo 补读 19/22/25/26:超粉/定制/身份/尺寸/熄灭', () async {
    final session = await connector.connect(
      const DanmakuSessionRequest(site: 'huya', roomId: '9527'),
    );
    final socket = transport.sockets.single;
    final received = <DanmakuMessage>[];
    final sub = session.messages.listen(received.add);

    socket.pushBytes(
      _pushFrame(
        1400,
        _chatNotice(
          nick: '全字段',
          content: '徽章全字段',
          decorations: {
            8: [
              _decorationInfo(
                10400,
                _fansBadgeInfoFull(
                  name: '全字段团',
                  level: 15,
                  superFansFlag: 1,
                  customBadgeFlag: 1,
                  fansIdentity: 12,
                  badgeSize: 3,
                  extinguished: 1,
                ),
              ),
            ],
          },
        ),
      ),
    );

    await Future<void>.delayed(const Duration(milliseconds: 10));

    final badge = received.single.badges.single;
    expect(badge.identity, 12, reason: 'tExternal.iFansIdentity@25');
    expect(badge.badgeSize, 3, reason: 'tExternal.iBadgeSize@25');
    expect(badge.extinguished, 1, reason: 'iExtinguished@26');
    expect(badge.custom, isTrue, reason: 'iCustomBadgeFlag@22 == 1');
    expect(received.single.superFan, isTrue, reason: 'tSuperFansInfo.iSFFlag@19');
    expect(
      received.single.nobleLevel,
      0,
      reason: '贵族只在 OnTVBarrageNotice,弹幕流恒 0(不编数据)',
    );
    // 未接房间资源 → 底图空串,UI 降级自绘胶囊。
    expect(badge.floorUrlTemplate, '');
    expect(badge.url, '');

    await sub.cancel();
    await session.close();
  });

  test('connect 时拉一次 getResourceInfo,底图模板回填到每条弹幕', () async {
    fake.wupResponseByFunc['getResourceInfo'] = _wupResponse(
      'wupui',
      'getResourceInfo',
      _resourceInfoTars(
        floorUrl: _kFloorTemplate,
        identityUrl: _kIdentityTemplate,
      ),
    );
    final wired = HuyaDanmakuConnector(
      parserHttp: ParserHttp(client: fake),
      transport: transport,
      wup: HuyaWupClient(httpClient: fake),
      heartbeatInterval: const Duration(milliseconds: 50),
    );
    final session = await wired.connect(
      const DanmakuSessionRequest(site: 'huya', roomId: '9527'),
    );
    expect(fake.wupFuncNames, ['getResourceInfo'], reason: '房间资源只拉一次');

    // 资源 future 先完成,再推弹幕。
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final socket = transport.sockets.single;
    final received = <DanmakuMessage>[];
    final sub = session.messages.listen(received.add);
    socket.pushBytes(
      _pushFrame(
        1400,
        _chatNotice(
          nick: '有底图',
          content: '官方底图',
          decorations: {
            8: [
              _decorationInfo(
                10400,
                _fansBadgeInfoFull(
                  name: '有底图团',
                  level: 15,
                  fansIdentity: 4,
                  badgeSize: 2,
                ),
              ),
            ],
          },
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final badge = received.single.badges.single;
    expect(badge.floorUrlTemplate, _kFloorTemplate);
    expect(
      badge.url,
      'https://fileserver.cdn.huya.com/web_admin_badgeDefaultFloorUrl/'
      '73b846b6b8684ce9b1793d50824a3d4d/2_3_0_15.png',
      reason: '实测模板为 <size>_<ua>_<dark>_<level>.name,'
          'identity=4 命中不到占位符;size=max(2,2)=2,dark=0,level=15',
    );

    await sub.cancel();
    await session.close();
  });

  test('房间资源拉取失败不影响弹幕连接(降级空底图)', () async {
    // fake 对未注册的 wup func 返回 HTTP 500。
    final wired = HuyaDanmakuConnector(
      parserHttp: ParserHttp(client: fake),
      transport: transport,
      wup: HuyaWupClient(httpClient: fake),
      heartbeatInterval: const Duration(milliseconds: 50),
    );
    final session = await wired.connect(
      const DanmakuSessionRequest(site: 'huya', roomId: '9527'),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(fake.wupFuncNames, ['getResourceInfo']);

    final socket = transport.sockets.single;
    final received = <DanmakuMessage>[];
    final sub = session.messages.listen(received.add);
    socket.pushBytes(
      _pushFrame(
        1400,
        _chatNotice(
          nick: '降级',
          content: '资源挂了也能聊',
          decorations: {
            8: [
              _decorationInfo(
                10400,
                _fansBadgeInfo(name: '降级团', level: 9),
              ),
            ],
          },
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(received, hasLength(1));
    expect(received.single.text, '资源挂了也能聊');
    expect(received.single.badges.single.floorUrlTemplate, '');
    expect(received.single.badges.single.url, '');

    await sub.cancel();
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
    bool sendAsText = false,
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
