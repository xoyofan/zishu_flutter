// 分步定位 Dart 连 soop 聊天:纯 TCP → HttpClient 升级 → WebSocket.connect。
import 'dart:async';
import 'dart:io';

Future<void> main() async {
  const host = 'chat-DEE93652.sooplive.com';
  const port = 9000;

  stdout.writeln('1) 纯 TCP Socket.connect...');
  try {
    final socket = await Socket.connect(host, port)
        .timeout(const Duration(seconds: 6));
    stdout.writeln('   TCP OK: ${socket.remoteAddress}');
    socket.destroy();
  } on Object catch (e) {
    stdout.writeln('   TCP FAIL: $e');
  }

  stdout.writeln('2) HttpClient 手动 Upgrade...');
  try {
    final client = HttpClient();
    final request = await client
        .openUrl('GET', Uri.http('$host:$port', '/Websocket/phonics1'))
        .timeout(const Duration(seconds: 6));
    request.headers.set('Origin', 'https://play.sooplive.co.kr');
    request.headers.set('Connection', 'Upgrade');
    request.headers.set('Upgrade', 'websocket');
    request.headers.set('Sec-WebSocket-Version', '13');
    request.headers.set('Sec-WebSocket-Key', 'dGhlIHNhbXBsZSBub25jZQ==');
    request.headers.set('Sec-WebSocket-Protocol', 'chat');
    final response = await request.close().timeout(const Duration(seconds: 6));
    stdout.writeln('   HTTP ${response.statusCode}');
    client.close();
  } on Object catch (e) {
    stdout.writeln('   Upgrade FAIL: $e');
  }

  stdout.writeln('3) WebSocket.connect(带子协议)...');
  try {
    final socket = await WebSocket.connect(
      'ws://$host:$port/Websocket/phonics1',
      protocols: const ['chat'],
    ).timeout(const Duration(seconds: 6));
    stdout.writeln('   WS OK: readyState=${socket.readyState}');
    await socket.close();
  } on Object catch (e) {
    stdout.writeln('   WS FAIL: $e');
  }

  stdout.writeln('4) WebSocket.connect(无子协议)...');
  try {
    final socket = await WebSocket.connect(
      'ws://$host:$port/Websocket/phonics1',
    ).timeout(const Duration(seconds: 6));
    stdout.writeln('   WS OK: readyState=${socket.readyState}');
    await socket.close();
  } on Object catch (e) {
    stdout.writeln('   WS FAIL: $e');
  }
  stdout.writeln('== done ==');
  exit(0);
}
