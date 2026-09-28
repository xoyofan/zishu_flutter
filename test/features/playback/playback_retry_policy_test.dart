/// 有界重连策略单测(纯 Dart)。
///
/// 这一层的目的就是让"有限重试"成为**可验证的确定性规则** —— 直播断流场景
/// 最怕的不是失败,而是失败后无限空转。故用测试锁死三点:
/// 上限可达、退避递增且封顶、健康观察窗足够长。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:zishu_flutter/src/platforms/common/playback/playback_retry.dart';
import 'package:zishu_flutter/src/platforms/common/playback/player_error.dart';

void main() {
  group('默认参数', () {
    const policy = PlaybackRetryPolicy();

    test('默认上限 / 退避 / 观察窗与实机调参一致', () {
      expect(policy.maxAttempts, 6);
      expect(policy.baseDelay, const Duration(seconds: 8));
      expect(policy.stepDelay, const Duration(seconds: 4));
      expect(policy.maxDelay, const Duration(seconds: 30));
      expect(policy.healthWindow, const Duration(seconds: 10));
    });
  });

  group('canRetry', () {
    const policy = PlaybackRetryPolicy(maxAttempts: 3);

    test('未达上限可重试,达到上限即放弃', () {
      expect(policy.canRetry(0), isTrue);
      expect(policy.canRetry(1), isTrue);
      expect(policy.canRetry(2), isTrue);
      expect(policy.canRetry(3), isFalse, reason: '达到上限必须放弃,否则无限空转');
      expect(policy.canRetry(99), isFalse);
    });

    test('maxAttempts 为 0 时一次都不重试', () {
      const noRetry = PlaybackRetryPolicy(maxAttempts: 0);
      expect(noRetry.canRetry(0), isFalse);
    });
  });

  group('backoffFor', () {
    const policy = PlaybackRetryPolicy();

    test('第 0 次失败用 baseDelay', () {
      expect(policy.backoffFor(0), const Duration(seconds: 8));
    });

    test('退避随失败次数线性递增', () {
      expect(policy.backoffFor(1), const Duration(seconds: 12));
      expect(policy.backoffFor(2), const Duration(seconds: 16));
      expect(policy.backoffFor(3), const Duration(seconds: 20));
      expect(policy.backoffFor(4), const Duration(seconds: 24));
      expect(policy.backoffFor(5), const Duration(seconds: 28));
    });

    test('退避封顶到 maxDelay,不会无限增长', () {
      expect(policy.backoffFor(6), const Duration(seconds: 30));
      expect(policy.backoffFor(50), const Duration(seconds: 30));
    });

    test('越界(负)输入退化为 baseDelay,不会返回更短时长', () {
      expect(policy.backoffFor(-3), const Duration(seconds: 8));
    });

    test('退避单调不减', () {
      var previous = Duration.zero;
      for (var attempt = 0; attempt <= 20; attempt++) {
        final current = policy.backoffFor(attempt);
        expect(
          current >= previous,
          isTrue,
          reason: 'attempt=$attempt 的退避小于前一次:$current < $previous',
        );
        previous = current;
      }
    });

    test('自定义步长与封顶生效', () {
      const custom = PlaybackRetryPolicy(
        baseDelay: Duration(seconds: 1),
        stepDelay: Duration(seconds: 1),
        maxDelay: Duration(seconds: 3),
      );
      expect(custom.backoffFor(0), const Duration(seconds: 1));
      expect(custom.backoffFor(1), const Duration(seconds: 2));
      expect(custom.backoffFor(2), const Duration(seconds: 3));
      expect(custom.backoffFor(3), const Duration(seconds: 3));
    });
  });

  group('等待条件', () {
    test('健康观察窗需足够长才能区分"真健康"与"短暂出帧"', () {
      const policy = PlaybackRetryPolicy();
      // 抖动的死流通常几秒内再次断流;观察窗必须长于该抖动量级,
      // 否则计数被反复清零,重试上限形同虚设。
      expect(policy.healthWindow.inSeconds, greaterThanOrEqualTo(5));
    });

    test('中断时只有已连续健康播满观察窗才归零(防退避无限增长)', () {
      const policy = PlaybackRetryPolicy();
      // 未满观察窗:mpv 出帧后紧接的 buffering 不得把计数归零。
      expect(
        policy.shouldResetOnInterrupt(const Duration(seconds: 3)),
        isFalse,
      );
      // 已满观察窗:健康播放 35s 后的中断应归零(否则退避 8→12→16… 单调增长)。
      expect(
        policy.shouldResetOnInterrupt(const Duration(seconds: 35)),
        isTrue,
      );
      expect(
        policy.shouldResetOnInterrupt(policy.healthWindow),
        isTrue,
        reason: '恰好等于观察窗即视为健康',
      );
    });
  });

  group('进度文案', () {
    const policy = PlaybackRetryPolicy();

    test('未开始重连时为空串(不占位)', () {
      expect(policy.progressLabel(0), isEmpty);
      expect(policy.progressLabel(-1), isEmpty);
      expect(retryProgressLabel(0, 6), isEmpty);
    });

    test('重连中显示分子/分母', () {
      expect(policy.progressLabel(2), '自动重连中 2/6');
      expect(retryProgressLabel(5, 6), '自动重连中 5/6');
      expect(retryProgressLabel(1, 3), '自动重连中 1/3');
    });

    test('自由函数与策略方法同源(文案只维护一处)', () {
      for (var attempt = 0; attempt <= 7; attempt++) {
        expect(
          policy.progressLabel(attempt),
          retryProgressLabel(attempt, policy.maxAttempts),
          reason: 'attempt=$attempt',
        );
      }
    });
  });

  group('放弃文案', () {
    const policy = PlaybackRetryPolicy();

    test('复用错误类别的处置建议', () {
      expect(
        policy.giveUpMessage(PlayerErrorKind.network),
        playerErrorHint(PlayerErrorKind.network),
      );
      expect(
        policy.giveUpMessage(PlayerErrorKind.source),
        playerErrorHint(PlayerErrorKind.source),
      );
    });

    test('none 类别退化为兜底文案而非空串', () {
      final message = policy.giveUpMessage(PlayerErrorKind.none);
      expect(message, isNotEmpty);
      expect(message.contains('重试'), isTrue);
    });

    test('每个真实类别都有非空放弃文案', () {
      for (final kind in PlayerErrorKind.values) {
        expect(policy.giveUpMessage(kind), isNotEmpty, reason: '$kind');
      }
    });
  });

  group('backoffForWithLines(单线路感知退避)', () {
    test('默认策略未启用升级 → 单线路仍走标准退避(兼容既有契约)', () {
      const policy = PlaybackRetryPolicy();
      expect(policy.backoffForWithLines(0, 1), const Duration(seconds: 8));
      expect(policy.backoffForWithLines(1, 1), const Duration(seconds: 12));
      expect(policy.backoffForWithLines(5, 1), const Duration(seconds: 28));
    });

    test('多线路永远走标准退避(优先 mpv 内部跳线)', () {
      const policy = PlaybackRetryPolicy(escalateSingleLine: true);
      expect(policy.backoffForWithLines(0, 2), const Duration(seconds: 8));
      expect(policy.backoffForWithLines(3, 5), const Duration(seconds: 20));
    });

    test('启用升级 + 单线路 → 更快档位且封顶更低', () {
      const policy = PlaybackRetryPolicy(escalateSingleLine: true);
      expect(policy.backoffForWithLines(0, 1), const Duration(seconds: 4));
      expect(policy.backoffForWithLines(1, 1), const Duration(seconds: 8));
      expect(policy.backoffForWithLines(2, 1), const Duration(seconds: 12));
      // 封顶到 singleLineMaxDelay,不再随次数增长。
      expect(policy.backoffForWithLines(10, 1), const Duration(seconds: 12));
    });

    test('单线路升级退避单调不减', () {
      const policy = PlaybackRetryPolicy(escalateSingleLine: true);
      var previous = Duration.zero;
      for (var attempt = 0; attempt <= 20; attempt++) {
        final current = policy.backoffForWithLines(attempt, 1);
        expect(current >= previous, isTrue, reason: 'attempt=$attempt');
        previous = current;
      }
    });
  });

  group('shouldEscalateToResolve(单线路升级判定)', () {
    test('未启用升级 → 永不升级', () {
      const policy = PlaybackRetryPolicy();
      expect(
        policy.shouldEscalateToResolve(attempts: 5, lineCount: 1),
        isFalse,
      );
    });

    test('多线路 → 永不升级(交给 mpv 内部跳线)', () {
      const policy = PlaybackRetryPolicy(escalateSingleLine: true);
      expect(
        policy.shouldEscalateToResolve(attempts: 5, lineCount: 3),
        isFalse,
      );
    });

    test('启用 + 单线路 → 达到阈值才升级', () {
      const policy = PlaybackRetryPolicy(escalateSingleLine: true);
      expect(
        policy.shouldEscalateToResolve(attempts: 1, lineCount: 1),
        isFalse,
      );
      expect(
        policy.shouldEscalateToResolve(attempts: 2, lineCount: 1),
        isTrue,
      );
      expect(
        policy.shouldEscalateToResolve(attempts: 6, lineCount: 1),
        isTrue,
      );
    });

    test('自定义阈值生效', () {
      const policy = PlaybackRetryPolicy(
        escalateSingleLine: true,
        escalateResolveAfter: 3,
      );
      expect(
        policy.shouldEscalateToResolve(attempts: 2, lineCount: 1),
        isFalse,
      );
      expect(
        policy.shouldEscalateToResolve(attempts: 3, lineCount: 1),
        isTrue,
      );
    });
  });

  group('恢复节流策略(PlaybackRecoveryPolicy)', () {
    const policy = PlaybackRecoveryPolicy();

    test('默认最小间隔 40s', () {
      expect(policy.minInterval, const Duration(seconds: 40));
    });

    test('本会话尚未恢复过 → 允许', () {
      expect(
        policy.canRecover(now: DateTime(2026, 9, 13, 18), lastRecoverAt: null),
        isTrue,
      );
    });

    test('刚恢复过 → 拒绝(避免"重试→恢复→重试"高速空转)', () {
      final now = DateTime(2026, 9, 13, 18);
      expect(
        policy.canRecover(
          now: now,
          lastRecoverAt: now.subtract(const Duration(seconds: 5)),
        ),
        isFalse,
      );
    });

    test('恰好满间隔 → 允许(边界含等号)', () {
      final now = DateTime(2026, 9, 13, 18);
      expect(
        policy.canRecover(
          now: now,
          lastRecoverAt: now.subtract(policy.minInterval),
        ),
        isTrue,
      );
    });

    test('超过间隔 → 允许', () {
      final now = DateTime(2026, 9, 13, 18);
      expect(
        policy.canRecover(
          now: now,
          lastRecoverAt: now.subtract(const Duration(minutes: 3)),
        ),
        isTrue,
      );
    });

    test('节流间隔必须短于一轮重试总时长,否则恢复永远来不及兜底', () {
      const retry = PlaybackRetryPolicy();
      var oneCycle = Duration.zero;
      for (var i = 0; i < retry.maxAttempts; i++) {
        oneCycle += retry.backoffFor(i);
      }
      expect(policy.minInterval, lessThan(oneCycle));
    });
  });
}
