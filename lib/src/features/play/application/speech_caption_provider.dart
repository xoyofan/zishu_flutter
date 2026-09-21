/// 语音识别中文字幕编排:全局开关 + 房间平台先验语言驱动流水线生命周期。
///
/// 诊断日志:经 [PlaybackLog] 落 `%APPDATA%\zishu_flutter\logs\playback.log`,
/// 事件前缀 `caption_` / `prefetch_`。release GUI 无控制台，「模型下载到哪 /
/// 引擎是否加载成功 / 采集是否出音 / 是否产出字幕」只能靠它观测。
/// 调试时可用 `--dart-define=ZISHU_CAPTION_LOG=false` 关掉。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_parser/live_parser.dart' show UpstreamProxy;
import 'package:speech2zh/speech2zh.dart';

import '../../../platforms/common/playback/playback_log.dart';
import '../../../shared/application/translation/translation_provider.dart';
import '../../follow/application/settings_provider.dart';
import 'caption_lines.dart';
import 'play_provider.dart' show PlayParams;
import 'speech_tap_factory.dart';

SpeechLanguage speechLanguageForSite(String site) =>
    site == 'soop' ? SpeechLanguage.korean : SpeechLanguage.english;

/// 语言的中文展示名(字幕条文案:「英文/韩文字幕模型下载中…」)。
String speechLanguageLabel(SpeechLanguage language) => switch (language) {
  SpeechLanguage.english => '英文',
  SpeechLanguage.korean => '韩文',
};

/// 字幕诊断日志开关(默认开:低频事件,对分析与发布验证都必要)。
const bool kCaptionLogEnabled = bool.fromEnvironment(
  'ZISHU_CAPTION_LOG',
  defaultValue: true,
);

/// 停滞检测:每 10s 检查一次,连续 90s 没有新字节才算卡死。
///
/// 不能用「总耗时上限」:经代理下载实测约 100KB/s,68MB 模型要十几分钟,
/// 固定上限会把正常但慢的下载误杀(2026-09-21 真机 `download cancelled`)。
const Duration kCaptionStallCheckInterval = Duration(seconds: 10);
const Duration kCaptionStallLimit = Duration(seconds: 90);

final speechModelManagerProvider = Provider<ModelManager>((ref) {
  final appData = Platform.environment['APPDATA'] ?? Directory.systemTemp.path;
  final sep = Platform.pathSeparator;
  return ModelManager(
    baseDir: '$appData${sep}zishu_flutter${sep}speech_models',
    httpClientFactory: () {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 8);
      if (UpstreamProxy.enabled) {
        // HuggingFace 需代理;仍走统一主机策略,便于以后换镜像。
        client.findProxy = (uri) => UpstreamProxy.findProxyFor(uri);
      }
      return client;
    },
  );
});

enum CaptionUiPhase {
  idle,
  downloading,
  loadingModel,
  listening,
  unsupported,
  error,
}

class CaptionUiState {
  const CaptionUiState({
    this.phase = CaptionUiPhase.idle,
    this.language,
    this.downloadProgress,
    this.lines = const [],
    this.downloadBytesPerSecond,
    this.message,
  });

  final CaptionUiPhase phase;

  /// 当前字幕语言(文案要指明是哪个模型:「英文/韩文字幕模型下载中…」)。
  final SpeechLanguage? language;

  final double? downloadProgress;

  /// 当前在屏的多句字幕(每句存活 5s,过期由 controller 剪除)。
  final List<CaptionLine> lines;

  /// 下载速度(字节/秒);仅 downloading 有值 —— 慢速下载时它让「没卡住」
  /// 变得可见(实测经代理约 100KB/s,只显示百分比会被误认为卡死)。
  final double? downloadBytesPerSecond;

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
  StreamSubscription<CaptionSegment>? _segmentSub;
  int _generation = 0;
  int _lastProgressBucket = -1;
  DateTime? _lastAudioLogAt;
  Timer? _watchdog;
  CaptionUiPhase? _lastLoggedPhase;
  int _lastLoggedBucket = -1;
  String? _lastLoggedMessage;

  /// 当前相位(剪枝重建状态时用它保持相位不变)。
  CaptionUiPhase _phase = CaptionUiPhase.idle;

  /// 在屏字幕行(多句并存 + 定长存活)。
  final CaptionLineBuffer _lines = CaptionLineBuffer();
  Timer? _pruneTimer;

  /// 下载停滞检测用:上次进度与速度采样点。
  DateTime? _lastProgressAt;
  int _lastProgressBytes = 0;
  DateTime? _speedSampledAt;

  ModelDownloadInfo downloadInfo(SpeechLanguage language) =>
      ref.read(speechModelManagerProvider).inspect(language);

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
    Future<void>.microtask(_start);
    return const CaptionUiState();
  }

  /// 统一的 UI 状态出口:状态变化时落一条 `caption_phase`。
  ///
  /// 字幕条显示的永远是这个状态,把它与日志对齐后,「屏幕上卡在哪一步」
  /// 与「日志停在哪一步」可以直接对上。
  ///
  /// **只在相位变化或进度跳 10% 时落一条**:下载回调按网络 chunk 触发,
  /// 不去重会把日志刷成每秒几十条同样的行(2026-09-21 实测)。
  void _setState(CaptionUiState next) {
    state = next;
    _phase = next.phase;
    final progress = next.downloadProgress;
    final bucket = progress == null ? -1 : (progress * 10).floor();
    final changed =
        next.phase != _lastLoggedPhase ||
        bucket != _lastLoggedBucket ||
        next.message != _lastLoggedMessage;
    if (!changed) return;
    _lastLoggedPhase = next.phase;
    _lastLoggedBucket = bucket;
    _lastLoggedMessage = next.message;
    _log('caption_phase', {
      'phase': next.phase.name,
      if (progress != null) 'pct': (progress * 100).round(),
      if (next.message != null) 'msg': next.message,
    });
  }

  Future<void> _start() async {
    final generation = ++_generation;
    final language = speechLanguageForSite(params.site);
    final manager = ref.read(speechModelManagerProvider);
    final initial = manager.inspect(language);
    _log('caption_start', {
      'site': params.site,
      'room': params.roomId,
      'lang': language.code,
      'langLabel': speechLanguageLabel(language),
      'ready': initial.ready,
      'doneMB': _mb(initial.downloadedBytes),
      'totalMB': _mb(initial.totalBytes),
      'partial': initial.hasPartial,
    });
    _setState(
      CaptionUiState(
        phase: CaptionUiPhase.downloading,
        language: language,
        downloadProgress: initial.progress,
        lines: _lines.lines,
      ),
    );
    // 看门狗采用**停滞检测**而非总耗时上限:经代理下载实测约 100KB/s,
    // 68MB 要十几分钟 —— 固定 3 分钟上限会把「慢但在前进」误判为卡死
    // (2026-09-21 真机:caption_watchdog → download cancelled)。
    // 只有连续 kCaptionStallLimit 没有新字节才算真卡死。
    _lastProgressAt = DateTime.now();
    _lastProgressBytes = initial.downloadedBytes;
    final watchdog = Timer.periodic(kCaptionStallCheckInterval, (_) {
      if (generation != _generation) return;
      final stalledFor = DateTime.now().difference(_lastProgressAt!);
      if (stalledFor < kCaptionStallLimit) return;
      // 真停滞:解开卡死的在途任务(否则重试会拿到同一个永不完成的 Future),
      // 并推进代际 —— 让被弃任务随后的异常无法覆盖这里的错误文案。
      manager.abandon(language);
      _generation++;
      _watchdog?.cancel();
      _log('caption_watchdog', {
        'stage': 'model_or_engine',
        'stalledSec': stalledFor.inSeconds,
      });
      _setState(
        CaptionUiState(
          phase: CaptionUiPhase.error,
          message: '字幕模型下载停滞,请重试(已下载 ${_mb(_lastProgressBytes)}MB)',
          lines: _lines.lines,
        ),
      );
    });
    _watchdog = watchdog;
    try {
      final modelDir = await manager.ensureDownloaded(
        language,
        onProgress: (p) {
          _logProgress(p);
          if (generation != _generation) return;
          final bytes = (p * initial.totalBytes).round();
          if (bytes > _lastProgressBytes) {
            _lastProgressBytes = bytes;
            _lastProgressAt = DateTime.now();
          }
          _setState(
            CaptionUiState(
              phase: CaptionUiPhase.downloading,
              language: language,
              downloadProgress: p,
              downloadBytesPerSecond: _sampleSpeed(bytes),
              lines: _lines.lines,
            ),
          );
        },
      );
      if (generation != _generation) {
        watchdog.cancel();
        return;
      }
      _log('caption_download_done', {'lang': language.code, 'dir': modelDir});
      _setState(
        CaptionUiState(
          phase: CaptionUiPhase.loadingModel,
          language: language,
          lines: _lines.lines,
        ),
      );
      final loadStartedAt = DateTime.now();
      final pipeline = _createPipeline();
      await pipeline.start(
        tap: createSpeechTap(),
        language: language,
        modelDir: modelDir,
      );
      watchdog.cancel();
      _log('caption_load_ok', {
        'lang': language.code,
        'ms': DateTime.now().difference(loadStartedAt).inMilliseconds,
      });
      if (generation != _generation) {
        await pipeline.stop();
        return;
      }
      final sub = pipeline.segments.listen((segment) {
        _log('caption_seg', {
          'lang': segment.language,
          'len': segment.text.length,
          'translated': (segment.translated ?? '').isNotEmpty,
        });
        final text = segment.translated?.trim();
        if (generation != _generation || text == null || text.isEmpty) return;
        _lines.add(text, DateTime.now());
        _schedulePrune(generation);
        _setState(
          CaptionUiState(phase: CaptionUiPhase.listening, lines: _lines.lines),
        );
      });
      _segmentSub = sub;
      _pipeline = pipeline;
      _setState(
        CaptionUiState(
          phase: CaptionUiPhase.listening,
          language: language,
          lines: _lines.lines,
        ),
      );
    } on UnsupportedError catch (e) {
      watchdog.cancel();
      _log('caption_unsupported', {'error': '$e'});
      if (generation == _generation) {
        _setState(
          CaptionUiState(phase: CaptionUiPhase.unsupported, message: '$e'),
        );
      }
    } catch (e) {
      watchdog.cancel();
      _log('caption_fail', {'error': '$e'});
      if (generation == _generation) {
        _setState(CaptionUiState(phase: CaptionUiPhase.error, message: '$e'));
      }
    }
  }

  /// 下载进度按 10% 阶梯落盘(低频:一条模型只记 ≤11 条)。
  void _logProgress(double p) {
    final bucket = (p * 10).floor();
    if (bucket == _lastProgressBucket) return;
    _lastProgressBucket = bucket;
    _log('caption_download', {'pct': (p * 100).round()});
  }

  /// 音频块统计:首块必记,之后每 5s 记一条(诊断「采集是否出音」)。
  void _logAudio(int frames, double peak) {
    final now = DateTime.now();
    final last = _lastAudioLogAt;
    if (last != null && now.difference(last) < const Duration(seconds: 5)) {
      return;
    }
    _lastAudioLogAt = now;
    _log('caption_audio', {'frames': frames, 'peak': peak.toStringAsFixed(4)});
  }

  /// 剪枝排程:到最早一句过期时重算一次,无内容则不再排。
  ///
  /// 用「定时到最近一次过期」而不是高频轮询,避免空转;字幕条内容因此
  /// 到点自动消失(用户口径:每句存活 5s)。
  void _schedulePrune(int generation) {
    if (_pruneTimer != null) return;
    final delay = _lines.nextExpiryIn(DateTime.now());
    if (delay == null) return;
    _pruneTimer = Timer(delay, () {
      _pruneTimer = null;
      if (generation != _generation || !ref.mounted) return;
      final changed = _lines.prune(DateTime.now());
      if (changed) {
        _setState(
          CaptionUiState(
            phase: _phase,
            language: state.language,
            lines: _lines.lines,
          ),
        );
      }
      if (_lines.lines.isNotEmpty) _schedulePrune(generation);
    });
  }

  /// 采样下载速度(字节/秒):按 1s 窗口近似,首次采样返回 null。
  double? _sampleSpeed(int bytes) {
    final now = DateTime.now();
    final lastAt = _speedSampledAt;
    if (lastAt == null) {
      _speedSampledAt = now;
      return null;
    }
    final elapsed = now.difference(lastAt).inMilliseconds;
    if (elapsed < 1000) return state.downloadBytesPerSecond;
    final delta = bytes - _lastProgressBytes;
    _speedSampledAt = now;
    _lastProgressBytes = bytes;
    if (delta <= 0) return 0;
    return delta * 1000 / elapsed;
  }

  void _log(String event, Map<String, Object?> fields) {
    if (!kCaptionLogEnabled) return;
    PlaybackLog.write(event, fields);
  }

  String _mb(int bytes) => (bytes / 1024 / 1024).toStringAsFixed(1);

  CaptionPipeline _createPipeline() {
    final coordinator = ref.read(translationCoordinatorProvider);
    return CaptionPipeline(
      onAudio: _logAudio,
      translate: (text) async {
        final zh = await coordinator.translate(text);
        return zh == text ? null : zh;
      },
    );
  }

  void _stop() {
    _generation++;
    _watchdog?.cancel();
    _watchdog = null;
    _pruneTimer?.cancel();
    _pruneTimer = null;
    _lines.clear();
    unawaited(_segmentSub?.cancel());
    _segmentSub = null;
    _pipeline?.stop();
    _pipeline = null;
  }
}
