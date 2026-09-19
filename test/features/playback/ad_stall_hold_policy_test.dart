/// 广告期看门狗豁免策略单测:按住判定与预算封顶的确定性规则。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:zishu_flutter/src/platforms/common/playback/twitch_ad_filter.dart';

void main() {
  const policy = AdStallHoldPolicy();
  final now = DateTime(2026, 9, 20, 12);

  group('shouldHold', () {
    test('广告态为 false 一律不按住(由调用方清零计时)', () {
      expect(
        policy.shouldHold(adStalled: false, now: now, holdSince: null),
        isFalse,
      );
      expect(
        policy.shouldHold(
          adStalled: false,
          now: now,
          holdSince: now.subtract(policy.holdBudget),
        ),
        isFalse,
      );
    });

    test('首查命中广告态(holdSince 为 null)即按住', () {
      expect(policy.shouldHold(adStalled: true, now: now, holdSince: null), isTrue);
    });

    test('预算内按住,预算到点后按真断流处理', () {
      final started = now.subtract(policy.holdBudget - policy.recheckInterval);
      expect(
        policy.shouldHold(adStalled: true, now: now, holdSince: started),
        isTrue,
      );
      // 恰满预算:不再按住。
      final boundary = now.subtract(policy.holdBudget);
      expect(
        policy.shouldHold(adStalled: true, now: now, holdSince: boundary),
        isFalse,
      );
      // 超预算:不再按住。
      final over = now.subtract(policy.holdBudget).subtract(policy.recheckInterval);
      expect(
        policy.shouldHold(adStalled: true, now: now, holdSince: over),
        isFalse,
      );
    });
  });

  group('默认参数(与 Twitch 广告 pod 量级对齐)', () {
    test('按住预算 3 分钟(Twitch 广告 pod 上限量级)', () {
      expect(policy.holdBudget, const Duration(minutes: 3));
    });

    test('复查间隔 5 秒(playlist 刷新量级)', () {
      expect(policy.recheckInterval, const Duration(seconds: 5));
    });
  });
}
