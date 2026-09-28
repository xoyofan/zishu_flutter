/// LivePlayer 的 media_kit 实现:封装 Player + VideoController,
/// 把 Player.stream.* 事件归一为 PlayerSnapshot;静音语义由本类维护
/// (media_kit 无独立 muted 事件流,以 volume=0 模拟并记忆原音量)。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart'
    show
        AppLifecycleState,
        BoxFit,
        Color,
        Widget,
        WidgetsBinding,
        WidgetsBindingObserver;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:live_parser/live_parser.dart' show StreamLine, UpstreamProxy;
import 'package:window_manager/window_manager.dart'
    show DragToResizeArea, WindowListener, windowManager;

import 'buffering_stall_tracker.dart';
import 'live_player.dart';
import 'live_tuning_config.dart';
import 'playback_log.dart';
import 'playback_retry.dart';
import 'playback_resilience.dart';
import 'player_error.dart';
import 'twitch_ad_filter.dart';
import 'window_presentation.dart';

/// 是否需要「纹理首帧未上屏」自动 kick(BUG-WIN-VIDEO-001 候选)。
///
/// 判定的是**尺寸缺失型黑屏**:底层已宣称在播(playing)且不在缓冲,
/// 但视频宽高缺失或非法(null / <=0)—— 画面拿不到纹理尺寸,UI 只能黑屏,
/// 一次 pause/play 可让 mpv 重建输出、把首帧推上屏。
///
/// 抽成纯函数是为了可单测:武装(起计时)与到期复核必须走同一判定,
/// 二者语义漂移会让「武装了却复核不过」或反之的计时器空转。
/// [alreadyKicked] 为 true 时恒不 kick —— 一次 open 至多 kick 一次,
/// 禁止形成 pause/play 循环。
bool needsVideoKick({
  required bool playing,
  required bool buffering,
  required int? width,
  required int? height,
  required bool alreadyKicked,
}) {
  if (alreadyKicked) return false;
  if (!playing || buffering) return false;
  return width == null || width <= 0 || height == null || height <= 0;
}

class MediaKitLivePlayer
    with WidgetsBindingObserver
    implements
        LivePlayer,
        LineRecoveryAware,
        VideoHardwareAccelerationAware,
        RecoveryCancellable {
  /// [player] 是单测注入点:VM 测试无法加载原生 libmpv(`Player()` 会构造
  /// `NativePlayer` 并 `DynamicLibrary.open`),只能注入 `Player(platformPlayer:)`
  /// 的假后端来驱动事件与命令。生产调用点一律不传,行为与原先完全一致。
  /// [adFilter] 同理:Twitch 广告过滤代理,生产用默认实例,测试可注入
  /// 定制判定/上游的实例。
  MediaKitLivePlayer({
    Player? player,
    TwitchAdFilter? adFilter,
    this.videoHardwareAccelerationEnabled = true,
    PlaybackRetryPolicy policy = const PlaybackRetryPolicy(),
    PlaybackRecoveryPolicy recoveryPolicy = const PlaybackRecoveryPolicy(),
    PlaybackResiliencePolicy resiliencePolicy =
        const PlaybackResiliencePolicy(),
    this.stabilityInterval = const Duration(seconds: 5),
  }) : _player =
           player ??
           // logLevel 默认为 error:media_kit 只向 mpv 请求 error 级日志,
           // **warn 级(传输层 reconnect / hls 分段 404 / Connection reset 等
           // 自愈消息所在级别)根本不会发出**。提到 warn 让 stream.log 能
           // 观测到传输层自愈行为(见 [_wire] 的 mpv_log 落盘)。
           Player(
             configuration: const PlayerConfiguration(
               logLevel: MPVLogLevel.warn,
             ),
           ),
       _adFilter = adFilter ?? TwitchAdFilter() {
    _policy = policy;
    _recoveryPolicy = recoveryPolicy;
    _resiliencePolicy = resiliencePolicy;
    _wire();
    _windowListener = _WindowLifecycleListener(_logWindowEvent);
    _observeLifecycle();
    // 参照 pure_live 的直播卡顿根治:mpv 属性调优让断流/卡死的直播流
    // 主动报错而非无限缓冲,再由错误/看门狗路径重连。属性调优失败不阻断播放。
    unawaited(_applyLiveTuning());
  }

  final Player _player;
  bool videoHardwareAccelerationEnabled;

  /// 视频稳定性/噪音汇总的采样周期(生产 5s;测试注入更短值以便驱动 tick)。
  final Duration stabilityInterval;

  /// Twitch HLS 广告过滤代理:ttvnw.net 的线路经它改写为本地过滤地址,
  /// 非 Twitch 线路原样透传(见 [TwitchAdFilter.wrapLine])。
  final TwitchAdFilter _adFilter;

  /// 广告期看门狗豁免的计时起点(本轮"合法无新段等待"开始时刻)。
  /// 开流/离房/按真断流处理时清零。
  DateTime? _adHoldSince;

  /// 广告期豁免策略:按住预算与复查间隔的唯一来源(可单测)。
  static const AdStallHoldPolicy _adHoldPolicy = AdStallHoldPolicy();
  late final VideoController _videoController = VideoController(
    _player,
    configuration: VideoControllerConfiguration(
      hwdec: videoHardwareAccelerationEnabled ? 'auto-safe' : 'no',
    ),
  );

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

  /// 原生窗口事件转发器([WindowListener] 是普通 class,不能 `with`,用转发类
  /// 持有回调)。最小化/隐藏是「后端自暂停」首要嫌疑,事件落盘后可与
  /// `play_state source=external` 时间对齐。
  late final _WindowLifecycleListener _windowListener;

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

  /// 外部自暂停恢复计时器:mpv 因流 stall / paused-for-cache 自行 pause
  /// (`playing=false` 且 `source=external`)时挂起,到期仍 paused 则整组轮转重连。
  ///
  /// 与 [_stallTimer] **独立**:旧死锁根因是 buffering 看门狗被紧接着的
  /// `buffering=false` 取消(`stall_end ms=0`),而 `playing=false` 事件又无恢复
  /// 路径 → 永久卡 paused。此计时器不被 buffering 翻面取消,专门兜住"外部自暂停"
  /// 这一类;playing 一旦恢复([_onPlaying])即撤销。
  Timer? _externalPauseTimer;

  /// 卡顿时长记账:begin/end 配对输出每次 buffering 持续毫秒,落盘为
  /// `stall_begin` / `stall_end`。open/切源/离房/释放时重置,避免跨会话计时。
  final BufferingStallTracker _stallTracker = BufferingStallTracker();

  /// 「尺寸缺失型黑屏」复核计时:武装后 1.5s 到期,复核 [needsVideoKick]
  /// 仍成立才执行一次 pause/play(见 [_onVideoKickTimer])。
  /// open/stop/releaseNative/dispose 时 reset,不得跨会话。
  Timer? _videoKickTimer;

  /// 本次 open 是否已 kick 过:置位后不再武装(一次 open 至多一次)。
  /// open 时 reset。
  bool _videoKicked = false;

  /// 播放/暂停归因标记:底层 `playing` 事件变 false/true 时,区分是**本地指令**
  /// (play()/pause() 或视频 kick)触发的,还是**后端自暂停**(如窗口隐藏/最小化
  /// 时 mpv 自己停)。
  ///
  /// 2026-09-27 诊断背景:一次「房间仍开着、宽高齐全,却在播状态变 false 且
  /// 无 play_cmd 日志」的暂停,根因无法定位(全仓无 AppLifecycleState 监听,
  /// 也无窗口显隐监听)。加此埋点后,下次可直接从 `play_state source=` 判定是
  /// local(ui / video_kick)还是 external(后端/系统)。值随对应 playing 事件消费后清空。
  String? _pauseReason;
  String? _playReason;

  /// kick 观察窗:给 mpv 补报 video-params 留时间,避免把正常起播误踢。
  static const Duration _videoKickDelay = Duration(milliseconds: 1500);

  /// 健康观察窗:出帧后持续播满 [PlaybackRetryPolicy.healthWindow] 才把
  /// 连续失败计数归零。**这是"有限重试"能真正收敛的关键** —— 抖动的死流会
  /// 反复 `buffering true→false→true`,若在 false 就清零,计数永远涨不上去,
  /// 放弃分支不可达,退化为无限空转(旧实现的真实缺陷)。
  Timer? _healthTimer;

  /// 连续重开计数:健康窗口走完才归零,超过上限停止自动重试(交还手动重连)。
  int _stallRetries = 0;

  /// 本轮「连续健康播放」的起点:出帧时置位,中断(缓冲/重开/离房)时结算。
  /// 见 [_settleHealthyWindow]。
  DateTime? _playingSince;

  /// `_player.open` 发出的时刻;首个出帧事件时落盘 `open_to_first_frame`,
  /// 用于定位「打开慢」到底慢在 mpv 起播还是前序环节。
  DateTime? _openStartedAt;

  /// 最后一次**终局**错误的类别:用于自动重试耗尽后给出对症的处置建议。
  /// 刻意不存原始诊断文本 —— 那是 mpv 日志原文,其中大量条目是可自愈噪音。
  PlayerErrorKind _lastErrorKind = PlayerErrorKind.native;

  /// 有界重连策略(上限 / 退避 / 健康窗口的唯一来源)。
  late final PlaybackRetryPolicy _policy;

  /// 源级失败策略：首次确认源打不开即提前重新解析，不重放旧签名六次。
  late final PlaybackResiliencePolicy _resiliencePolicy;

  /// 当前会话连续确认的 source_open 终局错误数。
  int _sourceOpenFailures = 0;

  /// 单线路升级闩锁:**每个卡顿 episode 内至多升级 re-resolve 一次**。
  /// 防止"re-resolve 失败/节流 → 退化重开 → 又满足升级条件"形成高频空转;
  /// 升级失败后退化回同 URL 重开走完整退避阶梯,直到重试耗尽才真放弃。
  /// open(用户切源/重连)与健康出帧(_onPlaying)都会复位它,开启新 episode。
  bool _singleLineEscalated = false;

  /// 恢复(re-resolve)在途闩锁:终局诊断可能连续多条,mpv 对同一死源会反复
  /// 吐诊断,而 [_recoverOrGiveUp] 内部 await 期间失败计数仍在涨,不加闩锁
  /// 会并发发起多次 re-resolve/reopen。
  bool _recoverInFlight = false;

  /// 同一 URL 组的 host 健康状态。playlist 重开时优先使用未熔断 host；
  /// 即使全部熔断也保留候选，避免无线路可开。
  final CdnCircuitBreaker _cdnCircuitBreaker = CdnCircuitBreaker();

  /// 直播 mpv 属性调优表:**内置默认值**;构造期([_applyLiveTuning])先读
  /// 外部配置 `config/mpv_tuning.json` 逐键覆盖(见 live_tuning_config.dart),
  /// 再按序逐条 setProperty,对此后每一次 open/起播生效(playerProvider 是 app
  /// 单例,构造先于任何开流;mpv 属性在 loadfile 前设置即约束该次会话)。
  /// 抽成常量表是让默认配置可被单测直接断言(VM 测试无法实例化 NativePlayer)。
  ///
  /// 缓冲上限的语义与取值依据(mpv 手册,DOCS/man/options.rst):
  /// - `cache=yes` + `cache-secs=10`:网络流启用有界前向缓存,避免 HLS 短时
  ///   抖动直接把画面抽干;10s 是上限而非起播等待时间。历史:60s → 20s →
  ///   10s——CDN 假时间线(21214s)下缓存层朝目标无意义预读是内存爬升
  ///   (+200MB/10min)的主要推手;新窗口 8~12s 取 10s,与 readahead=10s
  ///   对齐(流缓存层与 demuxer 层预读目标一致,不叠加双层余量)。
  /// - `video-sync=audio`:直播以音频为同步基准,避免视频按显示时钟追帧造成
  ///   周期性小回退;配合 `framedrop=yes` 视频落后时丢帧保音频流畅。
  /// - `demuxer-thread=yes`:demuxer 独立线程读流,解码卡顿时 IO 不被阻塞
  ///   (mpv 默认即 yes,此处显式固化防止平台差异回退)。
  /// - `demuxer-max-bytes=134217728`(128 MiB) / `demuxer-max-back-bytes=8388608`
  ///   (8 MiB):前向与回看均有字节上限,不恢复后续被删除的主机深缓冲分档。
  ///   前向 128MiB 配合 `demuxer-readahead-secs=10`:预读秒数才是实际封顶项
  ///   (实测 2s 预读时 demuxer_cache_duration 恒≈2.3s,字节上限够不着),
  static const List<(String, String)> kLiveTuningProperties = [
    ('force-seekable', 'yes'),
    (
      'protocol_whitelist',
      'httpproxy,udp,rtp,tcp,tls,data,file,http,https,crypto,rtmp,rtmps,rtsp,srt',
    ),
    ('demuxer-lavf-probesize', '2097152'),
    ('demuxer-lavf-analyzeduration', '2'),
    ('network-timeout', '15'),
    // mpv 默认 hwdec=no → Windows Release 播放整机 CPU 约 42%(24 核)、
    // 暂停后 1.7%,确认为软件解码。auto-safe 优先走 d3d11va 硬解,失败时
    // 由下方 hwdec-software-fallback 回退软解,两者成对存在。
    ('hwdec', 'auto-safe'),
    ('hwdec-software-fallback', '1'),
    // 直播以音频为同步基准,恢复 b6be087 的稳定配置。
    ('video-sync', 'audio'),
    ('volume-max', '100'),
    ('cache', 'yes'),
    // 缓存抽干加厚沿袭(实测 demuxer_cache_duration 曾被 readahead-secs=2
    // 封顶,任何 >2s 网络抖动即抽干触发卡顿重连)。前向字节上限提到 128MiB:
    // 1080p@6Mbps≈0.75MiB/s,10s 预读仅 ≈7.5MiB,字节上限远够不着,纯粹是
    // 高码率/多倍率流的兜底预算;实际封顶项仍是下方 readahead-secs。
    ('demuxer-max-bytes', '134217728'),
    // 回看缓冲 8MiB:直播贴实时边沿,回看窗口仅作 seek 抖动余量,
    // 上限有界防止坏流回灌数据无限滞留。
    ('demuxer-max-back-bytes', '8388608'),
    // 预读秒数是前向缓冲的实际封顶项(字节上限够不着)。对齐斗鱼官方 web
    // 播放器缓冲窗口(2026-09-28 实测 getH5PlayV1 p2pMeta:max_play_buffer_ms
    // =6000/best=5000,超窗 1.05x 追帧):窗口取 6s。此前 10s 比官方深 4s,
    // 断流发现晚、追回实时边沿也慢;URL 预刷新上线后不再依赖深缓冲硬撑过期
    // token,窗口回落官方口径。
    ('demuxer-readahead-secs', '6'),
    // cache-secs 是流缓存层的预读目标,直播假时间线下该层朝目标无界预读
    // (实测 +200MB/10min),重放型坏流的重复数据也滞留在窗口里。与
    // readahead=6s 对齐,不叠加双层预读余量。
    ('cache-secs', '6'),
    // demuxer 独立线程:解码/渲染卡顿时网络读流不被阻塞(mpv 默认 yes,
    // 显式固化防平台默认值差异)。
    ('demuxer-thread', 'yes'),
    // 视频落后时丢帧(yes):直播卡顿时保音频连续,画面追帧而不是整流
    // 停顿。与 video-sync=audio 成对生效。
    ('framedrop', 'yes'),
    // mpv 默认 cache-pause=yes:demuxer 缓存抽干(demuxer_cache_duration→0)时
    // **自动置 pause=yes**——这是"播放无故自暂停"的 origin(2026-09-27 实测
    // playback.log 16:33:14:playing=false source=external,无 play_cmd,缓存
    // 恰好归零)。直播下该行为有害:缓存一旦断供(源卡死/边沿推进),pause
    // 可能永远不恢复。关掉后 mpv 不再自暂停,断流走 buffering 事件 + 看门狗
    // 重连的外部自暂停恢复计时器兜底,卡死收敛为可观测的重连。
    ('cache-pause', 'no'),
    // 2026-09-27 晚间对齐 pure_live:**刻意不设 stream-lavf-o reconnect**。
    // 传输层透明重连会对卡死连接原地无限重试——日志里 "Will reconnect at
    // <offset>" 的偏移不前进、重发旧数据把 FLV 时间戳打回跳,即用户看到的
    // "重复播放"循环。pure_live 不开这层:坏流让 ffmpeg 立即报错上抛,由
    // 上层**有界**看门狗(退避 + 上限 + 健康窗)收敛,坏连接绝不赖在原地。
  ];

  /// 恢复重解析的节流策略:避免"重试→恢复→重试"高速空转。
  late final PlaybackRecoveryPolicy _recoveryPolicy;

  /// 宿主注入的恢复回调:自动重连耗尽时用它换一份**重新解析**的地址。
  /// 为 null 表示宿主不支持(如 fixture 源),此时直接走放弃分支。
  LineRecoveryHandler? _lineRecovery;

  /// 上次发起恢复的时刻,供 [_recoveryPolicy] 节流。离房/释放时重置。
  DateTime? _lastRecoverAt;

  /// 上一次已落日志的 mpv 原始诊断:mpv 对同一故障会反复吐同一条日志行,
  /// 不去重会把文件日志灌满同一条噪音。换房/主动开流时重置。
  String? _lastLoggedDiag;

  /// mpv warn 日志的按型抑制表(归一化 key → 已抑制条数)与各型首条原文:
  /// media_kit 的 stream.log 自带严格相等 distinct,但 CDN 抖动行内嵌变化的
  /// byte offset("Will reconnect at 701644...")永不相等,逐字去重拦不住。
  /// 这里把数字归一为 `#` 后按型比对:每种型只落第一条原文,其余计数抑制,
  /// 换型/5s 稳定性采样/open 重置时补 `mpv_log_suppressed` 汇总。
  ///
  /// 2026-09-27 19:41 实测教训:不能用"单一 last key"——cplayer 的
  /// Invalid video timestamp 与 ad 的 Invalid audio PTS **交替刷屏**,单键
  /// 每次换型都把上一型当"已汇总"、把新型当"首条原文",A/B 轮替下全部
  /// 落盘。必须每型独立计数槽。
  final Map<String, int> _warnCounts = {};

  /// 各抑制型的首条原文(prefix, text),供汇总落盘还原现场。
  final Map<String, (String, String)> _warnShapes = {};

  /// 抑制表容量上限:归一化后的型数量理论有界(故障文案就那几类),
  /// 但仍封顶防御异常源吐海量不同型行撑爆内存。超限后新型静默丢弃。
  static const int _warnShapeCap = 128;
  VideoParams? _lastVideoParams;

  /// 本代源是否已收到有效视频参数(width>0)。open 时随 [_lastVideoParams] 复位。
  bool _videoParamsSeen = false;

  /// 死开流看门狗:open 后 mpv 起播但 [PlaybackRetryPolicy.deadOpenGrace] 内
  /// 无有效视频参数 → 同线路重开(黑屏 2 分钟无人管的根因修复)。
  Timer? _deadOpenTimer;

  /// 死开流重开计数(独立于 [_stallRetries]:症状不同——卡顿是"播着断了",
  /// 死开流是"连上却永远不出画面")。有效参数一到即清零。
  int _deadOpenRetries = 0;

  Timer? _videoStabilityTimer;
  int? _firstFrameWatchGeneration;

  /// 日志里的线路主机名(判断「恢复拿到的地址是否真的换了源」的关键线索)。
  static String? _hostOf(StreamLine line) => Uri.tryParse(line.url)?.host;

  /// 当前首条线路的 host:`stall_begin` / `stall_end` 的归属源。
  String? get _currentHost =>
      _currentLines.isEmpty ? null : _hostOf(_currentLines.first);

  /// 超长诊断截断,防止单条 mpv 日志把文件撑爆。
  static String _clamp(String text) =>
      text.length > 160 ? '${text.substring(0, 160)}…' : text;

  /// warn 日志噪音归一:数字序列替换为 `#` 后转小写。
  ///
  /// 传输层重连行内嵌持续变化的 byte offset/秒数("Will reconnect at
  /// 701644 in 0 second(s)"),逐字比对永不相等;归一后同型行折叠为一条。
  /// 首条原文仍全量落盘,归一只影响抑制判定,不丢信息。
  static String _normalizeLogText(String text) =>
      text.toLowerCase().replaceAll(RegExp(r'\d+'), '#');

  /// 落盘所有已抑制型别的汇总(新型出现 / open 重置 / 5s 稳定性采样时调用)。
  ///
  /// 每型独立计数:某型 5s 窗口内达到 [_transportFlapThreshold](≥50 条,即
  /// 传输层重连风暴)时追加一条 `transport_flap`:CDN 节点对本机连接持续
  /// reset、mpv ffmpeg 层 0 间隔重连的成功-被断循环(实测 2026-09-27 19:16
  /// hwa.douyucdn2.cn)。流本身仍在自愈供数,故只落观测事件不触发重开;
  /// 排查时按该事件名一击定位,不必翻几百行噪音。
  ///
  /// 时间戳混沌型(invalid video/audio timestamp、playback reset)合计达到
  /// [_decodeFlapThreshold] 时追加 `decode_flap`:CDN 数据涓流把 FLV 时间戳
  /// 打乱、mpv 反复 "Reset playback due to audio timestamp reset"(实测
  /// 2026-09-27 19:55-19:56 同节点 38s 内重置 5 次,肉眼即连续卡顿)。
  /// 流 technically 在播、看门狗不触发,此前对这种劣化完全失明——先落观测
  /// 事件量化,是否升级为自动换线待数据说话。
  ///
  /// 汇总只清计数、不清型表:型一旦见过,后续同型行永远只计数不再落原文,
  /// 否则 A/B 轮替噪音会借"换型"反复重打原文(单键版的实际翻车点)。
  void _flushWarnSuppression() {
    _settleDecodeChaosWindow();
    if (_warnCounts.isEmpty) return;
    for (final key in _warnCounts.keys.toList(growable: false)) {
      final count = _warnCounts[key]!;
      if (count == 0) continue;
      _warnCounts[key] = 0;
      final shape = _warnShapes[key];
      if (shape == null) continue;
      PlaybackLog.write('mpv_log_suppressed', {
        'prefix': shape.$1,
        'text': _clamp(shape.$2),
        'count': count,
      });
      if (count >= _transportFlapThreshold) {
        PlaybackLog.write('transport_flap', {
          'host': _currentHost,
          'count': count,
          'text': _clamp(shape.$2),
        });
      }
    }
  }

  /// 时间戳混沌累计计数器(逐行累加,达阈值结算后清零开新窗):
  /// 不搭车在 flush 的 per-型计数里算——那些计数每次 flush 都清零,新型出现
  /// 会把窗口切碎,cplayer/ad/reset 三型轮替下每段只剩零头,阈值永远凑不齐。
  /// 这里跨 flush 累计;flush 至少每 5s 一次(tick 兜底),检测延迟 ≤5s。
  int _decodeChaosCount = 0;

  /// 时间戳混沌型判定(归一化 key,已小写):PTS 回跳/重置类 warn。
  static bool _isDecodeChaosKey(String key) =>
      key.contains('invalid video timestamp') ||
      key.contains('invalid audio pts') ||
      key.contains('timestamp reset');

  /// 5s 汇总窗口内同型 warn 条数达到该值即视为传输层重连风暴。
  static const int _transportFlapThreshold = 50;

  /// 时间戳混沌行累计达到该值即视为解码级劣化。
  ///
  /// 实测校准(2026-09-27 19:55 用户可感知卡顿档):cplayer+ad 合计约 5 条/5s,
  /// 一次 playback reset 独立计入。取 12(约 2.5 倍)只标记"明显更糟"的风暴,
  /// 避免常规抖动刷事件。
  static const int _decodeFlapThreshold = 12;

  /// 上一次播放时钟采样(time-pos):直播播放位置应单调推进,回跳即
  /// "重复播放"的直接信号(mpv Reset playback / 上游重发旧数据)。
  double? _lastStabilityTimePos;

  /// 采样间 time-pos 回跳超过该秒数即视为内容重放(纯**观测**阈值)。
  ///
  /// 正常直播在 [stabilityInterval](5s)窗口内 time-pos 推进约 5s;播放
  /// 时钟由解码 PTS 驱动,>2s 的回跳不可能来自网络抖动,只有时间戳重置
  /// 后上游重发旧数据(重放)才会造成。
  static const double _timePosRegressionThreshold = 2.0;

  /// 结算混沌窗口:累计达阈值落 `decode_flap` **观测事件**并清零开新窗。
  ///
  /// 2026-09-27 晚间对齐 pure_live:自动重试类操作全部下线,解码混沌只
  /// 观测不重开——坏流收敛交给 mpv 主动报错 + 有界看门狗(退避 + 上限 +
  /// 健康窗);该事件仅用于事后归因("这段时间画面为什么烂")。
  void _settleDecodeChaosWindow() {
    final count = _decodeChaosCount;
    if (count < _decodeFlapThreshold) return;
    _decodeChaosCount = 0;
    PlaybackLog.write('decode_flap', {'host': _currentHost, 'count': count});
  }

  /// 死开流看门狗到期:mpv 自称在播却始终没有有效视频参数(黑屏),
  /// 同线路重开;重试预算耗尽则升级 re-resolve。gen 归属校验防旧代计时器
  /// 打新代;用户主动暂停(playing=false)归 stall/外部暂停看门狗管辖,不抢。
  void _onDeadOpenTimeout(int gen) {
    _deadOpenTimer = null;
    if (_disposed || gen != _sourceGeneration || _givenUp) return;
    final p = _lastVideoParams;
    if ((p?.dw ?? p?.w ?? _player.state.width ?? 0) > 0) return;
    if (!_player.state.playing) return;
    if (!_policy.canRetry(_deadOpenRetries)) {
      PlaybackLog.write('dead_open_recover', {'retries': _deadOpenRetries});
      unawaited(_recoverOrGiveUp());
      return;
    }
    _deadOpenRetries++;
    PlaybackLog.write('dead_open_reopen', {
      'attempt': _deadOpenRetries,
      'gen': gen,
      'host': _hostOf(_currentLines.first),
    });
    _emit((s) => s.copyWith(notice: PlaybackNotice.reconnecting));
    unawaited(open(_currentLines.first, _currentLines.skip(1).toList(), false));
  }

  @override
  void setLineRecovery(LineRecoveryHandler? handler) => _lineRecovery = handler;

  @override
  void setVideoHardwareAcceleration(bool enabled) {
    videoHardwareAccelerationEnabled = enabled;
    final platform = _player.platform;
    if (platform is! NativePlayer || _disposed) return;
    unawaited(_applyHardwareAcceleration(platform, enabled));
  }

  Future<void> _applyHardwareAcceleration(
    NativePlayer platform,
    bool enabled,
  ) async {
    try {
      await platform.setProperty('hwdec', enabled ? 'auto-safe' : 'no');
      PlaybackLog.write('video_hwdec', {'enabled': enabled});
    } catch (error) {
      PlaybackLog.write('video_hwdec_error', {'error': error});
    }
  }

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
    _subscriptions.add(
      _player.stream.videoParams
          .map<void>((value) {
            if (!_eventsFenced) _logVideoParams(value);
          })
          .listen((_) {}),
    );
    // mpv warn 级日志落盘(2026-09-27):PlayerConfiguration.logLevel 提到 warn
    // 后,stream.log 会送来传输层自愈的第一手证据——stream-lavf-o 的
    // "Connection reset by peer, retrying..."、HLS 分段 404、demuxer 异常等。
    // error 级仍走 events.error → mpv_diag(含分类),这里只落 warn,避免重复。
    // 连续重复去重(同 prefix+text),防同一瞬断反复重连把日志刷成噪音。
    _subscriptions.add(
      _player.stream.log.listen((entry) {
        if (entry.level != 'warn') return;
        final key = '${entry.prefix}|${_normalizeLogText(entry.text)}';
        // 混沌窗口逐行累加(含各型首条),只在 5s tick 结算——不搭车
        // _flushWarnSuppression,否则新型 flush 会把窗口切碎。
        if (_isDecodeChaosKey(key)) _decodeChaosCount++;
        final known = _warnCounts[key];
        if (known != null) {
          // 已见过的型(仅数字不同的重连行等):计数抑制,不落盘。
          _warnCounts[key] = known + 1;
          return;
        }
        if (_warnCounts.length >= _warnShapeCap) {
          // 防御:异常源吐海量不同型行时静默丢弃,不落盘也不撑表。
          return;
        }
        // 新型:先汇总既有各型的抑制量,再落本型首条原文。
        _flushWarnSuppression();
        _warnCounts[key] = 0;
        _warnShapes[key] = (entry.prefix, entry.text);
        PlaybackLog.write('mpv_log', {
          'prefix': entry.prefix,
          'text': _clamp(entry.text),
        });
      }),
    );
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
          // playing/buffering/宽高任一变化都重估 kick:尺寸迟到要撤销计时,
          // 尺寸缺失且在播要武装。读底层 _player.state(事件先落 state 再
          // 发出),不依赖快照去重;围栏期间 bind 直接返回,resync 补评估。
          _syncVideoKick();
        }),
      );
    }

    bind(events.playing, (s, v) {
      // 归因:本次 playing 翻转由本地指令还是后端自暂停触发(见 [_pauseReason])。
      final reason = v ? _playReason : _pauseReason;
      final source = reason == null ? 'external' : 'local:$reason';
      if (v) {
        _playReason = null;
      } else {
        _pauseReason = null;
        // 外部自暂停(mpv 因流 stall / paused-for-cache 自行 pause,非 UI / 视频
        // kick 触发):旧实现无恢复路径 → 死锁卡在 paused。挂独立恢复计时器
        // (不被 buffering 翻面取消),到期仍 paused 则整组轮转重连。
        if (reason == null) _scheduleExternalPauseRecovery();
      }
      final appState = _appLifecycleName();
      final fields = <String, Object?>{
        'playing': v,
        'source': source,
        'buffering': _latest.buffering,
        'width': _latest.width,
        'height': _latest.height,
      };
      if (appState != null) fields['app_state'] = appState;
      PlaybackLog.write('play_state', fields);
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
      if (classification.kind == PlayerErrorKind.source &&
          classification.code == 'source_open') {
        _sourceOpenFailures++;
        final failedHost = _currentLines.isEmpty
            ? null
            : _hostOf(_currentLines.first);
        if (failedHost != null) {
          _cdnCircuitBreaker.recordFailure(failedHost, DateTime.now());
        }
        PlaybackLog.write('source_open_failure', {
          'count': _sourceOpenFailures,
          'host': failedHost,
        });
        if (_resiliencePolicy.shouldRecoverSource(
          consecutiveSourceOpenFailures: _sourceOpenFailures,
        )) {
          // 首次终局 source_open 失败即升级 re-resolve,不再等下一轮退避重开:
          // 签名 URL 失效后重开必然再失败,盲重试只烧退避预算(2026-09-27
          // 18:23 虎牙事故:同一 wsSecret 重试 4 次白烧 39s,recover 613ms 出帧)。
          // 节流仍由 [_recoveryPolicy.minInterval] 把关,不会高频空转。
          _stallTimer?.cancel();
          _stallTimer = null;
          _externalPauseTimer?.cancel();
          _externalPauseTimer = null;
          PlaybackLog.write('recover_early', {
            'reason': 'source_open',
            'failures': _sourceOpenFailures,
            'host': failedHost,
            'trigger': 'immediate',
          });
          unawaited(_recoverOrGiveUp());
        }
      }
      _onTerminalError(classification);
      return s.copyWith(
        error: playerErrorHint(classification.kind),
        errorKind: classification.kind,
        notice:
            classification.kind == PlayerErrorKind.source &&
                classification.code == 'source_open'
            ? PlaybackNotice.sourceOpenFailed
            : s.notice,
      );
    });
  }

  /// 缓冲态切换:进入缓冲即起看门狗;退出缓冲仅撤销看门狗。
  ///
  /// **退出缓冲不清零失败计数**(旧实现清了,是收敛缺陷):直播流的 buffering
  /// 标志在死流上也会短暂回落再拉起,清零会让计数永远追不上"放弃"上限。
  /// 计数只由 [PlaybackRetryPolicy.healthWindow] 观察窗确认健康后归零。
  ///
  /// 卡顿埋点与看门狗解耦:[_stallTracker] 记真→假转换的持续时长
  /// (重复 true 不重置、孤立 false 忽略),只在新 begin / 已结算 end 落盘
  /// `stall_begin` / `stall_end`,供事后统计缓冲频率与每次卡顿的 ms。
  void _onBuffering(bool buffering) {
    if (buffering) {
      // 进入缓冲先结算健康窗(已播满观察窗就归零),再起看门狗。
      _settleHealthyWindow(reason: 'buffering_interrupt');
      if (_latest.notice == PlaybackNotice.none) {
        _emit((s) => s.copyWith(notice: PlaybackNotice.networkJitter));
      }
      _armStallTimer();
      if (_stallTracker.begin()) {
        PlaybackLog.write('stall_begin', {'host': _currentHost});
      }
    } else {
      _stallTimer?.cancel();
      _stallTimer = null;
      final stallMs = _stallTracker.end();
      if (stallMs != null) {
        PlaybackLog.write('stall_end', {'ms': stallMs, 'host': _currentHost});
      }
    }
  }

  /// 外部自暂停(`playing=false` 且 `source=external`)的恢复计时器。
  ///
  /// mpv 因流 stall / paused-for-cache 自行 pause 时,Dart 层没有对应的
  /// `play()` 指令,而缓冲看门狗又被紧接着的 `buffering=false` 取消
  /// (`stall_end ms=0`)→ 永久卡在 paused(见 playback.log 16:33:14 死锁)。
  /// 这里挂一个**独立**计时器(不被 buffering 翻面取消),到期读底层 state:
  /// 已自行恢复则只补快照,仍 paused 则走 [_reopenIfStalled] 整组轮转重连。
  /// 退避沿用 [_policy] 同一档(首连 8s),与卡顿看门狗口径一致。
  void _scheduleExternalPauseRecovery() {
    if (_disposedOrEmpty || _givenUp) return;
    _externalPauseTimer?.cancel();
    final backoff = _policy.backoffForWithLines(_stallRetries, _currentLines.length);
    _externalPauseTimer = Timer(backoff, () {
      _externalPauseTimer = null;
      if (_disposedOrEmpty || _givenUp) return;
      final state = _player.state;
      if (state.playing) {
        _resyncAfterOpen();
        return;
      }
      PlaybackLog.write('external_pause_recover', {
        'host': _currentHost,
        'retries': _stallRetries,
      });
      _reopenIfStalled();
    });
    PlaybackLog.write('external_pause_watchdog', {
      'armed': true,
      'backoffMs': backoff.inMilliseconds,
      'retries': _stallRetries,
    });
  }

  /// 出帧开始播放:撤看门狗、清残留错误文案(自动切到下一条线路后 mpv 未必
  /// 主动清空 error 属性),并启动健康观察窗 —— 只有持续播满观察窗才把连续
  /// 失败计数归零,避免"短暂出帧即视为康复"导致重试上限形同虚设。
  void _onPlaying() {
    _stallTimer?.cancel();
    _stallTimer = null;
    _externalPauseTimer?.cancel();
    _externalPauseTimer = null;
    // 健康出帧:单线路升级 episode 结转(新健康播放周期允许再次升级)。
    _singleLineEscalated = false;
    _startVideoStabilitySampling();
    _emit((s) => s.copyWith(error: null, notice: PlaybackNotice.none));
    final retries = _stallRetries;
    // 健康播放起点:重复的 playing 事件不重置,免得连续抖动永远凑不满观察窗。
    _playingSince ??= DateTime.now();
    final openedAt = _openStartedAt;
    if (openedAt != null) {
      _openStartedAt = null;
      PlaybackLog.write('open_to_first_frame', {
        'ms': DateTime.now().difference(openedAt).inMilliseconds,
        'host': _currentLines.isEmpty ? null : _hostOf(_currentLines.first),
      });
    }
    if (retries > 0) {
      // 出帧即记:配合 reopen/recover 事件,日志里能直接量出每次中断到恢复的耗时。
      PlaybackLog.write('playing_ok', {'afterRetries': retries});
      _healthTimer?.cancel();
      _healthTimer = Timer(_policy.healthWindow, () {
        if (_disposed) return;
        _settleHealthyWindow(reason: 'window_elapsed');
      });
    }
  }

  void _logVideoParams(VideoParams value) {
    final valid = (value.dw ?? value.w ?? 0) > 0;
    if (valid && !_videoParamsSeen) {
      _videoParamsSeen = true;
      _deadOpenTimer?.cancel();
      _deadOpenTimer = null;
      if (_deadOpenRetries > 0) {
        _deadOpenRetries = 0;
        PlaybackLog.write('dead_open_resolved', {'host': _currentHost});
      }
    }
    if (_lastVideoParams == value) return;
    _lastVideoParams = value;
    PlaybackLog.write('video_params', {
      'width': value.dw ?? value.w,
      'height': value.dh ?? value.h,
      'pixelformat': value.pixelformat,
      'hw_pixelformat': value.hwPixelformat,
    });
  }

  void _startVideoStabilitySampling() {
    _videoStabilityTimer?.cancel();
    final generation = _sourceGeneration;
    final platform = _player.platform;
    final native = platform is NativePlayer ? platform : null;
    // 计时器无条件启动:除稳定性快照外,它还承担 warn 噪音汇总与解码混沌
    // 的观测结算(测试 fake 不是 NativePlayer,但观测路径必须可被驱动)。
    if (native != null) unawaited(_logVideoStability(native, generation));
    _videoStabilityTimer = Timer.periodic(stabilityInterval, (_) {
      // 每 5s 先落被抑制的 warn 噪音汇总:持续刷屏型故障(传输层重连风暴)
      // 的汇总行不必等"换型"才出现,汇总窗口封顶 5s。
      _flushWarnSuppression();
      if (native != null) unawaited(_logVideoStability(native, generation));
      // 播放时钟采样对任意平台执行:回跳观测(fake 平台也要能驱动测试)
      // 依赖它;不支持的实现 getProperty 抛错即静默跳过。
      unawaited(_samplePlaybackClock(generation));
      // 解码混沌观测窗口结算(纯观测,不触发任何自动重开)。
      _settleDecodeChaosWindow();
    });
  }

  /// 播放时钟采样:直播位置应单调推进,回跳即"重复播放"直接信号。
  ///
  /// PlatformPlayer 未声明 getProperty(NativePlayer 独有),走动态分发:
  /// 生产为 NativePlayer 正常取值,测试 fake 有自己的实现;两者都不支持
  /// 时抛错被吞,采样静默降级为 no-op,不影响其余看门狗。
  Future<void> _samplePlaybackClock(int generation) async {
    if (_disposed || generation != _sourceGeneration) return;
    double? timePos;
    try {
      final raw = await (_player.platform as dynamic).getProperty('time-pos');
      timePos = double.tryParse('$raw');
    } catch (_) {
      return;
    }
    _onPlaybackClockSample(timePos);
  }

  /// 消费一次时钟采样:维护基线并判定回跳。基线无条件更新(暂停时
  /// time-pos 冻结也不影响下次恢复后的差值判定——恢复推进只会更大)。
  ///
  /// 回跳 = 内容在重复播放(上游重发旧数据)。2026-09-27 晚间对齐 pure_live:
  /// 只落 `time_pos_regression` **观测事件**,不做自动重开——重开属于重试类
  /// 自动操作;坏流收敛交给 mpv 主动报错 + 有界看门狗。
  void _onPlaybackClockSample(double? timePos) {
    if (timePos == null) return;
    final last = _lastStabilityTimePos;
    _lastStabilityTimePos = timePos;
    if (last == null) return;
    if (timePos >= last - _timePosRegressionThreshold) return;
    PlaybackLog.write('time_pos_regression', {
      'host': _currentHost,
      'from': last,
      'to': timePos,
    });
  }

  Future<void> _logVideoStability(NativePlayer platform, int generation) async {
    if (_disposed || generation != _sourceGeneration) return;
    try {
      final values = await Future.wait([
        platform.getProperty('paused-for-cache'),
        platform.getProperty('cache-buffering-state'),
        platform.getProperty('demuxer-cache-duration'),
        platform.getProperty('demuxer-cache-time'),
        platform.getProperty('decoder-frame-drop-count'),
        platform.getProperty('frame-drop-count'),
        platform.getProperty('vo-drop-frame-count'),
        platform.getProperty('mistimed-frame-count'),
        platform.getProperty('vo-delayed-frame-count'),
        platform.getProperty('video-codec'),
        platform.getProperty('hwdec-current'),
      ]);
      if (_disposed || generation != _sourceGeneration) return;
      PlaybackLog.write('video_stability', {
        'host': _currentHost,
        'paused_for_cache': values[0],
        'cache_buffering_state': values[1],
        'demuxer_cache_duration': values[2],
        'demuxer_cache_time': values[3],
        'decoder_frame_drops': values[4],
        'frame_drops': values[5],
        'vo_frame_drops': values[6],
        'mistimed_frames': values[7],
        'vo_delayed_frames': values[8],
        'video_codec': values[9],
        'hwdec_current': values[10],
        'rss_mb': (ProcessInfo.currentRss / 1024 / 1024).toStringAsFixed(1),
      });
    } catch (error) {
      PlaybackLog.write('video_stability_error', {'error': error});
    }
  }

  void _watchFirstFrame() {
    final generation = _sourceGeneration;
    if (_firstFrameWatchGeneration == generation) return;
    _firstFrameWatchGeneration = generation;
    unawaited(() async {
      try {
        await _videoController.waitUntilFirstFrameRendered.timeout(
          const Duration(seconds: 3),
        );
        if (!_disposed && generation == _sourceGeneration) {
          PlaybackLog.write('video_first_frame_rendered', {
            'generation': generation,
            'host': _currentHost,
          });
        }
      } catch (error) {
        if (!_disposed && generation == _sourceGeneration) {
          PlaybackLog.write('video_first_frame_timeout', {
            'generation': generation,
            'host': _currentHost,
            'error': error,
          });
        }
      }
    }());
  }

  /// 结算健康观察窗:连续健康播放满 [PlaybackRetryPolicy.healthWindow] 才把
  /// 连续失败计数归零。
  ///
  /// 旧实现在进入缓冲时直接撤销计时器,而 mpv 出帧后常紧接着再报一次
  /// `buffering`,于是计数只涨不落:退避随会话单调增长(实测 8→12→16→20s),
  /// 且无关故障会凑满上限而错误放弃。改为按已播时长结算后,能自愈的抖动
  /// 不再计入失败。
  void _settleHealthyWindow({required String reason}) {
    final since = _playingSince;
    _cancelHealthTimer();
    if (since == null) return;
    _playingSince = null;
    if (!_policy.shouldResetOnInterrupt(DateTime.now().difference(since))) {
      return;
    }
    if (_stallRetries == 0) return;
    _stallRetries = 0;
    PlaybackLog.write('health_reset', {'reason': reason});
    // 计数归零后进度文案要跟着退场,否则会残留"自动重连中 2/6"。
    _emit((s) => s.copyWith(retryAttempt: 0));
  }

  /// 按当前连续失败次数起看门狗。
  ///
  /// **已挂起则不重启**(幂等):mpv 对同一个故障会反复吐同一条诊断,缓冲标志也
  /// 会反复置位。若每次都 cancel + 重新计时,看门狗会被永久推迟 —— 表现为
  /// "自动重连永远不触发"的看门狗饥饿。已挂起就让它按原定时刻到期。
  /// 已闩锁放弃时也不再挂:自动重试已终结,挂上只会白跑一趟。
  void _armStallTimer() {
    if (_stallTimer != null || _givenUp) return;
    final backoff = _policy.backoffForWithLines(_stallRetries, _currentLines.length);
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
    // 解围栏处的低频样本(每次 open / 看门狗复核各一条):黑屏但状态栏
    // 「播放中」时,用它判定是否为「尺寸缺失型」—— playing=true 而
    // width/height 为 null/0 即是(正常起播会随后补报真实宽高)。
    PlaybackLog.write('video_state', {
      'width': width,
      'height': height,
      'playing': state.playing,
      'buffering': state.buffering,
    });
    _logVideoParams(state.videoParams);
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
    // 解围栏后的 kick 评估:open 在途被围栏吞掉的 playing/宽高事件在此
    // 一次性补评估(低频:每次 open / 看门狗复核各一次)。
    _syncVideoKick();
  }

  /// 按当前底层状态武装/撤销 kick 计时(幂等):
  /// - 条件([needsVideoKick])不成立(尺寸到位 / 非 playing / 缓冲中 /
  ///   已 kick 过)→ 撤销在途计时,不起新计时;
  /// - 成立且未武装 → 起 [_videoKickDelay] 计时,到期复核后才执行。
  /// 不直接执行 kick:尺寸可能只是晚报,到期复核才是准入门槛。
  void _syncVideoKick() {
    if (_disposed || _releaseRequested) return;
    final state = _player.state;
    final need = needsVideoKick(
      playing: state.playing,
      buffering: state.buffering,
      width: state.width,
      height: state.height,
      alreadyKicked: _videoKicked,
    );
    if (!need) {
      _videoKickTimer?.cancel();
      _videoKickTimer = null;
      return;
    }
    if (_videoKickTimer != null) return;
    _videoKickTimer = Timer(_videoKickDelay, _onVideoKickTimer);
  }

  /// kick 计时到期:复核同一条件(尺寸可能已迟到、可能已切源),仍成立才
  /// 置位 [_videoKicked]、留痕并执行一次 pause/play。复核不过则静默放弃,
  /// 后续事件仍可重新武装([_videoKicked] 未置位)。
  void _onVideoKickTimer() {
    _videoKickTimer = null;
    if (_disposed || _releaseRequested) return;
    final state = _player.state;
    if (!needsVideoKick(
      playing: state.playing,
      buffering: state.buffering,
      width: state.width,
      height: state.height,
      alreadyKicked: _videoKicked,
    )) {
      return;
    }
    _videoKicked = true;
    PlaybackLog.write('video_kick', {
      'reason': 'no_video_size',
      'width': state.width,
      'height': state.height,
    });
    unawaited(_runVideoKick());
  }

  /// 执行纹理 kick:pause/play 让 mpv 重建视频输出、把首帧推上屏。
  /// 这是实测手动恢复动作(暂停→播放)的自动化,只此一次,不进生命周期
  /// 队列(队列此时可能被新 open 占用,而 kick 只针对当前底层会话)。
  Future<void> _runVideoKick() async {
    _pauseReason = 'video_kick';
    _playReason = 'video_kick';
    try {
      await _player.pause();
      await _player.play();
    } catch (_) {
      // 底层已释放/切源时的竞态:kick 是尽力恢复,失败不得影响主链路。
      _pauseReason = null;
      _playReason = null;
    }
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
    _externalPauseTimer?.cancel();
    _externalPauseTimer = null;
    // buffering 事件可能在 open 围栏内丢失；计时到期必须复核底层状态，
    // 已恢复播放时只补发快照，不能机械重开视频管线。
    final state = _player.state;
    if (state.playing && !state.buffering) {
      _resyncAfterOpen();
      return;
    }
    // 单线路源卡顿升级:无内部回退线路时,重开同一死 URL 毫无意义,
    // 早一点 re-resolve(换节点 / 降画质)才有机会逃出被钉死的链路。
    // 每个 episode 至多升级一次(_singleLineEscalated 防退化重开后再触发);
    // 多线路源不升级(交给 mpv 播放列表内部跳线)。
    if (_policy.shouldEscalateToResolve(
          attempts: _stallRetries + 1,
          lineCount: _currentLines.length,
        ) &&
        !_singleLineEscalated) {
      _singleLineEscalated = true;
      PlaybackLog.write('single_line_escalate', {
        'attempt': _stallRetries + 1,
        'limit': _policy.escalateResolveAfter,
        'host': _currentHost,
      });
      unawaited(_escalateToResolve());
      return;
    }
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
    if (_resiliencePolicy.shouldRecoverSource(
      consecutiveSourceOpenFailures: _sourceOpenFailures,
    )) {
      PlaybackLog.write('recover_early', {
        'reason': 'source_open',
        'failures': _sourceOpenFailures,
        'host': _hostOf(_currentLines.first),
      });
      unawaited(_recoverOrGiveUp());
      return;
    }
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
    _settleHealthyWindow(reason: 'reopen');
    _emit((s) => s.copyWith(notice: PlaybackNotice.reconnecting));
    unawaited(open(_currentLines.first, _currentLines.skip(1).toList(), false));
  }

  /// 单线路源卡顿升级:向宿主请求**重新解析**(换节点 / 降画质),而非继续
  /// 重开同一死节点。与 [_recoverOrGiveUp](重试耗尽后的终局恢复)的关键区别:
  /// 这里的**节流失败 / 解析失败都不放弃**,而是退化回同 URL 重开
  /// ([_reopenIfStalled],因 [_singleLineEscalated] 已置位不会再递归升级),
  /// 避免把"重开死节点→re-resolve→又失败"的短暂抖动误判为"流不可救"而交出
  /// 错误卡片。节流仍由 [_recoveryPolicy] 把关,单线路升级不会高速空转。
  ///
  /// 节流间隔(默认 40s)对单线路恰恰是合理节奏:re-resolve 是跳出被钉死链路的
  /// 唯一希望,且每次解析都走 [RoomRecoverer] 绕开短缓存拿全新地址。若解析
  /// 持续返回同一坏节点,退化回的重开会继续累积退避,直到重试耗尽才真放弃。
  Future<void> _escalateToResolve() async {
    if (_disposedOrEmpty || _givenUp) return;
    final handler = _lineRecovery;
    PlaybackLog.write('escalate_recover_request', {
      'host': _currentHost,
      'retries': _stallRetries,
      'hasHandler': handler != null,
    });
    if (handler == null) {
      // 宿主不支持重解析:退化回同 URL 重开,不放弃。
      _reopenIfStalled();
      return;
    }
    final now = DateTime.now();
    if (!_recoveryPolicy.canRecover(now: now, lastRecoverAt: _lastRecoverAt)) {
      // 节流期内:退化回同 URL 重开,避免反复打解析服务;退避仍由策略控制。
      PlaybackLog.write('escalate_recover_throttled', {
        'host': _currentHost,
        'lastRecoverAt': _lastRecoverAt?.toIso8601String(),
      });
      _reopenIfStalled();
      return;
    }
    _lastRecoverAt = now;
    _emit((s) => s.copyWith(notice: PlaybackNotice.recoveringNewUrl));
    List<StreamLine>? fresh;
    try {
      fresh = await handler();
    } catch (_) {
      fresh = null;
    }
    if (!_disposed && !_givenUp && fresh != null && fresh.isNotEmpty) {
      PlaybackLog.write('escalate_recover_ok', {
        'lines': fresh.length,
        'host': _hostOf(fresh.first),
      });
      _stallRetries = 0;
      _sourceOpenFailures = 0;
      // resetRetries 默认 true:新地址开启新一轮有界重试,并复位本 episode
      // 升级闩锁,让新线路(若解析出多线路)正常走 mpv 内部跳线。
      await open(fresh.first, fresh.skip(1).toList());
      return;
    }
    PlaybackLog.write('escalate_recover_fail', {
      'host': _currentHost,
      'reason': fresh == null ? 'error' : 'empty',
    });
    // 解析失败:退化回同 URL 重开,不放弃。
    _reopenIfStalled();
  }

  /// 自动重连耗尽后的最后一步:向宿主请求**重新解析**后的线路。
  ///
  /// 拿到新线路 → 重置失败计数重开(等于一次带新地址的全新会话);拿不到
  /// (宿主不支持 / 解析失败 / 尚在节流窗口内)→ 发出终局错误卡片交出控制权。
  /// 恢复失败仍要走终止路径:既不返回新地址又不报错会把用户悬在"缓冲中"。
  Future<void> _recoverOrGiveUp() async {
    if (_recoverInFlight) return;
    _recoverInFlight = true;
    try {
      await _recoverOrGiveUpInner();
    } finally {
      _recoverInFlight = false;
    }
  }

  Future<void> _recoverOrGiveUpInner() async {
    // 撤销"出帧即康复"的假阳性记账:mpv 对打不开的源也会先发 playing(旧帧 /
    // vo 复位触发),随后才吐终局诊断(实测 2026-09-27 18:23:58 playing_ok 后
    // 99ms 即 source_open_failure)。健康观察窗未走完就收到终局错误,必须撤回
    // ——否则观察窗到期会把失败计数清零,重试上限形同虚设。
    if (_healthTimer != null || _playingSince != null) {
      _cancelHealthTimer();
      _playingSince = null;
      PlaybackLog.write('playing_ok_revoked', {'host': _currentHost});
    }
    final handler = _lineRecovery;
    final now = DateTime.now();
    final canAttempt =
        handler != null &&
        !_disposed &&
        _recoveryPolicy.canRecover(now: now, lastRecoverAt: _lastRecoverAt);
    if (canAttempt) {
      _lastRecoverAt = now;
      PlaybackLog.write('recover_request', {'lastKind': _lastErrorKind.name});
      _emit((s) => s.copyWith(notice: PlaybackNotice.recoveringNewUrl));
      List<StreamLine>? fresh;
      String? failReason;
      try {
        fresh = await handler();
      } catch (error) {
        // 解析异常按"拿不到新地址"处理,不吞掉下面的终止路径。
        failReason = 'error: ${_clamp('$error')}';
        fresh = null;
      }
      if (!_disposed && !_givenUp && fresh != null && fresh.isNotEmpty) {
        PlaybackLog.write('recover_ok', {
          'lines': fresh.length,
          'host': _hostOf(fresh.first),
        });
        _stallRetries = 0;
        _sourceOpenFailures = 0;
        // resetRetries 保持默认 true:新地址开启新一轮有界重试。
        await open(fresh.first, fresh.skip(1).toList());
        return;
      }
      PlaybackLog.write('recover_fail', {
        'reason': _givenUp
            ? 'cancelled_by_user'
            : (failReason ?? 'empty_lines'),
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
        notice: PlaybackNotice.none,
      ),
    );
  }

  /// 参照 pure_live 的直播卡顿根治方案:直接给 mpv 设属性,而非只靠 Flutter
  /// 侧轮询。核心是把 demuxer 缓存设为统一的有界低延迟(128MiB 前向 /
  /// 8MiB 回退 / 10s 预读 / 10s 封顶),并把网络超时压到 15s——这样断流或卡死的
  /// 直播流会主动抛 error(而非无限缓冲把画面冻住)。单条线路断流先由 mpv
  /// 播放列表内部自动跳下一条,全组耗尽(events.completed)或冻结卡顿(缓冲看门狗)
  /// 时再由 [_reopenIfStalled] 整组轮转。
  /// 另外 `demuxer-lavf-*` 加速探测、缓存落临时目录避免原生内存爬升。
  ///
  /// 属性表来源:`config/mpv_tuning.json` 逐键覆盖内置默认(见
  /// live_tuning_config.dart),首次运行先写模板文件。
  Future<void> _applyLiveTuning() async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return; // Web/测试等非原生后端跳过。
    try {
      await platform.waitForPlayerInitialization;
      ensureLiveTuningConfigExists();
      final tuning = resolveLiveTuningProperties(
        jsonContent: readLiveTuningFile(),
      );
      for (final (name, value) in tuning) {
        await platform.setProperty(name, value);
      }
      await _applyHardwareAcceleration(
        platform,
        videoHardwareAccelerationEnabled,
      );
      // 把实际生效的缓冲参数落盘:下一次会话可直接核对"配置是否真的注入",
      // 不必再从二进制/源码反推(排查卡顿时缺的正是这一环)。
      PlaybackLog.write('mpv_tuning', {
        'config_path': liveTuningConfigFilePath(),
        for (final (name, value) in tuning) name: value,
      });
      // 每次 open 只按当前线路主机重设代理,避免上一个源的代理策略残留。
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

  /// 按线路主机设置 mpv 的 `http-proxy`(进程级选项,故每次 open 都重设)。
  ///
  /// mpv 不支持按主机分流,只能整个进程一个值;这里用「当前源需要就设、不需要
  /// 就显式清空」的方式近似实现分流:同一时刻播放的只有一条源,语义足够。
  Future<void> _applyProxyForLine(StreamLine line) async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    final host = Uri.tryParse(line.url)?.host ?? '';
    final proxy = UpstreamProxy.needsProxy(host)
        ? UpstreamProxy.hostPort
        : null;
    try {
      await platform.waitForPlayerInitialization;
      await platform.setProperty(
        'http-proxy',
        proxy == null || proxy.isEmpty ? '' : 'http://$proxy',
      );
      PlaybackLog.write('mpv_proxy', {
        'host': host,
        'proxy': proxy == null || proxy.isEmpty ? 'direct' : proxy,
      });
    } catch (_) {
      // 设置失败不阻断播放:直连失败时仍有看门狗与恢复重解析兜底。
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
    _watchFirstFrame();
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
    _lastVideoParams = null;
    // 死开流看门狗随代际重布防:上代的计时器作废,新代在宽限期后复核参数。
    _deadOpenTimer?.cancel();
    _deadOpenTimer = Timer(
      _policy.deadOpenGrace,
      () => _onDeadOpenTimeout(myGen),
    );
    _videoParamsSeen = false;
    _videoStabilityTimer?.cancel();
    _videoStabilityTimer = null;
    // kick 计时与 flag 同步段 reset(先于入队):排队中的旧会话计时不得
    // 在新 open 落地前到期执行,新会话也从「未 kick」开始。
    _videoKickTimer?.cancel();
    _videoKickTimer = null;
    _videoKicked = false;
    // 度量生命周期队列等待:切房时前一个 stop 排在开流前面会直接推后首帧。
    final requestedAt = DateTime.now();
    return _enqueueLifecycle(() async {
      if (myGen != _sourceGeneration) {
        PlaybackLog.write('open_superseded', {
          'gen': myGen,
          'current': _sourceGeneration,
          'phase': 'queued',
        });
        return;
      }
      if (resetRetries) {
        // 只记用户主动开流(自动重开走同一队列但无此信号意义)。
        PlaybackLog.write('open_queue_wait', {
          'ms': DateTime.now().difference(requestedAt).inMilliseconds,
          'lines': [line, ...fallbacks].length,
        });
      }
      if (_disposed || _releaseRequested) return;
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
        if (_disposed || _releaseRequested || myGen != _sourceGeneration) {
          return;
        }
        final prepared = await _adFilter.wrapLine(item);
        if (!identical(prepared, item)) wrappedAny = true;
        wrappedLines.add(prepared);
      }
      _currentLines = wrappedLines;
      final orderedLines = _cdnCircuitBreaker.order(
        _currentLines,
        (item) => _hostOf(item) ?? item.url,
        DateTime.now(),
      );
      var reordered = false;
      for (var i = 0; i < orderedLines.length; i++) {
        if (!identical(orderedLines[i], _currentLines[i])) reordered = true;
      }
      if (reordered) {
        PlaybackLog.write('cdn_failover_order', {
          'lines': orderedLines.length,
          'firstHost': _hostOf(orderedLines.first),
        });
        _currentLines = orderedLines;
      }
      // 代理按当前线路主机取:被墙 CDN 走代理,国内可达站点显式清空
      // (mpv 选项是进程级,不重设会把上一个源的代理策略带过来)。
      await _applyProxyForLine(line);
      // 新会话从"无广告等待"开始记账。
      _adHoldSince = null;
      // 新会话重建播放时钟基线:重开/换源后 time-pos 时间线不同,旧基线
      // 会造成一次假回跳判定。任何 open(含自动重开)都算新会话。
      _lastStabilityTimePos = null;
      if (resetRetries) {
        _stallRetries = 0;
        _sourceOpenFailures = 0;
        // 单线路升级闩锁随新会话复位:新房/切线/换新地址都开启新 episode,
        // 允许再次在卡顿后升级 re-resolve。
        _singleLineEscalated = false;
        // 用户主动重试/切源是唯一的闩锁解除点。
        _givenUp = false;
        // 新会话(进房/切线/换新地址)重置诊断去重:不同故障的同文案也该再记。
        _lastLoggedDiag = null;
        _flushWarnSuppression();
        _warnCounts.clear();
        _warnShapes.clear();
        _decodeChaosCount = 0;
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
      _videoStabilityTimer?.cancel();
      _videoStabilityTimer = null;
      _cancelHealthTimer();
      _playingSince = null;
      // 切源/开流即开启新卡顿会话:丢弃旧源未结算的 begin,避免跨会话计时。
      _stallTracker.reset();
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
          notice: resetRetries ? PlaybackNotice.networkJitter : s.notice,
        ),
      );
      try {
        final playlist = Playlist(
          _currentLines
              .map((item) => Media(item.url, httpHeaders: item.headers))
              .toList(growable: false),
        );
        // 记下发时刻:首个出帧事件时落盘 open_to_first_frame。
        _openStartedAt = DateTime.now();
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
      if (myGen != _sourceGeneration || _releaseRequested || _disposed) return;
      if (_disposed) return;
      // 解围栏并补发真实状态(含看门狗重挂,见 [_resyncAfterOpen])。
      _eventsFenced = false;
      _resyncAfterOpen();
    });
  }

  @override
  Future<void> play() => _enqueueLifecycle(() async {
    PlaybackLog.write('play_cmd', {'action': 'play'});
    _playReason = 'ui';
    await _player.play();
    // 用户口径(2026-09-20 播放/暂停判断错):UI 反馈不等底层 playing 事件
    // 回流 —— media-kit 暂停后不一定再吐 playing 事件,回流也可能被时序
    // 吞掉,控制条图标会停在旧态。主动发布快照;底层事件晚到时值相同,
    // 经 _emit 去重不抖动。
    _emit((snapshot) => snapshot.copyWith(playing: true));
  });

  @override
  Future<void> pause() => _enqueueLifecycle(() async {
    PlaybackLog.write('play_cmd', {'action': 'pause'});
    _pauseReason = 'ui';
    await _player.pause();
    _emit((snapshot) => snapshot.copyWith(playing: false));
  });

  @override
  void cancelRecovery() {
    if (_disposed) return;
    // 停掉所有会触发重开/恢复的计时器:卡顿看门狗、外部自暂停看门狗、
    // 健康观察窗(取消后无需再确认康复,失败计数也不再清零)。
    _stallTimer?.cancel();
    _stallTimer = null;
    _externalPauseTimer?.cancel();
    _externalPauseTimer = null;
    _deadOpenTimer?.cancel();
    _deadOpenTimer = null;
    _cancelHealthTimer();
    _playingSince = null;
    // 与重试耗尽同一闩锁:置位后看门狗/终局错误/列表结束都不再重开,
    // 仅由 open(resetRetries: true)(手动 retry/切源)解除。**不轮转线路**。
    _givenUp = true;
    PlaybackLog.write('recovery_cancelled', {
      'host': _currentHost,
      'retries': _stallRetries,
    });
    _emit(
      (s) => s.copyWith(
        buffering: false,
        notice: PlaybackNotice.none,
        retryAttempt: 0,
        error: '已取消自动重连，点击重试恢复播放',
        errorKind: PlayerErrorKind.network,
      ),
    );
  }

  @override
  Future<void> stop() {
    // 同步自增代际:作废在途的 open —— 离房后旧的 open 不得再把源挂上。
    _sourceGeneration++;
    // kick 计时不得跨会话:离房即撤销,flag 一并归零(重进房允许重新武装)。
    _videoKickTimer?.cancel();
    _videoKickTimer = null;
    _videoKicked = false;
    // 死开流看门狗同理:离房后黑屏复核已无对象。
    _deadOpenTimer?.cancel();
    _deadOpenTimer = null;
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
      _videoStabilityTimer?.cancel();
      _videoStabilityTimer = null;
      _cancelHealthTimer();
      _playingSince = null;
      _stallTracker.reset();
      _openStartedAt = null;
      _currentLines = const [];
      // 离房即重置恢复节流与重试记账:下一次进房从干净状态开始,
      // 而不是继承上一间的窗口 / 已放弃闩锁(否则重进同一间永不自动重连)。
      _lastRecoverAt = null;
      _stallRetries = 0;
      _sourceOpenFailures = 0;
      _singleLineEscalated = false;
      _cdnCircuitBreaker.clear();
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

  Future<void>? _releaseFuture;
  bool _releaseRequested = false;

  Future<void> releaseNative() {
    return _releaseFuture ??= _beginNativeRelease();
  }

  Future<void> _beginNativeRelease() async {
    _releaseRequested = true;
    _videoKickTimer?.cancel();
    _videoKickTimer = null;
    await _lifecycleQueue;
    await _releaseNativeOnce();
  }

  Future<void> _releaseNativeOnce() async {
    if (!_disposed) {
      _disposed = true;
      _stallTimer?.cancel();
      _stallTimer = null;
      _externalPauseTimer?.cancel();
      _externalPauseTimer = null;
      _videoStabilityTimer?.cancel();
      _videoStabilityTimer = null;
      _videoKickTimer?.cancel();
      _videoKickTimer = null;
      _deadOpenTimer?.cancel();
      _deadOpenTimer = null;
      _cancelHealthTimer();
      _stallTracker.reset();
      _currentLines = const [];
      for (final subscription in _subscriptions) {
        await subscription.cancel();
      }
      _subscriptions.clear();
      try {
        WidgetsBinding.instance.removeObserver(this);
      } catch (_) {
        // 无 binding / 未注册:忽略。
      }
      try {
        windowManager.removeListener(_windowListener);
      } catch (_) {
        // 插件未初始化:忽略。
      }
      await _output.close();
      await _adFilter.dispose();
    }
    await _player.dispose();
    PlaybackLog.write('player_native_disposed');
  }

  @override
  void dispose() {
    unawaited(releaseNative());
  }

  // ---- 应用生命周期 / 窗口可见性埋点 --------------------------------------
  //
  // 归因「后端自暂停」用:2026-09-27 前一次播放无故暂停,日志里既无 play_cmd
  // (排除 UI 按钮/Space),也无任何 error/buffering,唯一嫌疑是窗口被隐藏/最小化
  // 时 mpv 自己停了。此前全仓没有这两类监听,无从证实。下面把生命周期与窗口
  // 显隐事件落盘,下次暂停可直接与 `play_state source=external` 时间对齐。
  // 原生/无窗口环境(VM 测试、Web、插件未就绪)一律静默降级。

  /// 注册应用生命周期 + 原生窗口事件监听。
  void _observeLifecycle() {
    try {
      WidgetsBinding.instance.addObserver(this);
    } catch (_) {
      // 纯 VM 测试未 pump binding:跳过。
    }
    try {
      windowManager.addListener(_windowListener);
    } catch (_) {
      // window_manager 插件未初始化:跳过。
    }
  }

  String? _appLifecycleName() {
    try {
      return WidgetsBinding.instance.lifecycleState?.name;
    } catch (_) {
      return null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    PlaybackLog.write('app_lifecycle', {
      'state': state.name,
      'playing': _latest.playing,
    });
  }

  void _logWindowEvent(String kind) {
    if (_disposed) return;
    PlaybackLog.write('window_event', {
      'kind': kind,
      'playing': _latest.playing,
    });
  }
}

/// 原生窗口事件 → 日志的薄转发:[WindowListener] 是普通 class(非 mixin),
/// 播放器无法 `with`,故用此小类持有回调转发。窗口最小化/隐藏是「后端自暂停」
/// 的首要嫌疑,这些事件落盘后可与 `play_state source=external` 时间对齐。
class _WindowLifecycleListener extends WindowListener {
  _WindowLifecycleListener(this._onEvent);

  final void Function(String) _onEvent;

  @override
  void onWindowMinimize() => _onEvent('minimize');
  @override
  void onWindowRestore() => _onEvent('restore');
  @override
  void onWindowMaximize() => _onEvent('maximize');
  @override
  void onWindowUnmaximize() => _onEvent('unmaximize');
  @override
  void onWindowEnterFullScreen() => _onEvent('enter_fullscreen');
  @override
  void onWindowLeaveFullScreen() => _onEvent('leave_fullscreen');
  @override
  void onWindowFocus() => _onEvent('focus');
  @override
  void onWindowBlur() => _onEvent('blur');
}
