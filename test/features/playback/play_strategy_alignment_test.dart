/// 线路编排回归测试：当前播放策略直接沿用解析器线路顺序，交给 mpv playlist
/// 自动切换，不额外做首包测速排序或测速后重开。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('播放编排不包含线路测速排序重开路径', () {
    final source = File('lib/src/features/play/application/play_provider.dart')
        .readAsStringSync();
    expect(source, isNot(contains('_openRanked')));
    expect(source, isNot(contains('rankLinesByLatency')));
    expect(source, isNot(contains('_probeLineLatency')));
    expect(source, contains('player.open(line, fallbacks)'));
  });
}
