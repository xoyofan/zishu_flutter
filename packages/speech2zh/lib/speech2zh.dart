/// speech2zh:本地语音识别中文字幕核心包。
///
/// 分层:
/// - [AudioTapSource]:平台音频采集抽象(app 侧按平台实现喂 PCM)。
/// - [SpeechModelManifest]/[ModelManager]:模型清单与下载校验。
/// - [SpeechRecognizer] 抽象 + [SherpaStreamingRecognizer] sherpa-onnx 流式实现。
/// - [CaptionPipeline]:采集 → 重采样 → 识别 → 分句 → 翻译 → 中文字幕段。
///
/// 纯 Dart:无 Flutter/Widget/media-kit 依赖;`sherpa_onnx` 为纯 dart:ffi 依赖。
library speech2zh;

export 'src/audio_tap_source.dart';
export 'src/caption_pipeline.dart';
export 'src/caption_segment.dart';
export 'src/model_manifest.dart';
export 'src/model_manager.dart';
export 'src/resample.dart';
export 'src/sherpa_streaming_recognizer.dart';
export 'src/speech_recognizer.dart';
