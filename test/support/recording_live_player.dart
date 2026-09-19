import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:live_parser/live_parser.dart';
import 'package:zishu_flutter/src/platforms/common/playback/live_player.dart';

class RecordedOpenCall {
  const RecordedOpenCall({
    required this.line,
    required this.fallbacks,
    required this.resetRetries,
  });

  final StreamLine line;
  final List<StreamLine> fallbacks;
  final bool resetRetries;
}

class RecordingLivePlayer implements LivePlayer {
  final StreamController<PlayerSnapshot> _snapshots =
      StreamController<PlayerSnapshot>.broadcast();
  final List<RecordedOpenCall> openCalls = <RecordedOpenCall>[];
  final List<double> volumeCalls = <double>[];
  final List<bool> mutedCalls = <bool>[];
  final List<bool> fullscreenCalls = <bool>[];
  final List<String> pipCalls = <String>[];
  int stopCalls = 0;
  int playCalls = 0;
  int pauseCalls = 0;
  PlayerSnapshot currentSnapshot = const PlayerSnapshot();
  bool disposed = false;

  @override
  Stream<PlayerSnapshot> get snapshots => _snapshots.stream;

  @override
  Widget buildVideoView({BoxFit fit = BoxFit.contain}) =>
      const SizedBox.expand();

  @override
  Future<void> open(
    StreamLine line, [
    List<StreamLine> fallbacks = const [],
    bool resetRetries = true,
  ]) async {
    openCalls.add(
      RecordedOpenCall(
        line: line,
        fallbacks: List<StreamLine>.of(fallbacks),
        resetRetries: resetRetries,
      ),
    );
  }

  @override
  Future<void> play() async {
    playCalls++;
    _emit(currentSnapshot.copyWith(playing: true));
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    _emit(currentSnapshot.copyWith(playing: false));
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    _emit(
      PlayerSnapshot(
        volume: currentSnapshot.volume,
        muted: currentSnapshot.muted,
      ),
    );
  }

  @override
  Future<void> setVolume(double volume) async {
    final value = volume.clamp(0, 100).toDouble();
    volumeCalls.add(value);
    _emit(
      currentSnapshot.copyWith(
        volume: value,
        muted: value <= 0 && currentSnapshot.muted,
      ),
    );
  }

  @override
  Future<void> setMuted(bool muted) async {
    mutedCalls.add(muted);
    _emit(currentSnapshot.copyWith(muted: muted));
  }

  @override
  Future<void> setFullscreen(bool fullscreen) async {
    fullscreenCalls.add(fullscreen);
  }

  @override
  Future<void> toggleFullscreen() async {
    fullscreenCalls.add(true);
  }

  @override
  Future<void> enterPictureInPicture({double? aspectRatio}) async {
    pipCalls.add('enter');
  }

  @override
  Future<void> exitPictureInPicture() async {
    pipCalls.add('exit');
  }

  @override
  Widget wrapPipSurface(Widget child) => child;

  void emitSnapshot(PlayerSnapshot snapshot) => _emit(snapshot);

  Future<void> waitForCall(String type) async {
    while (true) {
      final found = switch (type) {
        'open' => openCalls.isNotEmpty,
        'volume' => volumeCalls.isNotEmpty,
        'muted' => mutedCalls.isNotEmpty,
        'stop' => stopCalls > 0,
        'play' => playCalls > 0,
        'pause' => pauseCalls > 0,
        _ => false,
      };
      if (found) return;
      await Future<void>.delayed(Duration.zero);
    }
  }

  @override
  void dispose() {
    if (disposed) return;
    disposed = true;
    unawaited(_snapshots.close());
  }

  void _emit(PlayerSnapshot snapshot) {
    currentSnapshot = snapshot;
    if (!_snapshots.isClosed) _snapshots.add(snapshot);
  }
}
