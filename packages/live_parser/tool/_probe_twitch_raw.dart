// 探针:twitch IRC 原始报文打印(定位 join/消息问题)。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  final socket = await WebSocket.connect('wss://irc-ws.chat.twitch.tv:443')
      .timeout(const Duration(seconds: 15));
  socket.listen(
    (data) => stdout.writeln('<< $data'),
    onDone: () => stdout.writeln('<< [done]'),
    onError: (Object e) => stdout.writeln('<< [error] $e'),
  );
  socket.add(utf8.encode('CAP REQ :twitch.tv/tags\r\n'));
  socket.add(utf8.encode('PASS SCHMOOPIIE\r\n'));
  socket.add(utf8.encode('NICK justinfan81234\r\n'));
  Timer(const Duration(seconds: 20), () {
    stdout.writeln('== 20s 到,退出 ==');
    socket.close();
    exit(0);
  });
  // 收到 001 后再 JOIN(在 listen 回调里判断)太绕,这里直接定时 3s 后 JOIN
  // 观察 JOIN 是否被受理(应回显 JOIN 且开始来 PRIVMSG)。
  Timer(const Duration(seconds: 3), () {
    stdout.writeln('>> JOIN #ibai');
    socket.add(utf8.encode('JOIN #ibai\r\n'));
  });
}
