import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:live_parser/live_parser.dart';
import 'package:live_parser/src/platforms/douyin/emoji_image_data.dart';
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

    test('徽章提取:payGrade(#23.#6)→userLevel;fansclub(#61)→badgeLevel', () async {
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

      socket.push(
        _pushFrame(
          _response(
            message: _message(
              'WebcastChatMessage',
              _chatPayload(
                text: '带徽章',
                nick: '徽章哥',
                userId: 42,
                payGradeLevel: 18,
                fansBadgeLevel: 10,
                fansBadgeUrl: 'https://p3-webcast.douyinpic.com/ranklist_fansclub_pop_advanced_badge_10.png',
                fansBadgeName: '粉丝团十级',
                honorIconUrl: 'https://p3-webcast.douyinpic.com/honor/18.png',
              ),
            ),
          ),
          logId: 2,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(received, hasLength(1));
      expect(received.single.userLevel, 18, reason: 'User.payGrade 的 field 6');
      expect(received.single.badgeLevel, 10, reason: 'fansclub badge 项的等级');
      expect(received.single.badgeName, '粉丝团十级');
      expect(received.single.badgeUrl, 'https://p3-webcast.douyinpic.com/ranklist_fansclub_pop_advanced_badge_10.png');
      expect(received.single.userLevelIconUrl, 'https://p3-webcast.douyinpic.com/honor/18.png');

      // 无徽章用户:字段默认空/0。
      socket.push(
        _pushFrame(
          _response(
            message: _message(
              'WebcastChatMessage',
              _chatPayload(text: '无徽章', nick: '素人', userId: 43),
            ),
          ),
          logId: 3,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(received, hasLength(2));
      expect(received.last.userLevel, 0);
      expect(received.last.badgeLevel, 0);

      await subscription.cancel();
      await session.close();
    });

    test('徽章回归:#61 首项为荣誉等级徽章时不得当作粉丝牌(不得渲染两个平台等级)', () async {
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

      // 场景 A(实连 dump 形态):只有荣誉项,无粉丝团牌 → 粉丝牌必须为空,
      // 否则 UI 会在平台等级旁再画一个同图 → 看上去是两个平台等级。
      socket.push(
        _pushFrame(
          _response(
            message: _message(
              'WebcastChatMessage',
              _chatPayload(
                text: '只有荣誉',
                nick: '荣誉哥',
                userId: 51,
                payGradeLevel: 29,
                honorIconUrl:
                    'https://p3-webcast.douyinpic.com/img/webcast/'
                    'new_user_grade_level_v1_29.png~tplv-obj.image',
                honorBadgeInBadgeList: true,
              ),
            ),
          ),
          logId: 21,
        ),
      );
      // 场景 B:#61 = [荣誉项, 粉丝团牌] → 必须取到粉丝团牌那一项。
      socket.push(
        _pushFrame(
          _response(
            message: _message(
              'WebcastChatMessage',
              _chatPayload(
                text: '荣誉加粉丝团',
                nick: '双牌哥',
                userId: 52,
                payGradeLevel: 18,
                fansBadgeLevel: 10,
                honorBadgeInBadgeList: true,
              ),
            ),
          ),
          logId: 22,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(received, hasLength(2));
      expect(received[0].userLevel, 29, reason: '平台等级仍来自 payGrade');
      expect(
        received[0].badgeLevel,
        0,
        reason: '荣誉等级项不是粉丝牌,不得填粉丝牌槽',
      );
      expect(
        received[0].badges,
        isEmpty,
        reason: '否则聊天行会渲染出第二个平台等级',
      );
      expect(received[1].badgeLevel, 10, reason: '应跳过荣誉项取到粉丝团牌');
      expect(received[1].badgeName, contains('粉丝团'));
      expect(
        received[1].badgeUrl,
        contains('fansclub'),
        reason: '粉丝牌 URL 必须是 fansclub 官方图',
      );

      await subscription.cancel();
      await session.close();
    });

    test('富文本表情段:#22 image piece → segments(text/emoji 按序);纯文本 segments 空', () async {
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

      // Text{#4: [text'你好', emoji'呲牙', text'哈哈']},结构对齐 web 真源
      // parseDouyinTextMessage(packages/shared/src/protocol/douyin/
      // protobuf-lite.ts:494-527):表情名补 [ ] 括号,url 取 Image.#1 首个
      // http(s) 地址,相邻文本段不合并不跨界。
      const emojiUrl =
          'https://p3-webcast.douyinpic.com/webcast/emoji/emoji_001.png';
      socket.push(
        _pushFrame(
          _response(
            message: _message(
              'WebcastChatMessage',
              _chatPayload(
                text: '',
                nick: '表情哥',
                userId: 77,
                richText: [
                  ..._pbBytes(4, _textPieceText('你好')),
                  ..._pbBytes(4, _textPieceEmoji(name: '呲牙', url: emojiUrl)),
                  ..._pbBytes(4, _textPieceText('哈哈')),
                ],
              ),
            ),
          ),
          logId: 4,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(received, hasLength(1));
      expect(received.single.text, '你好😁哈哈', reason: '表情名映射 Unicode 字形拼入正文');
      expect(received.single.segments, [
        const DanmakuSegment.text('你好'),
        const DanmakuSegment.emoji(text: '😁', url: emojiUrl, name: '呲牙'),
        const DanmakuSegment.text('哈哈'),
      ], reason: 'text/emoji 段按协议顺序保留');

      // 纯文本消息(#3 兜底路径):segments 保持空(UI 直接渲染 text)。
      socket.push(
        _pushFrame(
          _response(
            message: _message(
              'WebcastChatMessage',
              _chatPayload(text: '纯文本弹幕', nick: '素人', userId: 78),
            ),
          ),
          logId: 5,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(received, hasLength(2));
      expect(received.last.text, '纯文本弹幕');
      expect(received.last.segments, isEmpty);

      await subscription.cancel();
      await session.close();
    });

    test('纯文本裸括号表情码 [赞] 解析为 emoji 段(渲染 Unicode,不依赖 CDN)', () async {
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

      // #3 纯文本兜底路径:正文里混有 [赞][火] 裸括号码,此前被当原样文字;
      // 现应解析成 emoji 段(url 空,UI 直接渲染 Unicode)。
      socket.push(
        _pushFrame(
          _response(
            message: _message(
              'WebcastChatMessage',
              _chatPayload(
                text: '[赞]主播好厉害[火]',
                nick: '观众丙',
                userId: 79,
              ),
            ),
          ),
          logId: 6,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(received, hasLength(1));
      expect(
        received.single.text,
        '👍主播好厉害🔥',
        reason: '命中表情名替换为 Unicode,未命中保留原样',
      );
      // [赞] 同时命中静态贴图表与 Unicode 表 → emoji 段挂 CDN 图 url、
      // 文本用 Unicode 字形;[火] 只在 Unicode 表 → url 空,离线渲染。
      expect(received.single.segments, hasLength(3));
      expect(received.single.segments[0].isEmoji, isTrue);
      expect(received.single.segments[0].text, '👍');
      expect(received.single.segments[0].url, kDouyinEmojiImage['赞']);
      expect(received.single.segments[1].text, '主播好厉害');
      expect(received.single.segments[2].isEmoji, isTrue);
      expect(received.single.segments[2].text, '🔥');
      expect(received.single.segments[2].url, '');

      // 未收录表情名保留原样,不丢字符。
      socket.push(
        _pushFrame(
          _response(
            message: _message(
              'WebcastChatMessage',
              _chatPayload(
                text: '求[连麦]关注',
                nick: '观众丁',
                userId: 80,
              ),
            ),
          ),
          logId: 7,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(received, hasLength(2));
      expect(received.last.text, '求[连麦]关注');
      expect(received.last.segments, isEmpty, reason: '无命中表情名则 segments 空');

      // [看]:贴图表命中、Unicode 表未收录 → emoji 段挂原版贴图 url,
      // 段文本保留 [看] 字面(图片加载失败时 UI 的兜底文案)。
      socket.push(
        _pushFrame(
          _response(
            message: _message(
              'WebcastChatMessage',
              _chatPayload(text: '[看]主播[捂脸]', nick: '观众戊', userId: 81),
            ),
          ),
          logId: 8,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(received, hasLength(3));
      expect(received.last.text, '[看]主播[捂脸]');
      expect(received.last.segments, hasLength(3));
      expect(received.last.segments[0].isEmoji, isTrue);
      expect(received.last.segments[0].text, '[看]');
      expect(received.last.segments[0].url, kDouyinEmojiImage['看']);
      expect(received.last.segments[0].name, '看');
      expect(received.last.segments[1].text, '主播');
      expect(received.last.segments[2].isEmoji, isTrue);
      expect(received.last.segments[2].text, '[捂脸]');
      expect(received.last.segments[2].url, kDouyinEmojiImage['捂脸']);

      await subscription.cancel();
      await session.close();
    });

    test('表情聊天 WebcastEmojiChatMessage:#5 default_content [看] 还原为原版贴图段', () async {
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

      // 表情聊天实际形态:default_content(#5) = [看] 纯文本括号码,
      // 协议无图片 URL;经静态贴图表还原成带 url 的 emoji 段。
      socket.push(
        _pushFrame(
          _response(
            message: _message(
              'WebcastEmojiChatMessage',
              _chatPayload(
                text: '',
                nick: '表情哥',
                userId: 82,
                defaultContent: '[看]',
              ),
            ),
          ),
          logId: 9,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(received, hasLength(1));
      expect(received.single.text, '[看]');
      expect(received.single.segments, hasLength(1));
      expect(received.single.segments.single.isEmoji, isTrue);
      expect(received.single.segments.single.text, '[看]');
      expect(received.single.segments.single.url, kDouyinEmojiImage['看']);
      expect(received.single.segments.single.name, '看');

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
  int payGradeLevel = 0,
  int fansBadgeLevel = 0,
  String fansBadgeUrl = '',
  String fansBadgeName = '',
  String honorIconUrl = '',
  bool honorBadgeInBadgeList = false,
  List<int> richText = const [],
  String defaultContent = '',
}) {
  final user = [
    ..._pbUint(1, userId),
    ..._pbString(3, nick),
    // payGrade(#23): level 在其 field 6(web 真源注释 + 实测一致)。
    if (payGradeLevel > 0)
      ..._pbBytes(
        23,
        [
          ..._pbUint(6, payGradeLevel),
          if (honorIconUrl.isNotEmpty) ..._pbString(19, honorIconUrl),
        ],
      ),
    // 粉丝团 badge 项(#61 repeated):#1 = 官方 CDN 图(含等级),
    // #8 = 描述子消息(#3 = 等级,#4 = 名称)。
    //
    // honorBadgeInBadgeList:实连 WS dump 到的真实形态 —— #61 反复携带的
    // 第一项常是**荣誉等级**徽章(`new_user_grade_level_v1_N.png` +
    // 描述子「荣誉等级N级勋章」),粉丝团牌只在其后。回归即由此产生:
    // 解析器把荣誉项当粉丝牌 → UI 渲染出两个平台等级。
    if (honorBadgeInBadgeList)
      ..._pbBytes(
        61,
        [
          ..._pbString(
            1,
            'https://p3-webcast.douyinpic.com/img/webcast/'
            'new_user_grade_level_v1_$payGradeLevel.png~tplv-obj.image',
          ),
          ..._pbBytes(
            8,
            [
              ..._pbUint(3, payGradeLevel),
              ..._pbString(4, '荣誉等级$payGradeLevel 级勋章'),
            ],
          ),
        ],
      ),
    if (fansBadgeLevel > 0)
      ..._pbBytes(
        61,
        [
          ..._pbString(
            1,
            fansBadgeUrl.isNotEmpty
                ? fansBadgeUrl
                : 'https://p11-webcast.douyinpic.com/img/webcast/'
                    'ranklist_fansclub_pop_advanced_badge_$fansBadgeLevel.png~tplv-obj.image',
          ),
          ..._pbBytes(
            8,
            [
              ..._pbUint(3, fansBadgeLevel),
              ..._pbString(
                4,
                fansBadgeName.isNotEmpty
                    ? fansBadgeName
                    : '粉丝团等级$fansBadgeLevel级勋章',
              ),            ],
          ),
        ],
      ),
  ];
  final common = [..._pbUint(4, 1700000000000)];
  return [
    ..._pbBytes(1, common),
    ..._pbBytes(2, user),
    ..._pbString(3, text),
    // Text 富文本(#22):web 真源 parseChatMessage 的首选路径
    // (packages/shared/src/protocol/douyin/protobuf-lite.ts:530-551)。
    if (richText.isNotEmpty) ..._pbBytes(22, richText),
    // default_content(#5):WebcastEmojiChatMessage 的纯文本括号码兜底
    // (web 真源 parseEmojiChatMessage 首选字段,protobuf-lite.ts:551-567)。
    if (defaultContent.isNotEmpty) ..._pbString(5, defaultContent),
  ];
}

/// TextPiece{#3 = 文本}(protobuf-lite.ts:508)。
List<int> _textPieceText(String value) => _pbString(3, value);

/// TextPiece{#8 = TextPieceImage{#1 = Image}};Image{#1 = url bytes,
/// #8 = Content{#1 = 表情名}}(web 真源 parseTextPieceImage +
/// parseImageContentName + parseImageUrlList,protobuf-lite.ts:441-461、149-157)。
List<int> _textPieceEmoji({required String name, required String url}) =>
    _pbBytes(
      8,
      _pbBytes(
        1,
        [..._pbString(1, url), ..._pbBytes(8, _pbString(1, name))],
      ),
    );

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
    bool sendAsText = false,
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
