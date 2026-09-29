/// [PlaybackLog] 事件分类契约:每行带 `cat=<分类>` 首字段,
/// 按调试场景聚合(grep 口径),未知事件落 other。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zishu_flutter/src/platforms/common/playback/playback_log.dart';

void main() {
  late File file;

  setUp(() {
    final dir = Directory.systemTemp.createTempSync('playback_log_test');
    file = File('${dir.path}/playback.log');
    PlaybackLog.initForTest(file.path);
  });

  tearDown(() async {
    PlaybackLog.resetForTest();
    try {
      await file.parent.delete(recursive: true);
    } catch (_) {}
  });

  test('每行事件名后首个字段是 cat=<分类>', () {
    PlaybackLog.write('stall_begin', {'host': 'hwa.douyucdn2.cn'});
    final line = file.readAsStringSync().trim();
    expect(line, matches(RegExp(r'^\d{2}:\d{2}:\d{2}\.\d{3} stall_begin cat=recovery host=hwa\.douyucdn2\.cn$')));
  });

  test('核心调试场景分类落位', () {
    PlaybackLog.write('resolve_ok');
    PlaybackLog.write('proxy_upstream_switch');
    PlaybackLog.write('host_avoid_applied');
    PlaybackLog.write('video_stability');
    PlaybackLog.write('mpv_log');
    PlaybackLog.write('app_start');
    PlaybackLog.write('resource_sample');
    final lines = file
        .readAsSyncSafe()
        .map((l) => RegExp(r'cat=(\w+)').firstMatch(l)?.group(1))
        .toList();
    expect(lines, [
      'resolve', // 解析
      'line', // URL 重签/线路
      'line', // 死节点避让
      'stream', // 流健康
      'mpv', // mpv 原始
      'lifecycle', // 生命周期
      'resource', // 资源采样
    ]);
  });

  test('未映射事件落 cat=other,字段照常保留', () {
    PlaybackLog.write('brand_new_event', {'k': 'v'});
    final line = file.readAsStringSync().trim();
    expect(line, endsWith('brand_new_event cat=other k=v'));
  });

  test('无字段事件只有 cat,不留尾随空格', () {
    PlaybackLog.write('stop');
    final line = file.readAsStringSync().trim();
    expect(line, matches(RegExp(r' stop cat=lifecycle$')));
  });

  test('resetForTest 后未注入的写入回落默认测试路径,不落真实日志', () {
    final fallback = File('${Directory.systemTemp.path}/playback_log_fallback_probe.log');
    if (fallback.existsSync()) fallback.deleteSync();
    PlaybackLog.setDefaultTestPath(fallback.path);
    PlaybackLog.resetForTest(); // 模拟其它测试文件的 tearDown
    PlaybackLog.write('leak_probe_event');
    expect(fallback.existsSync(), isTrue,
        reason: 'reset 后写入必须落在默认测试路径,绝不解析 %APPDATA% 真实日志');
    expect(fallback.readAsStringSync(), contains('leak_probe_event'));
    fallback.deleteSync();
    // 还原:清掉默认路径,后续测试回到本文件的注入路径。
    PlaybackLog.initForTest(file.path);
  });
}

extension on File {
  List<String> readAsSyncSafe() => readAsLinesSync();
}
