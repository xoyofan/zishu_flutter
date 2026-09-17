/// 播放请求头卫生化:统一头名大小写、剔除会打断 HTTP 头行的控制字符,
/// 避免宿主播放器(mpv/ffmpeg)收到畸形头而拒绝打开媒体流。
///
/// 纯 Dart、无外部依赖;各平台新增的播放头都必须先经 [sanitizeHeaders]
/// 归一,再赋给 StreamLine.headers。
library;

final RegExp _headerNamePattern = RegExp(r'^[A-Za-z0-9-]+$');
final RegExp _headerValueBreakers = RegExp(r'[\r\n\u0000]+');

/// 头名归一:trim + 小写;不合法的头名返回空串(调用方据此丢弃)。
String sanitizeHeaderName(String name) {
  final normalized = name.trim().toLowerCase();
  return _headerNamePattern.hasMatch(normalized) ? normalized : '';
}

/// 头值卫生化:CR/LF/NUL 替换为空格后 trim(防头注入与头行截断)。
String sanitizeHeaderValue(String value) =>
    value.replaceAll(_headerValueBreakers, ' ').trim();

/// 归一化整组播放头:丢弃非法头名与空值,输出不可变 Map。
Map<String, String> sanitizeHeaders(Map<String, String> headers) {
  final result = <String, String>{};
  for (final entry in headers.entries) {
    final name = sanitizeHeaderName(entry.key);
    if (name.isEmpty) continue;
    final value = sanitizeHeaderValue(entry.value);
    if (value.isEmpty) continue;
    result[name] = value;
  }
  return Map<String, String>.unmodifiable(result);
}
