/// 字幕流水线:音频采集 → 重采样 → 流式识别 → 分句 → 翻译 → 中文字幕段。
///
/// 口径(与弹幕翻译一致):译文就绪才产出 [CaptionSegment];翻译失败
/// 有限次重试,重试仍失败则丢弃该句(UI 不显示原文),状态流给出错误。
library;

import 'dart:async';
import 'dart:typed_data';

import 'audio_tap_source.dart';
import 'caption_segment.dart';
import 'model_manifest.dart';
import 'resample.dart';
import 'sherpa_streaming_recognizer.dart';
import 'speech_recognizer.dart';

/// 识别器工厂(默认 sherpa;测试注入 fake)。
typedef RecognizerFactory = SpeechRecognizer Function(
    SpeechLanguage language, String modelDir);

/// 翻译 hook:原文 → 中文;null 表示本次翻译失败。
typedef Translator = Future<String?> Function(String text);

class CaptionPipeline {
  CaptionPipeline({
    RecognizerFactory? recognizerFactory,
    this.translate,
    this.translateRetryDelay = const Duration(seconds: 2),
    this.maxTranslateRetries = 3,
  }) : _recognizerFactory = recognizerFactory ?? defaultRecognizerFactory;

  /// 默认实现(sherpa isolate)。
  static SpeechRecognizer defaultRecognizerFactory(
          SpeechLanguage language, String modelDir) =>
      SherpaStreamingRecognizer(language: language, modelDir: modelDir);

  final RecognizerFactory _recognizerFactory;
  final Translator? translate;
  final Duration translateRetryDelay;
  final int maxTranslateRetries;

  final _status = StreamController<CaptionStatus>.broadcast();
  final _segments = StreamController<CaptionSegment>.broadcast();

  SpeechRecognizer? _recognizer;
  StreamSubscription<Float32List>? _tapSub;
  StreamingResampler? _resampler;
  AudioTapSource? _tap;
  final _pendingTranslations = <Timer>[];

  Stream<CaptionStatus> get status => _status.stream;
  Stream<CaptionSegment> get segments => _segments.stream;

  bool get isRunning => _tapSub != null;

  /// 启动:拉起采集 → 识别器加载(异步,可能秒级)→ 进入监听。
  Future<void> start({
    required AudioTapSource tap,
    required SpeechLanguage language,
    required String modelDir,
  }) async {
    await stop();
    _tap = tap;
    _resampler = StreamingResampler(
        sourceRate: tap.sampleRate, channels: tap.channels);
    final recognizer = _recognizerFactory(language, modelDir);
    _recognizer = recognizer;
    _status.add(const CaptionStatus(phase: CaptionPhase.loadingModel));
    recognizer.events.listen(_onAsrEvent);
    await recognizer.load();
    await tap.start();
    _tapSub = tap.pcm.listen((chunk) {
      recognizer.acceptPcm(_resampler!.process(chunk));
    });
    _status.add(const CaptionStatus(phase: CaptionPhase.listening));
  }

  Future<void> stop() async {
    for (final t in _pendingTranslations) {
      t.cancel();
    }
    _pendingTranslations.clear();
    await _tapSub?.cancel();
    _tapSub = null;
    await _tap?.stop();
    _tap = null;
    _resampler = null;
    await _recognizer?.dispose();
    _recognizer = null;
    _status.add(CaptionStatus.idle());
  }

  void _onAsrEvent(AsrEvent event) {
    if (!event.isFinal) return; // partial 不上屏
    final text = event.text.trim();
    if (text.isEmpty) return;
    final recognizer = _recognizer;
    if (recognizer == null) return;
    _translateWithRetry(recognizer.languageCode, text, 0);
  }

  Future<void> _translateWithRetry(String language, String text, int attempt) async {
    final translator = translate;
    if (translator == null) {
      // 无翻译 hook:直接产出原文段(app 侧始终提供 hook,此为兜底)。
      _segments.add(CaptionSegment(
          text: text, translated: null, language: language, at: DateTime.now()));
      return;
    }
    String? zh;
    try {
      zh = await translator(text);
    } catch (_) {
      zh = null;
    }
    if (zh != null && zh.isNotEmpty) {
      _segments.add(CaptionSegment(
        text: text,
        translated: zh,
        language: language,
        at: DateTime.now(),
      ));
      return;
    }
    if (attempt < maxTranslateRetries && isRunning) {
      _pendingTranslations.add(Timer(translateRetryDelay, () {
        _translateWithRetry(language, text, attempt + 1);
      }));
      return;
    }
    _status.add(CaptionStatus(
      phase: CaptionPhase.listening,
      message: 'translate failed: $text',
    ));
  }
}
