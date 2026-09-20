/// 语音识别器抽象(可插拔:当前实现为 sherpa-onnx 流式 zipformer)。
library;

import 'dart:typed_data';

/// 一条识别事件。
class AsrEvent {
  const AsrEvent({required this.text, required this.isFinal});

  /// 识别文本(流式模型无标点,英文全大写)。
  final String text;

  /// true = 一句结束(触发分句);false = 流式部分结果(不上屏,调试用)。
  final bool isFinal;
}

/// 识别器生命周期:load(可秒级,必须异步)→ acceptPcm* → events → dispose。
abstract class SpeechRecognizer {
  /// 识别语言代码('en' / 'ko')。
  String get languageCode;

  /// 加载模型;完成前 [acceptPcm] 调用无效。
  Future<void> load();

  /// 喂入 16kHz 单声道 float32 PCM。
  void acceptPcm(Float32List mono16k);

  /// 识别事件流(load 完成后开始产出)。
  Stream<AsrEvent> get events;

  Future<void> dispose();
}
