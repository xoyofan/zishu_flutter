import 'package:flutter_test/flutter_test.dart';
import 'package:zishu_flutter/src/features/follow/application/settings_provider.dart';
import 'package:zishu_flutter/src/features/play/application/room_volume_provider.dart';

const _sites = <String>[
  'douyu',
  'huya',
  'bilibili',
  'douyin',
  'kuaishou',
  'yy',
  'twitch',
  'soop',
  'youtube',
];

void main() {
  group('roomVolumeKey', () {
    test(
      'normalizes platform and room whitespace/case for every registered site',
      () {
        for (final site in _sites) {
          expect(
            roomVolumeKey(' ${site.toUpperCase()} ', '  room-7 '),
            'room_vol_${site}_room-7',
            reason: site,
          );
        }
      },
    );

    test('isolates same room id across platforms', () {
      expect(
        roomVolumeKey('douyu', '123'),
        isNot(roomVolumeKey('huya', '123')),
      );
    });

    test('isolates different room ids on the same platform', () {
      expect(
        roomVolumeKey('douyu', '123'),
        isNot(roomVolumeKey('douyu', '456')),
      );
    });
  });

  group('resolveRoomVolume', () {
    test('uses the remembered value for each platform and room', () {
      for (final site in _sites) {
        final key = roomVolumeKey(site, 'room-7');
        final decision = resolveRoomVolume(
          roomVolumes: {key: 37},
          globalMuted: false,
          defaultVolume: 82,
          site: site,
          roomId: 'room-7',
        );
        expect(decision.volume, 37, reason: site);
        expect(decision.globalMuted, isFalse, reason: site);
      }
    });

    test(
      'falls back to the default value when a room has no remembered value',
      () {
        for (final site in _sites) {
          final decision = resolveRoomVolume(
            roomVolumes: const {},
            globalMuted: false,
            defaultVolume: 64,
            site: site,
            roomId: 'room-7',
          );
          expect(decision.volume, 64, reason: site);
        }
      },
    );

    test(
      'a remembered room never becomes the default of a never-set room '
      '(BUG-WIN-VOLUME-002 / VOL-001)',
      () {
        // 真机口径:房 A 调过 36.8 后,进从未设置过音量的全新房 B,
        // B 必须用出厂默认 100,不得把 A 的记忆值当 B 的默认。
        final roomVolumes = {
          roomVolumeKey('douyu', '24422'): 36.8,
          roomVolumeKey('twitch', 'zackrawrr'): 86.8,
        };
        final decision = resolveRoomVolume(
          roomVolumes: roomVolumes,
          globalMuted: false,
          defaultVolume: SettingsState.defaultVolumeLevel,
          site: 'huya',
          roomId: '709107',
        );
        expect(decision.volume, 100);
        expect(decision.globalMuted, isFalse);
      },
    );

    test('global mute overrides remembered and default volume', () {
      for (final site in _sites) {
        final decision = resolveRoomVolume(
          roomVolumes: {roomVolumeKey(site, 'room-7'): 37},
          globalMuted: true,
          defaultVolume: 82,
          site: site,
          roomId: 'room-7',
        );
        expect(decision.volume, 0, reason: site);
        expect(decision.globalMuted, isTrue, reason: site);
      }
    });

    test('clamps remembered and default values to 0..100', () {
      expect(
        resolveRoomVolume(
          roomVolumes: {roomVolumeKey('douyu', 'low'): -20},
          globalMuted: false,
          defaultVolume: 50,
          site: 'douyu',
          roomId: 'low',
        ).volume,
        0,
      );
      expect(
        resolveRoomVolume(
          roomVolumes: {roomVolumeKey('douyu', 'high'): 140},
          globalMuted: false,
          defaultVolume: 50,
          site: 'douyu',
          roomId: 'high',
        ).volume,
        100,
      );
      expect(
        resolveRoomVolume(
          roomVolumes: const {},
          globalMuted: false,
          defaultVolume: 140,
          site: 'douyu',
          roomId: 'default-high',
        ).volume,
        100,
      );
      expect(
        resolveRoomVolume(
          roomVolumes: const {},
          globalMuted: false,
          defaultVolume: -20,
          site: 'douyu',
          roomId: 'default-low',
        ).volume,
        0,
      );
    });

    test('a remembered volume of zero is not global mute', () {
      final decision = resolveRoomVolume(
        roomVolumes: {roomVolumeKey('douyu', 'silent'): 0},
        globalMuted: false,
        defaultVolume: 80,
        site: 'douyu',
        roomId: 'silent',
      );
      expect(decision.volume, 0);
      expect(decision.globalMuted, isFalse);
    });
  });

  group('withRoomVolume', () {
    test('copies the table without mutating the existing map', () {
      final current = <String, double>{roomVolumeKey('douyu', 'a'): 20};
      final next = withRoomVolume(
        current,
        site: 'huya',
        roomId: 'b',
        volume: 55,
      );

      expect(current, {roomVolumeKey('douyu', 'a'): 20});
      expect(next, {
        roomVolumeKey('douyu', 'a'): 20,
        roomVolumeKey('huya', 'b'): 55,
      });
    });

    test('clamps values written for every platform', () {
      for (final site in _sites) {
        final next = withRoomVolume(
          const {},
          site: site,
          roomId: 'room-7',
          volume: 200,
        );
        expect(next[roomVolumeKey(site, 'room-7')], 100, reason: site);
      }
    });
  });
}
