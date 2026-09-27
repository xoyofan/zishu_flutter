/// 直播源级故障恢复策略(纯 Dart,可单测/benchmark)。
library;

/// 决定看门狗到期时应重开旧 URL，还是重新解析新签名地址。
class PlaybackResiliencePolicy {
  const PlaybackResiliencePolicy({
    this.sourceOpenFailureThreshold = 1,
  });

  /// 连续出现多少次「打开源失败」后提前请求新地址。
  ///
  /// 旧值 2 的理由是"给 mpv/playlist 自愈留 1 次",但实测(2026-09-27 18:23
  /// 虎牙事故)签名 URL 一旦失效,重开必然再次失败:同一 wsSecret 盲重试 4 次
  /// 白烧 ~39s,而 re-resolve 路径 613ms 出帧。`source_open` 是**终局**诊断
  /// (URL 已被判死),第 1 次就该升级 re-resolve,退避等待只对"源活着只是
  /// 抖动"的场景有意义——那种场景根本不会产生 terminal 诊断。
  final int sourceOpenFailureThreshold;

  bool shouldRecoverSource({
    required int consecutiveSourceOpenFailures,
  }) => consecutiveSourceOpenFailures >= sourceOpenFailureThreshold;
}

class CdnCircuitBreaker {
  CdnCircuitBreaker({
    this.failureThreshold = 2,
    this.cooldown = const Duration(seconds: 30),
  });

  final int failureThreshold;
  final Duration cooldown;
  final Map<String, _HostHealth> _health = {};

  bool isOpen(String host, DateTime now) {
    final health = _health[host];
    if (health == null) return false;
    if (now.difference(health.openedAt) >= cooldown) {
      _health.remove(host);
      return false;
    }
    return true;
  }

  void recordFailure(String host, DateTime now) {
    final next = (_health[host]?.failures ?? 0) + 1;
    _health[host] = _HostHealth(
      failures: next,
      openedAt: next >= failureThreshold
          ? now
          : _health[host]?.openedAt ?? now,
    );
  }

  void recordSuccess(String host) => _health.remove(host);

  void clear() => _health.clear();

  List<T> order<T>(Iterable<T> lines, String Function(T) hostOf, DateTime now) {
    final available = <T>[];
    final cooling = <T>[];
    for (final line in lines) {
      if (isOpen(hostOf(line), now)) {
        cooling.add(line);
      } else {
        available.add(line);
      }
    }
    return [...available, ...cooling];
  }
}

class _HostHealth {
  const _HostHealth({required this.failures, required this.openedAt});
  final int failures;
  final DateTime openedAt;
}


class PlaybackRecoveryBenchmark {
  const PlaybackRecoveryBenchmark({
    required this.baseDelay,
    required this.stepDelay,
    required this.retryDelayMs,
    required this.resolveMs,
    required this.earlyResolveMs,
  });

  factory PlaybackRecoveryBenchmark.live({
    int retryDelayMs = 8000,
    int stepMs = 4000,
    int resolveMs = 250,
    int earlyResolveMs = 250,
  }) => PlaybackRecoveryBenchmark(
    baseDelay: Duration(milliseconds: retryDelayMs),
    stepDelay: Duration(milliseconds: stepMs),
    retryDelayMs: retryDelayMs,
    resolveMs: resolveMs,
    earlyResolveMs: earlyResolveMs,
  );

  final Duration baseDelay;
  final Duration stepDelay;
  final int retryDelayMs;
  final int resolveMs;
  final int earlyResolveMs;

  int _backoff(int attempts) => retryDelayMs + stepDelay.inMilliseconds * attempts;

  /// 旧方案：失败两次后仍先重开旧地址，再等第二次失败才解析。
  int baselineRecoveryMs() => _backoff(0) + _backoff(1) + resolveMs;

  /// 提前恢复：第一次失败后等待一次退避，直接解析新签名。
  int earlyRecoveryMs() => _backoff(0) + earlyResolveMs;
}

/// 一次 benchmark 汇总。
class PlaybackRecoveryBenchmarkResult {
  const PlaybackRecoveryBenchmarkResult({
    required this.baselineMs,
    required this.earlyMs,
  });

  final int baselineMs;
  final int earlyMs;

  int get savedMs => baselineMs - earlyMs;
  double get speedup => earlyMs == 0 ? 0 : baselineMs / earlyMs;
}
