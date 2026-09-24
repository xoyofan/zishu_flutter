import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart' show BoxFit, Widget, SizedBox;
import 'package:flutter_test/flutter_test.dart';
import 'package:live_parser/live_parser.dart';
import 'package:zishu_flutter/src/platforms/common/playback/idle_releasing_live_player.dart';
import 'package:zishu_flutter/src/platforms/common/playback/live_player.dart';
import 'package:zishu_flutter/src/platforms/common/playback/playback_log.dart';

const _line = StreamLine(
  name: 'A',
  url: 'https://example.com/a',
  format: 'hls',
);

void main() {
  late Directory directory;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('idle_player_log');
    PlaybackLog.initForTest(
      '${directory.path}${Platform.pathSeparator}playback.log',
    );
  });
  tearDown(() {
    PlaybackLog.resetForTest();
    directory.deleteSync(recursive: true);
  });

  test('lifecycle events log idle/create/dispose and RSS duration', () async {
    final fake = _FakePlayer();
    final player = IdleReleasingLivePlayer(
      createPlayer: () => fake,
      idleDelay: const Duration(milliseconds: 5),
    );
    final lease = player.enterRoom();
    await player.open(_line);
    await player.leaveRoom(lease);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final text = File('${directory.path}${Platform.pathSeparator}playback.log')
        .readAsStringSync();
    expect(text, contains('player_idle_cancelled'));
    expect(text, contains('player_created'));
    expect(text, contains('player_idle_scheduled'));
    expect(text, contains('player_dispose_start'));
    expect(text, contains('player_dispose_end'));
    expect(text, contains('elapsed_ms='));
    expect(text, contains('rss_mb='));
    player.dispose();
  });

  test('old leave stop is fenced before B open and A-B-C ends at C', () async {
    final fake = _GatedStopPlayer();
    final player = IdleReleasingLivePlayer(createPlayer: () => fake);
    final a = player.enterRoom();
    await player.open(_line);
    fake.gateStop();
    final leavingA = player.leaveRoom(a);
    await fake.stopStarted.future;
    player.enterRoom();
    final openingB = player.open(_line);
    final c = player.enterRoom();
    final openingC = player.open(_line);
    fake.finishStop();
    await leavingA;
    await openingB;
    await openingC;
    expect(fake.stops, 1);
    expect(fake.opens, 2);
    expect(player.activeRoomToken, c);
    expect(player.currentPlayer, same(fake));
    player.dispose();
  });

  test(
    'old leave stop cannot schedule idle timer after rapid re-entry',
    () async {
      final fake = _GatedStopPlayer();
      var releases = 0;
      final player = IdleReleasingLivePlayer(
        createPlayer: () => fake,
        releasePlayer: (_) async {
          releases++;
        },
        idleDelay: const Duration(milliseconds: 5),
      );
      final a = player.enterRoom();
      await player.open(_line);
      fake.gateStop();
      final leaving = player.leaveRoom(a);
      await fake.stopStarted.future;
      player.enterRoom();
      fake.finishStop();
      await leaving;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(releases, 0);
      player.dispose();
    },
  );

  test(
    'root disposal releases an existing player once and rejects later opens',
    () async {
      final fake = _FakePlayer();
      final player = IdleReleasingLivePlayer(createPlayer: () => fake);
      final lease = player.enterRoom();
      await player.open(_line);
      await player.disposeAsync();
      await player.disposeAsync();
      expect(fake.disposes, 1);
      expect(() => player.enterRoom(), throwsStateError);
      await player.open(_line);
      expect(fake.opens, 1);
      expect(fake.disposes, 1);
      await player.leaveRoom(lease);
    },
  );

  test(
    'root disposal waits for in-flight idle release and does not release twice',
    () async {
      final fake = _FakePlayer();
      final gate = Completer<void>();
      var releases = 0;
      final player = IdleReleasingLivePlayer(
        createPlayer: () => fake,
        releasePlayer: (_) async {
          releases++;
          await gate.future;
        },
        idleDelay: const Duration(milliseconds: 5),
      );
      final lease = player.enterRoom();
      await player.open(_line);
      await player.leaveRoom(lease);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final rootRelease = player.disposeAsync();
      expect(rootRelease, same(player.disposeAsync()));
      gate.complete();
      await rootRelease;
      expect(releases, 1);
      expect(fake.disposes, 0); // release callback owns disposal in this test.
    },
  );

  test(
    'recovery handler registered for new lease survives old idle release',
    () async {
      final fake = _AwareFakePlayer();
      final gate = Completer<void>();
      var releases = 0;
      final player = IdleReleasingLivePlayer(
        createPlayer: () => fake,
        releasePlayer: (_) async {
          releases++;
          await gate.future;
        },
        idleDelay: const Duration(milliseconds: 5),
      );
      final a = player.enterRoom();
      await player.open(_line);
      await player.leaveRoom(a);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final b = player.enterRoom();
      player.setLineRecovery(() async => <StreamLine>[]);
      final handler = player.debugRecoveryHandler!;
      gate.complete();
      await Future<void>.delayed(Duration.zero);
      expect(releases, 1);
      expect(fake.handler, same(handler));
      player.clearLineRecovery(a);
      expect(fake.handler, same(handler));
      await player.leaveRoom(b);
      player.dispose();
    },
  );

  test(
    'opening creates one player; leave stops and expiry disposes once',
    () async {
      final fake = _FakePlayer();
      var creates = 0;
      var releases = 0;
      final player = IdleReleasingLivePlayer(
        createPlayer: () {
          creates++;
          return fake;
        },
        releasePlayer: (p) async {
          releases++;
          p.dispose();
        },
        idleDelay: const Duration(milliseconds: 25),
      );
      final lease = player.enterRoom();
      await player.open(_line);
      expect(creates, 1);
      await player.leaveRoom(lease);
      expect(fake.stops, 1);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(releases, 1);
      expect(fake.disposes, 1);
      player.dispose();
    },
  );

  test(
    're-entry cancels release and stale lease does not stop current room',
    () async {
      final fake = _FakePlayer();
      var releases = 0;
      final player = IdleReleasingLivePlayer(
        createPlayer: () => fake,
        releasePlayer: (_) async {
          releases++;
        },
        idleDelay: const Duration(milliseconds: 30),
      );
      final a = player.enterRoom();
      await player.open(_line);
      final b = player.enterRoom();
      await player.leaveRoom(a);
      expect(fake.stops, 0);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(releases, 0);
      await player.leaveRoom(b);
      player.dispose();
    },
  );

  test('idle entry and stop never instantiate a player', () async {
    var created = 0;
    final player = IdleReleasingLivePlayer(
      createPlayer: () {
        created++;
        return _FakePlayer();
      },
    );
    await player.stop();
    expect(created, 0);
    player.dispose();
  });
}

class _GatedStopPlayer extends _FakePlayer {
  Completer<void>? _stopGate;
  final Completer<void> stopStarted = Completer<void>();
  void gateStop() {
    _stopGate = Completer<void>();
  }

  void finishStop() {
    final gate = _stopGate;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  @override
  Future<void> stop() async {
    stops++;
    if (!stopStarted.isCompleted) stopStarted.complete();
    await _stopGate?.future;
  }
}

class _AwareFakePlayer extends _FakePlayer implements LineRecoveryAware {
  LineRecoveryHandler? handler;
  @override
  void setLineRecovery(LineRecoveryHandler? value) {
    handler = value;
  }
}

class _FakePlayer implements LivePlayer {
  int get opens => openCount;
  int openCount = 0;
  int stops = 0;
  int disposes = 0;
  @override
  Stream<PlayerSnapshot> get snapshots => const Stream.empty();
  @override
  Widget buildVideoView({BoxFit fit = BoxFit.contain}) =>
      const SizedBox.shrink();
  @override
  Future<void> open(
    StreamLine line, [
    List<StreamLine> fallbacks = const [],
    bool resetRetries = true,
  ]) async {
    openCount++;
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> setMuted(bool muted) async {}
  @override
  void dispose() {
    disposes++;
  }

  @override
  Widget wrapPipSurface(Widget child) => child;
  @override
  Future<void> setFullscreen(bool fullscreen) async {}
  @override
  Future<void> toggleFullscreen() async {}
  @override
  Future<void> enterPictureInPicture({double? aspectRatio}) async {}
  @override
  Future<void> exitPictureInPicture() async {}
}
