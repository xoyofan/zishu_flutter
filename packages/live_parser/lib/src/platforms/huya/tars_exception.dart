/// Tars 编解码异常。
library;

class TarsEncodeException implements Exception {
  const TarsEncodeException(this.message);

  final String message;

  @override
  String toString() => 'TarsEncodeException: $message';
}

class TarsDecodeException implements Exception {
  const TarsDecodeException(this.message);

  final String message;

  @override
  String toString() => 'TarsDecodeException: $message';
}
