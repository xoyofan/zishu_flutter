import 'dart:async';

import 'package:live_parser/live_parser.dart';

import 'recording_live_player.dart';

class ScriptedLivePlayer extends RecordingLivePlayer {
  final Completer<void> _openStarted = Completer<void>();
  Completer<void>? _openGate;
  bool openCompleted = false;

  Future<void> get openStarted => _openStarted.future;

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
    if (!_openStarted.isCompleted) _openStarted.complete();
    final gate = _openGate;
    if (gate != null) await gate.future;
    openCompleted = true;
  }

  void gateNextOpen() {
    _openGate = Completer<void>();
    openCompleted = false;
  }

  void completeOpen() {
    final gate = _openGate;
    _openGate = null;
    if (gate != null && !gate.isCompleted) gate.complete();
    openCompleted = true;
  }

  void resetUnderlyingVolume(double volume) {
    emitSnapshot(currentSnapshot.copyWith(volume: volume, muted: false));
  }
}
