/// 房间独立音量:音量记忆表 + 解析顺序(全局静音 → 房间值 → 默认音量)。
///
/// 对齐上游 pure_live 的 `live_room_volume_manager`:
/// - 存储键 `room_vol_{platform}_{roomId}`(此处 site 即 platform);
/// - 每次写入复制整表再落盘(不可变更新,避免脏引用);
/// - 读档顺序:全局静音 → 房间记忆值 → 默认音量。
///
/// **口径差异(必须注意)**:上游为 0-1,本仓与 `LivePlayer.setVolume` 统一
/// **0-100**,所有读写入口一律钳制到 `SettingsState.volumeMin/Max`。
///
/// 状态真源与持久化 owner 仍是 `settingsProvider`(见 D2):本文件只做
/// 键名/解析/整表写入三件事,避免出现第二份音量状态;`SharedPreferencesAsync`
/// 的读写集中在 settings_provider,写入统一经 `setRoomVolumes`。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../follow/application/settings_provider.dart';

/// 房间音量入参:(site, roomId)。
///
/// 与 `PlayParams` 形状相同(记录类型结构化相等),编排层可直接传 `PlayParams`。
typedef RoomVolumeParams = ({String site, String roomId});

/// 房间音量存储键,对齐上游 `room_vol_{platform}_{roomId}`。
/// 平台名统一小写、两端去空白,避免 `douyu` 与 `DOUYU ` 存成两间。
String roomVolumeKey(String site, String roomId) =>
    'room_vol_${site.toLowerCase().trim()}_${roomId.trim()}';

/// 房间音量解析结果:有效音量(0-100)与是否全局静音。
///
/// 全局静音是独立语义(压过房间值),不能只用「音量 == 0」表达 —— 用户可能
/// 只是把某间拉到 0 而并未开启全局静音。
class RoomVolumeDecision {
  const RoomVolumeDecision({required this.volume, required this.globalMuted});

  /// 有效音量(0-100);全局静音时为 0。
  final double volume;

  /// 是否因全局静音而归零。
  final bool globalMuted;
}

/// 按上游口径解析某房间的有效音量(纯函数,便于单测)。
///
/// 顺序:全局静音 → 房间记忆值 → 默认音量;所有分支输出钳制到 0-100。
RoomVolumeDecision resolveRoomVolume({
  required Map<String, double> roomVolumes,
  required bool globalMuted,
  required double defaultVolume,
  required String site,
  required String roomId,
}) {
  if (globalMuted) {
    return const RoomVolumeDecision(volume: 0, globalMuted: true);
  }
  final remembered = roomVolumes[roomVolumeKey(site, roomId)];
  final volume = (remembered ?? defaultVolume)
      .clamp(SettingsState.volumeMin, SettingsState.volumeMax)
      .toDouble();
  return RoomVolumeDecision(volume: volume, globalMuted: false);
}

/// 生成写盘用的整表 copy:键 `room_vol_{site}_{roomId}` → volume(0-100)。
///
/// 上游 `saveRoomVolume` 同样每次复制整表再写(不可变更新),此处保持同款语义,
/// 只负责算出新表,落盘交给 [RoomVolumeStore]。
Map<String, double> withRoomVolume(
  Map<String, double> current, {
  required String site,
  required String roomId,
  required double volume,
}) {
  final next = Map<String, double>.of(current);
  next[roomVolumeKey(site, roomId)] = volume
      .clamp(SettingsState.volumeMin, SettingsState.volumeMax)
      .toDouble();
  return next;
}

/// 当前房间的音量决策(读设置;开流后由编排层套到播放器)。
final roomVolumeProvider = Provider.family<RoomVolumeDecision, RoomVolumeParams>(
  (ref, params) {
    final settings = ref.watch(settingsProvider);
    return resolveRoomVolume(
      roomVolumes: settings.roomVolumes,
      globalMuted: settings.globalMuted,
      defaultVolume: settings.defaultVolume,
      site: params.site,
      roomId: params.roomId,
    );
  },
);

/// 房间音量写入入口:整表 copy → `settingsProvider.setRoomVolumes` 落盘。
///
/// 做成 Provider 暴露的动作对象,让编排层(Ref)与 Widget(WidgetRef)共用同一
/// 入口 —— 两处的 ref 类型不同(Ref / WidgetRef),把复制逻辑放这里可避免重复。
class RoomVolumeStore {
  RoomVolumeStore(this._ref);

  final Ref _ref;

  /// 记忆某房间的音量(0-100 口径),并立即持久化。
  Future<void> save({
    required String site,
    required String roomId,
    required double volume,
  }) async {
    final current = _ref.read(settingsProvider).roomVolumes;
    await _ref
        .read(settingsProvider.notifier)
        .setRoomVolumes(
          withRoomVolume(current, site: site, roomId: roomId, volume: volume),
        );
  }
}

/// 房间音量写入器(应用级;非 autoDispose,持有 Ref 供任意端调用)。
final roomVolumeStoreProvider = Provider<RoomVolumeStore>(
  RoomVolumeStore.new,
);
