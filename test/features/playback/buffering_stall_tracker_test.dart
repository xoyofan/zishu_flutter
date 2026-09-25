/// BufferingStallTracker 契约:卡顿时长埋点的记账核心。
///
/// 只跟踪 buffering 真→假转换并输出持续时长;落盘由调用方(media_kit
/// 播放器)接 PlaybackLog 完成,本类保持纯 Dart 可单测。
library;
import 'package:flutter_test/flutter_test.dart';
import 'package:zishu_flutter/src/platforms/common/playback/buffering_stall_tracker.dart';

void main() {
  late DateTime now;
  late BufferingStallTracker tracker;

  setUp(() {
    now = DateTime(2026, 9, 21, 14, 17, 0);
    tracker = BufferingStallTracker(now: () => now);
  });

  test('begin→end 返回持续毫秒', () {
    expect(tracker.begin(), isTrue);
    now = now.add(const Duration(milliseconds: 1500));
    expect(tracker.end(), 1500);
  });

  test('end 无对应 begin 时忽略(返回 null)', () {
    expect(tracker.end(), isNull);
  });

  test('end 后再 end 返回 null(同一次卡顿只结算一次)', () {
    tracker.begin();
    now = now.add(const Duration(seconds: 2));
    expect(tracker.end(), 2000);
    expect(tracker.end(), isNull);
  });

  test('重复 begin 不重置起点', () {
    expect(tracker.begin(), isTrue);
    now = now.add(const Duration(milliseconds: 800));
    // mpv 对同一故障反复置位 buffering:第二次 begin 不应重置计时。
    expect(tracker.begin(), isFalse);
    now = now.add(const Duration(milliseconds: 200));
    expect(tracker.end(), 1000);
  });

  test('多次缓冲循环各自计时', () {
    tracker.begin();
    now = now.add(const Duration(milliseconds: 300));
    expect(tracker.end(), 300);

    now = now.add(const Duration(seconds: 300));
    expect(tracker.begin(), isTrue);
    now = now.add(const Duration(milliseconds: 1200));
    expect(tracker.end(), 1200);
  });

  test('reset 丢弃未完成的 begin(跨会话不计时)', () {
    tracker.begin();
    now = now.add(const Duration(seconds: 10));
    tracker.reset();
    // reset 后的 end 无 begin 可结算。
    expect(tracker.end(), isNull);
    // 重新开始的是一次全新卡顿。
    expect(tracker.begin(), isTrue);
    now = now.add(const Duration(milliseconds: 500));
    expect(tracker.end(), 500);
  });
}
