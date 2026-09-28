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
    this.deadOpenGrace = const Duration(seconds: 9),
    // 单线路升级默认关闭:仅在生产构造点显式开启(见 play_provider.dart),
    // 否则所有既有单测(默认策略 + 单线路 fixture)的退避契约保持不变。
    this.escalateSingleLine = false,
    this.escalateResolveAfter = 2,
    this.singleLineBaseDelay = const Duration(seconds: 4),
    this.singleLineStepDelay = const Duration(seconds: 4),
    this.singleLineMaxDelay = const Duration(seconds: 12),
  });

  /// 连续失败次数上限:达到即放弃自动重试。
  final int maxAttempts;

  /// 首次失败的退避时长。
  final Duration baseDelay;

  /// 每多一次连续失败的退避增量。
  final Duration stepDelay;

  /// 退避封顶(避免对已死线路空转过密)。
  final Duration maxDelay;

  /// 单线路源(无 mpv 内部回退线路)卡顿时,是否启用"快速退避 + 早升级
  /// re-resolve"。默认关闭以兼容既有单测契约;生产在 play_provider.dart
  /// 显式开启。
  ///
  /// 为什么需要它:实测 2026-09-28 斗鱼 room 9999 单线路(`lines=1`),CDN 节点
  /// `hwa.douyucdn2.cn` 断供时,mpv 播放列表只有一条线,整组轮转重开永远回到
  /// 同一死节点;退避阶梯(8→12→16→20→24→28→30s)爬满 6 次才轮到 re-resolve,
  /// 于是用户被卡 50~90s。单线路重开同一死 URL 毫无意义,早一点 re-resolve
  /// (换节点 / 降画质)才有机会逃出被钉死的链路 —— 多线路源不受影响,继续
  /// 优先交给 mpv 播放列表内部跳下一条线。
  final bool escalateSingleLine;

  /// 单线路源在第几次同 URL 重开后升级 re-resolve(从 1 起)。
  /// 默认 2:先做一次快速同 URL 重开(给 CDN 自恢复留 ~4s 窗口,实测斗鱼会自愈),
  /// 第 2 次即升级 re-resolve,把最坏等待从 30s+ 压到 ~4s。
  final int escalateResolveAfter;

  /// 单线路源的退避档位(更快,避免长退避空耗已被钉死的死节点)。
  final Duration singleLineBaseDelay;
  final Duration singleLineStepDelay;
  final Duration singleLineMaxDelay;

  /// 判定"这条流真的健康了"所需的持续出帧时长。
  /// 未满该时长就中断的播放**不算**成功,不重置计数(见库注释第 1 条)。
  final Duration healthWindow;

  /// 死开流宽限期:open 后 mpv 已起播但 [Duration] 内仍收不到有效视频参数
  /// (width>0)即判定"死开流"(连接成功、mpv 静默读数据却永远不出画面,
  /// 实测 2026-09-27 20:54 douyu 9999 黑屏 2m13s,同节点手动重开 300ms 恢复),
  /// 同线路重开一次。9s = 3s 首帧观察 + 6s 余量,覆盖慢启动的正常开流。
  final Duration deadOpenGrace;

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

  /// 单线路感知的退避时长:[lineCount]<=1 且启用升级时使用更激进的档位
  /// ([singleLineBaseDelay]/[singleLineStepDelay]/[singleLineMaxDelay]);其余
  /// 一律退回标准 [backoffFor],确保多线路与未启用升级的单线路行为不变。
  Duration backoffForWithLines(int attempts, int lineCount) {
    if (!escalateSingleLine || lineCount > 1) return backoffFor(attempts);
    if (attempts <= 0) return singleLineBaseDelay;
    final millis =
        singleLineBaseDelay.inMilliseconds +
        singleLineStepDelay.inMilliseconds * attempts;
    return Duration(
      milliseconds: millis.clamp(
        singleLineBaseDelay.inMilliseconds,
        singleLineMaxDelay.inMilliseconds,
      ),
    );
  }

  /// 本次卡顿后是否应升级为 re-resolve(换节点 / 降画质)而非同 URL 重开。
  ///
  /// [attempts] 为「即将进行的重开序号」(从 1 起);[lineCount] 为当前线路数
  /// (含回退)。仅 `lines<=1` 且无内部回退线路时触发,达到 [escalateResolveAfter]
  /// 即升级 —— 多线路源永远返回 false(优先交给 mpv 内部跳线)。
  bool shouldEscalateToResolve({
    required int attempts,
    required int lineCount,
  }) =>
      escalateSingleLine &&
      lineCount <= 1 &&
      attempts >= escalateResolveAfter;

  /// 供 UI 展示的重连进度文案;未开始重连时返回空串。
  String progressLabel(int attempts) =>
      retryProgressLabel(attempts, maxAttempts);

  /// 一次中断(进入缓冲 / 重开)时的归零判定:只有**连续健康播放**已满
  /// [healthWindow] 才允许把连续失败计数归零。
  ///
  /// 为什么需要它:出帧后 mpv 常紧接着再报一次 `buffering`,旧实现直接撤掉
  /// 健康计时器,于是计数在整个会话里只涨不落——退避逐步涨到 [maxDelay]。
  /// 实测日志(虎牙会话):健康播放 35s 后中断,计数仍停在 1,下一次退避
  /// 已从 8s 涨到 12s。改为按「已健康播满」结算后,自愈型抖动不再累积退避,
  /// 也不会被无关故障凑满 [maxAttempts] 而错误放弃。
  bool shouldResetOnInterrupt(Duration healthyElapsed) =>
      healthyElapsed >= healthWindow;

  /// 放弃自动重试时的最终文案:由最后一次**已归类**的错误类型给出处置建议。
  ///
  /// 刻意接收 [kind] 而非原始字符串:原始诊断可能是可自愈噪音,依据它生成
  /// 建议会给出错误指引(见 [PlayerErrorClassifier])。
  String giveUpMessage(PlayerErrorKind kind) {
    final hint = playerErrorHint(kind);
    return hint.isEmpty ? '直播流反复中断，请点击重试或切换线路' : hint;
  }
}

/// 恢复重解析的节流策略。
///
/// 自动重连耗尽后,播放器可向宿主请求「重新解析」拿一份全新地址(签名平台的
/// 地址时效短于观看会话,复用旧地址=无限重开失效源,见 [LineRecoveryAware])。
/// 但恢复不能无节制:若宿主侧解析持续返回同一批已失效地址,「重试 → 恢复 →
/// 重试」会变成一个高速空转循环,用户看到的仍是"反复中断来尝试"。
///
/// 故以 [minInterval] 约束两次恢复的最小间隔,让恢复节奏低于正常重连周期
/// (一轮重试 ≈ 8+12+16+20+24+28 = 108s),不会叠加成抖动。
class PlaybackRecoveryPolicy {
  const PlaybackRecoveryPolicy({this.minInterval = const Duration(seconds: 40)});

  /// 两次恢复之间的最小间隔。
  final Duration minInterval;

  /// 此刻是否允许发起恢复。[lastRecoverAt] 为 null 表示本会话尚未恢复过。
  ///
  /// 刻意把"上次恢复时刻"作为参数而非内部状态:策略保持纯函数,便于单测
  /// 覆盖边界(恰好等于间隔、刚恢复过、跨会话重置)。
  bool canRecover({required DateTime now, DateTime? lastRecoverAt}) {
    if (lastRecoverAt == null) return true;
    return now.difference(lastRecoverAt) >= minInterval;
  }
}
