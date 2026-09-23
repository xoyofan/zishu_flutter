import 'dart:async';
import 'dart:convert';
import 'dart:io';

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

      // ws 优先(wss 在多数网络出口超时,web resolve/soop 同结论)。
      expect(
        transport.lastUrl.toString(),
        'ws://chat.sooplive.co.kr:8088/Websocket/testbj',
      );
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

    test('旧集群域名失败:重取 player_live_api 换新集群,握手带 Origin/UA', () async {
      // 2026-09-19 实测:旧域 chat.sooplive.co.kr 已 NXDOMAIN,上游按出口
      // 轮换下发 chat-XXXX.sooplive.com:9000 动态域;第一轮全失败后必须
      // 重取一次 player_live_api 换新域名再连。
      final fresh = soopFixture('detail_live.json') as Map<String, dynamic>;
      final freshChannel = fresh['CHANNEL'] as Map<String, dynamic>;
      freshChannel['CHDOMAIN'] = 'chat-DEE93652.sooplive.com';
      freshChannel['CHPT'] = '9000';
      http.detailResponseQueue
        ..add(soopFixture('detail_live.json'))
        ..add(fresh);

      final transport = HostBlockingTransport(
        blockedHosts: {'chat.sooplive.co.kr'},
      );
      final connector = SoopDanmakuConnector(
        ParserHttp(client: http),
        transport: transport,
        heartbeatInterval: const Duration(milliseconds: 50),
      );

      final session = await connector.connect(
        const DanmakuSessionRequest(site: 'soop', roomId: 'testbj'),
      );

      expect(transport.attempted, [
        'ws://chat.sooplive.co.kr:8088',
        'wss://chat.sooplive.co.kr:8088',
        // Uri 会把 host 归一为小写。
        'ws://chat-dee93652.sooplive.com:9000',
      ]);
      expect(transport.lastHeaders?['Origin'], 'https://play.sooplive.co.kr');
      expect(transport.lastHeaders?['Referer'], 'https://play.sooplive.co.kr/');
      expect(transport.lastHeaders?['User-Agent'], contains('Chrome'));

      await session.close();
    });

    test('聊天帧字段归一,系统帧被过滤', () async {
      final session = await connector.connect(
        const DanmakuSessionRequest(site: 'soop', roomId: 'testbj'),
      );
      final socket = transport.sockets.single;
      final received = <DanmakuMessage>[];
      final subscription = session.messages.listen(received.add);

      // 真实 0005 聊天帧:文本␌userId␌0␌0␌userType␌昵称␌积分|等级␌-1␌文字色。
      socket.push(
        soopFrame([
          '\x1b\x09000500000600',
          'hello',
          'cdn',
          '0',
          '0',
          '1',
          '张三',
          '268468512',
          '12',
          '16777215',
        ]),
      );
      // 控制码 / 批量行仍被过滤。
      socket.push(
        soopFrame(['\x1b\x09000500000600', '1', 'x', 'x', 'x', 'x', '系统']),
      );
      socket.push(
        soopFrame(['\x1b\x09000500000600', '-1', 'x', 'x', 'x', 'x', '系统']),
      );
      socket.push(
        soopFrame(['\x1b\x09000500000600', 'a|b', 'x', 'x', 'x', 'x', '批量']),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(received, hasLength(1));
      expect(received.single.type, DanmakuMessageType.chat);
      expect(received.single.text, 'hello');
      expect(received.single.userName, '张三');
      expect(received.single.roomId, 'testbj');
      // 文字色 16777215 = 0xFFFFFF(web colorFromPackedInt 同构)。
      expect(received.single.color, 0xFFFFFF);
      expect(received.single.badges.map((b) => b.kind), [
        'subscriber',
        'manager',
        'topfan',
        'fanclub',
      ]);
      expect(received.single.badges.first.level, 12);
      expect(
        received.single.badges.first.url,
        'https://static.file.sooplive.com/spcon/pc_testbj_12.png',
      );

      await subscription.cancel();
      await session.close();
    });

    test('SVC_OGQ_EMOTICON(0109) 独立表情帧归一为 emoji segment', () async {
      final session = await connector.connect(
        const DanmakuSessionRequest(site: 'soop', roomId: 'testbj'),
      );
      final socket = transport.sockets.single;
      final received = <DanmakuMessage>[];
      final subscription = session.messages.listen(received.add);
      socket.push(soopFrame([
        '\x1b\x09010900000600', '你好', '12345', '2', '7', 'user-1',
        '张三', '268468512', '16777215', '0', '0', 'jpg', '12', '1', '',
      ]));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(received, hasLength(1));
      expect(received.single.rawType, 'soop:ogq_emoticon');
      expect(received.single.text, '你好');
      expect(received.single.userName, '张三');
      expect(received.single.segments, hasLength(2));
      expect(received.single.segments.last.isEmoji, isTrue);
      expect(
        received.single.segments.last.url,
        'https://ogq-sticker-global-cdn-z01.afreecatv.com/'
        'sticker/12345/2_160.webp?v=7',
      );
      await subscription.cancel();
      await session.close();
    });

    test('opcode 白名单:非聊天帧一律丢弃', () async {
      final session = await connector.connect(
        const DanmakuSessionRequest(site: 'soop', roomId: 'testbj'),
      );
      final socket = transport.sockets.single;
      final received = <DanmakuMessage>[];
      final subscription = session.messages.listen(received.add);

      // 0001 connect ACK、0002 进房 ACK、0004 观众列表、0127 粉丝勋章:
      // 旧解析器会把它们漏成假弹幕,白名单下必须全部丢弃。
      socket.push(
        soopFrame(['\x1b\x09000100000600', 'hello', '1', '2', '3', '4', '张三']),
      );
      socket.push(
        soopFrame(['\x1b\x09000200001100', 'testbj', '', '', '', '', '']),
      );
      socket.push(
        soopFrame(['\x1b\x09000400000100', '观众', '列表', '', '', '', '']),
      );
      socket.push(
        soopFrame(['\x1b\x09012700000100', '粉丝', '勋章', '', '', '', '']),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(received, isEmpty);

      await subscription.cancel();
      await session.close();
    });

    test('一条 WS 消息拼接多包时只提取 0005 聊天包,无色字段回默认色', () async {
      final session = await connector.connect(
        const DanmakuSessionRequest(site: 'soop', roomId: 'testbj'),
      );
      final socket = transport.sockets.single;
      final received = <DanmakuMessage>[];
      final subscription = session.messages.listen(received.add);

      // 同一条 WS 消息:0004 系统帧 + 0005 聊天帧(无文字色字段)+ 0005 聊天帧。
      final combined = utf8.encode(
        [
          soopText(['\x1b\x09000400000100', '观众', '列表', '', '', '', '']),
          soopText(['\x1b\x09000500000400', '第一条', 'u1', '0', '0', '1', '李四']),
          soopText([
            '\x1b\x09000500000600',
            '第二条',
            'u2',
            '0',
            '0',
            '1',
            '王五',
            '9|5',
            '-1',
            '-1',
          ]),
        ].join(),
      );
      socket.push(combined);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(received.map((m) => m.text), ['第一条', '第二条']);
      expect(received[0].userName, '李四');
      // 无文字色字段 → 0(UI 默认色)。
      expect(received[0].color, 0);
      // -1 按 32 位截断 → 0xFFFFFF(web colorFromPackedInt 同构)。
      expect(received[1].color, 0xFFFFFF);

      await subscription.cancel();
      await session.close();
    });
  });
}

String soopText(List<String> fields) => '${fields.join('\x0c')}\x0c';

List<int> soopFrame(List<String> fields) => utf8.encode(soopText(fields));

class FakeDanmakuTransport implements DanmakuTransport {
  final sockets = <FakeDanmakuSocket>[];
  Uri? lastUrl;
  List<String>? lastProtocols;
  Map<String, String>? lastHeaders;

  @override
  Future<DanmakuSocket> connect(
    Uri url, {
    List<String>? protocols,
    Map<String, String>? headers,
    bool sendAsText = false,
  }) async {
    lastUrl = url;
    lastProtocols = protocols;
    lastHeaders = headers;
    final socket = FakeDanmakuSocket();
    sockets.add(socket);
    return socket;
  }
}

/// 指定 host 的连接直接抛错(模拟旧集群域名 NXDOMAIN/超时),其余正常建连。
class HostBlockingTransport implements DanmakuTransport {
  HostBlockingTransport({required this.blockedHosts});

  final Set<String> blockedHosts;
  final attempted = <String>[];
  Map<String, String>? lastHeaders;

  @override
  Future<DanmakuSocket> connect(
    Uri url, {
    List<String>? protocols,
    Map<String, String>? headers,
    bool sendAsText = false,
  }) async {
    attempted.add('${url.scheme}://${url.host}:${url.port}');
    lastHeaders = headers;
    if (blockedHosts.contains(url.host)) {
      throw const SocketException('blocked host');
    }
    final socket = FakeDanmakuSocket();
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
