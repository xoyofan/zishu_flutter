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

class _QualityRoomSource implements RoomSource {
  @override
  Future<RoomPayload> resolveRoom({
    required String site,
    required String roomIdOrUrl,
    String? preferredQuality,
  }) async => RoomPayload(
    site: site,
    roomId: roomIdOrUrl,
    sourceUrl: 'https://$site.example.com/$roomIdOrUrl',
    anchorName: '主播',
    title: '标题',
    cover: '',
    avatar: '',
    category: '测试',
    cid: '1',
    roomState: RoomState.live,
    streams: const [
      StreamQuality(
        name: '高清',
        rate: 1,
        lines: [
          StreamLine(name: 'HLS', url: 'https://cdn/a.m3u8', format: 'hls'),
          StreamLine(name: 'FLV', url: 'https://cdn/a.flv', format: 'flv'),
        ],
      ),
      StreamQuality(
        name: '超清',
        rate: 2,
        lines: [
          StreamLine(name: 'HLS', url: 'https://cdn/b.m3u8', format: 'hls'),
          StreamLine(name: 'FLV', url: 'https://cdn/b.flv', format: 'flv'),
        ],
      ),
    ],
    availableQualities: [
      QualityOption(name: '高清', rate: 1),
      QualityOption(name: '超清', rate: 2),
    ],
    source: 'test',
    fetchedAt: DateTime.fromMillisecondsSinceEpoch(0),
  );
}

Future<
  ({ProviderContainer container, ScriptedLivePlayer player, PlayParams params})
>
_start() async {
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.withData({
        'zishu.settings.roomVolumes': jsonEncode({'room_vol_douyu_1': 37}),
        'zishu.settings.preferredLineFormat': 'flv',
      });
  final player = ScriptedLivePlayer();
  final container = ProviderContainer(
    overrides: [
      playerProvider.overrideWithValue(player),
      roomSourceProvider.overrideWithValue(_QualityRoomSource()),
    ],
  );
  final params = (site: 'douyu', roomId: '1');
  final settings = container.read(settingsProvider);
  for (var i = 0; i < 20 && !settings.hydrated; i++) {
    await Future<void>.delayed(Duration.zero);
    if (container.read(settingsProvider).hydrated) break;
  }
  expect(container.read(settingsProvider).hydrated, isTrue);
  final keepAlive = container.listen(
    playControllerProvider(params),
    (_, _) {},
    fireImmediately: true,
  );
  await container.read(playControllerProvider(params).future);
  for (var i = 0; i < 20 && player.volumeCalls.length < 2; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  // keepAlive is intentionally held until the caller disposes the container.
  // ignore: unused_local_variable
  final _ = keepAlive;
  return (container: container, player: player, params: params);
}

void main() {
  test(
    'quality switch keeps line format, room volume and generation monotonic',
    () async {
      final started = await _start();
      addTearDown(() {
        started.container.dispose();
        started.player.dispose();
      });
      final controller = started.container.read(
        playControllerProvider(started.params).notifier,
      );
      final before = started.container
          .read(playControllerProvider(started.params))
          .requireValue;

      controller.switchQuality(before.payload!.streams[1]);
      for (var i = 0; i < 20 && started.player.openCalls.length < 2; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      for (var i = 0; i < 20 && started.player.volumeCalls.length < 4; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      final after = started.container
          .read(playControllerProvider(started.params))
          .requireValue;
      expect(after.quality?.name, '超清');
      expect(after.line?.format, 'flv');
      expect(after.generation, greaterThan(before.generation));
      expect(started.player.volumeCalls, [37, 37, 37, 37]);
      expect(started.player.currentSnapshot.volume, 37);
    },
  );

  test(
    'line switch uses the same lifecycle volume and recovery path',
    () async {
      final started = await _start();
      addTearDown(() {
        started.container.dispose();
        started.player.dispose();
      });
      final controller = started.container.read(
        playControllerProvider(started.params).notifier,
      );
      final before = started.container
          .read(playControllerProvider(started.params))
          .requireValue;
      final hls = before.quality!.lines.first;

      controller.switchLine(hls);
      for (var i = 0; i < 20 && started.player.openCalls.length < 2; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      for (var i = 0; i < 20 && started.player.volumeCalls.length < 4; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      final after = started.container
          .read(playControllerProvider(started.params))
          .requireValue;
      expect(after.line?.format, 'hls');
      expect(after.quality?.name, before.quality?.name);
      expect(after.generation, greaterThan(before.generation));
      expect(started.player.volumeCalls, [37, 37, 37, 37]);
      expect(started.player.currentSnapshot.volume, 37);
    },
  );
}
