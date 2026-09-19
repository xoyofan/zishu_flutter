import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:live_parser/live_parser.dart' show StreamLine;
import 'package:zishu_flutter/src/app/app_theme.dart';

import 'package:zishu_flutter/src/features/follow/application/settings_provider.dart';

import 'package:zishu_flutter/src/features/play/application/play_provider.dart';
import 'package:zishu_flutter/src/features/play/application/play_screen_provider.dart';

import 'package:zishu_flutter/src/platforms/common/playback/live_player.dart';
import 'package:zishu_flutter/src/platforms/common/playback/play_screen_mode.dart';

class _RecordingPlayer implements LivePlayer {
  final calls = <String>[];

  @override
  Stream<PlayerSnapshot> get snapshots =>
      Stream<PlayerSnapshot>.value(const PlayerSnapshot());

  @override
  Widget buildVideoView({BoxFit fit = BoxFit.contain}) =>
      const SizedBox.expand();

  @override
  Future<void> open(
    StreamLine line, [
    List<StreamLine> fallbacks = const [],
    bool resetRetries = true,
  ]) async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> setMuted(bool muted) async {}

  @override
  Future<void> toggleFullscreen() async {}

  @override
  Future<void> setFullscreen(bool fullscreen) async {
    calls.add('fullscreen:$fullscreen');
  }

  @override
  Future<void> enterPictureInPicture({double? aspectRatio}) async {
    calls.add('pip:enter');
  }

  Completer<void>? exitPipGate;

  @override
  Future<void> exitPictureInPicture() async {
    calls.add('pip:exit');
    await exitPipGate?.future;
  }

  @override
  Future<void> stop() async {}

  @override
  Widget wrapPipSurface(Widget child) => child;

  @override
  void dispose() {}
}

void main() {
  test('退出 PiP 后清除 modeBeforePip 状态记忆', () async {
    final player = _RecordingPlayer();
    final container = ProviderContainer(
      overrides: [playerProvider.overrideWithValue(player)],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      playScreenProvider,
      (_, _) {},
      fireImmediately: true,
    );

    final controller = container.read(playScreenProvider.notifier);
    await controller.enterFullscreen();
    await controller.enterPip();
    await controller.exitPip();

    expect(
      container.read(playScreenProvider),
      const PlayScreenState(
        mode: PlayScreenMode.fullscreen,
        pip: false,
        modeBeforePip: PlayScreenMode.normal,
      ),
    );
    expect(player.calls, [
      'fullscreen:true',
      'fullscreen:false',
      'pip:enter',
      'pip:exit',
      'fullscreen:true',
    ]);
    subscription.close();
  });

  test('退出 PiP 优先恢复进入前的系统全屏状态', () async {
    final player = _RecordingPlayer();
    final container = ProviderContainer(
      overrides: [playerProvider.overrideWithValue(player)],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      playScreenProvider,
      (_, _) {},
      fireImmediately: true,
    );

    final controller = container.read(playScreenProvider.notifier);
    await controller.enterWidescreen();
    await controller.enterPip();
    await controller.exitPip();

    expect(container.read(playScreenProvider).mode, PlayScreenMode.widescreen);
    expect(container.read(playScreenProvider).pip, isFalse);
    expect(player.calls, [
      'fullscreen:false',
      'fullscreen:false',
      'pip:enter',
      'pip:exit',
      'fullscreen:false',
    ]);
    subscription.close();
  });

  test('播放页 provider 销毁时清理 PiP 和系统全屏副作用', () async {
    final player = _RecordingPlayer();
    final container = ProviderContainer(
      overrides: [playerProvider.overrideWithValue(player)],
    );
    final subscription = container.listen(
      playScreenProvider,
      (_, _) {},
      fireImmediately: true,
    );

    final controller = container.read(playScreenProvider.notifier);
    await controller.enterFullscreen();
    await controller.enterPip();
    subscription.close();
    container.dispose();
    await Future<void>.delayed(Duration.zero);

    expect(player.calls, contains('pip:exit'));
    expect(player.calls, contains('fullscreen:false'));
  });

  test('PiP 退出等待期间 provider 销毁时不恢复已失效的系统全屏', () async {
    final player = _RecordingPlayer()..exitPipGate = Completer<void>();
    final container = ProviderContainer(
      overrides: [playerProvider.overrideWithValue(player)],
    );
    final subscription = container.listen(
      playScreenProvider,
      (_, _) {},
      fireImmediately: true,
    );

    final controller = container.read(playScreenProvider.notifier);
    await controller.enterFullscreen();
    await controller.enterPip();
    player.calls.clear();

    final exitFuture = controller.exitPip();
    await Future<void>.delayed(Duration.zero);
    subscription.close();
    container.dispose();
    player.exitPipGate!.complete();
    await exitFuture;
    await Future<void>.delayed(Duration.zero);

    expect(player.calls, ['pip:exit', 'fullscreen:false']);
  });
  test('主题模式映射保持 MaterialApp 的三态契约', () {
    expect(ZishuTheme.modeOf(ThemeModeChoice.dark), ThemeMode.dark);
    expect(ZishuTheme.modeOf(ThemeModeChoice.light), ThemeMode.light);
    expect(ZishuTheme.modeOf(ThemeModeChoice.system), ThemeMode.system);
  });
}
