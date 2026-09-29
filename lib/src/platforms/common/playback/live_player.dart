/// 播放器抽象:业务层(feature/controller)只依赖此接口,
/// media_kit 等平台播放细节全部封装在各实现内。
/// 本文件位于 platforms 适配层,允许依赖 Flutter 基础 Widget,但禁止反向
/// 被"解析核心"(packages/live_parser)依赖。
library;

import 'package:flutter/widgets.dart' show BoxFit, Size, Widget;
import 'package:live_parser/live_parser.dart' show StreamLine;

import 'player_error.dart';

/// [PlayerSnapshot.copyWith] 的"未显式传入"哨兵。
///
/// [PlayerSnapshot.error] 是唯一可空字段:若直接以 `null` 作默认值,
/// `copyWith(error: null)` 与"不修改 error"无法区分,导致**错误一旦出现就
/// 永远清不掉**(播放恢复后错误卡片仍悬在画面上)。传哨兵即可区分二者:
/// 不传 = 保持原值,null = 显式清空。
const Object _kErrorUnset = Object();

/// 播放过程中向用户公开的脱敏状态。UI 只映射稳定枚举，不展示 mpv 原始诊断、
/// 完整 URL、query/token 或 HTTP headers。
enum PlaybackNotice {
  none,
  networkJitter,
  sourceOpenFailed,
  reconnecting,
  recoveringNewUrl,
}

/// 播放状态快照:由实现把底层事件流归一后发出。
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
    this.errorKind = PlayerErrorKind.none,
    this.retryAttempt = 0,
    this.retryLimit = 0,
    this.notice = PlaybackNotice.none,
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

  /// [error] 的语义类别,供 UI 决定处置提示(见 [playerErrorHint])。
  /// 与 [error] 同步维护:[error] 为 null 时恒为 [PlayerErrorKind.none]。
  final PlayerErrorKind errorKind;

  /// 已进行的自动重连次数(0 表示当前流健康或尚未失败)。
  final int retryAttempt;

  /// 自动重连次数上限(由重连策略给出);0 表示该实现不做自动重连。
  final int retryLimit;

  /// 当前卡顿/恢复阶段；不包含任何原始诊断或敏感播放地址。
  final PlaybackNotice notice;

  /// 是否正处于自动重连过程中(有错误且计数已推进)。
  bool get reconnecting => retryAttempt > 0 && error != null;

  Size? get size => width == null || height == null
      ? null
      : Size(width!.toDouble(), height!.toDouble());

  /// [error] 传 `null` 表示**显式清空**错误;不传则保持原值(见 [_kErrorUnset])。
  /// 清空时 [errorKind] 一并归位,避免"没错误却有类别"的漂移态。
  PlayerSnapshot copyWith({
    bool? playing,
    bool? buffering,
    double? volume,
    bool? muted,
    int? width,
    int? height,
    Object? error = _kErrorUnset,
    PlayerErrorKind? errorKind,
    int? retryAttempt,
    int? retryLimit,
    PlaybackNotice? notice,
  }) {
    final clearing = identical(error, _kErrorUnset)
        ? this.error == null
        : error == null;
    return PlayerSnapshot(
      playing: playing ?? this.playing,
      buffering: buffering ?? this.buffering,
      volume: volume ?? this.volume,
      muted: muted ?? this.muted,
      width: width ?? this.width,
      height: height ?? this.height,
      error: identical(error, _kErrorUnset) ? this.error : error as String?,
      errorKind: clearing ? PlayerErrorKind.none : errorKind ?? this.errorKind,
      retryAttempt: retryAttempt ?? this.retryAttempt,
      retryLimit: retryLimit ?? this.retryLimit,
      notice: notice ?? this.notice,
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
          other.error == error &&
          other.errorKind == errorKind &&
          other.retryAttempt == retryAttempt &&
          other.retryLimit == retryLimit &&
          other.notice == notice;

  @override
  int get hashCode => Object.hash(
    playing,
    buffering,
    volume,
    muted,
    width,
    height,
    error,
    errorKind,
    retryAttempt,
    retryLimit,
    notice,
  );

  @override
  String toString() =>
      'PlayerSnapshot(playing: $playing, buffering: $buffering, volume: $volume, '
      'muted: $muted, size: ${width}x$height, error: $error, '
      'errorKind: $errorKind, retry: $retryAttempt/$retryLimit, '
      'notice: ${notice.name})';
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

  /// [LivePlayer] 不直接承载"取消自动重连":接口新增成员会波及全部
  /// `implements` 替身(测试里有 25+ 个)。改为能力接口 [RecoveryCancellable],
  /// UI 用 `is` 探测后调用,不支持该能力的实现(含替身)零改动。

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

/// 线路恢复回调:返回**重新解析**后的一组线路(首选在前,其余作回退)。
/// 为空列表表示宿主无法提供(非真实解析源 / 解析失败),播放器应走放弃分支。
typedef LineRecoveryHandler = Future<List<StreamLine>> Function();

/// 可选能力:自动重连耗尽时向宿主请求「重新解析」后的线路。
///
/// 为什么需要它:签名平台(虎牙)的播放地址带时效参数,其生命周期**短于**
/// 观看会话。播放器内部所有重连用的都是开流时那一批地址,地址过期后就会
/// 反复重开一个失效源(症状:流反复中断、每次都在重试却永远起不来)。
/// 正解是回到解析层重新取地址(见 live_parser 的 `RoomRecoveryResolver`)。
///
/// 刻意做成**独立接口**而非往 [LivePlayer] 加方法:全仓有 20+ 个测试替身
/// 实现 [LivePlayer],往接口上添成员会强制它们全部跟进;恢复能力只有真实
/// media_kit 实现需要,以可选能力暴露即可由宿主按需探测。
abstract interface class LineRecoveryAware {
  /// 注册恢复回调;传 `null` 关闭恢复能力。
  void setLineRecovery(LineRecoveryHandler? handler);
}

/// 可动态切换视频硬件解码的播放器能力。
abstract interface class VideoHardwareAccelerationAware {
  /// enabled=true 使用 `hwdec=auto-safe`；false 强制 `hwdec=no`。
  void setVideoHardwareAcceleration(bool enabled);
}

/// 可选能力:用户主动取消自动重连(卡顿浮层上的 X)。
///
/// 语义:停止当前卡顿重试/恢复流程并置闩锁,**不轮转线路、不重新解析**;
/// 之后的 [LivePlayer.play] / 手动 retry / `open(resetRetries: true)` 解除。
/// 同 [LineRecoveryAware] 的理由做成独立接口:UI 用 `is` 探测后调用,
/// 不支持的实现(含全部测试替身)零改动。
abstract interface class RecoveryCancellable {
  void cancelRecovery();
}

