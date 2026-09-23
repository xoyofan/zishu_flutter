/// 直播源级故障恢复策略(纯 Dart,可单测/benchmark)。
library;

/// 决定看门狗到期时应重开旧 URL，还是重新解析新签名地址。
class PlaybackResiliencePolicy {
  const PlaybackResiliencePolicy({
    this.sourceOpenFailureThreshold = 2,
  });

  /// 连续出现多少次「打开源失败」后提前请求新地址。
  ///
  /// 1 次保留给 mpv/playlist 自愈及短时网络抖动；达到 2 次说明当前 URL 组
  /// 已连续失效，继续重放旧签名只会累积退避。
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
