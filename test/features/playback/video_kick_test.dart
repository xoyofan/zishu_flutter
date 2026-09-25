/// BUG-WIN-VIDEO-001 候选修复单测:进房黑屏但播放器已 playing ——
/// 纹理首帧未上屏的「尺寸缺失型」自动 kick。
///
/// 两层断言:
/// 1. 纯函数 [needsVideoKick]:武装/复核共用的判定本身;
/// 2. 集成(MediaKitLivePlayer + 假 PlatformPlayer):1.5s 计时、
///    pause/play 执行、`video_state` / `video_kick` 落盘、
///    Timer 与 flag 不跨会话、一次 open 至多 kick 一次。
///
/// 为什么注入假后端:VM 测试无法加载原生 libmpv,同
/// `media_kit_player_fence_test.dart`。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_parser/live_parser.dart' show StreamLine;
import 'package:media_kit/media_kit.dart';
import 'package:zishu_flutter/src/platforms/common/playback/live_player.dart';
import 'package:zishu_flutter/src/platforms/common/playback/media_kit_live_player.dart';
import 'package:zishu_flutter/src/platforms/common/playback/playback_log.dart';

/// [PlatformPlayer] 替身:记录命令;state 与事件流由测试手动驱动。
class _FakePlatformPlayer extends PlatformPlayer {
  _FakePlatformPlayer() : super(configuration: const PlayerConfiguration());

  final List<String> calls = <String>[];

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    final medias = playable is Playlist
        ? playable.medias
        : <Media>[playable as Media];
    final hosts = medias
        .map((media) => Uri.tryParse(media.uri)?.host ?? media.uri)
        .join(',');
    calls.add('open:$hosts');
  }

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  Future<void> play() async => calls.add('play');

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> setVolume(double volume) async {}

  /// 伪造底层真实状态(resync / kick 复核读的都是它)。
  void setStateValues({
    bool? playing,
    bool? buffering,
    int? width,
    int? height,
  }) =>
      state = state.copyWith(
        playing: playing,
        buffering: buffering,
        width: width,
        height: height,
      );

  void emitPlaying(bool value) => playingController.add(value);

  void emitBuffering(bool value) => bufferingController.add(value);

  void emitWidth(int? value) => widthController.add(value);

  void emitHeight(int? value) => heightController.add(value);
}

void main() {
  late Directory tempDir;
  late String logPath;
  late _FakePlatformPlayer fake;
  late MediaKitLivePlayer player;
  late List<PlayerSnapshot> snapshots;
  late StreamSubscription<PlayerSnapshot> snapshotSub;

  const lineA = StreamLine(
    name: 'A',
    url: 'https://a.example.com/live.m3u8',
    format: 'hls',
  );

  /// kick 观察窗 1.5s,留 200ms 余量。
  const settle = Duration(milliseconds: 1700);

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('video_kick_test');
    logPath = '${tempDir.path}${Platform.pathSeparator}playback.log';
    PlaybackLog.initForTest(logPath);
    fake = _FakePlatformPlayer();
    player = MediaKitLivePlayer(player: Player(platformPlayer: fake));
    snapshots = <PlayerSnapshot>[];
    snapshotSub = player.snapshots.listen(snapshots.add);
  });

  tearDown(() async {
    await snapshotSub.cancel();
    player.dispose();
    PlaybackLog.resetForTest();
    tempDir.deleteSync(recursive: true);
  });

  List<String> logLines() {
    final file = File(logPath);
    if (!file.existsSync()) return const [];
    return file.readAsLinesSync().where((line) => line.isNotEmpty).toList();
  }

  int kickLogCount() =>
      logLines().where((line) => line.contains('video_kick')).length;

  /// 进入「playing 但无视频尺寸」并让武装判定跑一遍。
  Future<void> enterPlayingWithoutSize() async {
    await player.open(lineA);
    await pumpEventQueue();
    fake.setStateValues(playing: true);
    fake.emitPlaying(true);
    await pumpEventQueue();
  }

  group('needsVideoKick 纯函数判定', () {
    test('playing 且无尺寸 → 要 kick', () {
      expect(
        needsVideoKick(
          playing: true,
          buffering: false,
          width: null,
          height: null,
          alreadyKicked: false,
        ),
        isTrue,
      );
    });

    test('playing 且尺寸正常 → 不 kick', () {
      expect(
        needsVideoKick(
          playing: true,
          buffering: false,
          width: 1920,
          height: 1080,
          alreadyKicked: false,
        ),
        isFalse,
      );
    });

    test('buffering 中 → 不 kick(等缓冲自行恢复)', () {
      expect(
        needsVideoKick(
          playing: true,
          buffering: true,
          width: null,
          height: null,
          alreadyKicked: false,
        ),
        isFalse,
      );
    });

    test('已 kick 过 → 不重复 kick', () {
      expect(
        needsVideoKick(
          playing: true,
          buffering: false,
          width: null,
          height: null,
          alreadyKicked: true,
        ),
        isFalse,
      );
    });

    test('pause 后(非 playing)→ 不 kick', () {
      expect(
        needsVideoKick(
          playing: false,
          buffering: false,
          width: null,
          height: null,
          alreadyKicked: false,
        ),
        isFalse,
      );
    });

    test('宽为 0(非法尺寸)→ 要 kick', () {
      expect(
        needsVideoKick(
          playing: true,
          buffering: false,
          width: 0,
          height: 1080,
          alreadyKicked: false,
        ),
        isTrue,
      );
    });

    test('仅高缺失 → 仍要 kick(单边缺失同样拿不到纹理)', () {
      expect(
        needsVideoKick(
          playing: true,
          buffering: false,
          width: 1920,
          height: null,
          alreadyKicked: false,
        ),
        isTrue,
      );
    });
  });

  group('自动 kick 集成(MediaKitLivePlayer)', () {
    test('playing 且无尺寸:1.5s 后 pause/play 一次并落 video_kick;不循环', () async {
      await enterPlayingWithoutSize();

      await Future<void>.delayed(settle);

      expect(
        fake.calls,
        ['open:a.example.com', 'pause', 'play'],
        reason: '计时到期复核仍无尺寸,应执行一次 pause/play 纹理 kick',
      );
      expect(kickLogCount(), 1);
      expect(
        logLines().any(
          (line) =>
              line.contains('video_kick') && line.contains('reason=no_video_size'),
        ),
        isTrue,
        reason: 'kick 必须留痕(无尺寸型黑屏的判定证据)',
      );
      expect(
        logLines().any((line) => line.contains('video_state')),
        isTrue,
        reason: 'resync 解围栏处应落 video_state 尺寸/播放态样本',
      );

      // 已 kick 后再次满足条件也不得重复(一次 open 至多一次)。
      fake.emitPlaying(true);
      await pumpEventQueue();
      await Future<void>.delayed(settle);
      expect(fake.calls, ['open:a.example.com', 'pause', 'play']);
      expect(kickLogCount(), 1);
    });

    test('playing 且尺寸正常 → 不武装 kick', () async {
      await player.open(lineA);
      await pumpEventQueue();
      fake.setStateValues(playing: true, width: 1920, height: 1080);
      fake.emitPlaying(true);
      await pumpEventQueue();

      await Future<void>.delayed(settle);

      expect(fake.calls, ['open:a.example.com']);
      expect(kickLogCount(), 0);
    });

    test('尺寸在计时窗内迟到 → 撤销 kick', () async {
      await enterPlayingWithoutSize();
      // mpv 迟到补报 video-params:state 与事件同源更新(真实后端先改 state 再发事件)。
      fake.setStateValues(width: 1920, height: 1080);
      fake.emitWidth(1920);
      fake.emitHeight(1080);
      await pumpEventQueue();

      await Future<void>.delayed(settle);

      expect(fake.calls, ['open:a.example.com']);
      expect(kickLogCount(), 0, reason: '尺寸到位必须取消计时,不得误 kick');
    });

    test('stop 后计时不得跨会话触发', () async {
      await enterPlayingWithoutSize();
      await player.stop();
      await pumpEventQueue();

      await Future<void>.delayed(settle);

      expect(fake.calls, ['open:a.example.com', 'stop']);
      expect(kickLogCount(), 0, reason: 'stop 必须 reset Timer,旧会话不得 kick');
    });

    test('pause 后不 kick', () async {
      await enterPlayingWithoutSize();
      await player.pause();
      fake.setStateValues(playing: false);
      fake.emitPlaying(false);
      await pumpEventQueue();

      await Future<void>.delayed(settle);

      expect(fake.calls, ['open:a.example.com', 'pause']);
      expect(kickLogCount(), 0, reason: 'pause 后条件不成立,不得触发 kick');
    });
  });
}
