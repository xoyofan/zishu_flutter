/// LivePlayer 的 media_kit 实现:封装 Player + VideoController,
/// 把 Player.stream.* 事件归一为 PlayerSnapshot;静音语义由本类维护
/// (media_kit 无独立 muted 事件流,以 volume=0 模拟并记忆原音量)。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart' show BoxFit, Color, Widget;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:live_parser/live_parser.dart' show StreamLine;
import 'package:window_manager/window_manager.dart' show DragToResizeArea;

import 'live_player.dart';
import 'playback_retry.dart';
import 'player_error.dart';
import 'window_presentation.dart';

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

  /// 窗口表现(系统全屏 / 画中画)统一委托给 [WindowPresentation]:幂等设置、
  /// 防重入与 PiP 进出的 bounds 记忆都在那一层,本类只转发,保持
  /// "播放器管播放、窗口管窗口"的边界。
  final WindowPresentation _windowPresentation = WindowPresentation.instance;

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

  /// 健康观察窗:出帧后持续播满 [PlaybackRetryPolicy.healthWindow] 才把
  /// 连续失败计数归零。**这是"有限重试"能真正收敛的关键** —— 抖动的死流会
  /// 反复 `buffering true→false→true`,若在 false 就清零,计数永远涨不上去,
  /// 放弃分支不可达,退化为无限空转(旧实现的真实缺陷)。
  Timer? _healthTimer;

  /// 连续重开计数:健康窗口走完才归零,超过上限停止自动重试(交还手动重连)。
  int _stallRetries = 0;

  /// 最后一次**终局**错误的类别:用于自动重试耗尽后给出对症的处置建议。
  /// 刻意不存原始诊断文本 —— 那是 mpv 日志原文,其中大量条目是可自愈噪音。
  PlayerErrorKind _lastErrorKind = PlayerErrorKind.native;

  /// 有界重连策略(上限 / 退避 / 健康窗口的唯一来源)。
  static const PlaybackRetryPolicy _policy = PlaybackRetryPolicy();

  bool get _disposedOrEmpty => _disposed || _currentLines.isEmpty;

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
    //
    // media_kit 的 error 流转发的是 **mpv 的 error 级日志行**,并非每条都是
    // 终局失败(硬解被拒后已自动软解、丢包后跟上了关键帧等)。因此这里先过
    // [PlayerErrorClassifier]:只有 `terminal` 的诊断才展示给用户,其余交给
    // mpv 自愈。旧实现把每一条都当"播放失败"弹卡片,会出现「画面照常在播、
    // 错误卡片却悬在中间」的假错误。
    bind(events.error, (s, v) {
      final classification = PlayerErrorClassifier.classify(v);
      if (!classification.isError) {
        return s.copyWith(error: null);
      }
      if (!classification.terminal) return s;
      _onTerminalError(classification);
      return s.copyWith(
        error: playerErrorHint(classification.kind),
        errorKind: classification.kind,
      );
    });
  }

  /// 缓冲态切换:进入缓冲即起看门狗;退出缓冲仅撤销看门狗。
  ///
  /// **退出缓冲不清零失败计数**(旧实现清了,是收敛缺陷):直播流的 buffering
  /// 标志在死流上也会短暂回落再拉起,清零会让计数永远追不上"放弃"上限。
  /// 计数只由 [PlaybackRetryPolicy.healthWindow] 观察窗确认健康后归零。
  void _onBuffering(bool buffering) {
    if (buffering) {
      _cancelHealthTimer();
      _armStallTimer();
    } else {
      _stallTimer?.cancel();
      _stallTimer = null;
    }
  }

  /// 出帧开始播放:撤看门狗、清残留错误文案(自动切到下一条线路后 mpv 未必
  /// 主动清空 error 属性),并启动健康观察窗 —— 只有持续播满观察窗才把连续
  /// 失败计数归零,避免"短暂出帧即视为康复"导致重试上限形同虚设。
  void _onPlaying() {
    _stallTimer?.cancel();
    _stallTimer = null;
    _emit((s) => s.copyWith(error: null));
    final retries = _stallRetries;
    if (retries > 0) {
      _healthTimer?.cancel();
      _healthTimer = Timer(_policy.healthWindow, () {
        _healthTimer = null;
        if (_disposed) return;
        _stallRetries = 0;
        // 计数归零后进度文案要跟着退场,否则会残留"自动重连中 2/6"。
        _emit((s) => s.copyWith(retryAttempt: 0));
      });
    }
  }

  /// 按当前连续失败次数起看门狗。
  ///
  /// **已挂起则不重启**(幂等):mpv 对同一个故障会反复吐同一条诊断,缓冲标志也
  /// 会反复置位。若每次都 cancel + 重新计时,看门狗会被永久推迟 —— 表现为
  /// "自动重连永远不触发"的看门狗饥饿。已挂起就让它按原定时刻到期。
  void _armStallTimer() {
    if (_stallTimer != null) return;
    _stallTimer = Timer(_policy.backoffFor(_stallRetries), _reopenIfStalled);
  }

  void _cancelHealthTimer() {
    _healthTimer?.cancel();
    _healthTimer = null;
  }

  /// 收到**终局**诊断:记录类别(供放弃时给出对症建议)。不在此处重连 ——
  /// 整组线路已作为 mpv 播放列表打开,某条断流时 mpv 内部自动跳下一条;
  /// Flutter 侧若同时重连会与 mpv 的自动跳转形成重开循环(踩坑记录)。
  /// 唯一例外:整组只有一条线路时 mpv 无处可跳,此时才由看门狗兜底。
  void _onTerminalError(PlayerErrorClassification classification) {
    _lastErrorKind = classification.kind;
    if (_currentLines.length <= 1 && !_disposed) _armStallTimer();
  }

  /// 播放列表自然结束(直播不该发生):视为整组线路失效,触发轮转重连。
  void _onCompleted() {
    if (!_disposedOrEmpty) _reopenIfStalled();
  }

  /// 卡顿/错误/结束回调:把整组线路(首选 + 回退)作为 mpv 播放列表重新打开。
  /// 连续失败达上限时放弃自动重试,留错误快照(含对症建议)交还手动重连。
  /// 注意:此处走 [resetRetries]=false 的 open,避免清空正在累积的失败计数
  /// (否则"放弃"分支永远走不到)。计数只在健康观察窗走完后归零。
  void _reopenIfStalled() {
    if (_disposedOrEmpty) return;
    _stallTimer = null;
    if (!_policy.canRetry(_stallRetries)) {
      _emit(
        (s) => s.copyWith(
          buffering: false,
          error: _policy.giveUpMessage(_lastErrorKind),
          errorKind: _lastErrorKind,
        ),
      );
      return;
    }
    _stallRetries++;
    _cancelHealthTimer();
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
  /// 统一补上重连上限,[retryLimit] 因此不需要每个发出点各自记得填。
  void _emit(PlayerSnapshot Function(PlayerSnapshot) mutate) {
    if (_output.isClosed) return;
    final next = mutate(_latest).copyWith(retryLimit: _policy.maxAttempts);
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
    _cancelHealthTimer();
    // 保留已出画面的宽高:自动重连期间 PiP 小窗要沿用原宽高比,不该退回 16:9。
    // 错误文案的区别对待很关键:用户主动切源([resetRetries] 为 true)才清错误,
    // 让卡片退出;自动重连([resetRetries] 为 false)要**留着**错误 + 计数,
    // 这样阶段浮层能显示"自动重连中 n/上限",用户知道程序在自救而非卡死。
    final keepError = !resetRetries && _latest.error != null;
    _emit(
      (s) => PlayerSnapshot(
        volume: s.volume,
        muted: _muted,
        width: s.width,
        height: s.height,
        buffering: true,
        error: keepError ? s.error : null,
        errorKind: keepError ? s.errorKind : PlayerErrorKind.none,
        retryAttempt: _stallRetries,
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
      // 原始异常(ArgumentError / PlatformException 等)不是 mpv 日志,直接展示
      // 对用户无意义;归类后给处置建议,归类不出则退到兜底文案。
      final classification = PlayerErrorClassifier.classify('$error');
      final kind = classification.isError
          ? classification.kind
          : PlayerErrorKind.native;
      _lastErrorKind = kind;
      _emit(
        (s) => s.copyWith(error: playerErrorHint(kind), errorKind: kind),
      );
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
    _cancelHealthTimer();
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
  Future<void> setFullscreen(bool fullscreen) =>
      _windowPresentation.setFullscreen(fullscreen);

  @override
  Future<void> toggleFullscreen() => _windowPresentation.toggleFullscreen();

  @override
  Future<void> enterPictureInPicture({double? aspectRatio}) =>
      _windowPresentation.enterPip(aspectRatio: aspectRatio ?? _videoAspectRatio);

  @override
  Future<void> exitPictureInPicture() => _windowPresentation.exitPip();

  @override
  Widget wrapPipSurface(Widget child) {
    // 仅 Windows 需要桌面包壳;其余平台(含单测 VM 之外的非桌面宿主)透传。
    // `DragToResizeArea` 自身传递性依赖 dart:io,只允许出现在平台层。
    if (!Platform.isWindows) return child;
    return DragToResizeArea(resizeEdgeColor: const Color(0x00000000), child: child);
  }

  /// 当前视频宽高比(PiP 小窗据此定尺寸);未出画面时返回 null,由 PiP 侧退回 16:9。
  double? get _videoAspectRatio {
    final width = _latest.width;
    final height = _latest.height;
    if (width == null || height == null || width <= 0 || height <= 0) {
      return null;
    }
    return width / height;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _stallTimer?.cancel();
    _stallTimer = null;
    _cancelHealthTimer();
    _currentLines = const [];
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    unawaited(_output.close());
    unawaited(_player.dispose());
  }
}
