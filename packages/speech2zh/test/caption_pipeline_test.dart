import 'dart:async';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:speech2zh/src/audio_tap_source.dart';
import 'package:speech2zh/src/caption_pipeline.dart';
import 'package:speech2zh/src/caption_segment.dart';
import 'package:speech2zh/src/model_manifest.dart';
import 'package:speech2zh/src/speech_recognizer.dart';

class FakeRecognizer implements SpeechRecognizer {
  FakeRecognizer(this.languageCode);

  @override
  final String languageCode;
  final controller = StreamController<AsrEvent>.broadcast();
  final accepted = <Float32List>[];

  void emit(String text, {required bool isFinal}) =>
      controller.add(AsrEvent(text: text, isFinal: isFinal));

  @override
  Stream<AsrEvent> get events => controller.stream;

  @override
  Future<void> load() async {}

  @override
  void acceptPcm(Float32List samples) => accepted.add(samples);

  @override
  Future<void> dispose() async {
    await controller.close();
  }
}

class FakeAudioTap implements AudioTapSource {
  FakeAudioTap({this.sampleRate = 48000, this.channels = 2});

  @override
  final int sampleRate;
  @override
  final int channels;

  final controller = StreamController<Float32List>.broadcast();

  void push(Float32List chunk) => controller.add(chunk);

  @override
  Stream<Float32List> get pcm => controller.stream;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}
}

/// broadcast 流收集器(避免 isEmpty/last 等待 done 挂死)。
class Collector<T> {
  final items = <T>[];
  StreamSubscription<T>? _sub;

  void attach(Stream<T> stream) {
    _sub = stream.listen(items.add);
  }

  Future<void> cancel() => _sub!.cancel();
}

Future<void> pump() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  late FakeRecognizer recognizer;
  late FakeAudioTap tap;

  setUp(() {
    recognizer = FakeRecognizer('ko');
    tap = FakeAudioTap();
  });

  CaptionPipeline build({
    Future<String?> Function(String)? translate,
    Duration retryDelay = const Duration(milliseconds: 5),
    int maxRetries = 3,
  }) => CaptionPipeline(
    recognizerFactory: (_, _) => recognizer,
    translate: translate,
    translateRetryDelay: retryDelay,
    maxTranslateRetries: maxRetries,
  );

  test('final 事件 → 翻译 → 字幕段(译文就绪才上屏)', () async {
    final pipeline = build(translate: (t) async => '中文[$t]');
    final segs = Collector<CaptionSegment>()..attach(pipeline.segments);
    await pipeline.start(
      tap: tap,
      language: SpeechLanguage.korean,
      modelDir: 'm',
    );

    recognizer.emit('안녕하세요', isFinal: true);
    await pump();
    expect(segs.items, hasLength(1));
    expect(segs.items.first.text, '안녕하세요');
    expect(segs.items.first.translated, '中文[안녕하세요]');
    expect(segs.items.first.language, 'ko');

    // partial 事件不上屏。
    recognizer.emit('안녕', isFinal: false);
    await pump();
    expect(segs.items, hasLength(1));
    await segs.cancel();
    await pipeline.stop();
  });

  test('onAudio 统计回调给出帧数与峰值振幅(诊断静音采集)', () async {
    final stats = <(int, double)>[];
    final pipeline = CaptionPipeline(
      recognizerFactory: (_, _) => recognizer,
      onAudio: (frames, peak) => stats.add((frames, peak)),
    );
    await pipeline.start(
      tap: tap,
      language: SpeechLanguage.korean,
      modelDir: 'm',
    );

    // 静音块:峰值 0(能区分「无声采集」与「根本没采到数据」)。
    tap.push(Float32List(4800));
    await pump();
    expect(stats, hasLength(1));
    expect(stats.first.$1, inInclusiveRange(750, 850));
    expect(stats.first.$2, 0);

    // 满幅块:峰值 1(左右声道同相,避免下混相消)。
    tap.push(Float32List.fromList(List.filled(4800, 1.0)));
    await pump();
    expect(stats, hasLength(2));
    expect(stats.last.$2, closeTo(1, 1e-6));
    await pipeline.stop();
  });

  test('采集 PCM 经重采样喂给识别器', () async {
    final pipeline = build();
    await pipeline.start(
      tap: tap,
      language: SpeechLanguage.korean,
      modelDir: 'm',
    );
    // 4800 交错样本 = 2400 帧 @48k → 16k 单声道约 800 帧。
    tap.push(Float32List.fromList(List.filled(4800, 0.5)));
    await pump();
    expect(recognizer.accepted, isNotEmpty);
    expect(recognizer.accepted.first.length, inInclusiveRange(750, 850));
    await pipeline.stop();
  });

  test('翻译失败重试后成功', () async {
    var calls = 0;
    // Windows Timer 精度 ~15.6ms,retryDelay 用 0 保证时序确定。
    final pipeline = build(
      translate: (t) async {
        calls++;
        return calls < 3 ? null : '회복됨';
      },
      retryDelay: Duration.zero,
    );
    final segs = Collector<CaptionSegment>()..attach(pipeline.segments);
    await pipeline.start(
      tap: tap,
      language: SpeechLanguage.korean,
      modelDir: 'm',
    );

    recognizer.emit('테스트', isFinal: true);
    await pump();
    expect(calls, 3);
    expect(segs.items.single.translated, '회복됨');
    await segs.cancel();
    await pipeline.stop();
  });

  test('重试耗尽:无字幕段,状态给出错误', () async {
    final pipeline = build(translate: (t) async => null, maxRetries: 1);
    final segs = Collector<CaptionSegment>()..attach(pipeline.segments);
    final statuses = Collector<CaptionStatus>()..attach(pipeline.status);
    await pipeline.start(
      tap: tap,
      language: SpeechLanguage.korean,
      modelDir: 'm',
    );

    recognizer.emit('버려진 문장', isFinal: true);
    await pump();
    expect(segs.items, isEmpty);
    expect(
      statuses.items.any((s) => s.message?.contains('failed') ?? false),
      isTrue,
    );
    await statuses.cancel();
    await segs.cancel();
    await pipeline.stop();
  });

  test('无翻译 hook:产出原文段(translated=null 兜底)', () async {
    final pipeline = build();
    final segs = Collector<CaptionSegment>()..attach(pipeline.segments);
    await pipeline.start(
      tap: tap,
      language: SpeechLanguage.korean,
      modelDir: 'm',
    );
    recognizer.emit('텍스트', isFinal: true);
    await pump();
    expect(segs.items.single.translated, isNull);
    await segs.cancel();
    await pipeline.stop();
  });

  test('stop 后空闲,状态回 idle', () async {
    final pipeline = build();
    final statuses = Collector<CaptionStatus>()..attach(pipeline.status);
    await pipeline.start(
      tap: tap,
      language: SpeechLanguage.korean,
      modelDir: 'm',
    );
    expect(pipeline.isRunning, isTrue);
    await pipeline.stop();
    await pump();
    expect(pipeline.isRunning, isFalse);
    expect(statuses.items.last.phase, CaptionPhase.idle);
    await statuses.cancel();
  });
}
