import 'package:flutter_test/flutter_test.dart';
import 'package:zishu_flutter/src/platforms/common/playback/playback_resilience.dart';

void main() {
  group('源级失败阈值', () {
    const policy = PlaybackResiliencePolicy();
    test('首次终局 source_open 失败即提前恢复(签名 URL 失效重开必然再失败)', () {
      expect(policy.shouldRecoverSource(consecutiveSourceOpenFailures: 0), isFalse);
      expect(policy.shouldRecoverSource(consecutiveSourceOpenFailures: 1), isTrue);
      expect(policy.shouldRecoverSource(consecutiveSourceOpenFailures: 2), isTrue);
    });
  });

  group('多 CDN 熔断', () {
    test('连续失败打开 host 并冷却后优先其他 CDN', () {
      final breaker = CdnCircuitBreaker();
      final now = DateTime(2026, 9, 24);
      breaker.recordFailure('a.huya.com', now);
      breaker.recordFailure('a.huya.com', now);
      final ordered = breaker.order(
        ['a.huya.com/live.m3u8', 'b.huya.com/live.m3u8'],
        (line) => line.split('/').first,
        now.add(const Duration(seconds: 1)),
      );
      expect(ordered.first, 'b.huya.com/live.m3u8');
      expect(breaker.isOpen('a.huya.com', now), isTrue);
      expect(
        breaker.isOpen('a.huya.com', now.add(const Duration(seconds: 30))),
        isFalse,
      );
    });

    test('全部 host 熔断时仍保留全部候选', () {
      final breaker = CdnCircuitBreaker();
      final now = DateTime(2026, 9, 24);
      for (final host in ['a.huya.com', 'b.huya.com']) {
        breaker.recordFailure(host, now);
        breaker.recordFailure(host, now);
      }
      final lines = ['a.huya.com', 'b.huya.com'];
      expect(
        breaker.order(lines, (line) => line, now),
        lines,
      );
    });
  });

  group('恢复延迟 benchmark', () {
    test('旧重试组与提前解析组按相同输入比较', () {
      final model = PlaybackRecoveryBenchmark.live(resolveMs: 250);
      const result = PlaybackRecoveryBenchmarkResult(
        baselineMs: 20250,
        earlyMs: 8250,
      );
      expect(model.baselineRecoveryMs(), result.baselineMs);
      expect(model.earlyRecoveryMs(), result.earlyMs);
      expect(result.savedMs, 12000);
      expect(result.speedup, closeTo(2.45, 0.01));
    });
  });
}
