import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:live_parser/src/http/danmaku_transport.dart';
import 'package:test/test.dart';

void main() {
  group('IoDanmakuTransport 裸升级', () {
    test('自定义头路径:请求头保持规范大小写;101 后立刻可用(含同包残留回放)',
        () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final requests = <String>[];
      final upgraded = Completer<void>();
      Socket? clientSocket;

      server.listen((client) {
        final buffer = <int>[];
        client.listen((data) {
          if (upgraded.isCompleted) return; // 升级后忽略后续(帧由断言覆盖)
          buffer.addAll(data);
          final text = latin1.decode(data);
          requests.add(text);
          if (!text.contains('\r\n\r\n')) return;
          clientSocket = client;
          // 101 响应与一个未掩码文本帧「hello」同包发出,验证残留字节回放。
          client.add(latin1.encode(
            'HTTP/1.1 101 Switching Protocols\r\n'
            'Upgrade: websocket\r\n'
            'Connection: Upgrade\r\n'
            'Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=\r\n'
            '\r\n',
          ));
          // 未掩码文本帧「hello」:FIN+text(0x81)、长度 5、payload。
          client.add([0x81, 0x05, 104, 101, 108, 108, 111]);
          upgraded.complete();
        });
      });

      final transport = IoDanmakuTransport(
        connectTimeout: const Duration(seconds: 3),
      );
      final socket = await transport.connect(
        Uri.parse('ws://127.0.0.1:${server.port}/Websocket/testbj'),
        protocols: const ['chat'],
        headers: const {'Origin': 'https://play.sooplive.co.kr'},
      );

      await upgraded.future;
      expect(requests, hasLength(1), reason: '升级请求必须一次写出');
      final request = requests.first;
      // 规范大小写:SOOP 聊天服按大小写匹配升级头,全小写会被黑洞(实测)。
      expect(request, contains('Upgrade: websocket'));
      expect(request, contains('Connection: Upgrade'));
      expect(request, contains('Sec-WebSocket-Version: 13'));
      expect(request, contains('Sec-WebSocket-Key: '));
      expect(request, contains('Sec-WebSocket-Protocol: chat'));
      expect(request, contains('Origin: https://play.sooplive.co.kr'));
      expect(request, isNot(contains('upgrade: websocket')));

      // 101 同包残留的「hello」帧必须经回放通道到达。
      final received = <Object?>[];
      final subscription = socket.data.listen(received.add);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(received, contains('hello'));

      await subscription.cancel();
      await socket.close();
      clientSocket?.destroy();
      await server.close();
    });

    test('非 101 响应抛握手异常', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((client) {
        client.listen((data) {
          if (latin1.decode(data).contains('\r\n\r\n')) {
            client.add(latin1.encode(
              'HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n',
            ));
          }
        });
      });

      final transport = IoDanmakuTransport(
        connectTimeout: const Duration(seconds: 3),
      );

      // 带自定义头强制走裸升级路径,断言非 101 的类型化异常。
      await expectLater(
        transport.connect(
          Uri.parse('ws://127.0.0.1:${server.port}/x'),
          headers: const {'Origin': 'https://play.sooplive.co.kr'},
        ),
        throwsA(
          isA<HttpException>().having(
            (e) => e.message,
            'message',
            contains('404'),
          ),
        ),
      );
      await server.close();
    });
  });
}
