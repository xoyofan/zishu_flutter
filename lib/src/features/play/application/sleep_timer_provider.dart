/// 睡眠定时器:到点停止播放。
///
/// **为什么必须是 app 级 provider(非 autoDispose)**:播放编排
/// `playControllerProvider` 是 `autoDispose.family`,离开播放页即销毁;
/// 若定时器挂在它身上,用户离房(或切页)时会被一并清掉 —— 而睡眠定时的
/// 使用场景恰恰是「设完定时后不再盯着播放页」。故本 provider 挂在应用根
/// 容器上,生命周期与 [playerProvider] 一致(仅 app 退出时释放)。
///
/// 对齐上游 pure_live `live_audio_handler.configureSleepTimer`:起定时器前先
/// cancel 旧的;到点执行 stop,并在 stop 路径里 cancel 定时器防「复活」。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'play_provider.dart';

/// 睡眠定时状态;[endsAt] 为到点时刻(null 表示未启用)。
@immutable
class SleepTimerState {
  const SleepTimerState({this.endsAt, this.remaining, this.firedCount = 0});

  /// 到点时刻;null 表示当前未启用定时。
  final DateTime? endsAt;

  /// 剩余时长(由 1s 心跳推进,供 UI 显示);未启用时为 null。
  final Duration? remaining;

  /// 已到点次数:每次到点 +1,UI 据此弹一次提示(单调递增,不随取消归零)。
  final int firedCount;

  /// 是否处于启用态。
  bool get active => endsAt != null;

  /// 剩余时间文案(`mm:ss`,满 1 小时为 `h:mm:ss`);未启用返回空串。
  String get remainingLabel {
    final value = remaining;
    if (value == null) return '';
    final total = value.inSeconds <= 0 ? 0 : value.inSeconds;
    final hours = total ~/ 3600;
    final minutes = (total % 3600) ~/ 60;
    final seconds = total % 60;
    final mm = minutes.toString().padLeft(2, '0');
    final ss = seconds.toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SleepTimerState &&
          other.endsAt == endsAt &&
          other.remaining == remaining &&
          other.firedCount == firedCount;

  @override
  int get hashCode => Object.hash(endsAt, remaining, firedCount);
}

/// 睡眠定时控制器(应用级)。
class SleepTimerController extends Notifier<SleepTimerState> {
  /// 常用预设(分钟):UI 菜单直接消费,避免两处各写一份。
  static const List<int> presetsMinutes = [15, 30, 60, 90, 120];

  /// 自定义时长上限(分钟):12 小时,防手滑输入超大值挂在内存里。
  static const int maxCustomMinutes = 720;

  Timer? _deadline;

  /// 1s 心跳:只用于推进 UI 剩余时间,不参与到点判定(到点由 [_deadline] 负责)。
  Timer? _ticker;

  @override
  SleepTimerState build() {
    ref.onDispose(_cancelTimers);
    return const SleepTimerState();
  }

  /// 设定定时;时长 ≤ 0 等同取消。
  void start(Duration duration) {
    if (duration <= Duration.zero) {
      cancel();
      return;
    }
    // 起新定时前先 cancel 旧的(上游同款,避免双定时器同时到点)。
    _cancelTimers();
    state = SleepTimerState(
      endsAt: DateTime.now().add(duration),
      remaining: duration,
      firedCount: state.firedCount,
    );
    _deadline = Timer(duration, () => unawaited(_fire()));
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  /// 取消定时:清掉定时器与心跳,状态回到未启用(不触发停止播放)。
  void cancel() {
    _cancelTimers();
    state = SleepTimerState(firedCount: state.firedCount);
  }

  void _tick() {
    final remaining = state.remaining;
    if (remaining == null) return;
    // 只为 UI 进度:递减显示值,不参与到点判定(判定唯一由 [_deadline] 负责)。
    // 不用 `endsAt - DateTime.now()`:那会把显示绑到墙钟上,定时器被节流的
    // 环境下会瞬间跳一大段。
    final next = remaining - const Duration(seconds: 1);
    if (next <= Duration.zero) return;
    state = SleepTimerState(
      endsAt: state.endsAt,
      remaining: next,
      firedCount: state.firedCount,
    );
  }

  /// 到点:先 cancel 定时器(防复活)再停播;firedCount +1 供 UI 弹提示。
  Future<void> _fire() async {
    _cancelTimers();
    state = SleepTimerState(firedCount: state.firedCount + 1);
    await ref.read(playerProvider).stop();
  }

  void _cancelTimers() {
    _deadline?.cancel();
    _deadline = null;
    _ticker?.cancel();
    _ticker = null;
  }
}

/// 睡眠定时 provider(应用级,非 autoDispose —— 见文件头说明)。
final sleepTimerProvider =
    NotifierProvider<SleepTimerController, SleepTimerState>(
      SleepTimerController.new,
    );
