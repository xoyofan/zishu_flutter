/// SSE EventSource 平台入口（条件导入桩）。
///
/// 仅 Web 平台提供真实实现（sse_event_source_web.dart，基于 package:web）；
/// 非 Web 平台（含 VM 单测）走 stub，调用即抛 UnsupportedError。
/// 单测只测纯逻辑，不触达这里。
library;

export 'sse_event_source_none.dart'
    if (dart.library.js_interop) 'sse_event_source_web.dart';

/// 服务端按事件名推送的一条 SSE 事件（`event:` + `data:`）。
class SseEvent {
  final String event;
  final String data;

  const SseEvent(this.event, this.data);
}

/// EventSource 薄封装接口：打开即连接，[close] 幂等。
abstract interface class SseEventSource {
  Stream<SseEvent> get events;

  void close();
}
