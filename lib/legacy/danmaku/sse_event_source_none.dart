/// 非 Web 平台桩：SSE EventSource 仅在 Web 可用。
library;

import 'sse_event_source.dart';

SseEventSource createEventSource(String url) =>
    throw UnsupportedError('SSE EventSource 仅在 Web 平台可用');
