/// 语音字幕的「多句并存」缓冲:每句存活固定时长,过期自动消失。
///
/// 用户口径(2026-09-21):字幕条充分利用播放宽度,多句**横向排列**、
/// 句间留空隙,每句显示 5 秒后消失 —— 而不是只显示最新一句。
///
/// 纯逻辑,不依赖 Flutter/Riverpod,便于确定性单测。
library;

import 'dart:collection';

class CaptionLine {
  const CaptionLine({
    required this.text,
    required this.at,
    this.lifetime = CaptionLineBuffer.defaultLifetime,
  });

  final String text;

  /// 上屏时刻(存活计时的起点)。
  final DateTime at;

  /// 本句存活时长。
  final Duration lifetime;

  DateTime get expiresAt => at.add(lifetime);
}

/// 定长存活的字幕行队列(先进先出)。
class CaptionLineBuffer {
  CaptionLineBuffer({this.lifetime = defaultLifetime});

  /// 每句存活时长(用户口径 5s)。
  static const Duration defaultLifetime = Duration(seconds: 5);

  /// 上限保护:极端情况下(极短句连发)也不至于无限累积。
  static const int maxLines = 12;

  final Duration lifetime;

  final List<CaptionLine> _lines = [];

  List<CaptionLine> get lines => UnmodifiableListView(_lines);

  bool get isEmpty => _lines.isEmpty;

  /// 追加一句;返回新行。
  CaptionLine add(String text, DateTime now) {
    final line = CaptionLine(text: text, at: now, lifetime: lifetime);
    _lines.add(line);
    while (_lines.length > maxLines) {
      _lines.removeAt(0);
    }
    return line;
  }

  /// 移除已过期(存活 ≥ [lifetime])的行;返回是否有变化。
  bool prune(DateTime now) {
    final before = _lines.length;
    _lines.removeWhere((line) => !now.isBefore(line.at.add(lifetime)));
    return _lines.length != before;
  }

  /// 距离最近一次过期的剩余时间;无内容返回 null(调用方据此停掉定时器)。
  Duration? nextExpiryIn(DateTime now) {
    if (_lines.isEmpty) return null;
    var earliest = _lines.first.expiresAt;
    for (final line in _lines) {
      if (line.expiresAt.isBefore(earliest)) earliest = line.expiresAt;
    }
    final remaining = earliest.difference(now);
    return remaining.isNegative ? Duration.zero : remaining;
  }

  void clear() => _lines.clear();
}
