import 'package:flutter_test/flutter_test.dart';
import 'package:live_parser/live_parser.dart';
import 'package:zishu_flutter/src/platforms/common/playback/live_player.dart';

import 'recording_live_player.dart';
import 'scripted_live_player.dart';

void main() {
  const line = StreamLine(
    name: '线路 A',
    url: 'https://cdn.example.com/live.flv',
    format: 'flv',
  );

  test(
    'RecordingLivePlayer records commands and exposes final snapshot',
    () async {
      final player = RecordingLivePlayer();
      addTearDown(player.dispose);

      await player.open(line);
      await player.setVolume(35);
      await player.setMuted(true);
      await player.stop();

      expect(player.openCalls, hasLength(1));
      expect(player.openCalls.single.line.url, line.url);
      expect(player.volumeCalls, [35]);
      expect(player.mutedCalls, [true]);
      expect(player.stopCalls, 1);
      expect(player.currentSnapshot.volume, 35);
      expect(player.currentSnapshot.muted, true);
    },
  );

  test(
    'RecordingLivePlayer clamps volume to the shared 0..100 contract',
    () async {
      final player = RecordingLivePlayer();
      addTearDown(player.dispose);

      await player.setVolume(-10);
      await player.setVolume(120);

      expect(player.volumeCalls, [0, 100]);
      expect(player.currentSnapshot.volume, 100);
    },
  );

  test(
    'ScriptedLivePlayer can gate open and simulate an underlying volume reset',
    () async {
      final player = ScriptedLivePlayer();
      addTearDown(player.dispose);

      player.gateNextOpen();
      final openFuture = player.open(line);
      await player.openStarted;
      expect(player.openCalls, hasLength(1));
      expect(player.openCompleted, isFalse);

      player.resetUnderlyingVolume(100);
      player.completeOpen();
      await openFuture;

      expect(player.openCompleted, isTrue);
      expect(player.currentSnapshot.volume, 100);
    },
  );

  test('recorded snapshot stream emits state changes', () async {
    final player = RecordingLivePlayer();
    addTearDown(player.dispose);
    final snapshots = <PlayerSnapshot>[];
    final subscription = player.snapshots.listen(snapshots.add);
    addTearDown(subscription.cancel);

    await player.setVolume(42);
    await player.setMuted(true);

    expect(snapshots.last.volume, 42);
    expect(snapshots.last.muted, true);
  });
}
