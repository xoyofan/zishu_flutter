/// LiveDanmaku 契约的远程实现：用 DanmakuChannelResolver 选通道
/// （douyu → 浏览器 WS 直连，其余 → 服务端 SSE），把通道的流桥接到回调。
///
/// 切房/停止用 generation fence：`start`/`stop` 递增代数，旧通道的迟到事件
/// 一律丢弃，防止串房（语义对齐 SFVideoLive useDanmaku 的 generation fence）。
library;

import 'dart:async';

import '../danmaku/danmaku_channel.dart';
import '../danmaku/danmaku_channel_resolver.dart';
import '../danmaku/danmaku_message.dart';
import '../danmaku/douyu_ws_danmaku_channel.dart';
import '../sites/live_danmaku.dart';

class RemoteDanmakuSource implements LiveDanmaku {
  RemoteDanmakuSource({
    required this.site,
    this.resolver = const DanmakuChannelResolver(),
    this.streamApiBaseUrl,
  });

  final String site;
  final DanmakuChannelResolver resolver;

  /// streaming-server base URL（SSE 通道需要；WS 直连不需要）。
  final String? streamApiBaseUrl;

  @override
  void Function(DanmakuMessage message)? onMessage;

  @override
  void Function(String message)? onClose;

  @override
  void Function()? onReady;

  @override
  int heartbeatTime = 45 * 1000;

  DanmakuChannel? _channel;
  StreamSubscription<DanmakuMessage>? _messageSub;
  StreamSubscription<DanmakuChannelState>? _stateSub;
  int _generation = 0;
  bool _connected = false;
  bool _closeNotified = false;

  @override
  bool get isConnected => _connected;

  @override
  Future<void> start({required String room}) async {
    final generation = ++_generation;
    final old = _channel;
    _channel = null;
    await _messageSub?.cancel();
    await _stateSub?.cancel();
    await old?.disconnect();
    if (generation != _generation) return;

    final channel = resolver.resolve(site, streamApiBaseUrl: streamApiBaseUrl);
    _channel = channel;
    _connected = false;
    _closeNotified = false;

    _messageSub = channel.messages.listen((message) {
      if (generation != _generation) return; // fence：旧房消息丢弃
      onMessage?.call(message);
    });
    _stateSub = channel.states.listen((state) {
      if (generation != _generation) return;
      switch (state) {
        case DanmakuChannelState.ready:
          _connected = true;
          _closeNotified = false;
          onReady?.call();
        case DanmakuChannelState.reconnecting:
          _notifyClose('弹幕连接中断，正在重连');
        case DanmakuChannelState.closed:
          _notifyClose('弹幕连接已关闭');
        case DanmakuChannelState.idle:
        case DanmakuChannelState.connecting:
          break;
      }
    });

    await channel.connect(roomId: room);
  }

  void _notifyClose(String message) {
    if (_connected) {
      _connected = false;
      if (!_closeNotified) {
        _closeNotified = true;
        onClose?.call(message);
      }
    }
  }

  @override
  Future<void> stop() async {
    _generation += 1;
    _connected = false;
    await _messageSub?.cancel();
    _messageSub = null;
    await _stateSub?.cancel();
    _stateSub = null;
    final channel = _channel;
    _channel = null;
    await channel?.disconnect();
  }

  @override
  void heartbeat() {
    // douyu WS 通道内部已有定时心跳；此方法供外部手动补发。
    final channel = _channel;
    if (channel is DouyuWsDanmakuChannel) channel.sendHeartbeat();
  }
}
