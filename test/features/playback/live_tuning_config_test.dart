/// mpv 调优外部配置文件(`config/mpv_tuning.json`)加载单测:
/// 配置解析是纯函数(内容 → 属性表),VM 测试直接断言,不依赖原生 mpv。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zishu_flutter/src/platforms/common/playback/live_tuning_config.dart';
import 'package:zishu_flutter/src/platforms/common/playback/media_kit_live_player.dart';

void main() {
  Map<String, String> asMap(List<(String, String)> entries) => {
    for (final (name, value) in entries) name: value,
  };

  group('resolveLiveTuningProperties', () {
    test('无配置文件内容 → 全量内置默认', () {
      final resolved = resolveLiveTuningProperties(jsonContent: null);
      expect(
        asMap(resolved),
        asMap(MediaKitLivePlayer.kLiveTuningProperties),
      );
    });

    test('文件覆盖 cache-secs 后,其余内置项保持不变', () {
      final resolved = resolveLiveTuningProperties(
        jsonContent: jsonEncode({'cache-secs': '12'}),
      );
      final map = asMap(resolved);
      expect(map['cache-secs'], '12');
      expect(map['cache'], 'yes');
      expect(map['cache-pause'], 'no');
      expect(map['framedrop'], 'yes');
      expect(map['demuxer-max-bytes'], '134217728');
    });

    test('文件可新增内置表没有的属性(高级调参不被白名单挡死)', () {
      final resolved = resolveLiveTuningProperties(
        jsonContent: jsonEncode({'osd-level': '1'}),
      );
      expect(asMap(resolved)['osd-level'], '1');
    });

    test('数字/布尔值归一化为 mpv 字符串(10 → "10", true → "yes")', () {
      final resolved = resolveLiveTuningProperties(
        jsonContent: jsonEncode({
          'cache-secs': 12,
          'demuxer-max-bytes': 134217728,
          'framedrop': false,
        }),
      );
      final map = asMap(resolved);
      expect(map['cache-secs'], '12');
      expect(map['demuxer-max-bytes'], '134217728');
      // 布尔 false → 'no'(framedrop=no 即不丢帧,语义正确,覆盖内置 'yes')。
      expect(map['framedrop'], 'no');
    });

    test('非法 JSON / 非对象 / 混入非法类型 → 整体回退内置默认', () {
      for (final content in [
        '{ not json',
        '[1,2,3]',
        '{"cache-secs": {"a": 1}}',
        '{"cache-secs": null}',
        '{"cache-secs": [10]}',
      ]) {
        final resolved = resolveLiveTuningProperties(jsonContent: content);
        expect(
          asMap(resolved),
          asMap(MediaKitLivePlayer.kLiveTuningProperties),
          reason: 'content=$content 应整体回退默认',
        );
      }
    });

    test('空字符串视为无配置 → 内置默认', () {
      final resolved = resolveLiveTuningProperties(jsonContent: '   ');
      expect(
        asMap(resolved),
        asMap(MediaKitLivePlayer.kLiveTuningProperties),
      );
    });

    test('_comment 等下划线键被跳过(模板文件的注释位)', () {
      final resolved = resolveLiveTuningProperties(
        jsonContent: jsonEncode({
          '_comment': '改这里调参',
          'cache-secs': '8',
        }),
      );
      final map = asMap(resolved);
      expect(map.containsKey('_comment'), isFalse);
      expect(map['cache-secs'], '8');
    });

    test('空值字符串剔除(mpv 属性空值无意义)', () {
      final resolved = resolveLiveTuningProperties(
        jsonContent: jsonEncode({'cache-secs': ''}),
      );
      // 剔除后该项回落到内置默认而非消失。
      expect(asMap(resolved)['cache-secs'], '6');
    });

    test('内置表属性名不重复(覆盖以文件值为准的前提)', () {
      final names = MediaKitLivePlayer.kLiveTuningProperties
          .map((e) => e.$1)
          .toList();
      expect(names.toSet().length, names.length);
    });
  });

  group('配置文件路径', () {
    test('落在 %APPDATA%\\zishu_flutter\\config\\mpv_tuning.json', () {
      final path = liveTuningConfigFilePath();
      expect(path, endsWith(
        '${Platform.pathSeparator}config${Platform.pathSeparator}mpv_tuning.json',
      ));
      expect(path, contains('zishu_flutter'));
    });

    test('模板内容是合法 JSON 且与内置默认一致', () {
      final decoded = jsonDecode(liveTuningConfigTemplate()) as Map<String, dynamic>;
      expect(decoded['_comment'], isA<String>());
      final tuning = <String, String>{
        for (final e in decoded.entries.where((e) => !e.key.startsWith('_')))
          e.key: e.value.toString(),
      };
      expect(
        tuning,
        asMap(MediaKitLivePlayer.kLiveTuningProperties),
      );
    });
  });
}
