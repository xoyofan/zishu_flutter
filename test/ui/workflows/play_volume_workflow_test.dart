import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:zishu_flutter/src/features/follow/application/settings_provider.dart';
import 'package:zishu_flutter/src/features/play/widgets/player_controls.dart';
import 'package:zishu_flutter/src/features/play/application/play_provider.dart';
import 'package:zishu_flutter/src/platforms/common/playback/play_screen_mode.dart';
import 'package:zishu_flutter/src/platforms/common/playback/live_player.dart';

import '../../support/recording_live_player.dart';

void main() {
  late RecordingLivePlayer player;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData(<String, Object>{});
    player = RecordingLivePlayer();
  });

  tearDown(() => player.dispose());

  Future<ProviderContainer> pumpControls(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [playerProvider.overrideWithValue(player)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1000,
              height: 100,
              child: PlayerControlsBar(
                site: 'douyu',
                roomId: '63136',
                showDanmaku: true,
                danmakuEnabled: true,
                speechCaptionEnabled: false,
                screenMode: PlayScreenMode.normal,
                onDanmakuToggle: () {},
                onCaptionToggle: () {},
                onToggleWidescreen: () {},
                onToggleFullscreen: () {},
                onTogglePip: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return container;
  }

  testWidgets('slider reflects the current player snapshot volume', (
    tester,
  ) async {
    await pumpControls(tester);
    player.emitSnapshot(const PlayerSnapshot(volume: 42));
    await tester.pump();
    await tester.pump();

    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.value, 42);
  });

  testWidgets('dragging the slider persists the current room volume', (
    tester,
  ) async {
    final container = await pumpControls(tester);
    player.emitSnapshot(const PlayerSnapshot(volume: 42));
    await tester.pump();
    await tester.pump();

    final sliderFinder = find.byType(Slider);
    await tester.drag(sliderFinder, const Offset(24, 0));
    await tester.pump();

    expect(player.volumeCalls, isNotEmpty);
    final applied = player.volumeCalls.last;
    final settings = container.read(settingsProvider);
    expect(
      settings.roomVolumes['room_vol_douyu_63136'],
      applied,
      reason: '拖动播放器音量后应同步写入当前房间音量表',
    );
  });

  testWidgets('mute and unmute keep the slider value tied to player state', (
    tester,
  ) async {
    await pumpControls(tester);
    player.emitSnapshot(const PlayerSnapshot(volume: 42));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const Key('play-toggle-mute')));
    await tester.pump();
    expect(tester.widget<Slider>(find.byType(Slider)).value, 0);

    await tester.tap(find.byKey(const Key('play-toggle-mute')));
    await tester.pump();
    expect(player.mutedCalls, [true, false]);
  });
}
