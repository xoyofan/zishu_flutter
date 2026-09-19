import 'dart:io';
Future<void> main() async {
  final client = HttpClient();
  final request = await client.openUrl('GET', Uri.http('127.0.0.1:19000', '/Websocket/phonics1'));
  request.headers.set('Origin', 'https://play.sooplive.co.kr');
  request.headers.set('Connection', 'Upgrade');
  request.headers.set('Upgrade', 'websocket');
  request.headers.set('Sec-WebSocket-Version', '13');
  request.headers.set('Sec-WebSocket-Key', 'dGhlIHNhbXBsZSBub25jZQ==');
  request.headers.set('Sec-WebSocket-Protocol', 'chat');
  await request.close().timeout(const Duration(seconds: 3)).catchError((_) => null as Object);
  client.close();
  exit(0);
}
