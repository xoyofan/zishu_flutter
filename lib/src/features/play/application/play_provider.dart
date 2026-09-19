/// 播放页编排:播放器单例、快照流与房间播放控制器。
/// 编排规则:解析房间 → 维持选中画质/线路 → 驱动 LivePlayer 开流;
/// 所有竞态用 generation fence 防护,Widget 不直接触碰播放器。
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_parser/live_parser.dart';

import '../../../platforms/common/playback/live_player.dart';
import '../../../platforms/common/playback/media_kit_live_player.dart';
import '../../../platforms/common/playback/playback_log.dart';
import '../../../shared/application/browse_source.dart';
import '../../../shared/application/providers.dart';
import '../../follow/application/settings_provider.dart';
import 'play_selection.dart';
import 'room_volume_provider.dart';

/// 播放器单例:app 生命周期内复用,不随页面销毁。
/// dispose 由根 ProviderContainer 统一触发(仅 app 退出时执行)。
final playerProvider = Provider<LivePlayer>((ref) {
  final player = MediaKitLivePlayer();
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

class PlayController extends AsyncNotifier<PlayState> {
  PlayController(this.params);

  final PlayParams params;

  int _generation = 0;

  /// 用户手动切档后的偏好覆盖(懒取流):切换到的档位若未预取线路,以此档
  /// 重新解析,解析侧只取该档,避免整房全档取流。
  String? _qualityOverride;

  @override
  FutureOr<PlayState> build() async {
    final generation = ++_generation;
    // 离开播放页(autoDispose 触发)→ 停止全局播放器:直播不得在后台继续出声/出画。
    // 仅卸载媒体源,不 dispose 实例(下次进房复用同一 Player)。捕获实例而非在
    // 回调里 ref.read,避免 provider 销毁期再去读依赖。
    final player = ref.read(playerProvider);
    ref.onDispose(() {
      // 先注销恢复回调再 stop:回调是播放器持有的**指向本 controller** 的活引用,
      // autoDispose 后播放器仍可能在自动重连里调用它,而那时 ref/state 已失效
      // (`_recoverLines` 读 state 会报 “Cannot use Ref after dispose”)。
      // 回调只能在本层注销 —— 播放器不知道宿主已离场。
      if (player case LineRecoveryAware aware) {
        aware.setLineRecovery(null);
      }
      unawaited(player.stop());
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
    final payload = await source.resolveRoom(
      site: params.site,
      roomIdOrUrl: params.roomId,
      preferredQuality: preferredQuality,
    );

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
    }
    return next;
  }

  /// 切换画质:已预取线路则直接开流;懒取流的档位(空线路占位)以其为偏好
  /// 重新解析,解析侧只取该档后自动开流。线路选取遵循线路格式偏好。
  void switchQuality(StreamQuality quality) {
    final current = state.value;
    if (current == null || current.payload == null) return;
    final line = pickStreamLine(
      quality,
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
      current.copyWith(quality: quality, line: line, generation: generation),
    );
    _open(line, _fallbackLines(quality, line));
  }

  /// 同画质内切换线路。
  void switchLine(StreamLine line) {
    final current = state.value;
    if (current == null || current.payload == null) return;
    final generation = ++_generation;
    state = AsyncData(current.copyWith(line: line, generation: generation));
    unawaited(
      ref
          .read(playerProvider)
          .open(line, _fallbackLines(current.quality, line)),
    );
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
    // LineRecoveryAware 不是 LivePlayer 的子类型,is 探测不产生类型提升,
    // 用 if-case 对象模式探测并绑定(免显式 as)。
    if (player case LineRecoveryAware aware) {
      aware.setLineRecovery(_recoverLines);
    }
    final generation = _generation;
    unawaited(_openAndApplyVolume(player, line, fallbacks, generation));
  }

  /// 等待媒体源真正落地后再补套一次房间音量。
  ///
  /// `open` 可能重建底层音频管线并把音量恢复为默认 100。开流前套用一次
  /// 可以尽快反馈 UI，开流完成后再套用一次才是最终一致性保证。代际检查
  /// 防止旧房间的异步收尾覆盖当前房间。
  Future<void> _openAndApplyVolume(
    LivePlayer player,
    StreamLine line,
    List<StreamLine> fallbacks,
    int generation,
  ) async {
    // 先应用一次，让控制条和播放器尽快进入当前房间状态。
    await _applyRoomVolume(player);
    await player.open(line, fallbacks);
    if (!ref.mounted || generation != _generation) return;
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

  /// 同画质下除 [line] 外的线路,作为 mpv 播放列表回退线路
  /// (参考 pure_live 的线路自动切换)。无画质或线路时返回空列表。
  List<StreamLine> _fallbackLines(StreamQuality? quality, StreamLine? line) {
    if (quality == null || line == null) return const [];
    return [
      for (final candidate in quality.lines)
        if (candidate.url != line.url) candidate,
    ];
  }

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
