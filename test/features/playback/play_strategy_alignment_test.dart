/// 线路编排回归测试：只播选中的这一条，**不做线路自动切换**，也不做首包测速
/// 排序或测速后重开。
///
/// 2026-09-26 用户口径去掉自动切线路：之前把同画质其余线路作为 mpv 播放列表
/// 回退项，导致用户手动切了线路后仍被自动改线、并显示「正在切换线路…」。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('播放编排不做线路测速排序重开', () {
    final source = File('lib/src/features/play/application/play_provider.dart')
        .readAsStringSync();
    expect(source, isNot(contains('_openRanked')));
    expect(source, isNot(contains('rankLinesByLatency')));
    expect(source, isNot(contains('_probeLineLatency')));
  });

  test('不再喂回退线路：_fallbackLines 恒返回空(去掉自动切线路)', () {
    final source = File('lib/src/features/play/application/play_provider.dart')
        .readAsStringSync();
    // 签名保留(底层 mpv 播放列表能力未拆)，但实现恒为空。
    expect(source, contains('_fallbackLines'));
    expect(
      source,
      contains('const [];'),
      reason: '_fallbackLines 必须恒返回空,不得再收集同画质其余线路',
    );
    expect(
      source,
      isNot(contains('if (candidate.url != line.url) candidate')),
      reason: '不得再把同画质其余线路拼进 mpv 播放列表',
    );
    // 失败文案不得再声称会自动切线路。
    final view = File('lib/src/features/play/views/play_view.dart')
        .readAsStringSync();
    expect(view, isNot(contains('正在切换线路')));
  });
}
