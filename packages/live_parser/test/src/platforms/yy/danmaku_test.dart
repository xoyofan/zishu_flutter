import 'dart:async';
import 'dart:typed_data';

import 'package:live_parser/live_parser.dart';
import 'package:live_parser/src/platforms/yy/danmaku.dart';
import 'package:live_parser/src/platforms/yy/subscribe_templates.dart';
import 'package:test/test.dart';

Uint8List _u32le(int v) {
  final data = ByteData(4)..setUint32(0, v, Endian.little);
  return data.buffer.asUint8List();
}

Uint8List _u16leStr(String s) {
  final bytes = Uint8List.fromList(_utf8(s));
  final out = Uint8List(2 + bytes.length);
  final data = ByteData.sublistView(out);
  data.setUint16(0, bytes.length, Endian.little);
  out.setRange(2, out.length, bytes);
  return out;
}

/// 构造一条符合 trident 协议的弹幕帧:
/// 帧头(10B) + pad(2B) + innerId@12(80216) + pad(4B) + marker@20(0x00045258) + u16字符串流。
Uint8List _chatFrame({
  required String channel,
  required String text,
  required String nick,
}) {
  final body = BytesBuilder();
  body.add(const [0, 0]); // 帧偏移 10-11
  body.add(_u32le(80216)); // 帧偏移 12-15 = CHAT_INNER_ID
  body.add(const [0, 0, 0, 0]); // 帧偏移 16-19
  body.add(const [0x58, 0x52, 0x04, 0x00]); // 帧偏移 20-23 = marker
  for (final s in [channel, text, nick]) {
    body.add(_u16leStr(s));
  }
  return buildYyFrame(512011, body.toBytes());
}

List<int> _utf8(String s) {
  // 简易 UTF-8:测试字符串均在 BMP 内。
  final out = <int>[];
  for (final rune in s.runes) {
    if (rune < 0x80) {
      out.add(rune);
    } else if (rune < 0x800) {
      out.add(0xC0 | (rune >> 6));
      out.add(0x80 | (rune & 0x3F));
    } else {
      out.add(0xE0 | (rune >> 12));
      out.add(0x80 | ((rune >> 6) & 0x3F));
      out.add(0x80 | (rune & 0x3F));
    }
  }
  return out;
}

/// 构造 778500 登录响应(Xo 信封 + No 票据)。
Uint8List _loginResponseFrame({
  int resCode = 200,
  int uid = 123456,
  String passport = '2094916962_prereg',
  String password = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  List<int> cookie = const [1, 2, 3, 4],
  List<int> ticket = const [],
}) {
  final no = YyTlWriter()
    ..str('NoCtx')
    ..u32(0)
    ..u32(uid)
    ..u32(0)
    ..str(passport)
    ..str(password)
    ..bytesN(cookie)
    ..bytesN(ticket);
  final xo = YyTlWriter()
    ..str('XoCtx')
    ..u32(resCode)
    ..u32(20078)
    ..bytes32(no.done());
  return buildYyFrame(778500, xo.done());
}

void main() {
  group('帧读写与登录', () {
    test('buildYyFrame:帧头 = [len u32LE][uri u32LE][200 u16LE][body]', () {
      final body = Uint8List.fromList([9, 8, 7]);
      final frame = buildYyFrame(778244, body);
      final data = ByteData.sublistView(frame);
      expect(frame.length, 13);
      expect(data.getUint32(0, Endian.little), 13);
      expect(data.getUint32(4, Endian.little), 778244);
      expect(data.getUint16(8, Endian.little), 200);
      expect(frame.sublist(10), [9, 8, 7]);
    });

    test('kYyLoginFrame:78 字节常量登录帧,uri = 778244', () {
      expect(kYyLoginFrame.length, 78);
      final data = ByteData.sublistView(kYyLoginFrame);
      expect(data.getUint32(0, Endian.little), 78);
      expect(data.getUint32(4, Endian.little), 778244);
      // SDK 硬编码 MAC(B8-97-5A-17-AD-4D)与 appid yymwebh5 在帧内可见。
      expect(
        String.fromCharCodes(kYyLoginFrame),
        contains('B8-97-5A-17-AD-4D'),
      );
      expect(String.fromCharCodes(kYyLoginFrame), contains('yymwebh5'));
    });

    test('parseYyLoginRes:Xo/No 信封往返', () {
      final frame = _loginResponseFrame(
        uid: 777,
        passport: 'sess_prereg',
        password: 'tokentokentokentokentokentokentokentoken',
        cookie: const [7, 7, 7],
        ticket: const [8, 8],
      );
      final ticket = parseYyLoginRes(frame);
      expect(ticket.resCode, 0);
      expect(ticket.uid, 777);
      expect(ticket.passport, 'sess_prereg');
      expect(ticket.password, 'tokentokentokentokentokentokentokentoken');
      expect(ticket.cookie, [7, 7, 7]);
      expect(ticket.ticket, [8, 8]);
    });

    test('parseYyLoginRes:登录被拒绝(resCode 非 200/0)抛错', () {
      expect(
        () => parseYyLoginRes(_loginResponseFrame(resCode: 500)),
        throwsA(isA<YyProtocolException>()),
      );
    });

    test('buildYyRegister:uri = 775684,携带票据与 uuid', () {
      final ticket = YyLoginTicket(
        resCode: 0,
        uid: 424242,
        passport: 'p_session',
        password: 'pwd40charspwd40charspwd40charspwd40ch',
        cookie: Uint8List.fromList([1, 1]),
        ticket: Uint8List.fromList([2, 2]),
      );
      final frame = buildYyRegister(ticket, 'uuid-abc');
      final data = ByteData.sublistView(frame);
      expect(data.getUint32(4, Endian.little), 775684);
      final text = String.fromCharCodes(frame);
      expect(text, contains('p_session'));
      expect(text, contains('yytianlaitv')); // 官方常量 from
      expect(text, contains('B8-97-5A-17-AD-4D')); // 硬编码 MAC
      expect(text, contains('uuid-abc')); // instance
    });

    test('kYyHeartbeat:uri = 794116 的 14 字节心跳', () {
      final data = ByteData.sublistView(kYyHeartbeat);
      expect(kYyHeartbeat.length, 14);
      expect(data.getUint32(4, Endian.little), 794116);
    });
  });

  group('订阅模板 patch', () {
    test('模板 uid/sid 被字节替换且长度不变', () {
      final patched =
          patchYyTemplate(kYySubscribeTemplates.first, 0x11223344, 0x55667788);
      final originalLen = kYySubscribeTemplates.first.length ~/ 2;
      expect(patched.length, originalLen);

      final text = patched
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      // 模板 uid a16d797d / sid d06a4503 不再出现。
      expect(text, isNot(contains('a16d797d')));
      expect(text, isNot(contains('d06a4503')));
      // 新 uid/sid(LE)出现。
      expect(text, contains('44332211'));
      expect(text, contains('88776655'));
    });

    test('模板清单 uri 全部属于协议白名单', () {
      const allowed = {513035, 512011, 537944, 538456, 538712};
      for (final hex in kYySubscribeTemplates) {
        final bytes = _hexToBytes(hex);
        final uri = ByteData.sublistView(bytes).getUint32(4, Endian.little);
        final declaredLen =
            ByteData.sublistView(bytes).getUint32(0, Endian.little);
        expect(declaredLen, bytes.length, reason: '模板自述长度必须等于字节数');
        expect(allowed.contains(uri), isTrue, reason: 'uri $uri 不在白名单');
      }
    });
  });

  group('弹幕帧解析', () {
    test('512011/80216/marker 帧解析出 [频道名,文本,昵称]', () {
      final frame = _chatFrame(
        channel: 'YY频道',
        text: '主播好强',
        nick: '老观众甲',
      );
      final item = parseYyChatFrame(frame);
      expect(item, isNotNull);
      expect(item!.text, '主播好强');
      expect(item.user, '老观众甲');
    });

    test('非 512011 / 缺 marker 的帧返回 null', () {
      expect(parseYyChatFrame(buildYyFrame(778500, Uint8List(60))), isNull);
      // 80216 正确但无 marker
      final body = BytesBuilder()
        ..add(const [0, 0])
        ..add(_u32le(80216))
        ..add(Uint8List(40));
      expect(parseYyChatFrame(buildYyFrame(512011, body.toBytes())), isNull);
      expect(parseYyChatFrame(Uint8List(10)), isNull);
    });
  });

  group('勋章缓存', () {
    test('nick/medal 资料帧积累后,chat 可命中勋章 URL', () {
      final cache = YyMedalCache();
      const medalJson =
          '{"pcMedal":[{"res":{"url":"https://img.yy.com/noble.png"}}]}';
      final body = BytesBuilder()
        ..add(const [0, 0])
        ..add(_u32le(80216))
        ..add(const [0, 0, 0, 0]);
      for (final s in ['nick', '测试昵称', 'medal', medalJson]) {
        body.add(_u16leStr(s));
      }
      cache.rememberUserInfoFrame(buildYyFrame(512011, body.toBytes()));
      expect(cache.medalFor('测试昵称'), 'https://img.yy.com/noble.png');
      expect(cache.medalFor('不存在'), '');
    });
  });

  group('会话状态机', () {
    late FakeYyTransport transport;

    setUp(() => transport = FakeYyTransport());

    Future<YyDanmakuSession> open() async {
      final connector = YyDanmakuConnector(
        transport: transport,
        sidResolver: (_) async => 54880976,
        subscribeStagger: Duration.zero,
        heartbeatInterval: const Duration(hours: 1),
        chatDedupeWindow: const Duration(seconds: 3),
      );
      final session = await connector.connect(
        const DanmakuSessionRequest(site: 'yy', roomId: '1414787909'),
      );
      return session as YyDanmakuSession;
    }

    test('登录 → 注册 → 订阅 → connected → 弹幕流出 → close 断开', () async {
      final session = await open();
      final socket = transport.sockets.single;

      // 未登录前只有 1 条(常量登录帧)。
      await Future<void>.delayed(Duration.zero);
      expect(socket.sentFrames, hasLength(1));
      expect(socket.sentFrames.first, 778244);

      // 注入登录响应 → 应发出注册帧。
      socket.push(_loginResponseFrame(uid: 999));
      await Future<void>.delayed(Duration.zero);
      expect(socket.sentFrames, contains(775684));

      // 注册成功回执 → 订阅模板全量发出 + connected。
      socket.push(buildYyFrame(775940, Uint8List(8)));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(session.isRegistered, isTrue);
      final subs = socket.sentFrames
          .skip(2) // 登录 + 注册
          .toList();
      expect(subs, hasLength(kYySubscribeTemplates.length));
      expect(
        subs.toSet().difference(const {513035, 512011, 537944, 538456, 538712}),
        isEmpty,
      );

      // 弹幕帧 → 消息流出。
      final future = session.messages.first;
      socket.push(
        _chatFrame(channel: '房', text: '弹幕A', nick: '甲甲'),
      );
      final msg = await future;
      expect(msg.type, DanmakuMessageType.chat);
      expect(msg.text, '弹幕A');
      expect(msg.userName, '甲甲');

      // 同文本 3 秒窗口去重。
      final second = Completer<DanmakuMessage>();
      final sub = session.messages.listen(second.complete);
      socket.push(_chatFrame(channel: '房', text: '弹幕A', nick: '甲甲'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(second.isCompleted, isFalse, reason: '重复文本应被去重');
      // 不同文本放行。
      socket.push(_chatFrame(channel: '房', text: '弹幕B', nick: '甲甲'));
      final msg2 = await second.future;
      expect(msg2.text, '弹幕B');
      await sub.cancel();

      // 关闭 → disconnected。
      final states = <DanmakuSessionState>[];
      final sub2 = session.states.listen(states.add);
      socket.closeFromServer();
      await Future<void>.delayed(Duration.zero);
      expect(states, contains(DanmakuSessionState.disconnected));
      await sub2.cancel();
      await session.close();
    });

    test('sid 解析器把房间号解析为订阅模板的目标 sid', () async {
      String? captured;
      final connector = YyDanmakuConnector(
        transport: transport,
        sidResolver: (roomId) async {
          captured = roomId;
          return 87654321;
        },
        subscribeStagger: Duration.zero,
        heartbeatInterval: const Duration(hours: 1),
      );
      await connector.connect(
        const DanmakuSessionRequest(site: 'yy', roomId: '12345'),
      );
      expect(captured, '12345');
    });

    test('连接错误路径:socket 异常 → disconnected', () async {
      final session = await open();
      final socket = transport.sockets.single;
      final states = <DanmakuSessionState>[];
      final sub = session.states.listen(states.add);
      socket.failFromServer();
      await Future<void>.delayed(Duration.zero);
      expect(states, contains(DanmakuSessionState.disconnected));
      await sub.cancel();
      await session.close();
    });
  });
}

Uint8List _hexToBytes(String hex) {
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

class FakeYyTransport implements DanmakuTransport {
  final sockets = <FakeYySocket>[];
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
    final socket = FakeYySocket();
    sockets.add(socket);
    return socket;
  }
}

class FakeYySocket implements DanmakuSocket {
  final sent = <List<int>>[];

  /// 发出帧的 uri 列表(u32LE @4)。
  List<int> get sentFrames => [
        for (final bytes in sent)
          if (bytes.length >= 8)
            ByteData.sublistView(Uint8List.fromList(bytes))
                .getUint32(4, Endian.little),
      ];

  final _controller = StreamController<Object?>(sync: true);

  void push(List<int> bytes) => _controller.add(bytes);

  void closeFromServer() {
    _controller.add(null); // 触发 onDone 语义由 session 处理
    _controller.close();
  }

  void failFromServer() => _controller.addError(StateError('boom'));

  @override
  Stream<Object?> get data => _controller.stream;

  @override
  void send(List<int> bytes) => sent.add(bytes);

  @override
  Future<void> close() async {
    if (!_controller.isClosed) await _controller.close();
  }
}
