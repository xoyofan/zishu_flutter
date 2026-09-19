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

import '../../support/scripted_live_player.dart';

class _RoutingRoomSource implements RoomSource {
  @override
  Future<RoomPayload> resolveRoom({
    required String site,
    required String roomIdOrUrl,
    String? preferredQuality,
  }) async => _payload(roomIdOrUrl, site: site);
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
      roomSourceProvider.overrideWithValue(_RoutingRoomSource()),
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
