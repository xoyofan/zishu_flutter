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
}
