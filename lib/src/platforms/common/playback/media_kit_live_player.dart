/// LivePlayer 的 media_kit 实现:封装 Player + VideoController,
/// 把 Player.stream.* 事件归一为 PlayerSnapshot;静音语义由本类维护
/// (media_kit 无独立 muted 事件流,以 volume=0 模拟并记忆原音量)。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart' show BoxFit, Color, Widget;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:live_parser/live_parser.dart' show StreamLine, UpstreamProxy;
import 'package:window_manager/window_manager.dart' show DragToResizeArea;

import 'live_player.dart';
import 'playback_log.dart';
import 'playback_retry.dart';
import 'player_error.dart';
import 'twitch_ad_filter.dart';
import 'window_presentation.dart';

class MediaKitLivePlayer implements LivePlayer, LineRecoveryAware {
  /// [player] 是单测注入点:VM 测试无法加载原生 libmpv(`Player()` 会构造
  /// `NativePlayer` 并 `DynamicLibrary.open`),只能注入 `Player(platformPlayer:)`
  /// 的假后端来驱动事件与命令。生产调用点一律不传,行为与原先完全一致。
  /// [adFilter] 同理:Twitch 广告过滤代理,生产用默认实例,测试可注入
  /// 定制判定/上游的实例。
  MediaKitLivePlayer({Player? player, TwitchAdFilter? adFilter})
    : _player = player ?? Player(),
      _adFilter = adFilter ?? TwitchAdFilter() {
    _wire();
    // 参照 pure_live 的直播卡顿根治:mpv 属性调优让断流/卡死的直播流
    // 主动报错而非无限缓冲,再由错误/看门狗路径重连。属性调优失败不阻断播放。
    unawaited(_applyLiveTuning());
  }

  final Player _player;

  /// Twitch HLS 广告过滤代理:ttvnw.net 的线路经它改写为本地过滤地址,
  /// 非 Twitch 线路原样透传(见 [TwitchAdFilter.wrapLine])。
  final TwitchAdFilter _adFilter;

  /// 广告期看门狗豁免的计时起点(本轮"合法无新段等待"开始时刻)。
  /// 开流/离房/按真断流处理时清零。
  DateTime? _adHoldSince;

  /// 广告期豁免策略:按住预算与复查间隔的唯一来源(可单测)。
  static const AdStallHoldPolicy _adHoldPolicy = AdStallHoldPolicy();
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

  /// 生命周期串行队列:open / stop / play / pause 依调用顺序逐条执行。
  ///
  /// 切房竞态(调用方 `unawaited(stop())` 与新房的 `unawaited(open(...))` 交错,
  /// 旧 stop 落到新 open 之后把新源卸载 → 黑屏/无声且日志无错)的根治。
  /// 队尾吞错:单步失败不得卡死后续生命周期调用(仿 pure_live 的 player_manager)。
  /// 窗口/PiP 调用不入队 —— 它们与媒体源无关,排队只会让窗口操作变迟钝。
  Future<void> _lifecycleQueue = Future.value();

  /// 源代际计数:每次 open / stop 同步自增;在途的旧 open 在下一个 await
  /// 回来后若代际已变即作废。与编排层 `PlayState.generation`(房间/画质场景
  /// 代际)无关,本字段只服务播放器内部「旧指令不得覆盖新指令」。
  int _sourceGeneration = 0;

  /// 事件围栏:open 在途期间屏蔽底层事件。
  ///
  /// 旧源的 `completed` / `error` 会在切源瞬间才吐出,放过去会污染新房状态
  /// (推高失败计数、覆写错误文案)。刻意按「open 在途窗口」而非媒体 path 做
  /// 门禁:path 门禁会误杀 mpv 播放列表内部自动跳到下一条线路时发出的事件。
  /// open 落地后由 [_resyncAfterOpen] 解除并补发真实状态。
  bool _eventsFenced = false;

  /// 放弃闩锁:自动重试 + 恢复重解析都耗尽后置位,此后不再自动重试
  /// (补 R3 缺陷:无终局标记时看门狗会持续空转)。只在 `open(resetRetries: true)`
  /// (用户主动重试/切源)时清除。
  bool _givenUp = false;

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

  /// 直播 mpv 属性调优表:构造期([_applyLiveTuning])按序逐条 setProperty,
  /// 对此后每一次 open/起播生效(playerProvider 是 app 单例,构造先于任何
  /// 开流;mpv 属性在 loadfile 前设置即约束该次会话)。抽成常量表是让配置
  /// 可被单测直接断言(VM 测试无法实例化 NativePlayer)。
  ///
  /// 缓冲上限的语义与取值依据(mpv 手册,DOCS/man/options.rst):
  /// - `cache-secs=60`:「How many seconds of audio/video to prefetch if the
  ///   cache is active … Setting this option is usually only useful for
  ///   limiting readahead」—— cache 激活(网络流默认激活)时以**秒**为单位的
  ///   前向预读上限;默认值极高(实际由字节顶兜底),显式设 60 即「回放缓冲
  ///   约 60s 封顶」,与 web 真源 hls.js `backBufferLength: 60`(SFVideoLive
  ///   commit 7515cff,默认无上限导致长时观看内存持续涨)对齐。它与
  ///   `demuxer-readahead-secs` 取较大者生效(设 60 覆盖 2s 只放宽数值,
  ///   真正封顶靠字节顶)。
  /// - `demuxer-max-bytes=33554432`(32 MiB):「This controls how much the
  ///   demuxer is allowed to buffer ahead … The demuxer will stop reading
  ///   additional packets as soon as one of the limits is reached」—— 前向
  ///   字节硬顶;高码率(≥4.5 Mbps)下先于 60s 到达,内存上限约 32 MiB。
  /// - `demuxer-max-back-bytes=4194304`(4 MiB):「This controls how much
  ///   past data the demuxer is allowed to preserve … there is no control how
  ///   many seconds are actually cached」—— 已播(回看)缓冲**只有字节上限、
  ///   无秒级控制**,故 60s 语义无法落在它上面;4 MiB 本就封顶(总缓存用量被
  ///   手册限定为前向+回退之和),比真源的 60s 回看余量更省内存,不放大。
  static const List<(String, String)> kLiveTuningProperties = [
    ('force-seekable', 'yes'),
    (
      'protocol_whitelist',
      'httpproxy,udp,rtp,tcp,tls,data,file,http,https,crypto,rtmp,rtmps,rtsp,srt',
    ),
    ('demuxer-lavf-probesize', '2097152'),
    ('demuxer-lavf-analyzeduration', '2'),
    ('network-timeout', '15'),
    ('hwdec-software-fallback', '1'),
    // video-sync=audio:直播以音频为同步基准(对齐 pure_live 的
    // media_kit_video/windows/video_output.cc),避免视频按显示时钟追帧
    // 造成的周期性小回退(观感为"回跳")。
    ('video-sync', 'audio'),
    ('volume-max', '100'),
    ('demuxer-max-bytes', '33554432'),
    ('demuxer-max-back-bytes', '4194304'),
    ('demuxer-readahead-secs', '2'),
    ('cache-secs', '60'),
  ];

  /// 恢复重解析的节流策略:避免"重试→恢复→重试"高速空转。
  static const PlaybackRecoveryPolicy _recoveryPolicy =
      PlaybackRecoveryPolicy();

  /// 宿主注入的恢复回调:自动重连耗尽时用它换一份**重新解析**的地址。
  /// 为 null 表示宿主不支持(如 fixture 源),此时直接走放弃分支。
  LineRecoveryHandler? _lineRecovery;

  /// 上次发起恢复的时刻,供 [_recoveryPolicy] 节流。离房/释放时重置。
  DateTime? _lastRecoverAt;

  /// 上一次已落日志的 mpv 原始诊断:mpv 对同一故障会反复吐同一条日志行,
  /// 不去重会把文件日志灌满同一条噪音。换房/主动开流时重置。
  String? _lastLoggedDiag;

  /// 日志里的线路主机名(判断「恢复拿到的地址是否真的换了源」的关键线索)。
  static String? _hostOf(StreamLine line) => Uri.tryParse(line.url)?.host;

  /// 超长诊断截断,防止单条 mpv 日志把文件撑爆。
  static String _clamp(String text) =>
      text.length > 160 ? '${text.substring(0, 160)}…' : text;

  @override
  void setLineRecovery(LineRecoveryHandler? handler) => _lineRecovery = handler;

  bool get _disposedOrEmpty => _disposed || _currentLines.isEmpty;

  /// 把 [task] 串到生命周期队尾执行。
  ///
  /// 返回值是**队尾**(已吞掉本次失败),而非原始 task 结果:调用点大多
  /// `unawaited(...)`,若让异常沿返回的 Future 逃逸会产生未处理异步异常。
  Future<void> _enqueueLifecycle(Future<void> Function() task) {
    final result = _lifecycleQueue.then<void>((_) => task());
    _lifecycleQueue = result.catchError((Object _) {});
    return _lifecycleQueue;
  }

  void _wire() {
    final events = _player.stream;
    void bind<T>(
      Stream<T> source,
      PlayerSnapshot Function(PlayerSnapshot, T) patch,
    ) {
      _subscriptions.add(
        source.listen((value) {
          // 围栏:open 在途期间的事件可能是旧源残留(completed/error),
          // 直接丢弃;open 落地后 [_resyncAfterOpen] 会补发真实状态。
          if (_eventsFenced) return;
          _emit((snapshot) => patch(snapshot, value));
        }),
      );
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
      // 原始诊断去重后落文件日志:release 环境下 mpv 日志没有别的出口,
      // 这是外部诊断「为什么反复中断」的第一手材料(含可自愈噪音)。
      if (v != _lastLoggedDiag) {
        _lastLoggedDiag = v;
        PlaybackLog.write('mpv_diag', {
          'terminal': classification.terminal,
          'kind': classification.kind.name,
          'diag': _clamp(v),
        });
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
      // 出帧即记:配合 reopen/recover 事件,日志里能直接量出每次中断到恢复的耗时。
      PlaybackLog.write('playing_ok', {'afterRetries': retries});
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
  /// 已闩锁放弃时也不再挂:自动重试已终结,挂上只会白跑一趟。
  void _armStallTimer() {
    if (_stallTimer != null || _givenUp) return;
    final backoff = _policy.backoffFor(_stallRetries);
    _stallTimer = Timer(backoff, _reopenIfStalled);
    PlaybackLog.write('stall_watchdog', {
      'armed': true,
      'backoffMs': backoff.inMilliseconds,
      'retries': _stallRetries,
    });
  }

  void _cancelHealthTimer() {
    _healthTimer?.cancel();
    _healthTimer = null;
  }

  /// open 落地后的收尾:解除围栏并补发一帧**真实**状态。
  ///
  /// 围栏在 open 在途期间会丢掉底层事件(含健康流在打开瞬间就发出的 playing),
  /// 若只解围栏不补发,UI 会停在「缓冲中」直到下一次状态变化 —— 可能几秒后,
  /// 也可能永远不来。这里直接读底层 state:先把真实态推给 UI,再据其恢复
  /// 看门狗 / 健康观察窗的记账。
  void _resyncAfterOpen() {
    final state = _player.state;
    final width = state.width;
    final height = state.height;
    _emit(
      (s) => s.copyWith(
        playing: state.playing,
        buffering: state.buffering,
        // 未出画面时 mpv 报 null/0,沿用旧宽高(PiP 小窗不该退回 16:9)。
        width: width != null && width > 0 ? width : null,
        height: height != null && height > 0 ? height : null,
      ),
    );
    if (state.playing) {
      _onPlaying();
    } else if (state.buffering) {
      _onBuffering(true);
    }
    // 看门狗重挂(补 R4 饥饿缺陷):open 开头撤掉看门狗后,若 mpv 重组播放
    // 列表不再发出 buffering 状态变化,自动重连会静默停摆。已挂则不覆盖(幂等)。
    if (!state.playing) _armStallTimer();
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
  ///
  /// **不立即重开**,走与缓冲看门狗同一退避入口(补 R8 缺陷:立即重开会对
  /// 已失效的整批地址高频空转,并把日志刷成每秒一条)。
  void _onCompleted() {
    if (_disposedOrEmpty) return;
    _armStallTimer();
  }

  /// 卡顿/错误/结束回调:把整组线路(首选 + 回退)作为 mpv 播放列表重新打开。
  /// 连续失败达上限时放弃自动重试,留错误快照(含对症建议)交还手动重连。
  /// 注意:此处走 [resetRetries]=false 的 open,避免清空正在累积的失败计数
  /// (否则"放弃"分支永远走不到)。计数只在健康观察窗走完后归零。
  void _reopenIfStalled() {
    if (_disposedOrEmpty || _givenUp) return;
    _stallTimer = null;
    // 广告剔除造成的"无新段"是预期内的合法等待:按住看门狗,不计失败、
    // 不重开(广告期 playlist 全被剔除,重开只会烧掉重连预算,且恢复
    // 重解析拿到的还是同一批广告地址)。预算封顶见 [AdStallHoldPolicy]。
    final now = DateTime.now();
    final adStalled = _adFilter.isAdStalled(_currentLines.first.url);
    if (_adHoldPolicy.shouldHold(
      adStalled: adStalled,
      now: now,
      holdSince: _adHoldSince,
    )) {
      _adHoldSince ??= now;
      PlaybackLog.write('ad_stall_hold', {
        'host': _hostOf(_currentLines.first),
      });
      _stallTimer = Timer(_adHoldPolicy.recheckInterval, _reopenIfStalled);
      return;
    }
    _adHoldSince = null;
    if (!_policy.canRetry(_stallRetries)) {
      // 自动重试耗尽:**先尝试向宿主重新解析**,而不是直接把错误卡片交出去。
      // 虎牙等签名平台的地址在连续失败期间多半已过期,继续复用 _currentLines
      // 就是"反复重开一个失效源" —— 恰是"流反复中断来尝试"的成因。
      unawaited(_recoverOrGiveUp());
      return;
    }
    _stallRetries++;
    PlaybackLog.write('reopen_requested', {
      'attempt': _stallRetries,
      'limit': _policy.maxAttempts,
      'lines': _currentLines.length,
      'host': _hostOf(_currentLines.first),
    });
    _cancelHealthTimer();
    unawaited(open(_currentLines.first, _currentLines.skip(1).toList(), false));
  }

  /// 自动重连耗尽后的最后一步:向宿主请求**重新解析**后的线路。
  ///
  /// 拿到新线路 → 重置失败计数重开(等于一次带新地址的全新会话);拿不到
  /// (宿主不支持 / 解析失败 / 尚在节流窗口内)→ 发出终局错误卡片交出控制权。
  /// 恢复失败仍要走终止路径:既不返回新地址又不报错会把用户悬在"缓冲中"。
  Future<void> _recoverOrGiveUp() async {
    final handler = _lineRecovery;
    final now = DateTime.now();
    final canAttempt =
        handler != null &&
        !_disposed &&
        _recoveryPolicy.canRecover(now: now, lastRecoverAt: _lastRecoverAt);
    if (canAttempt) {
      _lastRecoverAt = now;
      PlaybackLog.write('recover_request', {'lastKind': _lastErrorKind.name});
      List<StreamLine>? fresh;
      String? failReason;
      try {
        fresh = await handler();
      } catch (error) {
        // 解析异常按"拿不到新地址"处理,不吞掉下面的终止路径。
        failReason = 'error: ${_clamp('$error')}';
        fresh = null;
      }
      if (!_disposed && fresh != null && fresh.isNotEmpty) {
        PlaybackLog.write('recover_ok', {
          'lines': fresh.length,
          'host': _hostOf(fresh.first),
        });
        _stallRetries = 0;
        // resetRetries 保持默认 true:新地址开启新一轮有界重试。
        await open(fresh.first, fresh.skip(1).toList());
        return;
      }
      PlaybackLog.write('recover_fail', {
        'reason': failReason ?? 'empty_lines',
      });
    } else {
      PlaybackLog.write('recover_skip', {
        'reason': handler == null ? 'no_handler' : 'throttled_or_disposed',
      });
    }
    if (_disposed) return;
    // 放弃闩锁:置位后看门狗/终止错误/列表结束都不再触发重开(补 R3),
    // 只在 resetRetries 的 open(用户主动重试/切源)清除。
    _givenUp = true;
    PlaybackLog.write('give_up_latched', {'kind': _lastErrorKind.name});
    PlaybackLog.write('give_up', {'kind': _lastErrorKind.name});
    _emit(
      (s) => s.copyWith(
        buffering: false,
        error: _policy.giveUpMessage(_lastErrorKind),
        errorKind: _lastErrorKind,
      ),
    );
  }

  /// 参照 pure_live 的直播卡顿根治方案:直接给 mpv 设属性,而非只靠 Flutter
  /// 侧轮询。核心是把 demuxer 缓存设为有界低延迟(32MiB 前向 / 4MiB 回退 /
  /// 2s 预读,另加 `cache-secs=60` 秒级封顶,依据见 [kLiveTuningProperties]),
  /// 并把网络超时压到 15s——这样断流或卡死的直播流会主动抛 error
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
      for (final (name, value) in kLiveTuningProperties) {
        await platform.setProperty(name, value);
      }
      // 上游代理必须同步给 mpv:`mpv` 不读系统代理也不读 Dart 侧的
      // HttpClient.findProxy,被墙的 CDN(如 YouTube 的
      // manifest.googlevideo.com)会直接 `tcp: Connection failed`
      // (2026-09-21 真机故障)。代理是运行期值,故不进常量表。
      final proxy = UpstreamProxy.hostPort;
      if (proxy != null && proxy.isNotEmpty) {
        await platform.setProperty('http-proxy', 'http://$proxy');
      }
      // 缓存目录依赖运行期路径,无法进常量表;其余动态项在下方逐条设置。
      final cacheDir =
          '${Directory.systemTemp.path}${Platform.pathSeparator}zishu_demuxer_cache';
      await Directory(cacheDir).create(recursive: true);
      await platform.setProperty('demuxer-cache-dir', cacheDir);
      // 音频输出必须显式指定:mpv `ao=auto` 在部分 Windows 环境会退化成 null
      // (实测 AO: [null] → 完全无声,且 mpv 自身仍报 vol=100/muted=false)。
      if (Platform.isWindows) {
        await platform.setProperty('ao', 'wasapi,openal,null');
      }
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
  ]) {
    // 同步自增代际:后续任何 await 回来后若代际已变,说明有更新的 open/stop
    // 覆盖了本次指令,直接作废(不写快照、不动计时器)。
    final myGen = ++_sourceGeneration;
    return _enqueueLifecycle(() async {
      if (myGen != _sourceGeneration) {
        PlaybackLog.write('open_superseded', {
          'gen': myGen,
          'current': _sourceGeneration,
          'phase': 'queued',
        });
        return;
      }
      // 进入开流:屏蔽底层事件,直到本次 open 落地再补发真实状态。
      _eventsFenced = true;
      // 切源即重置快照:清错误、退出播放态,进入缓冲。
      // Twitch 线路经广告过滤代理改写为本地地址(其余平台原样透传),
      // 整组线路(首选 + 回退)按顺序拼成 mpv 播放列表:某条断流时 mpv
      // 内部自动跳下一条,耗尽后再由看门狗整体轮转。
      final baseLines = [line, ...fallbacks];
      final wrappedLines = <StreamLine>[];
      var wrappedAny = false;
      for (final item in baseLines) {
        final prepared = await _adFilter.wrapLine(item);
        if (!identical(prepared, item)) wrappedAny = true;
        wrappedLines.add(prepared);
      }
      _currentLines = wrappedLines;
      // 新会话从"无广告等待"开始记账。
      _adHoldSince = null;
      if (resetRetries) {
        _stallRetries = 0;
        // 用户主动重试/切源是唯一的闩锁解除点。
        _givenUp = false;
        // 新会话(进房/切线/换新地址)重置诊断去重:不同故障的同文案也该再记。
        _lastLoggedDiag = null;
        PlaybackLog.write('open', {
          'lines': _currentLines.length,
          'host': _hostOf(line),
        });
        if (wrappedAny) {
          PlaybackLog.write('ad_filter_wrap', {'lines': _currentLines.length});
        }
      }
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
        // 被更新的指令顶掉:连错误都不该写(否则旧源的异常会覆写新房文案)。
        if (myGen != _sourceGeneration) {
          PlaybackLog.write('open_superseded', {
            'gen': myGen,
            'current': _sourceGeneration,
            'phase': 'failed',
          });
          return;
        }
        // 原始异常(ArgumentError / PlatformException 等)不是 mpv 日志,直接展示
        // 对用户无意义;归类后给处置建议,归类不出则退到兜底文案。
        final classification = PlayerErrorClassifier.classify('$error');
        final kind = classification.isError
            ? classification.kind
            : PlayerErrorKind.native;
        _lastErrorKind = kind;
        _eventsFenced = false;
        _emit((s) => s.copyWith(error: playerErrorHint(kind), errorKind: kind));
        return;
      }
      // open 途中被更新的 open/stop 顶掉:作废,不写快照、不动计时器。
      if (myGen != _sourceGeneration) {
        PlaybackLog.write('open_superseded', {
          'gen': myGen,
          'current': _sourceGeneration,
          'phase': 'in_flight',
        });
        return;
      }
      if (_disposed) return;
      // 解围栏并补发真实状态(含看门狗重挂,见 [_resyncAfterOpen])。
      _eventsFenced = false;
      _resyncAfterOpen();
    });
  }

  @override
  Future<void> play() => _enqueueLifecycle(() async {
    await _player.play();
    // 用户口径(2026-09-20 播放/暂停判断错):UI 反馈不等底层 playing 事件
    // 回流 —— media-kit 暂停后不一定再吐 playing 事件,回流也可能被时序
    // 吞掉,控制条图标会停在旧态。主动发布快照;底层事件晚到时值相同,
    // 经 _emit 去重不抖动。
    _emit((snapshot) => snapshot.copyWith(playing: true));
  });

  @override
  Future<void> pause() => _enqueueLifecycle(() async {
    await _player.pause();
    _emit((snapshot) => snapshot.copyWith(playing: false));
  });

  @override
  Future<void> stop() {
    // 同步自增代际:作废在途的 open —— 离房后旧的 open 不得再把源挂上。
    _sourceGeneration++;
    return _enqueueLifecycle(() async {
      if (_disposed) return;
      // 若上一个被作废的 open 死在围栏里,这里负责解围栏。
      _eventsFenced = false;
      // 卸载媒体即终止自动重连(离房不应在后台空转重连)。
      if (_currentLines.isNotEmpty) {
        PlaybackLog.write('stop', {'retries': _stallRetries});
      }
      _stallTimer?.cancel();
      _stallTimer = null;
      _cancelHealthTimer();
      _currentLines = const [];
      // 离房即重置恢复节流与重试记账:下一次进房从干净状态开始,
      // 而不是继承上一间的窗口 / 已放弃闩锁(否则重进同一间永不自动重连)。
      _lastRecoverAt = null;
      _stallRetries = 0;
      _givenUp = false;
      _adHoldSince = null;
      _lastErrorKind = PlayerErrorKind.native;
      await _player.stop();
      // 卸载媒体后回到空闲快照:清播放/缓冲/错误,保留音量与静音语义。
      _emit((_) => PlayerSnapshot(volume: _latest.volume, muted: _muted));
    });
  }

  @override
  Future<void> setVolume(double volume) async {
    final clamped = volume.clamp(0, 100).toDouble();
    // 手动拉起音量即解除静音;静音状态下置 0 则维持静音语义。
    _muted = _muted && clamped <= 0;
    if (!_muted && clamped > 0) _volumeBeforeMute = clamped;
    await _player.setVolume(clamped);
    // 主动把目标音量归一进快照,不得单赌底层 volume 属性事件回流:
    // 切房开流窗口内回流会被事件围栏丢弃,open 落地后属性已幂等、mpv 不再
    // 补发,快照就会永远停在上一间房的音量(真机 BUG-WIN-VOLUME-002:
    // 全新房间的 slider 显示上一房调过的值而非默认 100)。底层回流晚到时
    // 与本值相同,经 _emit 去重不会抖动。
    _emit((snapshot) => snapshot.copyWith(volume: clamped, muted: _muted));
  }

  @override
  Future<void> setMuted(bool muted) async {
    if (muted == _muted) return;
    _muted = muted;
    if (muted) {
      if (_latest.volume > 0) _volumeBeforeMute = _latest.volume;
      await _player.setVolume(0);
      // 静音只翻 muted 位,不改 volume 字段:快照 volume 始终保存
      // 「用户感知音量基准」,UI 按 muted 位显示 0(见 player_controls)。
      _emit((snapshot) => snapshot.copyWith(muted: muted));
    } else {
      // 解除静音与 setVolume 同理:主动把恢复后的音量归一进快照,
      // 防止底层恢复回流丢失时 slider 停在静音的 0。
      final restored = _volumeBeforeMute <= 0 ? 100.0 : _volumeBeforeMute;
      await _player.setVolume(restored);
      _emit((snapshot) => snapshot.copyWith(volume: restored, muted: muted));
    }
  }

  @override
  Future<void> setFullscreen(bool fullscreen) =>
      _windowPresentation.setFullscreen(fullscreen);

  @override
  Future<void> toggleFullscreen() => _windowPresentation.toggleFullscreen();

  @override
  Future<void> enterPictureInPicture({double? aspectRatio}) =>
      _windowPresentation.enterPip(
        aspectRatio: aspectRatio ?? _videoAspectRatio,
      );

  @override
  Future<void> exitPictureInPicture() => _windowPresentation.exitPip();

  @override
  Widget wrapPipSurface(Widget child) {
    // 仅 Windows 需要桌面包壳;其余平台(含单测 VM 之外的非桌面宿主)透传。
    // `DragToResizeArea` 自身传递性依赖 dart:io,只允许出现在平台层。
    if (!Platform.isWindows) return child;
    return DragToResizeArea(
      resizeEdgeColor: const Color(0x00000000),
      child: child,
    );
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
    unawaited(_adFilter.dispose());
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    unawaited(_output.close());
    unawaited(_player.dispose());
  }
}
