/// 卡顿(缓冲)时长记账:跟踪 buffering 真→假转换,输出每次卡顿的持续毫秒。
///
/// 纯 Dart、无 Flutter 依赖:时间源 [now] 可注入,便于单测确定性推进。
/// 本类只做内存记账 —— 不写文件、不引用 PlaybackLog;落盘
/// (`stall_begin` / `stall_end`)由播放器接线层负责。
///
/// 语义:
/// - [begin] 在已处于卡顿时返回 false 且**不重置起点**(mpv 对同一故障会
///   反复置位 buffering,重置会让计时永远归零);
/// - [end] 在无未结算 begin 时返回 null(孤立的 false 直接忽略);
/// - [reset] 丢弃未结算的 begin(open/切源/释放时调用,避免跨会话计时)。
library;

class BufferingStallTracker {
  BufferingStallTracker({DateTime Function()? now})
      : _now = now ?? DateTime.now;

  /// 时间源注入点;生产路径为 `DateTime.now`。
  final DateTime Function() _now;

  DateTime? _beganAt;

  /// 当前是否处于未结算的卡顿中。
  bool get isStalling => _beganAt != null;

  /// 记卡顿开始。返回 true 表示这是一次新卡顿;已在卡顿时返回 false,
  /// 不重置起点。
  bool begin() {
    if (_beganAt != null) return false;
    _beganAt = _now();
    return true;
  }

  /// 记卡顿结束,返回持续毫秒;无未结算的 begin 时返回 null。
  int? end() {
    final beganAt = _beganAt;
    if (beganAt == null) return null;
    _beganAt = null;
    return _now().difference(beganAt).inMilliseconds;
  }

  /// 跨会话重置:丢弃未结算的 begin,此后 [end] 返回 null。
  void reset() => _beganAt = null;
}
