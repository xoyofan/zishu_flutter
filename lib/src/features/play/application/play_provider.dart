/// 播放页编排:播放器单例、快照流与房间播放控制器。
/// 编排规则:解析房间 → 维持选中画质/线路 → 驱动 LivePlayer 开流;
/// 所有竞态用 generation fence 防护,Widget 不直接触碰播放器。
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_parser/live_parser.dart';

import '../../../platforms/common/playback/live_player.dart';
import '../../../platforms/common/playback/media_kit_live_player.dart';
import '../../../shared/application/providers.dart';
import '../../follow/application/settings_provider.dart';

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

  @override
  FutureOr<PlayState> build() async {
    final generation = ++_generation;
    // 数据源端口变化(G1 换真实解析)时自动重建,Widget 无感。
    final source = ref.watch(roomSourceProvider);
    // 默认画质:平台单独配置优先,未配置回落全平台默认(设置页可改)。
    // select 以「该平台生效值」为 key,只有它变化才重建本 family;
    // 房间缺该档时 _pickQuality 回退 streams.first(「没有才退」)。
    final preferredQuality = ref.watch(
      settingsProvider.select(
        (settings) => settings.effectiveDefaultQuality(params.site),
      ),
    );
    final payload = await source.resolveRoom(
      site: params.site,
      roomIdOrUrl: params.roomId,
    );

    // generation fence:等待期间出现了更新的代际(retry 等),丢弃本次结果。
    if (generation != _generation) {
      return state.value ?? PlayState(generation: generation);
    }

    final quality = _pickQuality(payload, preferredQuality);
    final line = quality?.preferredLine;
    final next = PlayState(
      payload: payload,
      quality: quality,
      line: line,
      generation: generation,
    );

    if (!next.isFixture && line != null) {
      // 开流不阻塞状态落地;错误经快照流呈现在舞台 overlay。
      unawaited(ref.read(playerProvider).open(line));
    }
    return next;
  }

  /// 按默认画质挑档:命中同名 stream 则选中它,否则回退到首档。
  ///
  /// 判据用 `streams`(点得动的集合)而非 `availableQualities`,保证
  /// 选中态必然能被 QualityLineBar 渲染成选中 chip;两集合不同源时
  /// 也不会出现「选中了列表外的档」。找不到即回退 `streams.first`,
  /// 不抛错、不提示。
  static StreamQuality? _pickQuality(RoomPayload payload, String? name) {
    if (payload.streams.isEmpty) return null;
    if (name == null) return payload.streams.first;
    for (final stream in payload.streams) {
      if (stream.name == name) return stream;
    }
    return payload.streams.first;
  }

  /// 切换画质:落到该画质首选线路,并代际 +1 后重新开流。
  void switchQuality(StreamQuality quality) {
    final current = state.value;
    if (current == null || current.payload == null) return;
    final line = quality.preferredLine;
    final generation = ++_generation;
    state = AsyncData(
      current.copyWith(quality: quality, line: line, generation: generation),
    );
    _openSelected();
  }

  /// 同画质内切换线路。
  void switchLine(StreamLine line) {
    final current = state.value;
    if (current == null || current.payload == null) return;
    final generation = ++_generation;
    state = AsyncData(current.copyWith(line: line, generation: generation));
    _openSelected();
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

  /// 用最新代际把选中线路送进播放器。
  void _openSelected() {
    final current = state.value;
    final line = current?.line;
    if (current == null || current.isFixture || line == null) return;
    unawaited(ref.read(playerProvider).open(line));
  }
}
