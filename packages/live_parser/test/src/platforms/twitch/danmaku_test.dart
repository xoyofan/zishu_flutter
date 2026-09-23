import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:live_parser/live_parser.dart';
import 'package:live_parser/src/platforms/twitch/danmaku.dart';
import 'package:live_parser/src/platforms/twitch/twitch_site.dart';
import 'package:test/test.dart';

void main() {
  group('Twitch 弹幕会话(fake transport)', () {
    late FakeIrcTransport transport;
    late TwitchDanmakuConnector connector;

    setUp(() {
      transport = FakeIrcTransport();
      connector = TwitchDanmakuConnector(transport: transport);
    });

    test('注册项声明弹幕能力', () {
      final registration = buildTwitchRegistration(
        httpClient: FakeNeverHttp(),
        danmakuTransport: transport,
      );
      expect(registration.capabilities.danmaku, isTrue);
      expect(registration.danmaku, isA<TwitchDanmakuConnector>());
    });

    test('连接:匿名 justinfan 握手;JOIN 等 001 后才发', () async {
      final session = await connector.connect(
        const DanmakuSessionRequest(site: 'twitch', roomId: 'SomeChannel'),
      );
      final socket = transport.sockets.single;

      expect(transport.lastUrl.toString(), 'wss://irc-ws.chat.twitch.tv');
      // IRC 行必须走 TEXT 帧:BINARY 帧被 Twitch tmi 网关直接断连
      // (2026-09-20 探针实证,见 DanmakuTransport.connect 注释)。
      expect(transport.lastSendAsText, isTrue,
          reason: 'Twitch 必须以 TEXT 帧发送,否则连接被上游秒断');
      List<String> linesOf() => socket.rawSent
          .map(utf8.decode)
          .map((l) => l.trimRight())
          .toList();
      var lines = linesOf();
      expect(lines, contains('CAP REQ :twitch.tv/tags'));
      expect(
        lines.where((l) => l.startsWith('NICK justinfan')),
        hasLength(1),
        reason: '匿名只读账号,每连接一个',
      );
      // 注册未完成(001 前)发 JOIN 会被上游静默丢弃:绝不能提前发。
      expect(lines.where((l) => l.startsWith('JOIN #')), isEmpty);

      socket.pushText(':tmi.twitch.tv 001 justinfan8123 :Welcome, GLHF!');
      await Future<void>.delayed(Duration.zero);
      lines = linesOf();
      expect(lines, contains('JOIN #somechannel'), reason: '频道统一小写');

      await session.close();
      expect(socket.closeCount, 1);
    });

    test('PRIVMSG 归一:tags/display-name/color/emotes 段', () async {
      final session = await connector.connect(
        const DanmakuSessionRequest(site: 'twitch', roomId: 'somechannel'),
      );
      final socket = transport.sockets.single;
      final received = <DanmakuMessage>[];
      final subscription = session.messages.listen(received.add);

      socket.pushText(
        '@badge-info=;badges=moderator/1,vip/4;color=#1E90FF;display-name=张三;emotes=25:0-4;id=abc-123;'
        'tmi-sent-ts=1700000000000;user-id=42'
        ' :zhangsan!zhangsan@zhangsan.tmi.twitch.tv PRIVMSG #somechannel :Kappa 你好',
      );
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(1));
      final message = received.single;
      expect(message.type, DanmakuMessageType.chat);
      expect(message.roomId, 'somechannel');
      expect(message.userName, '张三');
      expect(message.userId, 'zhangsan');
      expect(message.text, 'Kappa 你好');
      expect(message.color, 0x1E90FF);
      expect(message.id, 'abc-123');
      expect(message.sentAt, DateTime.fromMillisecondsSinceEpoch(1700000000000));
      // emotes 区间是码点下标:Kappa(0-4)为表情段,「 你好」为文本段。
      expect(message.segments, hasLength(2));
      expect(message.segments[0].isEmoji, isTrue);
      expect(message.segments[0].text, '[Kappa]');
      expect(message.segments[0].name, 'Kappa');
      expect(message.badges, hasLength(1));
      expect(message.badges.single.kind, 'twitch');
      expect(message.badges.single.name, 'vip', reason: 'Web 优先级 vip 高于 moderator');
      expect(message.badges.single.url, contains('/badges/v1/'));
      expect(
        message.segments[0].url,
        'https://static-cdn.jtvnw.net/emoticons/v2/25/default/dark/1.0',
      );
      expect(message.segments[1].isEmoji, isFalse);
      expect(message.segments[1].text, ' 你好');

      await subscription.cancel();
      await session.close();
    });

    test('无 display-name 回退登录名;无 color 按 0', () async {
      final session = await connector.connect(
        const DanmakuSessionRequest(site: 'twitch', roomId: 'chan'),
      );
      final socket = transport.sockets.single;
      final received = <DanmakuMessage>[];
      final subscription = session.messages.listen(received.add);

      socket.pushText(
        '@badges=;color=;display-name=;emotes='
        ' :foo!foo@foo.tmi.twitch.tv PRIVMSG #chan :hello',
      );
      await Future<void>.delayed(Duration.zero);

      expect(received.single.userName, 'foo');
      expect(received.single.color, 0);
      expect(received.single.segments, isEmpty, reason: 'emotes 标签为空不出段');

      await subscription.cancel();
      await session.close();
    });

    test('一条 WS 消息多行 IRC:PING 回 PONG,非 PRIVMSG 行忽略', () async {
      final session = await connector.connect(
        const DanmakuSessionRequest(site: 'twitch', roomId: 'chan'),
      );
      final socket = transport.sockets.single;
      final received = <DanmakuMessage>[];
      final subscription = session.messages.listen(received.add);

      socket.pushText(
        ':tmi.twitch.tv 001 justinfan8123>Welcome, GLHF!\r\n'
        'PING :tmi.twitch.tv\r\n'
        ':justinfan8123!justinfan8123@justinfan8123.tmi.twitch.tv JOIN #chan\r\n'
        '@color=#0000FF;display-name=Bar;emotes= '
        ':bar!bar@bar.tmi.twitch.tv PRIVMSG #chan :hi\r\n',
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        socket.rawSent.map(utf8.decode).any((l) => l.startsWith('PONG :tmi.twitch.tv')),
        isTrue,
      );
      expect(received, hasLength(1));
      expect(received.single.userName, 'Bar');
      expect(received.single.text, 'hi');

      await subscription.cancel();
      await session.close();
    });

    test('RECONNECT 按断开上报', () async {
      final session = await connector.connect(
        const DanmakuSessionRequest(site: 'twitch', roomId: 'chan'),
      );
      final socket = transport.sockets.single;
      final states = <DanmakuSessionState>[];
      final subscription = session.states.listen(states.add);

      socket.pushText(':tmi.twitch.tv RECONNECT');
      await Future<void>.delayed(Duration.zero);

      expect(states, contains(DanmakuSessionState.disconnected));

      await subscription.cancel();
      await session.close();
    });
  });
}

class FakeNeverHttp extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    throw StateError('本用例不应发起 HTTP 请求');
  }
}

class FakeIrcTransport implements DanmakuTransport {
  final sockets = <FakeIrcSocket>[];
  Uri? lastUrl;
  bool? lastSendAsText;

  @override
  Future<DanmakuSocket> connect(
    Uri url, {
    List<String>? protocols,
    Map<String, String>? headers,
    bool sendAsText = false,
  }) async {
    lastUrl = url;
    lastSendAsText = sendAsText;
    final socket = FakeIrcSocket();
    sockets.add(socket);
    return socket;
  }
}

class FakeIrcSocket implements DanmakuSocket {
  final rawSent = <List<int>>[];
  int closeCount = 0;

  final _controller = StreamController<Object?>.broadcast();

  void pushText(String text) => _controller.add(text);

  @override
  Stream<Object?> get data => _controller.stream;

  @override
  void send(List<int> bytes) => rawSent.add(Uint8List.fromList(bytes));

  @override
  Future<void> close() async {
    closeCount++;
  }
}
