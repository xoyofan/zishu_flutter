/// 弹幕底层 socket 抽象:默认走 dart:io WebSocket,测试注入内存实现。
library;

import 'dart:async';
import 'dart:io';

/// 建立弹幕 WebSocket 连接的传输工厂。
abstract interface class DanmakuTransport {
  Future<DanmakuSocket> connect(Uri url);
}

/// 已建立的弹幕连接:data 为二进制帧([List<int>])或文本帧(String)。
abstract interface class DanmakuSocket {
  Stream<Object?> get data;
  void send(List<int> bytes);
  Future<void> close();
}

/// dart:io WebSocket 默认实现。
class IoDanmakuTransport implements DanmakuTransport {
  const IoDanmakuTransport();

  @override
  Future<DanmakuSocket> connect(Uri url) async {
    final socket = await WebSocket.connect(url.toString());
    return _IoDanmakuSocket(socket);
  }
}

class _IoDanmakuSocket implements DanmakuSocket {
  _IoDanmakuSocket(this._socket);

  final WebSocket _socket;

  @override
  Stream<Object?> get data => _socket;

  @override
  void send(List<int> bytes) => _socket.add(bytes);

  @override
  Future<void> close() => _socket.close();
}
