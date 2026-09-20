/// 交错 PCM → 16kHz 单声道的流式重采样。
///
/// [StreamingResampler] 保存块间相位(源位置小数部分 + 上块尾样本),
/// 保证跨块输出连续,可对任意大小的块反复 [process]。
library;

import 'dart:typed_data';

/// 目标采样率:sherpa-onnx 特征输入固定 16k。
const int kTargetSampleRate = 16000;

class StreamingResampler {
  StreamingResampler({required this.sourceRate, required this.channels})
      : assert(sourceRate > 0),
        assert(channels >= 1);

  final int sourceRate;
  final int channels;

  double _srcPos = 0; // 下一个输出样本对应的源帧位置(帧 = 一次采样所有声道)
  double _prevFrame = 0; // 上块最后一帧的均值(块边界插值用)
  bool _hasPrev = false;

  /// 处理一块交错 PCM,返回 16k 单声道样本。
  Float32List process(Float32List interleaved) {
    final frameCount = interleaved.length ~/ channels;
    if (frameCount == 0) return Float32List(0);

    // 均值混单声道。
    final mono = Float32List(frameCount);
    for (var f = 0; f < frameCount; f++) {
      var acc = 0.0;
      final base = f * channels;
      for (var c = 0; c < channels; c++) {
        acc += interleaved[base + c];
      }
      mono[f] = acc / channels;
    }

    final ratio = sourceRate / kTargetSampleRate;
    final outCapacity = (frameCount / ratio).ceil() + 1;
    final out = Float32List(outCapacity);
    var n = 0;

    // 输出位置 _srcPos 落在 [本块首帧] 与 [本块末帧+1) 之间;跨块插值时
    // 左邻帧取 _prevFrame(上块尾)。
    final lastSrc = frameCount - 1;
    while (_srcPos < frameCount) {
      final i0 = _srcPos.floor();
      final frac = _srcPos - i0;
      final left = i0 < 0 ? (_hasPrev ? _prevFrame : mono[0]) : mono[i0];
      final right = i0 >= lastSrc ? mono[lastSrc] : mono[i0 + 1];
      out[n++] = left + (right - left) * frac;
      _srcPos += ratio;
    }
    _srcPos -= frameCount; // 折算成下一块的相对位置(可能 <0,由 _prevFrame 补)
    _prevFrame = mono[lastSrc];
    _hasPrev = true;
    return Float32List.sublistView(out, 0, n);
  }
}
