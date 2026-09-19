/// 弹幕底层 socket 抽象:默认走 dart:io WebSocket,测试注入内存实现。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'upstream_proxy.dart';

/// 建立弹幕 WebSocket 连接的传输工厂。
abstract interface class DanmakuTransport {
  /// [protocols] 为可选子协议(如 SOOP 要求 `Sec-WebSocket-Protocol: chat`);
  /// [headers] 为额外握手头(如抖音要求 Origin/Cookie)。
  Future<DanmakuSocket> connect(
    Uri url, {
    List<String>? protocols,
    Map<String, String>? headers,
  });
}

/// 已建立的弹幕连接:data 为二进制帧([List<int>])或文本帧(String)。
abstract interface class DanmakuSocket {
  Stream<Object?> get data;
  void send(List<int> bytes);
  Future<void> close();
}

/// dart:io WebSocket 默认实现。
///
/// 自定义头通过 HttpClient 手动完成 Upgrade 握手:纯 `WebSocket.connect`
/// 不支持自定义请求头,而抖音弹幕网关要求 Origin/Cookie。
class IoDanmakuTransport implements DanmakuTransport {
  const IoDanmakuTransport({this.connectTimeout = const Duration(seconds: 15)});

  /// 握手超时:无超时的 connect 在网络受限(非 443 端口被拦等)时会永久挂起,
  /// 让上层弹幕会话永远停在 connecting。超时后抛错交由连接方进入断开态。
  final Duration connectTimeout;

  @override
  Future<DanmakuSocket> connect(
    Uri url, {
    List<String>? protocols,
    Map<String, String>? headers,
  }) async {
    // 统一走手动 Upgrade:HttpClient 接上游代理(CONNECT 隧道)后,
    // WebSocket.connect 的「只认环境变量」限制就被绕开了(海外站弹幕
    // wss 在直连不可达的网络下必须经代理,与 HTTP 层同一条配置)。
    final client = HttpClient();
    if (UpstreamProxy.enabled) {
      client.findProxy = (uri) => UpstreamProxy.findProxyValue;
    }
    try {
      // HttpClient 只认 http/https;先降级 scheme 再手动 Upgrade。
      final requestUrl = switch (url.scheme) {
        'wss' => url.replace(scheme: 'https'),
        'ws' => url.replace(scheme: 'http'),
        _ => url,
      };
      final request = await client
          .openUrl('GET', requestUrl)
          .timeout(connectTimeout);
      headers?.forEach(request.headers.set);
      request.headers
        ..set(HttpHeaders.connectionHeader, 'Upgrade')
        ..set(HttpHeaders.upgradeHeader, 'websocket')
        ..set('Sec-WebSocket-Version', '13')
        ..set('Sec-WebSocket-Key', _webSocketKey());
      if (protocols != null && protocols.isNotEmpty) {
        request.headers.set('Sec-WebSocket-Protocol', protocols.join(', '));
      }
      final response = await request.close().timeout(connectTimeout);
      if (response.statusCode != HttpStatus.switchingProtocols) {
        throw HttpException(
          '弹幕 WebSocket 握手失败: HTTP ${response.statusCode}',
          uri: url,
        );
      }
      final socket = WebSocket.fromUpgradedSocket(
        await response.detachSocket(),
        serverSide: false,
        protocol: response.headers.value('sec-websocket-protocol'),
      );
      return _IoDanmakuSocket(socket);
    } finally {
      client.close();
    }
  }
}

String _webSocketKey() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  return base64.encode(bytes);
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
