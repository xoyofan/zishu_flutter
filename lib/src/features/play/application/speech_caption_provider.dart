/// 语音识别中文字幕编排:全局开关 + 房间平台先验语言驱动流水线生命周期。
///
/// 生命周期:随播放页 autoDispose;开关开启即后台下载模型(一次)→ 加载
/// 识别 isolate → 启动 WASAPI 采集;关闭/离页即停。失败(平台不支持/
/// 下载失败)落 UI 提示,不影响播放主链路。
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_parser/live_parser.dart' show UpstreamProxy;
import 'package:speech2zh/speech2zh.dart';

import '../../../shared/application/translation/translation_provider.dart';
import '../../follow/application/settings_provider.dart';
import 'play_provider.dart' show PlayParams;
import 'speech_tap_factory.dart';

/// 语言先验:SOOP 韩语站,其余按英语(手动切换设置后续接入)。
SpeechLanguage speechLanguageForSite(String site) =>
    site == 'soop' ? SpeechLanguage.korean : SpeechLanguage.english;

/// 模型根目录:`%APPDATA%\zishu_flutter\speech_models`。包内不感知平台
/// 数据路径,由这里注入。下载走 HuggingFace,与解析/翻译同源消费
/// [UpstreamProxy](海外网络下直连不可达)。
final speechModelManagerProvider = Provider<ModelManager>((ref) {
  final appData = Platform.environment['APPDATA'] ?? Directory.systemTemp.path;
  final sep = Platform.pathSeparator;
  return ModelManager(
    baseDir: '$appData${sep}zishu_flutter${sep}speech_models',
    httpClientFactory: () {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 8);
      if (UpstreamProxy.enabled) {
        client.findProxy = (uri) => UpstreamProxy.findProxyValue;
      }
      return client;
    },
  );
});

/// 字幕条 UI 状态。
enum CaptionUiPhase { idle, downloading, loadingModel, listening, unsupported, error }

class CaptionUiState {
  const CaptionUiState({
    this.phase = CaptionUiPhase.idle,
    this.downloadProgress,
    this.caption,
    this.message,
  });

  final CaptionUiPhase phase;

  /// 模型下载进度 0-1(仅 downloading)。
  final double? downloadProgress;

  /// 最新一条中文字幕。
  final String? caption;

  /// 人读提示(错误/不支持)。
  final String? message;
}

final roomSpeechCaptionProvider = NotifierProvider.autoDispose
    .family<SpeechCaptionController, CaptionUiState, PlayParams>(
      SpeechCaptionController.new,
    );

class SpeechCaptionController extends Notifier<CaptionUiState> {
  SpeechCaptionController(this.params);

  final PlayParams params;

  CaptionPipeline? _pipeline;
  int _generation = 0;

  @override
  CaptionUiState build() {
    ref.onDispose(_stop);
    final enabled = ref.watch(
      settingsProvider.select((s) => s.speechCaptionEnabled),
    );
    if (!enabled) {
      _stop();
      return const CaptionUiState();
    }
    // 异步启动(build 内不允许 await);generation 防竞态(开关连点/换房)。
    Future<void>.microtask(_start);
    return const CaptionUiState();
  }

  Future<void> _start() async {
    final generation = ++_generation;
    state = const CaptionUiState(phase: CaptionUiPhase.downloading);
    try {
      final language = speechLanguageForSite(params.site);
      final modelDir = await ref
          .read(speechModelManagerProvider)
          .ensureDownloaded(
            language,
            onProgress: (p) {
              if (generation == _generation) {
                state = CaptionUiState(
                  phase: CaptionUiPhase.downloading,
                  downloadProgress: p,
                );
              }
            },
          );
      if (generation != _generation) return;
      state = const CaptionUiState(phase: CaptionUiPhase.loadingModel);
      final pipeline = _pipeline ?? _createPipeline();
      await pipeline.start(
        tap: createSpeechTap(),
        language: language,
        modelDir: modelDir,
      );
      if (generation != _generation) {
        await pipeline.stop();
        return;
      }
      _pipeline = pipeline;
      state = const CaptionUiState(phase: CaptionUiPhase.listening);
    } on UnsupportedError catch (e) {
      if (generation == _generation) {
        state = CaptionUiState(phase: CaptionUiPhase.unsupported, message: '$e');
      }
    } catch (e) {
      if (generation == _generation) {
        state = CaptionUiState(phase: CaptionUiPhase.error, message: '$e');
      }
    }
  }

  CaptionPipeline _createPipeline() {
    final coordinator = ref.read(translationCoordinatorProvider);
    return CaptionPipeline(
      // 口径:译文就绪才放行。协调器失败时回退原文,这里识别「原文回退」
      // 按未译处理(触发重试/最终丢弃,不显示原文)。
      translate: (text) async {
        final zh = await coordinator.translate(text);
        return zh == text ? null : zh;
      },
    );
  }

  void _stop() {
    _generation++;
    _pipeline?.stop();
    _pipeline = null;
  }
}
