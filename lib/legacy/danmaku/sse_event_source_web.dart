/// Web 平台 EventSource 实现（package:web；dart:html 已废弃勿用）。
///
/// 仅本文件触达 Web DOM API；通道与测试只依赖 sse_event_source.dart 接口。
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'sse_event_source.dart';

SseEventSource createEventSource(String url) => WebSseEventSource(url);

/// streaming-server SSE 端点推送的事件名（对齐 sse.ts 的 addEventListener 集合）。
const List<String> kSseEventNames = [
  'ready',
  'chat',
  'meta',
  'error',
  'message',
];

class WebSseEventSource implements SseEventSource {
  final web.EventSource _es;
  final StreamController<SseEvent> _controller =
      StreamController<SseEvent>.broadcast();

  WebSseEventSource(String url) : _es = web.EventSource(url) {
    for (final name in kSseEventNames) {
      _es.addEventListener(
        name,
        (web.Event e) {
          final data = e.isA<web.MessageEvent>()
              ? stringifyMessageData((e as web.MessageEvent).data)
              : '';
          _controller.add(SseEvent(name, data));
        }.toJS,
      );
    }
  }

  /// MessageEvent.data 为 JSAny?；SSE data 是字符串，兜底 dartify 转 String。
  static String stringifyMessageData(JSAny? data) {
    if (data == null) return '';
    if (data.isA<JSString>()) return (data as JSString).toDart;
    return data.dartify()?.toString() ?? '';
  }

  @override
  Stream<SseEvent> get events => _controller.stream;

  @override
  void close() => _es.close();
}
