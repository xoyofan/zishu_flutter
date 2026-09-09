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
  const PlayState({this.payload, this.quality, this.line, this.generation = 0});

  final RoomPayload? payload;
  final StreamQuality? quality;
  final StreamLine? line;

  /// 代际计数:切房/重解析/切换画质或线路时 +1,
  /// 旧异步回调回来后 generation 不匹配即丢弃。
  final int generation;

  /// fixture 数据不进真实播放器,舞台显示占位。
  bool get isFixture => payload?.source == 'fixture';

  PlayState copyWith({
    RoomPayload? payload,
    StreamQuality? quality,
    StreamLine? line,
    int? generation,
  }) {
    return PlayState(
      payload: payload ?? this.payload,
      quality: quality ?? this.quality,
      line: line ?? this.line,
      generation: generation ?? this.generation,
    );
  }
}

/// 播放页控制器:family by (site, roomId);autoDispose 随页面离开释放状态,
/// 但全局播放器实例不在此销毁。
final playControllerProvider =
    AsyncNotifierProvider.autoDispose.family<PlayController, PlayState, PlayParams>(
      PlayController.new,
    );

class PlayController extends AsyncNotifier<PlayState> {
  PlayController(this.params);

  final PlayParams params;

  int _generation = 0;

  @override
  FutureOr<PlayState> build() async {
    final generation = ++_generation;
    // 数据源端口变化(G1 换真实解析)时自动重建,Widget 无感。
    final source = ref.watch(roomSourceProvider);
    final payload = await source.resolveRoom(
      site: params.site,
      roomIdOrUrl: params.roomId,
    );

    // generation fence:等待期间出现了更新的代际(retry 等),丢弃本次结果。
    if (generation != _generation) {
      return state.value ?? PlayState(generation: generation);
    }

    final quality = payload.streams.isEmpty ? null : payload.streams.first;
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
