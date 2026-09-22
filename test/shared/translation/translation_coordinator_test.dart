/// 翻译协调器单测:语言判定 / 引擎解析与 failover / 缓存去重 / 节流队列。
///
/// 全部用注入的 fake fetcher / fake engine,不触网。
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_parser/live_parser.dart';
import 'package:zishu_flutter/src/shared/application/translation/translation_coordinator.dart';

void main() {
  group('needsChineseTranslation', () {
    test('英文/日文/韩文需要翻译', () {
      expect(needsChineseTranslation('hello world'), isTrue);
      expect(needsChineseTranslation('こんにちは、配信見て！'), isTrue);
      expect(needsChineseTranslation('안녕하세요'), isTrue);
      // 日文标题常夹汉字,假名存在即要翻。
      expect(needsChineseTranslation('初配信です！頑張ります'), isTrue);
      // 韩文标题夹英文。
      expect(needsChineseTranslation('브이로그 Daily vlog'), isTrue);
    });

    test('中文/纯符号数字 emoji 不需要翻译', () {
      expect(needsChineseTranslation('今天打英雄联盟 上分冲刺'), isFalse);
      expect(needsChineseTranslation('中文里夹一个 English brand 词'), isFalse);
      expect(needsChineseTranslation('123456!!!'), isFalse);
      // 颜文字/emoji 无字母 → 不翻(夹 zzZ 之类拉丁拟声词则视为要翻)。
      expect(needsChineseTranslation('🎉🎉 ( ˘ω˘ )'), isFalse);
      expect(needsChineseTranslation('   '), isFalse);
      expect(needsChineseTranslation(''), isFalse);
    });
  });

  group('needsNameTranslation(主播名:韩/日名翻,英文/中文名不翻)', () {
    test('韩文/日文名要翻,英文/中文名不翻', () {
      expect(needsNameTranslation('김도혜'), isTrue); // soop 韩文名
      expect(needsNameTranslation('브이로거TV'), isTrue);
      expect(needsNameTranslation('配信主のゆい'), isTrue); // 日文假名
      expect(needsNameTranslation('sundae_kim'), isFalse); // 英文名
      expect(needsNameTranslation('老王打游戏'), isFalse); // 中文名
      expect(needsNameTranslation('123456'), isFalse);
    });
  });

  group('LingvaEngine', () {
    test('拼 URL 并解析 translation 字段', () async {
      Uri? captured;
      final engine = LingvaEngine(
        bases: ['https://lingva.example.com/'],
        fetcher: (uri) async {
          captured = uri;
          return {'translation': '你好世界'};
        },
      );
      final out = await engine.translate('hello world');
      expect(out, '你好世界');
      expect(captured!.host, 'lingva.example.com');
      expect(captured!.path, '/api/v1/auto/zh/hello%20world');
    });

    test('实例失败逐个 failover,全失败返回 null', () async {
      var calls = 0;
      final engine = LingvaEngine(
        bases: ['https://a.example.com', 'https://b.example.com'],
        fetcher: (uri) async {
          calls++;
          if (calls == 1) throw Exception('boom');
          return {'translation': '译文'};
        },
      );
      expect(await engine.translate('hello'), '译文');
      expect(calls, 2);

      final dead = LingvaEngine(
        bases: ['https://a.example.com'],
        fetcher: (uri) async => throw Exception('down'),
      );
      expect(await dead.translate('hello'), isNull);
    });

    test('非字符串/空译文视为失败', () async {
      final engine = LingvaEngine(
        bases: ['https://a.example.com'],
        fetcher: (uri) async => {'translation': '   '},
      );
      expect(await engine.translate('hello'), isNull);
    });
  });

  group('GoogleWebEngine(浏览器字典端点 dict-chrome-ex)', () {
    test('走 translate_a/t + client=dict-chrome-ex,解析 [译文, 源语言] 对', () async {
      Uri? captured;
      final engine = GoogleWebEngine(
        fetcher: (uri) async {
          captured = uri;
          return [
            ['你好世界', 'en'],
          ];
        },
      );
      final out = await engine.translate('hello world');
      expect(out, '你好世界');
      expect(captured!.host, 'translate.googleapis.com');
      expect(captured!.path, '/translate_a/t');
      expect(captured!.queryParameters['client'], 'dict-chrome-ex');
      expect(captured!.queryParameters['sl'], 'auto');
      expect(captured!.queryParameters['tl'], 'zh-CN');
      expect(captured!.queryParameters['q'], 'hello world');
    });

    test('响应缺失/形态不符/译文为空时返回 null(上层回退原文)', () async {
      expect(
        await GoogleWebEngine(fetcher: (_) async => null).translate('hi'),
        isNull,
      );
      expect(
        await GoogleWebEngine(fetcher: (_) async => 'oops').translate('hi'),
        isNull,
      );
      expect(
        await GoogleWebEngine(fetcher: (_) async => <Object?>[]).translate('hi'),
        isNull,
      );
      expect(
        await GoogleWebEngine(
          fetcher: (_) async => [
            ['', 'en'],
          ],
        ).translate('hi'),
        isNull,
      );
    });

    test('批量:重复 q 参数一次请求（不用换行合并），结果按序对应', () async {
      Uri? captured;
      final engine = GoogleWebEngine(
        fetcher: (uri) async {
          captured = uri;
          return [
            ['你好', 'en'],
            ['世界', 'ko'],
          ];
        },
      );
      final out = await engine.translateBatch(['hello', '안녕']);
      expect(captured!.path, '/translate_a/t');
      expect(captured!.queryParametersAll['q'], ['hello', '안녕']);
      expect(out, ['你好', '世界']);
    });

    test('批量:条数不齐返回 null(协调器回退逐条)；空输入返回空表', () async {
      final engine = GoogleWebEngine(
        fetcher: (_) async => [
          ['只有一个', 'en'],
        ],
      );
      expect(await engine.translateBatch(['a', 'b']), isNull);
      expect(await engine.translateBatch(const []), isEmpty);
    });

    test('超长文本不上请求,直接返回 null', () async {
      var called = false;
      final engine = GoogleWebEngine(
        fetcher: (_) async {
          called = true;
          return [
            ['x', 'en'],
          ];
        },
      );
      expect(await engine.translate('a' * (kTranslationMaxChars + 1)), isNull);
      expect(called, isFalse);
    });
  });

  group('SimplyTranslateEngine', () {
    test('拼 query 参数并解析 translated-text 字段', () async {
      Uri? captured;
      final engine = SimplyTranslateEngine(
        bases: ['https://st.example.com'],
        fetcher: (uri) async {
          captured = uri;
          return {'translated-text': '你好'};
        },
      );
      expect(await engine.translate('hello'), '你好');
      expect(captured!.path, '/api');
      expect(captured!.queryParameters['engine'], 'google');
      expect(captured!.queryParameters['lang'], 'auto');
      expect(captured!.queryParameters['tl'], 'zh-CN');
      expect(captured!.queryParameters['text'], 'hello');
    });
  });

  group('TranslationCoordinator', () {
    test('译文缓存:同文本只打一次引擎', () async {
      var calls = 0;
      final coordinator = TranslationCoordinator(
        engines: [
          _FakeEngine(() {
            calls++;
            return 'bonjour 的译文';
          }),
        ],
      );
      expect(await coordinator.translate('bonjour'), 'bonjour 的译文');
      expect(await coordinator.translate('bonjour'), 'bonjour 的译文');
      expect(calls, 1);
    });

    test('无需翻译的文本直接原文返回,不进引擎', () async {
      var calls = 0;
      final coordinator = TranslationCoordinator(
        engines: [_FakeEngine(() {
          calls++;
          return null;
        })],
      );
      expect(await coordinator.translate('纯中文标题'), '纯中文标题');
      expect(await coordinator.translate('123'), '123');
      expect(calls, 0);
    });

    test('失败回原文并进负缓存(短窗口内不再打引擎)', () async {
      var calls = 0;
      final coordinator = TranslationCoordinator(
        engines: [_FakeEngine(() {
          calls++;
          return null;
        })],
      );
      expect(await coordinator.translate('konnichiha'), 'konnichiha');
      expect(await coordinator.translate('konnichiha'), 'konnichiha');
      expect(calls, 1);
    });

    test('并发同文本合并为一次请求', () async {
      final gate = Completer<void>();
      var calls = 0;
      final coordinator = TranslationCoordinator(
        engines: [
          _FakeEngine(() {
            calls++;
            return '结果';
          }, onCall: () => gate.future),
        ],
      );
      final f1 = coordinator.translate('hello there');
      final f2 = coordinator.translate('hello there');
      gate.complete();
      expect(await f1, '结果');
      expect(await f2, '结果');
      expect(calls, 1);
    });

    test('translateBody:文本段翻译、表情段保留、无变化返回相等列表', () async {
      final coordinator = TranslationCoordinator(
        engines: [_FakeEngine(() => '文本译文')],
      );
      final out = await coordinator.translateBody(
        text: '',
        segments: [
          const DanmakuSegment.text('hello'),
          const DanmakuSegment.emoji(text: '[Kappa]', url: 'https://e/1'),
        ],
      );
      expect(out[0].text, '文本译文');
      expect(out[0].isEmoji, isFalse);
      expect(out[1].isEmoji, isTrue);
      expect(out[1].text, '[Kappa]');

      // 已是中文:返回与输入相等的段(值相等),调用方据此跳过替换。
      final unchanged = await coordinator.translateBody(
        text: '',
        segments: const [DanmakuSegment.text('中文')],
      );
      expect(unchanged, const [DanmakuSegment.text('中文')]);

      // 空 segments:整条翻译;原文已是中文返回空列表。
      expect(
        await coordinator.translateBody(text: 'hello', segments: const []),
        [DanmakuSegment.text('文本译文')],
      );
      expect(
        await coordinator.translateBody(text: '中文', segments: const []),
        isEmpty,
      );
    });

    test('dispose 后未出队任务回退原文', () async {
      final gate = Completer<void>();
      late TranslationCoordinator coordinator;
      coordinator = TranslationCoordinator(
        engines: [
          _FakeEngine(() => 'x', onCall: () => gate.future),
        ],
        maxConcurrent: 1,
        minInterval: const Duration(milliseconds: 5),
      );
      final first = coordinator.translate('job one');
      final second = coordinator.translate('job two');
      coordinator.dispose();
      gate.complete();
      expect(await first, isNotNull);
      // 第二个未出队(串行 + 首个未完成)→ dispose 回退原文。
      expect(await second, 'job two');
    });
  });
}

/// 计数 fake 引擎:[compute] 返回译文(可 null = 失败);[onCall] 用于
/// 挂完成门闩,控制并发时序。
class _FakeEngine implements TranslationEngine {
  _FakeEngine(this.compute, {this.onCall});

  final String? Function() compute;
  final Future<void> Function()? onCall;

  @override
  Future<String?> translate(String text) async {
    final hook = onCall;
    if (hook != null) await hook();
    return compute();
  }
}
