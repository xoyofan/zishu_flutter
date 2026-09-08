/// 服务端 SSE 弹幕通道：`GET {streamApiBaseUrl}/api/{site}/danmaku/stream?room=<roomId>`。
///
/// 事件名对齐 SFVideoLive web/src/platforms/connectors/sse.ts：
/// - `ready`：连接就绪；
/// - `chat`：data 为一条弹幕 JSON；
/// - `meta`：房间元信息（暂不消费，预留）；
/// - `error` / onerror：断开后按指数退避重连。
///
/// 重连策略：指数退避（DanmakuBackoff），`ready` 后重置；切房先 close 旧
/// EventSource，generation fence 保证旧连接的迟到事件不会串进新房。
library;

import 'dart:async';
import 'dart:convert';

import 'danmaku_backoff.dart';
import 'danmaku_channel.dart';
import 'danmaku_message.dart';
import 'sse_event_source.dart';

/// 构造 SSE 端点 URL（site/room 均做 URI 编码）。
Uri buildSseUrl(String baseUrl, String site, String roomId) {
  final normalized = baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;
  return Uri.parse(
      '$normalized/api/${Uri.encodeComponent(site)}/danmaku/stream?room=${Uri.encodeComponent(roomId)}');
}

/// 解析 SSE `chat` 事件 data 文本 → [DanmakuMessage]。
///
/// JSON 非法或不是对象时返回 null（吞掉脏包，不中断流）。
DanmakuMessage? parseChatJson(String data, {int seq = 0, String? room}) {
  try {
    final raw = jsonDecode(data);
    if (raw is! Map) return null;
    return DanmakuMessage.fromSseJson(
      Map<String, dynamic>.from(raw),
      seq: seq,
      room: room,
    );
  } catch (_) {
    return null;
  }
}

/// SSE 帧解析器（纯逻辑，可测）。
///
/// Web 端 EventSource 原生完成帧解析；本类用于：
/// 1. 单测直接喂 event 文本验证解析规则；
/// 2. 后续若改用 dio 流式响应自解析 SSE，可直接复用。
class SseEventParser {
  final StringBuffer _buffer = StringBuffer();

  // 跨 push 的帧内状态：半行/半帧内容与当前 event 名、data 收集。
  String _event = 'message';
  final List<String> _dataLines = <String>[];
  bool _hasData = false;

  /// 喂入任意切分的文本块，返回其中完整帧解析出的事件。
  ///
  /// 规则（简化 SSE 规范）：`event:` 设置事件名（默认 `message`）；
  /// `data:` 为载荷（多行以 \n 连接）；`:` 开头的注释忽略；空行派发完整帧；
  /// 末尾不完整行（含已收到的 event:/data: 状态）保留到下次 push。
  List<SseEvent> push(String chunk) {
    _buffer.write(chunk);
    final text = _buffer.toString();
    final events = <SseEvent>[];
    var lineStart = 0;

    void handleLine(String raw) {
      var line = raw.endsWith('\r') ? raw.substring(0, raw.length - 1) : raw;
      if (line.isEmpty) {
        if (_hasData) {
          events.add(SseEvent(_event, _dataLines.join('\n')));
        }
        _event = 'message';
        _dataLines.clear();
        _hasData = false;
        return;
      }
      if (line.startsWith(':')) return;
      if (line.startsWith('event:')) {
        final name = line.substring(6).trim();
        _event = name.isEmpty ? 'message' : name;
      } else if (line.startsWith('data:')) {
        _hasData = true;
        _dataLines.add(
            line.startsWith('data: ') ? line.substring(6) : line.substring(5));
      }
    }

    for (var i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) != 0x0A) continue;
      handleLine(text.substring(lineStart, i));
      lineStart = i + 1;
    }
    _buffer
      ..clear()
      ..write(text.substring(lineStart));
    return events;
  }
}

/// SSE 弹幕通道。
class SseDanmakuChannel implements DanmakuChannel {
  SseDanmakuChannel({required this.site, required this.baseUrl});

  @override
  final String site;

  /// streaming-server base URL（如 http://127.0.0.1:8766）。
  final String baseUrl;

  final StreamController<DanmakuMessage> _messages =
      StreamController<DanmakuMessage>.broadcast();
  final StreamController<DanmakuChannelState> _states =
      StreamController<DanmakuChannelState>.broadcast();

  SseEventSource? _source;
  StreamSubscription<SseEvent>? _subscription;
  Timer? _reconnectTimer;
  int _generation = 0;
  int _attempt = 0;
  int _seq = 0;

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
    await _teardown();
    if (generation != _generation) return;
    _open(generation, roomId);
  }

  void _open(int generation, String roomId) {
    if (generation != _generation) return;
    _setState(DanmakuChannelState.connecting);
    final SseEventSource source;
    try {
      source = createEventSource(buildSseUrl(baseUrl, site, roomId).toString());
    } catch (error) {
      _scheduleReconnect(generation, roomId, 'EventSource 创建失败: $error');
      return;
    }
    _source = source;
    _subscription = source.events.listen(
      (event) => _handleEvent(event, generation, roomId),
      onDone: () => _scheduleReconnect(generation, roomId, 'SSE 流结束'),
      onError: (Object error) =>
          _scheduleReconnect(generation, roomId, 'SSE 流错误: $error'),
    );
  }

  void _handleEvent(SseEvent event, int generation, String roomId) {
    if (generation != _generation) return; // generation fence：旧房事件丢弃
    switch (event.event) {
      case 'ready':
        _attempt = 0;
        _setState(DanmakuChannelState.ready);
      case 'chat':
        _seq += 1;
        final message = parseChatJson(event.data, seq: _seq, room: roomId);
        if (message != null && !_messages.isClosed) _messages.add(message);
      case 'error':
        _scheduleReconnect(generation, roomId, 'SSE error 事件');
      default:
        // meta / message（心跳注释等）暂不消费。
        break;
    }
  }

  void _scheduleReconnect(int generation, String roomId, String reason) {
    if (generation != _generation) return;
    _setState(DanmakuChannelState.reconnecting);
    _attempt += 1;
    _reconnectTimer = Timer(DanmakuBackoff.delay(_attempt - 1), () {
      _open(generation, roomId);
    });
  }

  Future<void> _teardown() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    _source?.close();
    _source = null;
  }

  @override
  Future<void> disconnect() async {
    _generation += 1;
    await _teardown();
    _setState(DanmakuChannelState.closed);
  }
}
