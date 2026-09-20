/// 平台音频采集抽象。
///
/// 实现方(如 Windows WASAPI 进程 loopback)产出播放中的原始 PCM,
/// 交错排列,[sampleRate]/[channels] 描述其格式;重采样与混单声道由
/// [CaptionPipeline] 内部完成,实现方无需关心。
library;

import 'dart:typed_data';
abstract class AudioTapSource {
  /// 原始采样率(如 48000)。
  int get sampleRate;

  /// 声道数(如 2)。
  int get channels;

  /// 交错 PCM(float32,[-1,1])块流。
  Stream<Float32List> get pcm;

  Future<void> start();

  Future<void> stop();
}
