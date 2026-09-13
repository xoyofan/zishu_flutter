/// 播放错误分类器单测(纯 Dart,不依赖 Flutter 运行时与播放器实例)。
///
/// 重点验证两件事:
/// 1. **类别判定**:mpv 各类诊断文本落到正确的 [PlayerErrorKind];
/// 2. **终局性判定**:只有"不换源/不改状态就无法自愈"的错误才 `terminal`,
///    因为 UI 据此决定是否弹错误卡片 —— 把可自愈噪音弹成错误卡片是本模块
///    要修的原始缺陷。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:zishu_flutter/src/platforms/common/playback/player_error.dart';

void main() {
  group('空输入', () {
    test('空串与纯空白归类为 none,不算错误', () {
      for (final input in <String>['', '   ', '\n\t ']) {
        final result = PlayerErrorClassifier.classify(input);
        expect(result.kind, PlayerErrorKind.none, reason: 'input=$input');
        expect(result.isError, isFalse);
        expect(result.terminal, isFalse);
      }
    });

    test('PlayerErrorClassification.none 是稳定的哨兵', () {
      expect(PlayerErrorClassification.none.kind, PlayerErrorKind.none);
      expect(PlayerErrorClassification.none.isError, isFalse);
    });
  });

  group('类别与终局性', () {
    test('网络类诊断 → network 且终局', () {
      const samples = <String>[
        'Connection timed out',
        'Network is unreachable',
        'Connection reset by peer',
        'Failed to resolve hostname',
        'TLS handshake failed',
        'Input/output error',
      ];
      for (final raw in samples) {
        final result = PlayerErrorClassifier.classify(raw);
        expect(result.kind, PlayerErrorKind.network, reason: raw);
        expect(result.terminal, isTrue, reason: raw);
        expect(result.code, 'transport', reason: raw);
      }
    });

    test('源侧打开失败(4xx/协议/输入)→ source 且终局', () {
      const samples = <String>[
        'Server returned 404 Not Found',
        'protocol not found',
        'No protocol handler for rtmp',
        'Failed to open input',
        'Invalid data found when processing input',
        'No streams found',
      ];
      for (final raw in samples) {
        final result = PlayerErrorClassifier.classify(raw);
        expect(result.kind, PlayerErrorKind.source, reason: raw);
        expect(result.terminal, isTrue, reason: raw);
        expect(result.code, 'source_open', reason: raw);
      }
    });

    test('编码不受支持 → codec 且终局', () {
      const samples = <String>[
        'No decoder found for AV1',
        'Unsupported codec h265',
        'codec is not supported',
      ];
      for (final raw in samples) {
        final result = PlayerErrorClassifier.classify(raw);
        expect(result.kind, PlayerErrorKind.codec, reason: raw);
        expect(result.terminal, isTrue, reason: raw);
        expect(result.code, 'decoder_init', reason: raw);
      }
    });

    test('解码过程抖动 → codec 但**非终局**(交给 mpv 自愈)', () {
      const samples = <String>[
        'error while decoding MB 12 3',
        'corrupt decoded frame',
        'missing reference picture',
        'Invalid NAL unit size',
      ];
      for (final raw in samples) {
        final result = PlayerErrorClassifier.classify(raw);
        expect(result.kind, PlayerErrorKind.codec, reason: raw);
        expect(result.terminal, isFalse, reason: raw);
        expect(result.code, 'decoder_runtime', reason: raw);
      }
    });

    test('视频输出失败 → texture 且终局', () {
      const samples = <String>[
        'Failed to create texture',
        'surface has been released',
        'vulkan error: device lost',
      ];
      for (final raw in samples) {
        final result = PlayerErrorClassifier.classify(raw);
        expect(result.kind, PlayerErrorKind.texture, reason: raw);
        expect(result.terminal, isTrue, reason: raw);
        expect(result.code, 'video_output', reason: raw);
      }
    });

    test('播放器生命周期噪音 → lifecycle 且终局', () {
      const samples = <String>[
        'player has been disposed',
        'Operation Was Cancelled',
      ];
      for (final raw in samples) {
        final result = PlayerErrorClassifier.classify(raw);
        expect(result.kind, PlayerErrorKind.lifecycle, reason: raw);
        expect(result.terminal, isTrue, reason: raw);
      }
    });

    test('源运行时(EOF/demuxer)→ source 但非终局', () {
      const samples = <String>['demuxer: unexpected eof', 'End of file'];
      for (final raw in samples) {
        final result = PlayerErrorClassifier.classify(raw);
        expect(result.kind, PlayerErrorKind.source, reason: raw);
        expect(result.terminal, isFalse, reason: raw);
        expect(result.code, 'source_runtime', reason: raw);
      }
    });

    test('无法识别的诊断 → native 且非终局', () {
      final result = PlayerErrorClassifier.classify('some new mpv diagnostic');
      expect(result.kind, PlayerErrorKind.native);
      expect(result.terminal, isFalse);
      expect(result.isError, isTrue);
    });
  });

  group('判定优先级', () {
    test('同时像源侧与网络的文本,源侧优先(更具体)', () {
      // `failed to open input` 同时命中 source-open 与 source-runtime 标记,
      // 排序决定它必须归到更具体的 source_open。
      final result = PlayerErrorClassifier.classify('Failed to open input stream');
      expect(result.kind, PlayerErrorKind.source);
      expect(result.code, 'source_open');
    });

    test('lifecycle 优先于一切(切源竞态噪音不该被当成源失效)', () {
      final result = PlayerErrorClassifier.classify(
        'player has been disposed while failed to open input',
      );
      expect(result.kind, PlayerErrorKind.lifecycle);
    });
  });

  group('文本归一与组件标记', () {
    test('大小写与首尾空白不影响判定', () {
      final a = PlayerErrorClassifier.classify('  CONNECTION TIMED OUT  ');
      final b = PlayerErrorClassifier.classify('connection timed out');
      expect(a, b);
    });

    test('nativePrefix 只影响码位,不影响类别', () {
      final audio = PlayerErrorClassifier.classify(
        'no decoder found',
        nativePrefix: 'ad',
      );
      final video = PlayerErrorClassifier.classify(
        'no decoder found',
        nativePrefix: 'vd',
      );
      expect(audio.kind, PlayerErrorKind.codec);
      expect(audio.code, 'audio_decoder_init');
      expect(video.kind, PlayerErrorKind.codec);
      expect(video.code, 'video_decoder_init');
    });

    test('未知 nativePrefix 退化为不带通道前缀的码位', () {
      final result = PlayerErrorClassifier.classify(
        'no decoder found',
        nativePrefix: 'zz',
      );
      expect(result.code, 'decoder_init');
    });
  });

  group('shouldSurface', () {
    test('只有终局错误才值得上报给用户', () {
      expect(PlayerErrorClassifier.shouldSurface('connection timed out'), isTrue);
      expect(PlayerErrorClassifier.shouldSurface('error while decoding MB 1'), isFalse);
      expect(PlayerErrorClassifier.shouldSurface(''), isFalse);
    });
  });

  group('处置建议文案', () {
    test('每个类别都有非空且不重复的建议(除 none)', () {
      final messages = <PlayerErrorKind, String>{};
      for (final kind in PlayerErrorKind.values) {
        final hint = playerErrorHint(kind);
        if (kind == PlayerErrorKind.none) {
          expect(hint, isEmpty);
          continue;
        }
        expect(hint, isNotEmpty, reason: '$kind 缺少建议文案');
        messages[kind] = hint;
      }
      expect(
        messages.values.toSet().length,
        messages.length,
        reason: '不同类别应有区分度，不应共用同一句建议',
      );
    });

    test('建议文案包含可操作动词,不是纯陈述', () {
      for (final kind in <PlayerErrorKind>[
        PlayerErrorKind.network,
        PlayerErrorKind.source,
        PlayerErrorKind.codec,
        PlayerErrorKind.texture,
        PlayerErrorKind.lifecycle,
      ]) {
        final hint = playerErrorHint(kind);
        expect(
          hint.contains('重试') || hint.contains('切换'),
          isTrue,
          reason: '$kind 的建议缺少可操作动作:$hint',
        );
      }
    });
  });
}
