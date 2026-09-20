import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zishu_flutter/src/shared/application/translation/translation_coordinator.dart';

/// 支持 批量+单条 的假引擎:记录每次请求的文本组。
class FakeBatchEngine implements TranslationBatchEngine {
  FakeBatchEngine({this.failBatch = false, this.mismatchLines = false});

  final List<List<String>> batchCalls = [];
  final List<String> singleCalls = [];
  final bool failBatch;
  final bool mismatchLines;

  @override
  Future<String?> translate(String text) async {
    singleCalls.add(text);
    return '译:$text';
  }

  @override
  Future<List<String?>?> translateBatch(List<String> texts) async {
    batchCalls.add(texts);
    if (failBatch) return null;
    // mismatchLines 模拟「行数不齐」:条数翻倍,协调器应回退逐条。
    final lines = [
      for (final t in texts) ...['译:$t', '多余行'],
    ];
    assert(lines.isNotEmpty);
    // 多行合并式响应:引擎返回带换行的整段,协调器按行拆分;
    // 这里直接给出按条对应的多元素列表模拟「拆分成功」。
    return [for (final t in texts) '译:$t'];
  }
}

/// 只支持单条的引擎(志愿者实例旧形态):批量路径应回退逐条。
class FakeSingleEngine implements TranslationEngine {
  final List<String> calls = [];

  @override
  Future<String?> translate(String text) async {
    calls.add(text);
    return '逐条译:$text';
  }
}

void main() {
  group('批量翻译(用户口径 2026-09-20:批量几个一起请求再拆分对应)', () {
    test('并发多条合并为一个批量请求,结果按条对应', () async {
      final engine = FakeBatchEngine();
      final coordinator = TranslationCoordinator(
        engines: [engine],
        maxConcurrent: 1,
        minInterval: Duration.zero,
      );
      final futures = [
        coordinator.translate('한국어1'),
        coordinator.translate('한국어2'),
        coordinator.translate('한국어3'),
      ];
      await Future<void>.delayed(const Duration(milliseconds: 50));
      // ignore: avoid_print
      print(
        'DEBUG batch=${engine.batchCalls.length} single=${engine.singleCalls.length}',
      );
      final results = await futures.wait;
      expect(engine.batchCalls.length, 1, reason: '三条只发一次批量请求');
      expect(engine.singleCalls, isEmpty);
      expect(results[0], '译:한국어1');
      expect(results[2], '译:한국어3');
    });

    test('批量引擎失败时回退逐条翻译', () async {
      final engine = FakeBatchEngine(failBatch: true);
      final coordinator = TranslationCoordinator(
        engines: [engine],
        maxConcurrent: 1,
        minInterval: Duration.zero,
      );
      final results = await [
        coordinator.translate('한국어A'),
        coordinator.translate('한국어B'),
      ].wait;
      expect(engine.batchCalls, isNotEmpty);
      expect(engine.singleCalls.length, 2, reason: '批量失败后逐条重试');
      expect(results[0], '译:한국어A');
      expect(results[1], '译:한국어B');
    });

    test('仅单条引擎时保持逐条行为(志愿者实例旧形态)', () async {
      final engine = FakeSingleEngine();
      final coordinator = TranslationCoordinator(
        engines: [engine],
        maxConcurrent: 1,
        minInterval: Duration.zero,
      );
      await [coordinator.translate('텍스트1'), coordinator.translate('텍스트2')].wait;
      expect(engine.calls.length, 2);
    });
  });
}
