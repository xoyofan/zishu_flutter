/// sherpa-onnx 流式 zipformer 识别器(isolate 实现)。
///
/// 模型加载与推理都在独立 isolate(加载约数秒,推理每 160ms 块约 12ms);
/// `sherpa_onnx` 的 FFI 状态是 per-isolate 的,worker 内必须重新 init。
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'model_manifest.dart';
import 'speech_recognizer.dart';

/// Windows 防御:若 System32 存在旧版全局 onnxruntime.dll,依赖搜索会先于
/// PATH 命中导致初始化崩溃;先按 exe 同目录显式预加载配套版本(Flutter 插件
/// 会把 onnxruntime.dll bundling 到 exe 目录)可抢占同名基名。见设计文档。
void _preloadWindowsRuntime() {
  if (!Platform.isWindows) return;
  final exeDir = Platform.resolvedExecutable;
  final sep = exeDir.lastIndexOf('\\');
  if (sep <= 0) return;
  try {
    DynamicLibrary.open('${exeDir.substring(0, sep)}\\onnxruntime.dll');
  } catch (_) {
    // 预加载失败不致命:常规依赖搜索路径仍可工作。
  }
}

sherpa.OnlineRecognizerConfig _buildConfig(SpeechLanguage language, String modelDir) {
  final spec = SpeechModelManifest.specOf(language);
  final sep = Platform.pathSeparator;
  String inDir(String name) => '$modelDir$sep$name';
  final encoder = spec.files.firstWhere((f) => f.name.startsWith('encoder')).name;
  final decoder = spec.files.firstWhere((f) => f.name.startsWith('decoder')).name;
  final joiner = spec.files.firstWhere((f) => f.name.startsWith('joiner')).name;
  return sherpa.OnlineRecognizerConfig(
    model: sherpa.OnlineModelConfig(
      transducer: sherpa.OnlineTransducerModelConfig(
        encoder: inDir(encoder),
        decoder: inDir(decoder),
        joiner: inDir(joiner),
      ),
      tokens: inDir('tokens.txt'),
      numThreads: 4,
      debug: false,
      provider: 'cpu',
    ),
    decodingMethod: 'modified_beam_search',
    // 分句节奏(用户口径 2026-09-21:连续说话也要持续出字幕):
    // 尾静音 1.8s 收句、句间快速停顿 0.9s 收句。原值 2.4/1.2 在连读时
    // 长时间不产生 final,字幕表现为「时有时无」。
    enableEndpoint: true,
    rule1MinTrailingSilence: 1.8,
    rule2MinTrailingSilence: 0.9,
    rule3MinUtteranceLength: 20,
  );
}

/// worker isolate 入口。消息协议:
/// 进:{'cmd':'pcm','samples':Float32List} | {'cmd':'close'}
/// 出:{'type':'ready'} | {'type':'partial','text':..} | {'type':'final','text':..}
///    | {'type':'error','message':..} | {'type':'closed'}
Future<void> _sherpaWorker(Map<String, Object?> cfg) async {
  final reply = cfg['reply']! as SendPort;
  try {
    _preloadWindowsRuntime();
    sherpa.initBindings();
    final recognizer = sherpa.OnlineRecognizer(
        _buildConfig(cfg['language']! as SpeechLanguage, cfg['modelDir']! as String));
    final stream = recognizer.createStream();
    final port = ReceivePort();
    // 先 port 后 ready:host 侧顺序处理,'ready' 完成时下行端口已就绪。
    reply.send({'type': 'port', 'port': port.sendPort});
    reply.send(const {'type': 'ready'});
    var lastPartial = '';
    await for (final msg in port) {
      if (msg is Map && msg['cmd'] == 'close') {
        port.close();
        reply.send(const {'type': 'closed'});
        return;
      }
      if (msg is Map && msg['cmd'] == 'pcm') {
        final samples = msg['samples']! as Float32List;
        stream.acceptWaveform(samples: samples, sampleRate: 16000);
        while (recognizer.isReady(stream)) {
          recognizer.decode(stream);
        }
        if (recognizer.isEndpoint(stream)) {
          final text = recognizer.getResult(stream).text.trim();
          stream.inputFinished();
          recognizer.reset(stream);
          lastPartial = '';
          if (text.isNotEmpty) {
            reply.send({'type': 'final', 'text': text});
          }
        } else {
          final partial = recognizer.getResult(stream).text.trim();
          if (partial != lastPartial) {
            lastPartial = partial;
            reply.send({'type': 'partial', 'text': partial});
          }
        }
      }
    }
  } catch (e) {
    reply.send({'type': 'error', 'message': '$e'});
  }
}

class SherpaStreamingRecognizer implements SpeechRecognizer {
  SherpaStreamingRecognizer({required this.language, required this.modelDir});

  @override
  String get languageCode => language.code;

  final SpeechLanguage language;
  final String modelDir;

  final _events = StreamController<AsrEvent>.broadcast();
  Isolate? _isolate;
  SendPort? _workerPort;
  ReceivePort? _hostPort;

  @override
  Future<void> load() async {
    if (_isolate != null) return;
    final hostPort = ReceivePort();
    _hostPort = hostPort;
    final ready = Completer<void>();
    late final SendPort workerPort;

    hostPort.listen((msg) {
      if (msg is Map) {
        switch (msg['type']) {
          case 'port':
            workerPort = msg['port']! as SendPort;
          case 'ready':
            if (!ready.isCompleted) ready.complete();
          case 'partial':
            _events.add(AsrEvent(text: msg['text']! as String, isFinal: false));
          case 'final':
            _events.add(AsrEvent(text: msg['text']! as String, isFinal: true));
          case 'error':
            if (!ready.isCompleted) {
              ready.completeError(StateError('${msg['message']}'));
            } else {
              _events.addError(StateError('${msg['message']}'));
            }
          case 'closed':
            _hostPort?.close();
        }
      }
    });

    _isolate = await Isolate.spawn(_sherpaWorker, {
      'reply': hostPort.sendPort,
      'language': language,
      'modelDir': modelDir,
    });
    await ready.future.timeout(const Duration(seconds: 120));
    _workerPort = workerPort;
  }

  @override
  void acceptPcm(Float32List mono16k) {
    _workerPort?.send({'cmd': 'pcm', 'samples': mono16k});
  }

  @override
  Stream<AsrEvent> get events => _events.stream;

  @override
  Future<void> dispose() async {
    final port = _workerPort;
    if (port != null) {
      port.send({'cmd': 'close'});
    }
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _workerPort = null;
    _hostPort?.close();
    _hostPort = null;
    await _events.close();
  }
}
