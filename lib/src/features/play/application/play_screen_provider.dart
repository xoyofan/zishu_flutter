/// 播放页窗口呈现编排:三态(normal / widescreen / fullscreen)+ 画中画。
///
/// **单一真源**:本条 provider 是播放页唯一的呈现态来源——布局、控制条图标、
/// 控制条自动隐藏、快捷键分派、平台窗口调用全部由它派生。旧实现把沉浸态放在
/// `PlayView` 的本地 bool、把窗口全屏放在播放器里,两边互不感知,直接导致
/// 「点全屏按钮窗口全屏了但界面还是普通布局」「F 键只全屏窗口不进沉浸态」
/// 「退出时 toggle 反向」三类错位。对齐参考实现 pure_live 的做法:
/// `LivePlayController.ui.screenMode`(单一状态)+ `toggleFullScreen()`(单一入口)。
///
/// 生命周期:`autoDispose` —— 离开播放页(不再有 listener)即销毁,并在
/// [Ref.onDispose] 里把系统窗口全屏 / PiP 收干净。销毁时**不经过 ref**
/// (捕获播放器实例 + 镜像状态字段),因为 onDispose 期间 ref 已失效。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../platforms/common/playback/live_player.dart' show LivePlayer;
import '../../../platforms/common/playback/play_screen_mode.dart';
import 'play_provider.dart';

/// Esc 在播放页的分派目标(对齐参考实现的 `resolveEscapePresentationAction`)。
enum EscapePresentationAction {
  none,
  exitPip,
  exitFullscreen,
  exitWidescreen,
  popRoute,
}

/// Esc 分派规则(纯函数,便于单测):画中画 > 全屏 > 网页全屏 > 返回上一页。
@visibleForTesting
EscapePresentationAction resolveEscapePresentationAction({
  required bool pip,
  required bool fullscreen,
  required bool widescreen,
}) {
  if (pip) return EscapePresentationAction.exitPip;
  if (fullscreen) return EscapePresentationAction.exitFullscreen;
  if (widescreen) return EscapePresentationAction.exitWidescreen;
  return EscapePresentationAction.popRoute;
}

/// 播放页呈现状态:三态 + PiP(含进入 PiP 前的呈现态记忆)。
@immutable
class PlayScreenState {
  const PlayScreenState({
    this.mode = PlayScreenMode.normal,
    this.pip = false,
    this.modeBeforePip = PlayScreenMode.normal,
  });

  final PlayScreenMode mode;

  /// 是否处于画中画小窗(与 [PlayScreenMode] 正交:PiP 期间呈现态被临时覆盖)。
  final bool pip;

  /// 进入 PiP 前的呈现态,退出 PiP 时还原。
  final PlayScreenMode modeBeforePip;

  /// 是否隐藏页面 chrome(房间头/侧栏)并启用控制条自动隐藏。
  bool get hidesChrome => pip || mode.hidesChrome;

  bool get isFullscreen => mode == PlayScreenMode.fullscreen;
  bool get isWidescreen => mode == PlayScreenMode.widescreen;

  PlayScreenState copyWith({
    PlayScreenMode? mode,
    bool? pip,
    PlayScreenMode? modeBeforePip,
  }) {
    return PlayScreenState(
      mode: mode ?? this.mode,
      pip: pip ?? this.pip,
      modeBeforePip: modeBeforePip ?? this.modeBeforePip,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlayScreenState &&
          other.mode == mode &&
          other.pip == pip &&
          other.modeBeforePip == modeBeforePip;

  @override
  int get hashCode => Object.hash(mode, pip, modeBeforePip);

  @override
  String toString() =>
      'PlayScreenState(mode: ${mode.name}, pip: $pip, '
      'modeBeforePip: ${modeBeforePip.name})';
}

final playScreenProvider =
    NotifierProvider.autoDispose<PlayScreenController, PlayScreenState>(
      PlayScreenController.new,
    );

class PlayScreenController extends Notifier<PlayScreenState> {
  /// 状态镜像:onDispose 与异步续段里不读 `state`/`ref`(provider 可能已销毁)。
  PlayScreenState _mirror = const PlayScreenState();

  @override
  PlayScreenState build() {
    final player = ref.read(playerProvider);
    // 离开播放页(provider 销毁)= 把窗口呈现收干净:全屏与 PiP 都是窗口级副作用,
    // 不清会残留到其它页面。这里用捕获的播放器实例 + 镜像状态,不触碰 ref。
    ref.onDispose(() => _restoreWindow(player, _mirror));
    return _mirror;
  }

  /// 同步镜像并落状态。
  void _set(PlayScreenState next) {
    _mirror = next;
    state = next;
  }

  /// 当前播放器;provider 已销毁时返回 null(异步续段防御)。
  LivePlayer? get _player => ref.mounted ? ref.read(playerProvider) : null;

  /// 切换到 [mode]:先落 UI 态(布局立刻响应),再幂等驱动系统窗口全屏。
  /// PiP 期间切呈现态视为"退出 PiP 并切到目标态"。
  Future<void> apply(PlayScreenMode mode) async {
    final player = _player;
    if (player == null) return;
    final previous = _mirror;
    final wasPip = previous.pip;
    if (!wasPip && previous.mode == mode) return;
    _set(wasPip ? PlayScreenState(mode: mode) : previous.copyWith(mode: mode));
    if (wasPip) {
      await player.exitPictureInPicture();
      if (!ref.mounted) return;
    }
    await player.setFullscreen(mode.wantsSystemFullscreen);
  }

  Future<void> enterFullscreen() => apply(PlayScreenMode.fullscreen);

  Future<void> enterWidescreen() => apply(PlayScreenMode.widescreen);

  /// 退出任一呈现态,回到常规布局(同时复位系统窗口全屏)。
  Future<void> exitPresentation() => apply(PlayScreenMode.normal);

  /// 全屏按钮:常规 ⇄ 全屏;网页全屏态按「升级为全屏」处理(与参考实现一致)。
  Future<void> toggleFullscreen() => apply(
    _mirror.isFullscreen ? PlayScreenMode.normal : PlayScreenMode.fullscreen,
  );

  /// 网页全屏按钮:常规 ⇄ 网页全屏。
  Future<void> toggleWidescreen() => apply(
    _mirror.isWidescreen ? PlayScreenMode.normal : PlayScreenMode.widescreen,
  );

  Future<void> togglePip() => _mirror.pip ? exitPip() : enterPip();

  /// 进入画中画:记住当前呈现态 → 先退出系统全屏(小窗不能是全屏窗口)→ 缩窗置顶。
  Future<void> enterPip() async {
    final player = _player;
    if (player == null || _mirror.pip) return;
    _set(_mirror.copyWith(pip: true, modeBeforePip: _mirror.mode));
    await player.setFullscreen(false);
    if (!ref.mounted) return;
    await player.enterPictureInPicture();
  }

  /// 退出画中画:恢复进入前的呈现态(含系统窗口全屏)与窗口几何。
  Future<void> exitPip() async {
    final player = _player;
    if (player == null || !_mirror.pip) return;
    final restore = _mirror.modeBeforePip;
    _set(
      PlayScreenState(
        mode: restore,
        pip: false,
        modeBeforePip: PlayScreenMode.normal,
      ),
    );
    await player.exitPictureInPicture();
    if (!ref.mounted) return;
    await player.setFullscreen(restore.wantsSystemFullscreen);
  }

  /// Esc 分派:退出一层呈现态。返回 true 表示已被消费(调用方不再放行)。
  /// 常规态返回 false —— 是否「返回上一页」由页面决定,不在此处越权导航。
  Future<bool> handleEscape() async {
    final action = resolveEscapePresentationAction(
      pip: _mirror.pip,
      fullscreen: _mirror.isFullscreen,
      widescreen: _mirror.isWidescreen,
    );
    switch (action) {
      case EscapePresentationAction.exitPip:
        await exitPip();
        return true;
      case EscapePresentationAction.exitFullscreen:
      case EscapePresentationAction.exitWidescreen:
        await exitPresentation();
        return true;
      case EscapePresentationAction.none:
      case EscapePresentationAction.popRoute:
        return false;
    }
  }
}

/// 把窗口呈现复位到常规态:只调平台层,不触碰 provider。
void _restoreWindow(LivePlayer player, PlayScreenState snapshot) {
  if (snapshot.pip) {
    unawaited(player.exitPictureInPicture());
  }
  if (snapshot.mode.wantsSystemFullscreen) {
    unawaited(player.setFullscreen(false));
  }
}
