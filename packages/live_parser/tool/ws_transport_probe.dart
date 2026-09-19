import 'package:live_parser/live_parser.dart';

Future<void> main() async {
  UpstreamProxy.configure('127.0.0.1:7897');
  final transport = IoDanmakuTransport();
  try {
    final socket = await transport.connect(
      Uri.parse('wss://irc-ws.chat.twitch.tv:443/'),
    ).timeout(const Duration(seconds: 12));
    print('transport ws: connected');
    socket.send('NICK justinfan12345\r\n'.codeUnits);
    var count = 0;
    await for (final _ in socket.data) {
      count++;
      if (count >= 2) break;
    }
    print('frames: $count');
    await socket.close();
  } catch (e) {
    print('transport ws FAIL: $e');
  }
}
