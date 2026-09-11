/// LivePlayer 的 media_kit 实现:封装 Player + VideoController,
/// 把 Player.stream.* 事件归一为 PlayerSnapshot;静音语义由本类维护
/// (media_kit 无独立 muted 事件流,以 volume=0 模拟并记忆原音量)。
library;

import 'dart:async';

import 'package:flutter/widgets.dart' show BoxFit, Widget;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';
import 'package:live_parser/live_parser.dart' show StreamLine;

import 'live_player.dart';

class MediaKitLivePlayer implements LivePlayer {
  MediaKitLivePlayer() {
    _wire();
  }

  final Player _player = Player();
  late final VideoController _videoController = VideoController(_player);

  /// 向 UI 广播的快照流。
  final StreamController<PlayerSnapshot> _output =
      StreamController<PlayerSnapshot>.broadcast();

  /// 最近一次发出的快照,用于合并去重。
  PlayerSnapshot _latest = const PlayerSnapshot();

  bool _muted = false;

  /// 静音前音量,解除静音时恢复。
  double _volumeBeforeMute = 100;

  final List<StreamSubscription<void>> _subscriptions = [];

  void _wire() {
    final events = _player.stream;
    void bind<T>(Stream<T> source, PlayerSnapshot Function(PlayerSnapshot, T) patch) {
      _subscriptions.add(source.listen((value) => _emit((snapshot) => patch(snapshot, value))));
    }

    bind(events.playing, (s, v) => s.copyWith(playing: v));
    bind(events.buffering, (s, v) => s.copyWith(buffering: v));
    bind(events.volume, (s, v) => s.copyWith(volume: v));
    bind(events.width, (s, v) => s.copyWith(width: v));
    bind(events.height, (s, v) => s.copyWith(height: v));
    // 错误统一归一为快照字段;copyWith 无法回置 null,空串需显式重建清错。
    bind(events.error, (s, v) {
      if (v.isEmpty) {
        return PlayerSnapshot(
          playing: s.playing,
          buffering: s.buffering,
          volume: s.volume,
          muted: s.muted,
          width: s.width,
          height: s.height,
        );
      }
      return s.copyWith(error: v);
    });
  }

  /// 以 [mutate] 生成新快照,仅在发生变化时广播。
  void _emit(PlayerSnapshot Function(PlayerSnapshot) mutate) {
    if (_output.isClosed) return;
    final next = mutate(_latest);
    if (next == _latest) return;
    _latest = next;
    _output.add(next);
  }

  @override
  Stream<PlayerSnapshot> get snapshots => _output.stream;

  @override
  Widget buildVideoView({BoxFit fit = BoxFit.contain}) {
    // 不启用内置控制条(由 play feature 的控制条接管),其余用库默认。
    return Video(controller: _videoController, fit: fit, controls: null);
  }

  @override
  Future<void> open(StreamLine line) async {
    // 切源即重置快照:清错误、退出播放态,进入缓冲。
    _emit(
      (_) => PlayerSnapshot(
        volume: _latest.volume,
        muted: _muted,
        buffering: true,
      ),
    );
    try {
      await _player.open(Media(line.url, httpHeaders: line.headers), play: true);
    } catch (error) {
      _emit((snapshot) => snapshot.copyWith(error: '播放失败:$error'));
    }
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> setVolume(double volume) async {
    final clamped = volume.clamp(0, 100).toDouble();
    // 手动拉起音量即解除静音;静音状态下置 0 则维持静音语义。
    _muted = _muted && clamped <= 0;
    if (!_muted && clamped > 0) _volumeBeforeMute = clamped;
    await _player.setVolume(clamped);
    _emit((snapshot) => snapshot.copyWith(muted: _muted));
  }

  @override
  Future<void> setMuted(bool muted) async {
    if (muted == _muted) return;
    _muted = muted;
    if (muted) {
      if (_latest.volume > 0) _volumeBeforeMute = _latest.volume;
      await _player.setVolume(0);
    } else {
      await _player.setVolume(_volumeBeforeMute <= 0 ? 100 : _volumeBeforeMute);
    }
    _emit((snapshot) => snapshot.copyWith(muted: muted));
  }

  @override
  Future<void> toggleFullscreen() async {
    // Windows 桌面全屏:取当前状态再取反。VM / 无窗口环境(单测注入 Fake 时
    // 不调用本实现,这里仍做静默降级,避免原生插件不可用时抛错)。
    try {
      await windowManager.setFullScreen(!await windowManager.isFullScreen());
    } catch (_) {
      // 平台不支持 / 插件未就绪:静默降级,不阻断上层沉浸态切换。
    }
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    unawaited(_output.close());
    unawaited(_player.dispose());
  }
}
