/// 有界自动重连策略(纯 Dart,无 Flutter 依赖)。
///
/// 把"还能不能重试 / 退避多久 / 怎么向用户报进度"从播放器实现里抽出来,
/// 让"有限重试"成为可单测的确定性规则,而不是散在回调里的魔法数字。
///
/// 三条设计约束(均来自实机踩坑):
///
/// 1. **必须收敛**。计数只在"确认健康"后归零,不能因为缓冲标志短暂回落就
///    清零 —— 抖动的死流会出现 `buffering true→false→true` 循环,若在
///    false 就清零,计数永远涨不上去,"放弃"分支不可达,变成无限空转。
///    故引入 [healthWindow]:只有在出帧后**持续健康**满该时长才归零。
/// 2. **退避递增且有上限**。首连失败后退避随连续失败次数增长,封顶
///    [maxDelay],避免对已死线路高频空转。
/// 3. **上限可解释**。超过 [maxAttempts] 即放弃,交还用户手动重试或切线路,
///    并把进度([progressLabel])暴露给 UI,让"它在自动重连"这件事可见。
library;

import 'player_error.dart';

/// 重连进度文案的唯一格式来源。
///
/// UI 只拿到快照里的 [attempts] / [limit] 两个数字,格式统一由此函数给出,
/// 避免"播放器里一份、Widget 里再抄一份"导致文案漂移。
String retryProgressLabel(int attempts, int limit) =>
    attempts <= 0 ? '' : '自动重连中 $attempts/$limit';

/// 自动重连策略。
class PlaybackRetryPolicy {
  const PlaybackRetryPolicy({
    this.maxAttempts = 6,
    this.baseDelay = const Duration(seconds: 8),
    this.stepDelay = const Duration(seconds: 4),
    this.maxDelay = const Duration(seconds: 30),
    this.healthWindow = const Duration(seconds: 10),
  });

  /// 连续失败次数上限:达到即放弃自动重试。
  final int maxAttempts;

  /// 首次失败的退避时长。
  final Duration baseDelay;

  /// 每多一次连续失败的退避增量。
  final Duration stepDelay;

  /// 退避封顶(避免对已死线路空转过密)。
  final Duration maxDelay;

  /// 判定"这条流真的健康了"所需的持续出帧时长。
  /// 未满该时长就中断的播放**不算**成功,不重置计数(见库注释第 1 条)。
  final Duration healthWindow;

  /// 已用 [attempts] 次后是否还可继续自动重试。
  bool canRetry(int attempts) => attempts < maxAttempts;

  /// 第 [attempts] 次失败(从 0 起)后的退避时长。
  ///
  /// 例:base=8s、step=4s、max=30s → 8s、12s、16s、20s、24s、28s,
  /// 之后再算也不会超过 30s。
  Duration backoffFor(int attempts) {
    if (attempts <= 0) return baseDelay;
    final millis =
        baseDelay.inMilliseconds + stepDelay.inMilliseconds * attempts;
    return Duration(
      milliseconds: millis.clamp(
        baseDelay.inMilliseconds,
        maxDelay.inMilliseconds,
      ),
    );
  }

  /// 供 UI 展示的重连进度文案;未开始重连时返回空串。
  String progressLabel(int attempts) =>
      retryProgressLabel(attempts, maxAttempts);

  /// 放弃自动重试时的最终文案:由最后一次**已归类**的错误类型给出处置建议。
  ///
  /// 刻意接收 [kind] 而非原始字符串:原始诊断可能是可自愈噪音,依据它生成
  /// 建议会给出错误指引(见 [PlayerErrorClassifier])。
  String giveUpMessage(PlayerErrorKind kind) {
    final hint = playerErrorHint(kind);
    return hint.isEmpty ? '直播流反复中断，请点击重试或切换线路' : hint;
  }
}
