/// 播放事件文件日志单测。
///
/// 这份日志是真机验证虎牙断流修复的观测通道:release GUI 进程没有控制台,
/// print 输出被丢弃,只有文件能带回运行时事实。用测试锁死三点:
/// 事件确实落盘、多事件按序追加、IO 失败静默降级绝不弄崩播放。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zishu_flutter/src/platforms/common/playback/playback_log.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('playback_log_test');
    PlaybackLog.initForTest('${tempDir.path}\\playback.log');
  });

  tearDown(() {
    PlaybackLog.resetForTest();
    tempDir.deleteSync(recursive: true);
  });

  test('事件落盘:时间戳 + 事件名 + 键值对', () {
    PlaybackLog.write('open', {'lines': 3, 'host': 'example.com'});

    final text = File('${tempDir.path}\\playback.log').readAsStringSync();
    expect(text, contains('open'));
    expect(text, contains('lines=3'));
    expect(text, contains('host=example.com'));
    // HH:mm:ss.SSS 前缀,便于日志里量出事件间隔。
    expect(text, matches(RegExp(r'^\d{2}:\d{2}:\d{2}\.\d{3} ', multiLine: true)));
  });

  test('无字段事件与多事件按序追加', () {
    PlaybackLog.write('stop');
    PlaybackLog.write('reopen', {'attempt': 2, 'limit': 6});

    final lines = File('${tempDir.path}\\playback.log')
        .readAsLinesSync()
        .where((line) => line.isNotEmpty)
        .toList();
    expect(lines, hasLength(2));
    expect(lines[0], contains('stop'));
    expect(lines[1], contains('attempt=2'));
    expect(lines[1], contains('limit=6'));
  });

  test('目标不可写时静默降级,绝不抛异常', () {
    // 把"文件"指到目录上:写入必失败,日志器应吞掉异常并熔断。
    PlaybackLog.initForTest(tempDir.path);
    expect(() => PlaybackLog.write('open', {'k': 'v'}), returnsNormally);
    // 熔断后的后续调用同样安全。
    expect(() => PlaybackLog.write('stop'), returnsNormally);
  });
}
