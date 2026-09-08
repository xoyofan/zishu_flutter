/// 重连退避计算（纯逻辑，可测）。
///
/// 指数退避：1s → 2s → 4s → 8s → 16s → 30s（封顶），供 SSE / WS 通道共用。
library;

class DanmakuBackoff {
  static const Duration base = Duration(seconds: 1);
  static const Duration max = Duration(seconds: 30);

  /// [attempt] 从 0 开始；成功连接后应重置为 0。
  static Duration delay(int attempt) {
    if (attempt <= 0) return base;
    final shift = attempt.clamp(0, 5);
    var ms = base.inMilliseconds * (1 << shift);
    if (ms > max.inMilliseconds) ms = max.inMilliseconds;
    return Duration(milliseconds: ms);
  }
}
