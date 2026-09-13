/// 播放器抽象:业务层(feature/controller)只依赖此接口,
/// media_kit 等平台播放细节全部封装在各实现内。
/// 本文件位于 platforms 适配层,允许依赖 Flutter 基础 Widget,但禁止反向
/// 被"解析核心"(packages/live_parser)依赖。
library;

import 'package:flutter/widgets.dart' show BoxFit, Size, Widget;
import 'package:live_parser/live_parser.dart' show StreamLine;

/// [PlayerSnapshot.copyWith] 的"未显式传入"哨兵。
///
/// [PlayerSnapshot.error] 是唯一可空字段:若直接以 `null` 作默认值,
/// `copyWith(error: null)` 与"不修改 error"无法区分,导致**错误一旦出现就
/// 永远清不掉**(播放恢复后错误卡片仍悬在画面上)。传哨兵即可区分二者:
/// 不传 = 保持原值,null = 显式清空。
const Object _kErrorUnset = Object();

/// 播放器状态快照:由实现把底层事件流归一后发出。
/// 带字段级相等性,便于下游做去重与 UI 局部重建。
class PlayerSnapshot {
  const PlayerSnapshot({
    this.playing = false,
    this.buffering = false,
    this.volume = 100,
    this.muted = false,
    this.width,
    this.height,
    this.error,
  });

  /// 是否正在播放。
  final bool playing;

  /// 是否处于缓冲中。
  final bool buffering;

  /// 音量(0-100,与底层播放器惯例对齐)。
  final double volume;

  /// 是否静音(由实现自行维护,底层无独立事件流)。
  final bool muted;

  /// 视频宽高(尚未出画面前为 null)。
  final int? width;
  final int? height;

  /// 最近一次归一化错误文案;null 表示无错误。
  final String? error;

  Size? get size => width == null || height == null
      ? null
      : Size(width!.toDouble(), height!.toDouble());

  /// [error] 传 `null` 表示**显式清空**错误;不传则保持原值(见 [_kErrorUnset])。
  PlayerSnapshot copyWith({
    bool? playing,
    bool? buffering,
    double? volume,
    bool? muted,
    int? width,
    int? height,
    Object? error = _kErrorUnset,
  }) {
    return PlayerSnapshot(
      playing: playing ?? this.playing,
      buffering: buffering ?? this.buffering,
      volume: volume ?? this.volume,
      muted: muted ?? this.muted,
      width: width ?? this.width,
      height: height ?? this.height,
      error: identical(error, _kErrorUnset) ? this.error : error as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlayerSnapshot &&
          other.playing == playing &&
          other.buffering == buffering &&
          other.volume == volume &&
          other.muted == muted &&
          other.width == width &&
          other.height == height &&
          other.error == error;

  @override
  int get hashCode =>
      Object.hash(playing, buffering, volume, muted, width, height, error);

  @override
  String toString() =>
      'PlayerSnapshot(playing: $playing, buffering: $buffering, volume: $volume, '
      'muted: $muted, size: ${width}x$height, error: $error)';
}

/// 直播播放器统一接口。
abstract class LivePlayer {
  /// 归一化后的播放状态快照流。
  Stream<PlayerSnapshot> get snapshots;

  /// 构建视频画面 Widget(各实现负责给出平台对应的渲染视图)。
  /// UI 层只负责摆放,不得接触底层播放器类型。
  Widget buildVideoView({BoxFit fit});

  /// 打开一条线路并开始播放(替换当前媒体源)。
  ///
  /// [fallbacks] 为同画质下的其余线路:整组会拼成 mpv 播放列表一次打开,
  /// 某条断流/超时时 mpv 自动跳到下一条(参考 pure_live 的线路自动切换),
  /// 无需 Flutter 侧轮询即可跨线路容错。无回退线路时退化为单线播放。
  /// [resetRetries] 为 false 时不清空自动重连计数(看门狗内部重连使用)。
  Future<void> open(
    StreamLine line, [
    List<StreamLine> fallbacks = const [],
    bool resetRetries = true,
  ]);

  Future<void> play();

  Future<void> pause();

  /// 停止并卸载当前媒体源(画面与声音一并退出),但保留播放器实例以便复用。
  /// 离开播放页时由控制器调用,避免直播在后台继续出声。
  Future<void> stop();

  /// 设置音量(0-100);拉起音量应解除静音语义。
  Future<void> setVolume(double volume);

  Future<void> setMuted(bool muted);

  /// 幂等设置系统窗口全屏。调用方已经知道目标态时用本方法,而非"切换":
  /// 切换语义在 UI 态与窗口态漂移时会反向操作窗口(旧实现的错位根因)。
  /// 实现未支持时保持空操作。
  Future<void> setFullscreen(bool fullscreen) async {}

  /// 兼容"切换"语义的调用点保留;实现层按当前窗口态取反。
  /// 新代码应优先用 [setFullscreen]。
  Future<void> toggleFullscreen() async {}

  /// 进入画中画:把应用窗口缩成置顶小窗(仅桌面实现,其余平台空操作)。
  /// [aspectRatio] 为视频宽高比(宽/高),用于小窗尺寸。
  Future<void> enterPictureInPicture({double? aspectRatio}) async {}

  /// 退出画中画并恢复进入前的窗口几何与置顶态。
  Future<void> exitPictureInPicture() async {}

  /// 给画中画内容套上「桌面窗口外壳」:窗口边缘拖拽/缩放热区等原生窗口交互。
  ///
  /// 默认直接透传子级。桌面实现返回带原生交互的包壳——这笔依赖只能落在
  /// 平台层:实现它的 Widget(如 window_manager 的 `DragToResizeArea`)会
  /// 传递性引入 `dart:io`,而播放页 UI 是三端共享的,不能在共享依赖图里
  /// 出现 `dart:io`(Web 端会直接编译失败)。
  Widget wrapPipSurface(Widget child) => child;

  /// 释放底层资源。全局播放器由应用根统一管理生命周期。
  void dispose();
}
