// WASAPI 采集探针:验证 wasapi_loopback_tap.dart 的 FFI 链路。
// 用法:dart run tool/speech_wasapi_probe.dart [process|system]
// - process:进程 loopback,CLI 自身不发声,期望激活成功、样本全静默。
// - system:系统输出 loopback,配合外部播放声音,期望 RMS > 0。
import 'dart:io';

import 'package:zishu_flutter/src/platforms/windows/speech/wasapi_loopback_tap.dart';

Future<void> main(List<String> args) async {
  final mode = args.isEmpty ? 'process' : args[0];
  final tap = WasapiLoopbackTap(
    captureSystemOutput: mode == 'system',
  );
  var packets = 0;
  var samples = 0;
  var peak = 0.0;
  var silentPackets = 0;
  final sub = tap.pcm.listen((chunk) {
    packets++;
    samples += chunk.length;
    for (final v in chunk) {
      final a = v.abs();
      if (a > peak) peak = a;
    }
    var maxAbs = 0.0;
    for (final v in chunk) {
      final a = v.abs();
      if (a > maxAbs) maxAbs = a;
    }
    if (maxAbs == 0.0) silentPackets++;
  });

  final watch = Stopwatch()..start();
  await tap.start();
  stdout.writeln(
      'tap started: mode=$mode rate=${tap.sampleRate} ch=${tap.channels} (${watch.elapsedMilliseconds}ms)');
  await Future<void>.delayed(const Duration(seconds: 4));
  await tap.stop();
  await sub.cancel();
  stdout.writeln(
      'captured: packets=$packets samples=$samples peak=${peak.toStringAsFixed(4)} '
      'silentPackets=$silentPackets/${packets == 0 ? 0 : packets}');
  stdout.writeln(mode == 'process'
      ? (packets > 0 ? 'PROCESS LOOPBACK: OK (activation + streaming)' : 'FAIL: no packets')
      : (peak > 0.001 ? 'SYSTEM LOOPBACK: OK (audio captured)' : 'WARN: no audio heard (play something)'));
  exit(0);
}
