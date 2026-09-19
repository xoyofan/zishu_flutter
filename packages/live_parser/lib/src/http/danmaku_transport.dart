/// 弹幕底层 socket 抽象:默认走 dart:io WebSocket,测试注入内存实现。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

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
/// 带自定义头(或需走代理)时用**裸 socket 手工 Upgrade**:dart:io 的
/// HttpClient/WebSocket.connect 把请求头名全部写成小写,而 SOOP 聊天服务
/// 器按规范大小写匹配升级头、全小写直接黑洞(2026-09-20 实测:curl 规范
/// 大小写 101、全小写 000;TCP 可达但永不响应)。手工升级逐字节写出规范
/// 大小写,再经 [WebSocket.fromUpgradedSocket] 回填帧层。
///
/// 代理(海外站弹幕 wss 直连不可达)经 CONNECT 隧道,与 HTTP 层共用同一
/// 条 [UpstreamProxy] 配置。RawSocket 是单订阅事件流,整个连接周期共用
/// 一个 [_RawEventTap] 泵分发读/写/关闭事件。
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
    // 无自定义头且无代理:dart:io 原生路径(对端为常规实现,小写头无碍)。
    if ((headers == null || headers.isEmpty) && !UpstreamProxy.enabled) {
      final socket = await WebSocket.connect(
        url.toString(),
        protocols: protocols,
      ).timeout(connectTimeout);
      return _IoDanmakuSocket(socket);
    }

    final (tap, _) = await _dial(url);
    try {
      final handshake = await _upgrade(tap, url, protocols, headers);
      final webSocket = WebSocket.fromUpgradedSocket(
        _RawUpgradedSocket(tap),
        serverSide: false,
        protocol: handshake.protocol,
      );
      return _IoDanmakuSocket(webSocket);
    } on Object {
      tap.dispose();
      rethrow;
    }
  }

  /// 建立到目标的连接(直连或经代理 CONNECT 隧道;wss 做 TLS)。
  ///
  /// 返回 (tap, raw)。**RawSocket 事件流只能 listen 一次**:
  /// - ws+代理:CONNECT 与后续升级/帧层共用同一个 tap;
  /// - wss+代理:TLS 交给 [RawSecureSocket.secure] 时把 tap 的 subscription
  ///   移交出去(其 subscription 参数会替换事件处理器),TLS 后换绑新 tap。
  Future<(_RawEventTap, RawSocket)> _dial(Uri url) async {
    final isSecure = url.scheme == 'wss' || url.scheme == 'https';
    final port = url.port != 0 ? url.port : (isSecure ? 443 : 80);

    if (!UpstreamProxy.enabled) {
      if (isSecure) {
        final raw = await RawSecureSocket.connect(
          url.host,
          port,
          timeout: connectTimeout,
        );
        return (_RawEventTap(raw, connectTimeout), raw);
      }
      final raw = await RawSocket.connect(
        url.host,
        port,
        timeout: connectTimeout,
      );
      return (_RawEventTap(raw, connectTimeout), raw);
    }

    final proxyHostPort = UpstreamProxy.hostPort!;
    final separator = proxyHostPort.lastIndexOf(':');
    final proxyHost =
        separator < 0 ? proxyHostPort : proxyHostPort.substring(0, separator);
    final proxyPort = separator < 0
        ? 80
        : int.tryParse(proxyHostPort.substring(separator + 1)) ?? 80;
    final raw =
        await RawSocket.connect(proxyHost, proxyPort, timeout: connectTimeout);
    final tap = _RawEventTap(raw, connectTimeout);
    // CONNECT 隧道:请求头同样保持规范大小写。
    _rawWriteAll(tap, latin1.encode(
      'CONNECT ${url.host}:$port HTTP/1.1\r\n'
      'Host: ${url.host}:$port\r\n'
      'Proxy-Connection: keep-alive\r\n'
      '\r\n',
    ));
    final response = await _waitForHeader(tap);
    final statusLine = _statusLineOf(response.headerBytes);
    if (!statusLine.contains(' 200')) {
      throw HttpException('代理 CONNECT 失败: $statusLine', uri: url);
    }
    if (!isSecure) {
      // ws:隧道已就绪,CONNECT 与升级/帧层继续共用同一个 tap。
      return (tap, raw);
    }
    // TLS 接管 tap 的订阅(secure 的 subscription 参数会替换事件处理器),
    // 握手完成后事件流换了新对象,换绑新 tap。
    final secureRaw = await RawSecureSocket.secure(
      raw,
      subscription: tap.subscription,
      host: url.host,
    ).timeout(connectTimeout);
    return (_RawEventTap(secureRaw, connectTimeout), secureRaw);
  }

  /// 写升级请求(逐字节控制头部大小写)并读响应头;返回 101 与协商子协议。
  Future<({String? protocol})> _upgrade(
    _RawEventTap tap,
    Uri url,
    List<String>? protocols,
    Map<String, String>? headers,
  ) async {
    final port = url.port != 0 ? url.port : (url.scheme == 'wss' ? 443 : 80);
    final hostHeader =
        port == 80 || port == 443 ? url.host : '${url.host}:$port';
    final path = '${url.path.isEmpty ? '/' : url.path}'
        '${url.query.isEmpty ? '' : '?${url.query}'}';
    final request = StringBuffer()
      ..write('GET $path HTTP/1.1\r\n')
      ..write('Host: $hostHeader\r\n')
      ..write('Upgrade: websocket\r\n')
      ..write('Connection: Upgrade\r\n')
      ..write('Sec-WebSocket-Key: ${_webSocketKey()}\r\n')
      ..write('Sec-WebSocket-Version: 13\r\n');
    if (protocols != null && protocols.isNotEmpty) {
      request.write('Sec-WebSocket-Protocol: ${protocols.join(', ')}\r\n');
    }
    headers?.forEach((name, value) => request.write('$name: $value\r\n'));
    request.write('\r\n');
    _rawWriteAll(tap, latin1.encode(request.toString()));

    final response = await _waitForHeader(tap);
    final statusLine = _statusLineOf(response.headerBytes);
    if (!statusLine.contains(' 101')) {
      throw HttpException('弹幕 WebSocket 握手失败: $statusLine', uri: url);
    }
    return (
      protocol: _headerValueOf(response.headerBytes, 'sec-websocket-protocol'),
    );
  }
}

/// 握手响应:状态行 + 头(到 \r\n\r\n 为止)。
class _HeaderBytes {
  const _HeaderBytes(this.headerBytes);
  final List<int> headerBytes;
}

/// 等到缓冲里出现完整 HTTP 头(\r\n\r\n);消费掉头字节,残留留给帧层。
Future<_HeaderBytes> _waitForHeader(_RawEventTap tap) {
  final completer = Completer<_HeaderBytes>();
  void check() {
    final end = tap.headerEndIndex();
    if (end < 0) return;
    final headerBytes = tap.takeBytes(length: end + 4);
    if (!completer.isCompleted) completer.complete(_HeaderBytes(headerBytes));
  }

  tap
    ..onRead = check
    ..onClosed = () {
      if (!completer.isCompleted) {
        completer.completeError(
          const SocketException('连接在 WebSocket 握手中关闭'),
        );
      }
    };
  check();
  return completer.future.timeout(tap.connectTimeout);
}

int _headerEndIndex(List<int> bytes) {
  for (var i = 0; i + 3 < bytes.length; i++) {
    if (bytes[i] == 13 &&
        bytes[i + 1] == 10 &&
        bytes[i + 2] == 13 &&
        bytes[i + 3] == 10) {
      return i;
    }
  }
  return -1;
}

String _statusLineOf(List<int> headerBytes) =>
    latin1.decode(headerBytes).split('\r\n').first;

/// 大小写不敏感地取响应头值;无该头返回 null。
String? _headerValueOf(List<int> headerBytes, String name) {
  for (final line in latin1.decode(headerBytes).split('\r\n').skip(1)) {
    final colon = line.indexOf(':');
    if (colon <= 0) continue;
    if (line.substring(0, colon).trim().toLowerCase() == name) {
      return line.substring(colon + 1).trim();
    }
  }
  return null;
}

String _webSocketKey() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  return base64.encode(bytes);
}

/// RawSocket 是**单订阅**事件流(重复 listen 抛「already been listened to」),
/// 连接全程共用本泵:事件持续读进 [buffer],消费方通过回调拿数据。
class _RawEventTap {
  _RawEventTap(this.raw, this.connectTimeout) {
    subscription = raw.listen(_dispatch);
    raw.readEventsEnabled = true;
  }

  final RawSocket raw;
  late final StreamSubscription<RawSocketEvent> subscription;

  /// 该连接的握手超时(与上层 [IoDanmakuTransport.connectTimeout] 同值)。
  final Duration connectTimeout;

  /// 尚未被消费方取走的字节(握手头/残留帧都在这里流转)。
  final List<int> buffer = <int>[];

  /// 新数据到达。
  void Function()? onRead;

  /// 内核写缓冲腾出(可继续 write)。
  void Function()? onWrite;

  /// 连接关闭(读方向 EOF 或断开)。
  void Function()? onClosed;

  /// 连接持有方不再需要时关整条 socket。
  void dispose() => raw.close();

  void _dispatch(RawSocketEvent event) {
    switch (event) {
      case RawSocketEvent.read:
        final chunk = raw.read();
        if (chunk != null && chunk.isNotEmpty) {
          buffer.addAll(chunk);
          onRead?.call();
        }
      case RawSocketEvent.write:
        onWrite?.call();
      case RawSocketEvent.readClosed:
      case RawSocketEvent.closed:
        onClosed?.call();
    }
  }

  /// 取走缓冲前 [length] 字节;不传取全部。
  Uint8List takeBytes({int? length}) {
    final effective = length ?? buffer.length;
    final taken = Uint8List.fromList(buffer.sublist(0, effective));
    buffer.removeRange(0, effective);
    return taken;
  }

  /// 头结束位置(\r\n\r\n 后一位);没有返回 -1。
  int headerEndIndex() => _headerEndIndex(buffer);
}

/// 把整块字节写到 RawSocket;内核缓冲满时经 [tap.onWrite] 续写。
Future<void> _rawWriteAll(_RawEventTap tap, List<int> bytes) {
  final completer = Completer<void>();
  var offset = 0;
  void flush() {
    while (offset < bytes.length) {
      final written = tap.raw.write(bytes, offset);
      if (written <= 0) {
        tap.onWrite = flush;
        tap.raw.writeEventsEnabled = true;
        return;
      }
      offset += written;
    }
    tap.onWrite = null;
    if (!completer.isCompleted) completer.complete();
  }

  flush();
  return completer.future;
}

/// RawSocket → dart:io [Socket] 适配:握手残留经 [_RawEventTap.buffer] 回放,
/// 之后的数据由泵持续推进。[WebSocket.fromUpgradedSocket] 需要一个 Socket 实例。
class _RawUpgradedSocket implements Socket {
  _RawUpgradedSocket(this._tap);

  final _RawEventTap _tap;

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List data)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final controller = StreamController<Uint8List>();
    controller.onListen = () {
      if (_tap.buffer.isNotEmpty) {
        controller.add(_tap.takeBytes());
      }
      _tap
        ..onRead = () {
          if (_tap.buffer.isNotEmpty) controller.add(_tap.takeBytes());
        }
        ..onClosed = () {
          _tap.onRead = null;
          controller.close();
        };
    };
    return controller.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  final _pendingWrites = <int>[];

  @override
  void add(List<int> bytes) {
    _pendingWrites.addAll(bytes);
    _flush();
  }

  void _flush() {
    while (_pendingWrites.isNotEmpty) {
      final written = _tap.raw.write(_pendingWrites);
      if (written <= 0) {
        _tap
          ..onWrite = _flush
          ..raw.writeEventsEnabled = true;
        return;
      }
      _pendingWrites.removeRange(0, written);
    }
  }

  @override
  Future addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      add(chunk);
    }
  }

  @override
  void write(Object? data) {
    if (data is String) add(utf8.encode(data));
  }

  @override
  Future flush() => Future.value();

  @override
  Future close() async {
    // 尽力把排队帧写出后整条关闭;会话语义是终端清理(close 后不再使用),
    // 对端 close 帧不再等待。
    _flush();
    _tap.dispose();
  }

  @override
  void destroy() => _tap.dispose();

  RawSocket? getRawSocket() => _tap.raw;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('_RawUpgradedSocket 不支持 ${invocation.memberName}');
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
