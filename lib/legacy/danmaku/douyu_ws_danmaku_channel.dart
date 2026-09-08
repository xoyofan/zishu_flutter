/// douyu 浏览器 WS 直连弹幕通道。
///
/// 服务端没有 douyu 弹幕 adapter，浏览器直连 `wss://danmuproxy.douyu.com:8506`。
/// 协议移植自 pure_live（AGPL-3.0）：connect 后发 loginreq + joingroup 完成进房，
/// 每 45s 发 `type@=mrkl/` 心跳；断线按指数退避重连（上限 [maxReconnectAttempts] 次）。
///
/// 用 web_socket_channel 的平台无关 [WebSocketChannel.connect]（Web 上编译通过，
/// 禁止 dart:io WebSocket）。
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'danmaku_backoff.dart';
import 'danmaku_channel.dart';
import '../core/models/danmaku_message.dart';
import 'douyu_danmaku_codec.dart';

class DouyuWsDanmakuChannel implements DanmakuChannel {
  DouyuWsDanmakuChannel({
    this.serverUrl = DouyuDanmakuCodec.defaultServerUrl,
    this.heartbeatInterval = const Duration(seconds: 45),
    this.maxReconnectAttempts = 8,
  });

  final String serverUrl;
  final Duration heartbeatInterval;
  final int maxReconnectAttempts;

  @override
  String get site => 'douyu';

  final StreamController<DanmakuMessage> _messages =
      StreamController<DanmakuMessage>.broadcast();
  final StreamController<DanmakuChannelState> _states =
      StreamController<DanmakuChannelState>.broadcast();

  WebSocketChannel? _socket;
  StreamSubscription<dynamic>? _subscription;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  int _generation = 0;
  int _attempt = 0;
  String _roomId = '';

  @override
  Stream<DanmakuMessage> get messages => _messages.stream;

  @override
  Stream<DanmakuChannelState> get states => _states.stream;

  void _setState(DanmakuChannelState state) {
    if (!_states.isClosed) _states.add(state);
  }

  @override
  Future<void> connect({required String roomId}) async {
    final generation = ++_generation;
    _roomId = roomId;
    await _teardown();
    if (generation != _generation) return;
    _attempt = 0;
    await _open(generation);
  }

  Future<void> _open(int generation) async {
    if (generation != _generation) return;
    _setState(DanmakuChannelState.connecting);
    final channel = WebSocketChannel.connect(Uri.parse(serverUrl));
    _socket = channel;
    try {
      await channel.ready;
    } catch (error) {
      // 关闭可能未完成的握手，防止泄漏。
      unawaited(channel.sink.close().catchError((_) {}));
      _scheduleReconnect(generation, '连接失败: $error');
      return;
    }
    if (generation != _generation) {
      unawaited(channel.sink.close().catchError((_) {}));
      return;
    }

    _subscription = channel.stream.listen(
      (data) {
        if (generation != _generation) return;
        _attempt = 0;
        _onFrame(data);
      },
      onError: (Object error) {
        if (generation != _generation) return;
        _scheduleReconnect(generation, '连接错误: $error');
      },
      onDone: () {
        if (generation != _generation) return;
        _scheduleReconnect(generation, '连接被关闭');
      },
      cancelOnError: true,
    );

    // auth + join（对齐 pure_live joinRoom）。
    _sendRaw(DouyuDanmakuCodec.serialize('type@=loginreq/roomid@=$_roomId/'));
    _sendRaw(
      DouyuDanmakuCodec.serialize('type@=joingroup/rid@=$_roomId/gid@=-9999/'),
    );

    _startHeartbeat(generation);
    _setState(DanmakuChannelState.ready);
  }

  void _onFrame(dynamic data) {
    if (data is! List<int>) return; // douyu 弹幕网关只发二进制帧
    final roomId = _roomId;
    for (final packet in DouyuDanmakuCodec.deserializePackets(data)) {
      try {
        final object = DouyuDanmakuCodec.sttToObject(packet);
        if (object is! Map) continue;
        final message = DouyuDanmakuCodec.chatFromStt(
          Map<String, dynamic>.from(object),
          roomId: roomId,
        );
        if (message != null && !_messages.isClosed) _messages.add(message);
      } catch (_) {
        // 单包解析失败不能丢弃同帧后续合法包。
      }
    }
  }

  void _sendRaw(List<int> bytes) {
    try {
      _socket?.sink.add(Uint8List.fromList(bytes));
    } catch (_) {
      // 发送失败交给 stream onError/onDone 触发重连。
    }
  }

  void _startHeartbeat(int generation) {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) {
      if (generation != _generation) return;
      sendHeartbeat();
    });
  }

  /// 手动补发一条心跳（LiveDanmaku.heartbeat 桥接用）。
  void sendHeartbeat() {
    _sendRaw(DouyuDanmakuCodec.serialize('type@=mrkl/'));
  }

  void _scheduleReconnect(int generation, String reason) {
    if (generation != _generation) return;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _setState(DanmakuChannelState.reconnecting);
    _attempt += 1;
    if (_attempt > maxReconnectAttempts) {
      _setState(DanmakuChannelState.closed);
      return;
    }
    _reconnectTimer = Timer(DanmakuBackoff.delay(_attempt - 1), () {
      _open(generation);
    });
  }

  Future<void> _teardown() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    final socket = _socket;
    _socket = null;
    try {
      await socket?.sink.close();
    } catch (_) {}
  }

  @override
  Future<void> disconnect() async {
    _generation += 1;
    await _teardown();
    _setState(DanmakuChannelState.closed);
  }
}
