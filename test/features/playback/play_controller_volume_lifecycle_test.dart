import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_parser/live_parser.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:zishu_flutter/src/features/follow/application/settings_provider.dart';
import 'package:zishu_flutter/src/features/play/application/play_provider.dart';
import 'package:zishu_flutter/src/shared/application/browse_source.dart';
import 'package:zishu_flutter/src/shared/application/providers.dart';
import 'package:zishu_flutter/src/platforms/common/playback/live_player.dart';

import '../../support/scripted_live_player.dart';

class _RoutingRoomSource implements RoomSource, RoomRecoverer {
  int recoverCalls = 0;

  @override
  Future<RoomPayload> resolveRoom({
    required String site,
    required String roomIdOrUrl,
    String? preferredQuality,
  }) async => _payload(roomIdOrUrl, site: site);

  @override
  Future<RoomPayload> recoverRoom({
    required String site,
    required String roomIdOrUrl,
    String? preferredQuality,
  }) async {
    recoverCalls++;
    return _payload('$roomIdOrUrl-recovered', site: site);
  }
}

class _RecoveringScriptedLivePlayer extends ScriptedLivePlayer
    implements LineRecoveryAware {
  LineRecoveryHandler? recovery;

  @override
  void setLineRecovery(LineRecoveryHandler? handler) => recovery = handler;

  Future<void> recoverAndOpen() async {
    final handler = recovery;
    if (handler == null) throw StateError('recovery handler not installed');
    final lines = await handler();
    if (lines.isEmpty) throw StateError('recovery returned no lines');
    await open(lines.first, lines.skip(1).toList());
  }
}

RoomPayload _payload(String roomId, {String site = 'douyu'}) => RoomPayload(
  site: site,
  roomId: roomId,
  sourceUrl: 'https://$site.example.com/$roomId',
  anchorName: '主播 $roomId',
  title: '直播 $roomId',
  cover: '',
  avatar: '',
  category: '测试',
  cid: '1',
  roomState: RoomState.live,
  streams: [
    StreamQuality(
      name: '高清',
      rate: 0,
      lines: [
        StreamLine(
          name: 'FLV',
          url: 'https://cdn.example.com/$site/$roomId.flv',
          format: 'flv',
        ),
      ],
    ),
  ],
  availableQualities: const [QualityOption(name: '高清', rate: 0)],
  source: 'test',
  fetchedAt: DateTime.fromMillisecondsSinceEpoch(0),
);

Future<ProviderContainer> _makeContainer({
  required Map<String, double> roomVolumes,
  required ScriptedLivePlayer player,
  RoomSource? source,
  bool globalMuted = false,
}) async {
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.withData({
        'zishu.settings.roomVolumes': jsonEncode(roomVolumes),
        'zishu.settings.globalMuted': globalMuted,
      });
  final container = ProviderContainer(
    overrides: [
      playerProvider.overrideWithValue(player),
      roomSourceProvider.overrideWithValue(source ?? _RoutingRoomSource()),
    ],
  );
  addTearDown(container.dispose);
  final settings = container.read(settingsProvider);
  for (var i = 0; i < 20 && !settings.hydrated; i++) {
    await Future<void>.delayed(Duration.zero);
    if (container.read(settingsProvider).hydrated) break;
  }
  expect(container.read(settingsProvider).hydrated, isTrue);
  return container;
}

Future<void> _startRoom(
  ProviderContainer container,
  PlayParams params,
  ScriptedLivePlayer player, {
  required int expectedOpenCount,
  required int expectedVolumeCount,
}) async {
  final keepAlive = container.listen(
    playControllerProvider(params),
    (_, _) {},
    fireImmediately: true,
  );
  addTearDown(keepAlive.close);
  final stateFuture = container.read(playControllerProvider(params).future);
  await stateFuture;
  for (var i = 0; i < 20 && player.openCalls.length < expectedOpenCount; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  for (
    var i = 0;
    i < 20 && player.volumeCalls.length < expectedVolumeCount;
    i++
  ) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test(
    're-parsing after a disconnect keeps the room volume and mute state',
    () async {
      final player = _RecoveringScriptedLivePlayer();
      final source = _RoutingRoomSource();
      final container = await _makeContainer(
        roomVolumes: {'room_vol_douyu_A': 35},
        globalMuted: true,
        player: player,
        source: source,
      );
      final params = (site: 'douyu', roomId: 'A');
      final keepAlive = container.listen(
        playControllerProvider(params),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(keepAlive.close);
      await container.read(playControllerProvider(params).future);
      for (var i = 0; i < 20 && player.mutedCalls.isEmpty; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      player.resetUnderlyingVolume(100);

      await player.recoverAndOpen();
      for (var i = 0; i < 20 && player.openCalls.length < 2; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      final state = container.read(playControllerProvider(params)).requireValue;
      expect(source.recoverCalls, 1);
      expect(state.payload?.roomId, 'A-recovered');
      expect(state.generation, 2);
      expect(player.mutedCalls, [true, true]);
      expect(player.currentSnapshot.muted, isTrue);
    },
  );

  test('global mute remains effective after switching rooms', () async {
    final player = ScriptedLivePlayer();
    final container = await _makeContainer(
      roomVolumes: {'room_vol_douyu_A': 35, 'room_vol_douyu_B': 62},
      player: player,
    );
    final settings = container.read(settingsProvider.notifier);
    await _startRoom(
      container,
      (site: 'douyu', roomId: 'A'),
      player,
      expectedOpenCount: 1,
      expectedVolumeCount: 2,
    );
    await settings.setGlobalMuted(true);
    await _startRoom(
      container,
      (site: 'douyu', roomId: 'B'),
      player,
      expectedOpenCount: 2,
      expectedVolumeCount: 2,
    );

    expect(player.mutedCalls, [true]);
    expect(player.volumeCalls, [35, 35]);
    expect(player.currentSnapshot.volume, 35);
    expect(player.currentSnapshot.muted, isTrue);
  });

  test(
    'rapid A to B to C switching leaves only C generation, volume and snapshot',
    () async {
      final player = ScriptedLivePlayer()..gateNextOpen();
      final a = await _makeContainer(
        roomVolumes: {
          'room_vol_douyu_A': 11,
          'room_vol_douyu_B': 22,
          'room_vol_douyu_C': 33,
        },
        player: player,
      );
      final b = await _makeContainer(
        roomVolumes: {
          'room_vol_douyu_A': 11,
          'room_vol_douyu_B': 22,
          'room_vol_douyu_C': 33,
        },
        player: player,
      );
      final c = await _makeContainer(
        roomVolumes: {
          'room_vol_douyu_A': 11,
          'room_vol_douyu_B': 22,
          'room_vol_douyu_C': 33,
        },
        player: player,
      );
      final aKeepAlive = a.listen(
        playControllerProvider((site: 'douyu', roomId: 'A')),
        (_, _) {},
        fireImmediately: true,
      );
      final bKeepAlive = b.listen(
        playControllerProvider((site: 'douyu', roomId: 'B')),
        (_, _) {},
        fireImmediately: true,
      );
      final cKeepAlive = c.listen(
        playControllerProvider((site: 'douyu', roomId: 'C')),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(() {
        aKeepAlive.close();
        bKeepAlive.close();
        cKeepAlive.close();
      });
      final aFuture = a.read(
        playControllerProvider((site: 'douyu', roomId: 'A')).future,
      );
      final bFuture = b.read(
        playControllerProvider((site: 'douyu', roomId: 'B')).future,
      );
      final cFuture = c.read(
        playControllerProvider((site: 'douyu', roomId: 'C')).future,
      );
      await player.openStarted;
      await Future<void>.delayed(Duration.zero);
      aKeepAlive.close();
      bKeepAlive.close();
      player.completeOpen();
      await Future.wait([aFuture, bFuture, cFuture]);
      for (var i = 0; i < 20 && player.volumeCalls.length < 4; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      final state = c
          .read(playControllerProvider((site: 'douyu', roomId: 'C')))
          .requireValue;
      expect(state.generation, 1);
      expect(state.payload?.roomId, 'C');
      expect(player.currentSnapshot.volume, 33);
      expect(player.volumeCalls, [11, 22, 33, 33]);
      expect(player.openCalls.map((call) => call.line.url), [
        'https://cdn.example.com/douyu/A.flv',
        'https://cdn.example.com/douyu/B.flv',
        'https://cdn.example.com/douyu/C.flv',
      ]);
    },
  );

  test('re-applies the current room volume after open resets the underlying player', () async {
    final player = ScriptedLivePlayer()..gateNextOpen();
    final container = await _makeContainer(
      roomVolumes: {'room_vol_douyu_A': 35},
      player: player,
    );
    final params = (site: 'douyu', roomId: 'A');
    final keepAlive = container.listen(
      playControllerProvider(params),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(keepAlive.close);
    final stateFuture = container.read(playControllerProvider(params).future);
    await player.openStarted;

    for (var i = 0; i < 20 && player.volumeCalls.isEmpty; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(player.volumeCalls, [35]);

    player.resetUnderlyingVolume(100);
    player.completeOpen();
    await stateFuture;
    for (var i = 0; i < 20 && player.volumeCalls.length < 2; i++) {
      await Future<void>.delayed(Duration.zero);
    }

    expect(player.volumeCalls, [35, 35]);
    expect(player.currentSnapshot.volume, 35);
  });

  test('switching rooms applies each room volume instead of leaking the previous room', () async {
    final player = ScriptedLivePlayer();
    final container = await _makeContainer(
      roomVolumes: {'room_vol_douyu_A': 35, 'room_vol_douyu_B': 62},
      player: player,
    );
    await _startRoom(
      container,
      (site: 'douyu', roomId: 'A'),
      player,
      expectedOpenCount: 1,
      expectedVolumeCount: 2,
    );
    await _startRoom(
      container,
      (site: 'douyu', roomId: 'B'),
      player,
      expectedOpenCount: 2,
      expectedVolumeCount: 4,
    );

    expect(player.volumeCalls, [35, 35, 62, 62]);
    expect(player.currentSnapshot.volume, 62);
  });

  test(
    'entering a never-set room applies the factory default 100, not the previous room value',
    () async {
      // BUG-WIN-VOLUME-002 / VOL-001:房 A 记忆 36.8,全新房 B 无记忆,
      // 进 B 必须把播放器套到出厂默认 100,不得继承 A 的值。
      final player = ScriptedLivePlayer();
      final container = await _makeContainer(
        roomVolumes: {'room_vol_douyu_A': 36.8},
        player: player,
      );
      await _startRoom(
        container,
        (site: 'douyu', roomId: 'A'),
        player,
        expectedOpenCount: 1,
        expectedVolumeCount: 2,
      );
      await _startRoom(
        container,
        (site: 'huya', roomId: '709107'),
        player,
        expectedOpenCount: 2,
        expectedVolumeCount: 4,
      );

      expect(player.volumeCalls, [36.8, 36.8, 100, 100]);
      expect(player.currentSnapshot.volume, 100);
    },
  );

  test('returning to the first room restores its remembered volume', () async {
    final player = ScriptedLivePlayer();
    final first = await _makeContainer(
      roomVolumes: {'room_vol_douyu_A': 35, 'room_vol_douyu_B': 62},
      player: player,
    );
    final second = await _makeContainer(
      roomVolumes: {'room_vol_douyu_A': 35, 'room_vol_douyu_B': 62},
      player: player,
    );
    final third = await _makeContainer(
      roomVolumes: {'room_vol_douyu_A': 35, 'room_vol_douyu_B': 62},
      player: player,
    );
    addTearDown(player.dispose);

    await _startRoom(
      first,
      (site: 'douyu', roomId: 'A'),
      player,
      expectedOpenCount: 1,
      expectedVolumeCount: 2,
    );
    await _startRoom(
      second,
      (site: 'douyu', roomId: 'B'),
      player,
      expectedOpenCount: 2,
      expectedVolumeCount: 4,
    );
    await _startRoom(
      third,
      (site: 'douyu', roomId: 'A'),
      player,
      expectedOpenCount: 3,
      expectedVolumeCount: 6,
    );

    expect(player.volumeCalls, [35, 35, 62, 62, 35, 35]);
    expect(player.currentSnapshot.volume, 35);
  });

  test(
    'same room id on different platforms keeps independent volume values',
    () async {
      final player = ScriptedLivePlayer();
      final container = await _makeContainer(
        roomVolumes: {'room_vol_douyu_123': 35, 'room_vol_huya_123': 71},
        player: player,
      );
      await _startRoom(
        container,
        (site: 'douyu', roomId: '123'),
        player,
        expectedOpenCount: 1,
        expectedVolumeCount: 2,
      );
      await _startRoom(
        container,
        (site: 'huya', roomId: '123'),
        player,
        expectedOpenCount: 2,
        expectedVolumeCount: 4,
      );

      expect(player.volumeCalls, [35, 35, 71, 71]);
      expect(player.currentSnapshot.volume, 71);
    },
  );

  test(
    'global mute overrides each room volume and sends mute to the player',
    () async {
      final player = ScriptedLivePlayer();
      final container = await _makeContainer(
        roomVolumes: {'room_vol_douyu_A': 35},
        globalMuted: true,
        player: player,
      );
      await _startRoom(
        container,
        (site: 'douyu', roomId: 'A'),
        player,
        expectedOpenCount: 1,
        expectedVolumeCount: 0,
      );
      expect(player.mutedCalls, [true]);
      expect(player.currentSnapshot.muted, isTrue);
    },
  );

  test(
    'remembered room volume zero is not converted into global mute',
    () async {
      final player = ScriptedLivePlayer();
      final container = await _makeContainer(
        roomVolumes: {'room_vol_douyu_A': 0},
        player: player,
      );
      await _startRoom(
        container,
        (site: 'douyu', roomId: 'A'),
        player,
        expectedOpenCount: 1,
        expectedVolumeCount: 2,
      );
      expect(player.mutedCalls, isEmpty);
      expect(player.currentSnapshot.muted, isFalse);
    },
  );
}
