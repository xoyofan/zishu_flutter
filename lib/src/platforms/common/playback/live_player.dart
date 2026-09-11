/// 播放器抽象:业务层(feature/controller)只依赖此接口,
/// media_kit 等平台播放细节全部封装在各实现内。
/// 本文件位于 platforms 适配层,允许依赖 Flutter 基础 Widget,但禁止反向
/// 被"解析核心"(packages/live_parser)依赖。
library;

import 'package:flutter/widgets.dart' show BoxFit, Size, Widget;
import 'package:live_parser/live_parser.dart' show StreamLine;

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

  Size? get size =>
      width == null || height == null ? null : Size(width!.toDouble(), height!.toDouble());

  PlayerSnapshot copyWith({
    bool? playing,
    bool? buffering,
    double? volume,
    bool? muted,
    int? width,
    int? height,
    String? error,
  }) {
    return PlayerSnapshot(
      playing: playing ?? this.playing,
      buffering: buffering ?? this.buffering,
      volume: volume ?? this.volume,
      muted: muted ?? this.muted,
      width: width ?? this.width,
      height: height ?? this.height,
      error: error ?? this.error,
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
  int get hashCode => Object.hash(playing, buffering, volume, muted, width, height, error);

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
  Future<void> open(StreamLine line);

  Future<void> play();

  Future<void> pause();

  /// 停止并卸载当前媒体源(画面与声音一并退出),但保留播放器实例以便复用。
  /// 离开播放页时由控制器调用,避免直播在后台继续出声。
  Future<void> stop();

  /// 设置音量(0-100);拉起音量应解除静音语义。
  Future<void> setVolume(double volume);

  Future<void> setMuted(bool muted);

  /// 可选:切换全屏。实现未支持时保持空操作。
  Future<void> toggleFullscreen() async {}

  /// 释放底层资源。全局播放器由应用根统一管理生命周期。
  void dispose();
}
