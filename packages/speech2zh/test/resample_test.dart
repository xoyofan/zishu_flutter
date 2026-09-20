import 'dart:math' as math;
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:speech2zh/src/resample.dart';

Float32List stereo(Float32List mono, {int channels = 2}) {
  final out = Float32List(mono.length * channels);
  for (var i = 0; i < mono.length; i++) {
    for (var c = 0; c < channels; c++) {
      out[i * channels + c] = mono[i];
    }
  }
  return out;
}

void main() {
  test('48k 立体声恒定信号:输出长度≈帧数/3,值保持', () {
    final r = StreamingResampler(sourceRate: 48000, channels: 2);
    final frames = 4800; // 100ms
    final input = Float32List(frames * 2);
    for (var i = 0; i < input.length; i++) {
      input[i] = 0.25;
    }
    final out = r.process(input);
    expect(out.length, inInclusiveRange(frames ~/ 3 - 2, frames ~/ 3 + 2));
    for (final v in out) {
      expect(v, closeTo(0.25, 1e-6));
    }
  });

  test('跨块连续:整块处理与随机分块处理结果一致', () {
    final rand = math.Random(7);
    final frames = 48000; // 1s @48k
    final mono = Float32List(frames);
    for (var i = 0; i < frames; i++) {
      mono[i] = 0.5 * math.sin(2 * math.pi * 440 * i / 48000);
    }
    final whole = StreamingResampler(sourceRate: 48000, channels: 1).process(mono);

    final r = StreamingResampler(sourceRate: 48000, channels: 1);
    final chunked = <double>[];
    var off = 0;
    while (off < frames) {
      final len = math.min(777 + rand.nextInt(2000), frames - off);
      final out = r.process(Float32List.sublistView(mono, off, off + len));
      chunked.addAll(out);
      off += len;
    }
    expect(chunked.length, whole.length);
    for (var i = 0; i < whole.length; i++) {
      expect(chunked[i], closeTo(whole[i], 1e-6));
    }
  });

  test('双声道不等值:按均值混合', () {
    final r = StreamingResampler(sourceRate: 48000, channels: 2);
    // 6 帧:帧0=(0.2,0.6),帧1..5=(-0.4,0.0);48k→16k 输出约 2 帧。
    final input = Float32List.fromList(
        [0.2, 0.6, -0.4, 0.0, -0.4, 0.0, -0.4, 0.0, -0.4, 0.0, -0.4, 0.0]);
    final out = r.process(input);
    expect(out.length, 2);
    expect(out[0], closeTo(0.4, 1e-6));
    expect(out[1], closeTo(-0.2, 1e-6));
  });
}
