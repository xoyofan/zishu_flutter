/// 播放页编排:播放器单例、快照流与房间播放控制器。
/// 编排规则:解析房间 → 维持选中画质/线路 → 驱动 LivePlayer 开流;
/// 所有竞态用 generation fence 防护,Widget 不直接触碰播放器。
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_parser/live_parser.dart';

import '../../../platforms/common/playback/idle_releasing_live_player.dart';
import '../../../platforms/common/playback/live_player.dart';
import '../../../platforms/common/playback/media_kit_live_player.dart';
import '../../../platforms/common/playback/playback_log.dart';
import '../../../shared/application/browse_source.dart';
import '../../../shared/application/providers.dart';
import '../../follow/application/settings_provider.dart';
import 'play_selection.dart';
import 'room_volume_provider.dart';

/// 共享播放器上的最新开流操作 token。不同房间的 family controller 共用同一
/// `LivePlayer`，局部 generation 只能保护单个 controller，不能阻止旧房间的
/// open 收尾覆盖新房间；因此在播放器编排层再加一层全局 token。
int _latestPlayerOpenToken = 0;

/// 播放器单例:app 生命周期内复用,不随页面销毁。
/// dispose 由根 ProviderContainer 统一触发(仅 app 退出时执行)。
final playerProvider = Provider<LivePlayer>((ref) {
  final player = IdleReleasingLivePlayer(
    createPlayer: () => MediaKitLivePlayer(
      videoHardwareAccelerationEnabled: ref
          .read(settingsProvider)
          .videoHardwareAcceleration,
    ),
  );
  ref.listen<bool>(
    settingsProvider.select((settings) => settings.videoHardwareAcceleration),
    (_, enabled) {
      if (player case IdleReleasingLivePlayer idlePlayer) {
        final inner = idlePlayer.currentPlayer;
        if (inner case final VideoHardwareAccelerationAware aware) {
          aware.setVideoHardwareAcceleration(enabled);
        }
      }
    },
  );
  ref.onDispose(player.dispose);
  return player;
});

/// 播放快照流:控制条/舞台 overlay 用它驱动 UI。
final playerSnapshotProvider = StreamProvider<PlayerSnapshot>(
  (ref) => ref.watch(playerProvider).snapshots,
);

/// 播放控制器入参:(site, roomId)。
typedef PlayParams = ({String site, String roomId});

/// 播放页状态:解析结果 + 选中画质/线路 + 代际计数。
class PlayState {
  const PlayState({
    this.payload,
    this.quality,
    this.line,
    this.generation = 0,
    this.showDanmaku = true,
  });

  final RoomPayload? payload;
  final StreamQuality? quality;
  final StreamLine? line;

  /// 代际计数:切房/重解析/切换画质或线路时 +1,
  /// 旧异步回调回来后 generation 不匹配即丢弃。
  final int generation;

  /// 舞台弹幕叠加层开关:由控制条/快捷键切换,舞台据此挂载 overlay。
  final bool showDanmaku;

  /// fixture 数据不进真实播放器,舞台显示占位。
  bool get isFixture => payload?.source == 'fixture';

  PlayState copyWith({
    RoomPayload? payload,
    StreamQuality? quality,
    StreamLine? line,
    int? generation,
    bool? showDanmaku,
  }) {
    return PlayState(
      payload: payload ?? this.payload,
      quality: quality ?? this.quality,
      line: line ?? this.line,
      generation: generation ?? this.generation,
      showDanmaku: showDanmaku ?? this.showDanmaku,
    );
  }
}

/// 播放页控制器:family by (site, roomId);autoDispose 随页面离开释放状态,
/// 但全局播放器实例不在此销毁。
final playControllerProvider = AsyncNotifierProvider.autoDispose
    .family<PlayController, PlayState, PlayParams>(PlayController.new);

/// 后台预取的档位上限、并发数与首批错开间隔。
///
/// 预取是「锦上添花」:首档已可播,其余档位慢几秒无感;但若不限速,它会与
/// 起播/切房争抢代理连接(2026-09-21 Twitch 卡慢的成因)。上限之外的档位
/// 仍可点击 —— 切档时按需解析。
///
/// 并发 2:斗鱼/B站/YY/SOOP 每档 1~2 个请求,串行会把 4 档拖到 4~6s;
/// 并发 2 约减半,再高就会抢首帧带宽。
const int kPrefetchQualityLimit = 4;
const int kPrefetchConcurrency = 2;
const Duration kPrefetchStagger = Duration(milliseconds: 800);

class PlayController extends AsyncNotifier<PlayState> {
  PlayController(this.params);

  final PlayParams params;

  int _generation = 0;

  /// 用户手动切档后的偏好覆盖(懒取流):切换到的档位若未预取线路,以此档
  /// 重新解析,解析侧只取该档,避免整房全档取流。
  String? _qualityOverride;

  /// 后台预取到的档位线路,切档时优先复用。
  final Map<String, StreamQuality> _prefetchedQualities = {};

  /// 预取代际:只在「重新解析房间」(build/retry)时推进。
  ///
  /// 不能复用 [_generation]:切画质/切线路都会推进它,那会把还在跑的
  /// 后台预取全部作废(用户口径 2026-09-21:其他线路必须后台加载完)。
  int _prefetchToken = 0;

  @override
  FutureOr<PlayState> build() async {
    final generation = ++_generation;
    final prefetchToken = ++_prefetchToken;
    // 离开播放页(autoDispose 触发)→ 停止全局播放器:直播不得在后台继续出声/出画。
    // 仅卸载媒体源,不 dispose 实例(下次进房复用同一 Player)。捕获实例而非在
    // 回调里 ref.read,避免 provider 销毁期再去读依赖。
    final player = ref.read(playerProvider);
    final token = player is IdleReleasingLivePlayer ? player.enterRoom() : null;
    ref.onDispose(() {
      // 先注销恢复回调再 stop:回调是播放器持有的**指向本 controller** 的活引用,
      // autoDispose 后播放器仍可能在自动重连里调用它,而那时 ref/state 已失效
      // (`_recoverLines` 读 state 会报 “Cannot use Ref after dispose”)。
      // 回调只能在本层注销 —— 播放器不知道宿主已离场。
      if (player is IdleReleasingLivePlayer && token != null) {
        player.clearLineRecovery(token);
      } else if (player case LineRecoveryAware aware) {
        aware.setLineRecovery(null);
      }
      final stopWatch = Stopwatch()..start();
      final fields = <String, Object?>{
        'site': params.site,
        'room': params.roomId,
      };
      PlaybackLog.writeResourceSample('room_release_start', fields);
      if (token != null && player is IdleReleasingLivePlayer) {
        unawaited(
          player.leaveRoom(token).whenComplete(() {
            stopWatch.stop();
            PlaybackLog.writeResourceSample('room_release_end', {
              ...fields,
              'elapsed_ms': stopWatch.elapsedMilliseconds,
            });
          }),
        );
      } else {
        unawaited(_stopAndSampleRelease(player, stopWatch, fields));
      }
    });
    // 数据源端口变化(G1 换真实解析)时自动重建,Widget 无感。
    final source = ref.watch(roomSourceProvider);
    // 默认画质:平台单独配置 > 平台默认档 > 全平台默认(设置页可改)。
    // select 以「该平台生效值」为 key,只有它变化才重建本 family;
    // 房间缺该档时 _pickQuality 回退 streams.first(「没有才退」)。
    final settingsQuality = ref.watch(
      settingsProvider.select(
        (settings) => settings.effectiveDefaultQuality(params.site),
      ),
    );
    // 线路格式偏好(auto/hls/flv):设置页可改,进房/重解析时都按它选线。
    final preferredFormat = ref.watch(
      settingsProvider.select((settings) => settings.preferredLineFormat.value),
    );
    final preferredQuality = _qualityOverride ?? settingsQuality;
    final resolveWatch = Stopwatch()..start();
    final payload = await source.resolveRoom(
      site: params.site,
      roomIdOrUrl: params.roomId,
      preferredQuality: preferredQuality,
    );
    resolveWatch.stop();
    // 进房解析耗时落盘:此前只有失败才有日志,"打开慢"缺的正是这段度量。
    PlaybackLog.write('resolve_ms', {
      'ms': resolveWatch.elapsedMilliseconds,
      'site': params.site,
      'room': params.roomId,
    });

    // generation fence:等待期间出现了更新的代际(retry 等),丢弃本次结果。
    if (generation != _generation) {
      return state.value ?? PlayState(generation: generation);
    }
    final quality = _pickPlayableQuality(payload, preferredQuality);
    // 传入 site:白名单站点 auto 起播优选 FLV(首帧提速,见 play_selection)。
    final line = pickStreamLine(quality, preferredFormat, site: params.site);
    final next = PlayState(
      payload: payload,
      quality: quality,
      line: line,
      generation: generation,
    );

    if (!next.isFixture && line != null) {
      // 开流不阻塞状态落地;错误经快照流呈现在舞台 overlay。
      // 同画质其余线路作回退送进播放器,断流时 mpv 自动跳下一条(pure_live 式)。
      // 必须走 _open:首次进房就要装上恢复回调,否则签名平台地址过期后,
      // 播放器在放弃分支拿不到"重新解析"的新地址。
      _open(line, _fallbackLines(quality, line));
      // 首帧落地后才预取其他画质(pure_live 进房不做任何预取):开流握手的
      // 1~3s 是最敏感窗口,此刻并发补档会与它抢带宽,表现为「打开很慢」。
      unawaited(_prefetchAfterFirstFrame(payload, source, prefetchToken));
    }
    return next;
  }

  /// 离房后等全局播放器真正卸载旧源,再落一条释放后 RSS 样本。
  Future<void> _stopAndSampleRelease(
    LivePlayer player,
    Stopwatch stopWatch,
    Map<String, Object?> fields,
  ) async {
    try {
      await player.stop();
    } catch (error) {
      PlaybackLog.writeResourceSample('room_release_error', {
        ...fields,
        'error': error,
      });
    } finally {
      stopWatch.stop();
      PlaybackLog.writeResourceSample('room_release_end', {
        ...fields,
        'elapsed_ms': stopWatch.elapsedMilliseconds,
      });
    }
  }

  /// 等首个出帧事件后再启动画质预取。
  ///
  /// 保留本仓「切画质即开」的能力,但把时机推到首帧之后 —— 参考实现
  /// (pure_live)在进房时根本不预取,先帧优先是它开流快的一个原因。
  /// 首帧迟迟不来(15s 超时)则放弃预取:首帧都没来,切画质本就走懒取流。
  Future<void> _prefetchAfterFirstFrame(
    RoomPayload payload,
    RoomSource source,
    int prefetchToken,
  ) async {
    final player = ref.read(playerProvider);
    try {
      await player.snapshots
          .firstWhere((snapshot) => snapshot.playing && !snapshot.buffering)
          .timeout(const Duration(seconds: 15));
    } on Object {
      return; // 超时 / 流关闭:放弃预取,不阻塞任何路径。
    }
    if (prefetchToken != _prefetchToken || !ref.mounted) return;
    unawaited(_prefetchQualities(payload, source, prefetchToken));
  }

  Future<void> _prefetchQualities(
    RoomPayload initial,
    RoomSource source,
    int prefetchToken,
  ) async {
    // 待补档位:只选「确实缺线路」的档,超出上限的记录跳过原因。
    final targets = <QualityOption>[];
    for (final option in initial.availableQualities) {
      final existing =
          _prefetchedQualities[option.name] ??
          initial.qualityByName(option.name);
      // 已带线路的档位直接跳过 —— Twitch/YouTube 这类平台
      // 一次响应就已拿全档线路,完全不需要预取。
      if (existing != null && existing.lines.isNotEmpty) continue;
      if (targets.length >= kPrefetchQualityLimit) {
        PlaybackLog.write('prefetch_skip', {
          'site': params.site,
          'room': params.roomId,
          'quality': option.name,
          'reason': 'limit',
        });
        continue;
      }
      targets.add(option);
    }
    if (targets.isEmpty) return;

    // 只错开一次:让首帧先落地,随后并发补档(逐档 600ms 串行会把 4 档拖到
    // 4~6s;并发 2 约减半,又不至于抢首帧带宽)。
    await Future<void>.delayed(kPrefetchStagger);
    if (prefetchToken != _prefetchToken || !ref.mounted) return;

    var cursor = 0;
    Future<void> worker() async {
      while (true) {
        final index = cursor++;
        if (index >= targets.length) return;
        if (prefetchToken != _prefetchToken || !ref.mounted) return;
        await _prefetchOne(targets[index], source, prefetchToken);
      }
    }

    await Future.wait([
      for (var i = 0; i < kPrefetchConcurrency; i++) worker(),
    ]);
  }

  /// 补一个档位的线路并合并回当前 payload。
  Future<void> _prefetchOne(
    QualityOption option,
    RoomSource source,
    int prefetchToken,
  ) async {
    final startedAt = DateTime.now();
    PlaybackLog.write('prefetch_start', {
      'site': params.site,
      'room': params.roomId,
      'quality': option.name,
    });
    try {
      final fetchedPayload = await source.resolveRoom(
        site: params.site,
        roomIdOrUrl: params.roomId,
        preferredQuality: option.name,
      );
      if (prefetchToken != _prefetchToken || !ref.mounted) return;
      final fetched = fetchedPayload.qualityByName(option.name);
      if (fetched == null || fetched.lines.isEmpty) {
        PlaybackLog.write('prefetch_empty', {
          'site': params.site,
          'room': params.roomId,
          'quality': option.name,
          'ms': DateTime.now().difference(startedAt).inMilliseconds,
        });
        return;
      }
      _prefetchedQualities[option.name] = fetched;
      PlaybackLog.write('prefetch_ok', {
        'site': params.site,
        'room': params.roomId,
        'quality': option.name,
        'lines': fetched.lines.length,
        'ms': DateTime.now().difference(startedAt).inMilliseconds,
      });
      final current = state.value;
      final currentPayload = current?.payload;
      if (current == null || currentPayload == null) return;
      final merged = [
        for (final stream in currentPayload.streams)
          stream.name == fetched.name ? fetched : stream,
      ];
      state = AsyncData(
        current.copyWith(
          payload: currentPayload.copyWith(
            streams: merged,
            fetchedAt: fetchedPayload.fetchedAt,
          ),
        ),
      );
    } catch (error) {
      // 后台预取失败不影响当前播放;用户切档时仍按需解析。
      PlaybackLog.write('prefetch_fail', {
        'site': params.site,
        'room': params.roomId,
        'quality': option.name,
        'error': error,
        'ms': DateTime.now().difference(startedAt).inMilliseconds,
      });
    }
  }

  /// 切换画质:预取完成时直接开流;否则按需重新解析。
  void switchQuality(StreamQuality quality) {
    final current = state.value;
    if (current == null || current.payload == null) return;
    final effectiveQuality = _prefetchedQualities[quality.name] ?? quality;
    final line = pickStreamLine(
      effectiveQuality,
      ref.read(settingsProvider).preferredLineFormat.value,
      site: params.site,
    );
    if (line == null) {
      _qualityOverride = quality.name;
      ref.invalidateSelf();
      return;
    }
    final generation = ++_generation;
    state = AsyncData(
      current.copyWith(
        quality: effectiveQuality,
        line: line,
        generation: generation,
      ),
    );
    _open(line, _fallbackLines(effectiveQuality, line));
  }

  /// 同画质内切换线路。
  void switchLine(StreamLine line) {
    final current = state.value;
    if (current == null || current.payload == null) return;
    final generation = ++_generation;
    state = AsyncData(current.copyWith(line: line, generation: generation));
    _open(line, _fallbackLines(current.quality, line));
  }

  /// 切换舞台弹幕叠加层显隐(纯展示开关,不重开流、不换代际)。
  void toggleDanmaku() {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(current.copyWith(showDanmaku: !current.showDanmaku));
  }

  /// 重试:解析失败 → 整体重解析;播放失败 → 重开当前线路。
  void retry() {
    final current = state.value;
    if (current != null && current.payload == null) {
      ref.invalidateSelf();
      return;
    }
    final generation = ++_generation;
    // 整体重解析:旧一批预取线路已与当前 payload 脱钩,作废。
    _prefetchToken++;
    if (current != null) {
      state = AsyncData(current.copyWith(generation: generation));
    }
    _openSelected();
  }

  /// 用最新代际把选中线路(连同同画质回退线路)送进播放器。
  void _openSelected() {
    final current = state.value;
    final line = current?.line;
    if (current == null || current.isFixture || line == null) return;
    _open(line, _fallbackLines(current.quality, line));
  }

  /// 统一开流入口:确保播放器已装上「恢复重解析」回调再开流。
  ///
  /// 回调只能由编排层提供 —— 自动重连是播放器内部看门狗驱动的,编排层无法
  /// 感知"它已耗尽上限"。装上后,播放器在放弃前会回头向本层要一份**重新
  /// 解析**的地址(签名平台地址此时多半已过期,复用旧地址=无限重开失效源)。
  void _open(StreamLine line, List<StreamLine> fallbacks) {
    final player = ref.read(playerProvider);
    final openToken = ++_latestPlayerOpenToken;
    // LineRecoveryAware 不是 LivePlayer 的子类型,is 探测不产生类型提升,
    // 用 if-case 对象模式探测并绑定(免显式 as)。
    if (player case LineRecoveryAware aware) {
      aware.setLineRecovery(_recoverLines);
    }
    unawaited(
      _openAndApplyVolume(player, line, fallbacks, _generation, openToken),
    );
  }

  /// 开流前后套用本房间音量,不改变 pure_live 的线路选择和开流顺序。
  Future<void> _openAndApplyVolume(
    LivePlayer player,
    StreamLine line,
    List<StreamLine> fallbacks,
    int generation,
    int openToken,
  ) async {
    // 音量套用不阻塞开流(对齐 pure_live:进房先开流):mpv 的 volume 是
    // 进程级属性,通常先于首帧音频落地;开流后再补一次,校正快照与迟到回流。
    unawaited(_applyRoomVolume(player));
    await player.open(line, fallbacks);
    if (!ref.mounted ||
        generation != _generation ||
        openToken != _latestPlayerOpenToken) {
      return;
    }
    await _applyRoomVolume(player);
  }

  /// 把本房间的有效音量套到播放器。
  ///
  /// 全局静音走 [LivePlayer.setMuted](让控制条的静音图标同步点亮),其余情况
  /// 直接给音量 —— `setVolume(>0)` 本身就会解除会话内静音(见实现层)。
  Future<void> _applyRoomVolume(LivePlayer player) async {
    final decision = ref.read(roomVolumeProvider(params));
    if (decision.globalMuted) {
      await player.setMuted(true);
      return;
    }
    await player.setVolume(decision.volume);
  }

  /// 播放器请求恢复:重新解析当前房间,返回选中画质的**全新**线路。
  ///
  /// 故意走 [RoomRecoverer](绕开短缓存)而非 `resolveRoom` —— 后者可能命中
  /// 60s 短缓存,把过期地址原样交回去。非真实解析源(fixture)或解析异常时
  /// 返回空列表,由播放器走放弃分支给出终局建议。
  Future<List<StreamLine>> _recoverLines() async {
    // 宿主已离场(autoDispose)时一律拒答:下面要读 state,而销毁后读会抛错。
    // 回调注销是主动防护,这里再兜一道 —— 注销与调用之间存在竞态窗口。
    if (!ref.mounted) return const [];
    final current = state.value;
    final source = ref.read(roomSourceProvider);
    final quality = current?.quality;
    if (current == null ||
        current.payload == null ||
        source is! RoomRecoverer) {
      PlaybackLog.write('resolve_skip', {
        'site': params.site,
        'room': params.roomId,
        'reason': current == null || current.payload == null
            ? 'no_state'
            : 'source_unaware',
      });
      return const [];
    }
    try {
      final payload = await source.recoverRoom(
        site: params.site,
        roomIdOrUrl: params.roomId,
        preferredQuality: quality?.name,
      );
      if (!ref.mounted) return const [];
      final next = pickPlayQuality(payload, quality?.name);
      final line = pickStreamLine(
        next,
        ref.read(settingsProvider).preferredLineFormat.value,
        site: params.site,
      );
      if (line == null) {
        PlaybackLog.write('resolve_fail', {
          'site': params.site,
          'room': params.roomId,
          'reason': 'no_line',
        });
        return const [];
      }
      // 新地址落回状态:用户随后手动切线路 / 切档时用的才是同一批,
      // 否则又会退回那批过期地址。generation 推进以作废旧异步结果。
      PlaybackLog.write('resolve_ok', {
        'site': params.site,
        'room': params.roomId,
        'quality': next?.name,
        'lines': 1 + _fallbackLines(next, line).length,
        'host': Uri.tryParse(line.url)?.host,
      });
      state = AsyncData(
        current.copyWith(
          payload: payload,
          quality: next,
          line: line,
          generation: ++_generation,
        ),
      );
      // 恢复重解析由播放器内部随后重新 open,先把当前房间的音量/静音语义
      // 套回底层,避免恢复路径只更新线路而丢失控制条状态。
      await _applyRoomVolume(ref.read(playerProvider));
      return [line, ..._fallbackLines(next, line)];
    } catch (error) {
      PlaybackLog.write('resolve_fail', {
        'site': params.site,
        'room': params.roomId,
        'error': '$error',
      });
      return const [];
    }
  }

  /// 回退线路：**恒为空**（用户口径 2026-09-26：去掉线路自动切换）。
  ///
  /// 此前这里把同画质下的其余线路全部作为 mpv 播放列表回退项，某条断流/超时时
  /// mpv 会自动跳到下一条；副作用是**用户手动切了线路后**仍会看到
  /// 「直播地址暂时无法打开，正在切换线路…」并被自动改线，与用户选的那条冲突。
  /// 现在只播用户/策略选中的这一条，失败就如实报错，不偷换线路。
  ///
  /// 底层 [LivePlayer.open] 的 `fallbacks` 形参与 mpv 播放列表能力保留
  /// （属平台层能力，不在本轮拆除），只是不再被喂数据。
  List<StreamLine> _fallbackLines(StreamQuality? quality, StreamLine? line) =>
      const [];

  /// 按偏好挑**可起播**的档位:在 [pickPlayQuality] 结果落在空线路占位档
  /// (懒取流:解析侧只给实给档真实线路,其余档位占位;或服务器把高请求
  /// 档降级到低档)时,回退首个有线路的档 —— 选中占位档会让 line=null,
  /// 进房黑屏且不触发懒取流。pure_live「没有才退」同口径。
  StreamQuality? _pickPlayableQuality(
    RoomPayload payload,
    String? preferredName,
  ) {
    final selected = pickPlayQuality(payload, preferredName);
    if (selected == null || selected.lines.isNotEmpty) return selected;
    return payload.streams.firstWhere(
      (stream) => stream.lines.isNotEmpty,
      orElse: () => selected,
    );
  }
}
