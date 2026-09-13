/// LivePlayer 的 media_kit 实现:封装 Player + VideoController,
/// 把 Player.stream.* 事件归一为 PlayerSnapshot;静音语义由本类维护
/// (media_kit 无独立 muted 事件流,以 volume=0 模拟并记忆原音量)。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart' show BoxFit, Widget;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';
import 'package:live_parser/live_parser.dart' show StreamLine;

import 'live_player.dart';

/// 直播卡顿/断流的错误类型(对齐 pure_live 的 PlayerErrorType 子集)。
enum _StallErrorKind { network, codec, source, other }

class MediaKitLivePlayer implements LivePlayer {
  MediaKitLivePlayer() {
    _wire();
    // 参照 pure_live 的直播卡顿根治:mpv 属性调优让断流/卡死的直播流
    // 主动报错而非无限缓冲,再由错误/看门狗路径重连。属性调优失败不阻断播放。
    unawaited(_applyLiveTuning());
  }

  final Player _player = Player();
  late final VideoController _videoController = VideoController(_player);

  /// 向 UI 广播的快照流。
  final StreamController<PlayerSnapshot> _output =
      StreamController<PlayerSnapshot>.broadcast();

  /// 最近一次发出的快照,用于合并去重。
  PlayerSnapshot _latest = const PlayerSnapshot();

  bool _muted = false;

  /// 已释放标记:app 退出时根容器可能先销毁播放器再触发页面级 stop,
  /// 此标记保证 stop 不会打到已释放的原生播放内核。
  bool _disposed = false;

  /// 静音前音量,解除静音时恢复。
  double _volumeBeforeMute = 100;

  final List<StreamSubscription<void>> _subscriptions = [];

  /// 当前整组播放线路(首选 + 回退),按打开顺序排:卡顿看门狗据此把整组
  /// 作为 mpv 播放列表自动重连,某条断流时 mpv 先内部跳下一条,耗尽后再整体轮转。
  List<StreamLine> _currentLines = const [];

  /// 缓冲看门狗:缓冲态持续超过退避时长即视为断流,自动重开。
  Timer? _stallTimer;

  /// 连续重开计数:成功后归零,超过上限停止自动重试(交还手动重连)。
  int _stallRetries = 0;

  /// 自动重试上限:超过则不再空转,留下错误快照让用户切线路/点重试。
  static const int _kMaxStallRetries = 6;

  void _wire() {
    final events = _player.stream;
    void bind<T>(Stream<T> source, PlayerSnapshot Function(PlayerSnapshot, T) patch) {
      _subscriptions.add(source.listen((value) => _emit((snapshot) => patch(snapshot, value))));
    }

    bind(events.playing, (s, v) {
      if (v) _onPlaying();
      return s.copyWith(playing: v);
    });
    bind(events.buffering, (s, v) {
      _onBuffering(v);
      return s.copyWith(buffering: v);
    });
    bind(events.volume, (s, v) => s.copyWith(volume: v));
    bind(events.width, (s, v) => s.copyWith(width: v));
    bind(events.height, (s, v) => s.copyWith(height: v));
    // 直播流不应自然结束;播放列表耗尽或 EOF 视为断流,触发整组轮转重连。
    bind(events.completed, (s, v) {
      if (v) _onCompleted();
      return s;
    });
    // 错误统一归一为快照字段;copyWith 无法回置 null,空串需显式重建清错。
    bind(events.error, (s, v) {
      if (v.isEmpty) {
        return PlayerSnapshot(
          playing: s.playing,
          buffering: s.buffering,
          volume: s.volume,
          muted: s.muted,
          width: s.width,
          height: s.height,
        );
      }
      // 非空错误:直播流异常(断流/鉴权失效),尝试自动重连。
      _onError(v);
      return s.copyWith(error: v);
    });
  }

  /// 缓冲态切换:进入缓冲即起看门狗;退出缓冲(开始出帧)取消看门狗并归零计数。
  void _onBuffering(bool buffering) {
    if (buffering) {
      _stallTimer?.cancel();
      _stallTimer = Timer(_stallBackoff, _reopenIfStalled);
    } else {
      _stallTimer?.cancel();
      _stallTimer = null;
      _stallRetries = 0;
    }
  }

  /// 正常播放:清看门狗与失败计数(说明流健康),并清掉可能残留的错误文案
  /// (自动切到下一条线路后 mpv 未必主动清空 error 属性)。
  void _onPlaying() {
    _stallTimer?.cancel();
    _stallTimer = null;
    _stallRetries = 0;
    _emit((s) => s.copyWith(error: null));
  }

  /// 非空错误:不再由 Flutter 侧重连——整组线路已作为 mpv 播放列表打开,
  /// 某条断流时 mpv 内部自动跳下一条(pure_live 式)。错误仅归一到快照展示;
  /// 真正"全组耗尽"由 [_onCompleted] 触发整组轮转,冻结型卡顿由缓冲看门狗兜底。
  void _onError(String error) {}

  /// 播放列表自然结束(直播不该发生):视为整组线路失效,触发轮转重连。
  void _onCompleted() {
    if (_currentLines.isNotEmpty && !_disposed) _reopenIfStalled();
  }

  /// 退避随连续失败增长(8→12→16…),封顶 30s,避免对死流空转过密。
  Duration get _stallBackoff {
    final seconds = 8 + _stallRetries * 4;
    return Duration(seconds: seconds.clamp(8, 30));
  }

  /// 错误归类(对齐 pure_live 的 _mapErrorType):用于给出更贴近失败类型的提示。
  _StallErrorKind _classifyError(String error) {
    final lower = error.toLowerCase();
    if (lower.contains('network') ||
        lower.contains('timeout') ||
        lower.contains('io') ||
        lower.contains('rtmp') ||
        lower.contains('rtsp')) {
      return _StallErrorKind.network;
    }
    if (lower.contains('codec') ||
        lower.contains('mediacodec') ||
        lower.contains('decode')) {
      return _StallErrorKind.codec;
    }
    if (lower.contains('404') ||
        lower.contains('source') ||
        lower.contains('open')) {
      return _StallErrorKind.source;
    }
    return _StallErrorKind.other;
  }

  /// 自动重试耗尽后的兜底提示:结合最后一次错误类型给出可操作文案。
  String _retryGiveUpMessage(String? lastError) {
    final kind = _classifyError(lastError ?? '');
    final hint = switch (kind) {
      _StallErrorKind.network =>
        '网络中断或直播源失效',
      _StallErrorKind.codec =>
        '解码失败(该线路编码可能不被支持)',
      _StallErrorKind.source =>
        '直播地址失效,可能需要重新解析房间',
      _StallErrorKind.other => '直播流反复中断',
    };
    return '$hint,请点击重试或切换线路';
  }

  /// 卡顿/错误/结束回调:把整组线路(首选 + 回退)作为 mpv 播放列表重新打开。
  /// 连续失败达上限时放弃自动重试,留错误快照交还手动重连。
  /// 注意:此处走 [resetRetries]=false 的 open,避免清空正在累积的失败计数
  /// (否则"放弃"分支永远走不到)。计数只在真正出帧(_onPlaying)或退出缓冲时归零。
  void _reopenIfStalled() {
    if (_currentLines.isEmpty || _disposed) return;
    if (_stallRetries >= _kMaxStallRetries) {
      _emit(
        (s) => s.copyWith(
          buffering: false,
          error: _retryGiveUpMessage(s.error),
        ),
      );
      return;
    }
    _stallRetries++;
    unawaited(
      open(
        _currentLines.first,
        _currentLines.skip(1).toList(),
        false,
      ),
    );
  }

  /// 参照 pure_live 的直播卡顿根治方案:直接给 mpv 设属性,而非只靠 Flutter
  /// 侧轮询。核心是把 demuxer 缓存设为有界低延迟(32MiB 前向 / 4MiB 回退 /
  /// 2s 预读),并把网络超时压到 15s——这样断流或卡死的直播流会主动抛 error
  /// (而非无限缓冲把画面冻住)。单条线路断流先由 mpv 播放列表内部自动跳下一条,
  /// 全组耗尽(events.completed)或冻结卡顿(缓冲看门狗)时再由 [_reopenIfStalled] 整组轮转。
  /// 另外 `demuxer-lavf-*` 加速探测、缓存落临时目录避免原生内存爬升。
  /// `protocol_whitelist` 放开 rtmp/rtmps/rtsp/srt 等协议——斗鱼主线路即
  /// rtmp://,缺此项会整条打不开(不只是卡顿)。
  Future<void> _applyLiveTuning() async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return; // Web/测试等非原生后端跳过。
    try {
      await platform.waitForPlayerInitialization;
      final cacheDir = '${Directory.systemTemp.path}\\zishu_demuxer_cache';
      await Directory(cacheDir).create(recursive: true);
      await platform.setProperty('force-seekable', 'yes');
      await platform.setProperty(
        'protocol_whitelist',
        'httpproxy,udp,rtp,tcp,tls,data,file,http,https,crypto,rtmp,rtmps,rtsp,srt',
      );
      await platform.setProperty('demuxer-cache-dir', cacheDir);
      await platform.setProperty('demuxer-lavf-probesize', '2097152');
      await platform.setProperty('demuxer-lavf-analyzeduration', '2');
      await platform.setProperty('network-timeout', '15');
      await platform.setProperty('hwdec-software-fallback', '1');
      await platform.setProperty('volume-max', '100');
      await platform.setProperty('demuxer-max-bytes', '33554432');
      await platform.setProperty('demuxer-max-back-bytes', '4194304');
      await platform.setProperty('demuxer-readahead-secs', '2');
      // 直播为单曲播放:播放列表耗尽即停在末条,由看门狗整组轮转重连。
      await _player.setPlaylistMode(PlaylistMode.none);
    } catch (_) {
      // 调优失败不应阻断播放;默认缓存下卡顿看门狗仍可兜底重连。
    }
  }

  /// 以 [mutate] 生成新快照,仅在发生变化时广播。
  void _emit(PlayerSnapshot Function(PlayerSnapshot) mutate) {
    if (_output.isClosed) return;
    final next = mutate(_latest);
    if (next == _latest) return;
    _latest = next;
    _output.add(next);
  }

  @override
  Stream<PlayerSnapshot> get snapshots => _output.stream;

  @override
  Widget buildVideoView({BoxFit fit = BoxFit.contain}) {
    // 不启用内置控制条(由 play feature 的控制条接管),其余用库默认。
    return Video(controller: _videoController, fit: fit, controls: null);
  }

  @override
  Future<void> open(
    StreamLine line, [
    List<StreamLine> fallbacks = const [],
    bool resetRetries = true,
  ]) async {
    // 切源即重置快照:清错误、退出播放态,进入缓冲。
    // 整组线路(首选 + 回退)按顺序拼成 mpv 播放列表:某条断流时 mpv 内部
    // 自动跳下一条,耗尽后再由看门狗整体轮转。
    _currentLines = [line, ...fallbacks];
    if (resetRetries) _stallRetries = 0;
    _stallTimer?.cancel();
    _stallTimer = null;
    _emit(
      (_) => PlayerSnapshot(
        volume: _latest.volume,
        muted: _muted,
        buffering: true,
      ),
    );
    try {
      final playlist = Playlist(
        _currentLines
            .map((item) => Media(item.url, httpHeaders: item.headers))
            .toList(growable: false),
      );
      await _player.open(playlist, play: true);
    } catch (error) {
      _emit((snapshot) => snapshot.copyWith(error: '播放失败:$error'));
    }
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    if (_disposed) return;
    // 卸载媒体即终止自动重连(离房不应在后台空转重连)。
    _stallTimer?.cancel();
    _stallTimer = null;
    _currentLines = const [];
    await _player.stop();
    // 卸载媒体后回到空闲快照:清播放/缓冲/错误,保留音量与静音语义。
    _emit(
      (_) => PlayerSnapshot(volume: _latest.volume, muted: _muted),
    );
  }

  @override
  Future<void> setVolume(double volume) async {
    final clamped = volume.clamp(0, 100).toDouble();
    // 手动拉起音量即解除静音;静音状态下置 0 则维持静音语义。
    _muted = _muted && clamped <= 0;
    if (!_muted && clamped > 0) _volumeBeforeMute = clamped;
    await _player.setVolume(clamped);
    _emit((snapshot) => snapshot.copyWith(muted: _muted));
  }

  @override
  Future<void> setMuted(bool muted) async {
    if (muted == _muted) return;
    _muted = muted;
    if (muted) {
      if (_latest.volume > 0) _volumeBeforeMute = _latest.volume;
      await _player.setVolume(0);
    } else {
      await _player.setVolume(_volumeBeforeMute <= 0 ? 100 : _volumeBeforeMute);
    }
    _emit((snapshot) => snapshot.copyWith(muted: muted));
  }

  @override
  Future<void> toggleFullscreen() async {
    // Windows 桌面全屏:取当前状态再取反。VM / 无窗口环境(单测注入 Fake 时
    // 不调用本实现,这里仍做静默降级,避免原生插件不可用时抛错)。
    try {
      await windowManager.setFullScreen(!await windowManager.isFullScreen());
    } catch (_) {
      // 平台不支持 / 插件未就绪:静默降级,不阻断上层沉浸态切换。
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _stallTimer?.cancel();
    _stallTimer = null;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    unawaited(_output.close());
    unawaited(_player.dispose());
  }
}
