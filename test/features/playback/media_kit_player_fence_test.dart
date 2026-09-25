/// 播放韧性内核单测:生命周期串行队列 / 源代际围栏 / 事件围栏 / 看门狗重挂。
///
/// 为什么必须注入假后端:VM 单测里构造 `Player()` 会走 `NativePlayer`,
/// 直接 `DynamicLibrary.open(libmpv-2.dll)` 而测试进程拿不到该动态库。
/// 唯一可行的驱动路径是 `Player(platformPlayer:)` —— 用 `PlatformPlayer`
/// 替身把 open/stop/play/pause 与 mpv 事件流捏在测试手里。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_parser/live_parser.dart' show StreamLine;
import 'package:media_kit/media_kit.dart';
import 'package:zishu_flutter/src/platforms/common/playback/live_player.dart';
import 'package:zishu_flutter/src/platforms/common/playback/media_kit_live_player.dart';
import 'package:zishu_flutter/src/platforms/common/playback/playback_log.dart';
import 'package:zishu_flutter/src/platforms/common/playback/playback_retry.dart';

/// [PlatformPlayer] 替身:记录命令调用顺序,并允许测试放行/挂起 open、
/// 手动推送 mpv 事件。所有流控制器都是 `@protected`,子类可直接写入。
class _FakePlatformPlayer extends PlatformPlayer {
  _FakePlatformPlayer() : super(configuration: const PlayerConfiguration());

  /// 收到的命令序列(带地址主机名,便于断言"底层到底打开了谁")。
  final List<String> calls = <String>[];

  /// 第一次 open 到达底层的信号(测试据此知道"现在处于 open 在途")。
  final Completer<void> openStarted = Completer<void>();

  Completer<void>? _gate;
  int disposeCalls = 0;

  @override
  Future<void> dispose() async {
    disposeCalls++;
    await super.dispose();
  }

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    final medias = playable is Playlist ? playable.medias : <Media>[playable as Media];
    final hosts = medias
        .map((media) => Uri.tryParse(media.uri)?.host ?? media.uri)
        .join(',');
    calls.add('open:$hosts');
    if (!openStarted.isCompleted) openStarted.complete();
    final gate = _gate;
    if (gate != null) await gate.future;
  }

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  Future<void> play() async => calls.add('play');

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> setVolume(double volume) async {}

  /// 让紧随其后的那次 open 挂起,直到 [releaseGatedOpen]。
  void gateNextOpen() => _gate = Completer<void>();

  void releaseGatedOpen() {
    final gate = _gate;
    _gate = null;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  /// 伪造底层真实状态(重连后补发真实态时要读它)。
  void setStateValues({bool? playing, bool? buffering}) =>
      state = state.copyWith(playing: playing, buffering: buffering);

  void emitPlaying(bool value) => playingController.add(value);

  void emitVideoParams({
    int width = 1920,
    int height = 1080,
    String pixelformat = 'yuv420p',
  }) {
    videoParamsController.add(
      VideoParams(w: width, h: height, pixelformat: pixelformat),
    );
  }

  void emitCompleted() => completedController.add(true);

  void emitError(String message) => errorController.add(message);

  /// 伪造底层音量属性回流(模拟 mpv observeproperty volume 事件)。
  void emitVolume(double value) => volumeController.add(value);
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
  const lineB = StreamLine(
    name: 'B',
    url: 'https://b.example.com/live.m3u8',
    format: 'hls',
  );

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('mk_player_fence_test');
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

  group('releaseNative 底层释放围栏', () {
    test('挂起的 native open 结束前不 dispose，重复请求只 dispose 一次', () async {
      fake.gateNextOpen();
      final opening = player.open(lineA);
      await fake.openStarted.future;
      final firstRelease = player.releaseNative();
      final secondRelease = player.releaseNative();
      expect(identical(firstRelease, secondRelease), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(fake.disposeCalls, 0);
      fake.releaseGatedOpen();
      await opening;
      await firstRelease;
      expect(fake.disposeCalls, 1);
    });

    test('已排队 stop 完成后才释放 PlatformPlayer', () async {
      await player.open(lineA);
      final stopping = player.stop();
      final releasing = player.releaseNative();
      await stopping;
      await releasing;
      expect(fake.disposeCalls, 1);
      expect(fake.calls.last, 'stop');
    });
  });

  group('视频画面诊断锚点', () {
    test('videoParams 变化记录分辨率和像素格式', () async {
      await player.open(lineA);
      fake.emitVideoParams();
      await pumpEventQueue();

      expect(
        logLines().any(
          (line) =>
              line.contains('video_params') &&
              line.contains('width=1920') &&
              line.contains('height=1080') &&
              line.contains('pixelformat=yuv420p'),
        ),
        isTrue,
      );
    });
  });

  group('A1 生命周期串行队列', () {
    test('open 未落地时 stop 不抢占,旧 stop 不会卸载新源', () async {
      fake.gateNextOpen();
      final openFuture = player.open(lineA);
      await fake.openStarted.future;
      expect(fake.calls, ['open:a.example.com']);

      final stopFuture = player.stop();
      await pumpEventQueue();
      expect(
        fake.calls,
        ['open:a.example.com'],
        reason: 'stop 应排在 open 之后(切房竞态的根治点)',
      );

      fake.releaseGatedOpen();
      await openFuture;
      await stopFuture;
      expect(fake.calls, ['open:a.example.com', 'stop']);
    });

    test('play/pause 走同一队列,open 在途时不抢跑', () async {
      fake.gateNextOpen();
      final openFuture = player.open(lineA);
      await fake.openStarted.future;

      final playFuture = player.play();
      await pumpEventQueue();
      expect(fake.calls, ['open:a.example.com'], reason: 'open 未落地前 play 不得抢跑');

      fake.releaseGatedOpen();
      await openFuture;
      await playFuture;
      expect(fake.calls, ['open:a.example.com', 'play']);
    });
  });

  group('A2 源代际围栏', () {
    test('切房:旧 open 被代际作废,底层只收到新房地址', () async {
      final first = player.open(lineA);
      final second = player.open(lineB);
      await first;
      await second;

      expect(
        fake.calls,
        ['open:b.example.com'],
        reason: '排队的旧 open 应被代际作废,底层只打开新房地址',
      );
      expect(
        logLines().any((line) => line.contains('open_superseded')),
        isTrue,
        reason: '作废应留痕(open_superseded)',
      );
    });

    test('在途 open 被 stop 作废:不补发缓冲快照、不重挂看门狗', () async {
      fake.gateNextOpen();
      final openFuture = player.open(lineA);
      await fake.openStarted.future;

      final stopFuture = player.stop();
      fake.releaseGatedOpen();
      await openFuture;
      await stopFuture;
      await pumpEventQueue();

      expect(fake.calls, ['open:a.example.com', 'stop']);
      expect(snapshots.last.buffering, isFalse, reason: 'stop 后的空闲快照应压过在途 open');
      expect(
        logLines().any((line) => line.contains('stall_watchdog')),
        isFalse,
        reason: '被作废的 open 不得重挂看门狗(否则离房后仍会空转重连)',
      );
    });
  });

  group('A3 事件围栏与真实状态补发', () {
    test('open 在途期间的终局错误被屏蔽,落地后重新接受', () async {
      fake.gateNextOpen();
      final openFuture = player.open(lineA);
      await fake.openStarted.future;

      fake.emitError('server returned 404');
      await pumpEventQueue();
      expect(
        snapshots.where((snapshot) => snapshot.error != null),
        isEmpty,
        reason: '在途旧源的错误不得污染新房',
      );

      fake.releaseGatedOpen();
      await openFuture;
      await pumpEventQueue();

      fake.emitError('server returned 404');
      await pumpEventQueue();
      expect(
        snapshots.last.error,
        isNotNull,
        reason: 'open 落地后围栏解除,新房错误应上报',
      );
    });

    test('open 落地补发真实状态:围栏内丢掉的 playing 由 resync 补上', () async {
      fake.gateNextOpen();
      final openFuture = player.open(lineA);
      await fake.openStarted.future;

      // 围栏期间底层已出帧:事件被屏蔽,但底层真实 state 已是 playing。
      fake.emitPlaying(true);
      fake.setStateValues(playing: true);
      await pumpEventQueue();

      fake.releaseGatedOpen();
      await openFuture;
      await pumpEventQueue();

      expect(
        snapshots.last.playing,
        isTrue,
        reason: 'resync 应把底层真实 playing 补发给 UI(否则界面停在缓冲中)',
      );
    });
  });

  group('A4/A5 看门狗重挂与 completed 退避', () {
    test('open 落地即主动挂看门狗(补 R4 饥饿)', () async {
      await player.open(lineA);
      await pumpEventQueue();

      expect(fake.calls, ['open:a.example.com']);
      expect(
        logLines().any(
          (line) => line.contains('stall_watchdog') && line.contains('backoffMs=8000'),
        ),
        isTrue,
        reason: 'open 末尾应以 backoffFor(0)=8s 主动重挂看门狗',
      );
    });

    test('计时到期前底层已恢复 playing 时不得重开', () async {
      final fastPolicy = PlaybackRetryPolicy(
        baseDelay: const Duration(milliseconds: 20),
        stepDelay: Duration.zero,
        maxDelay: const Duration(milliseconds: 20),
      );
      final fastPlayer = MediaKitLivePlayer(
        player: Player(platformPlayer: fake),
        policy: fastPolicy,
      );
      addTearDown(fastPlayer.dispose);
      await fastPlayer.open(lineA);

      // 模拟恢复事件在 open 围栏内丢失,但底层真实状态已经恢复。
      fake.setStateValues(playing: true, buffering: false);
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(
        fake.calls,
        ['open:a.example.com'],
        reason: '计时器到期时必须复核底层状态,已恢复时不得重开视频管线',
      );
    });

    test('completed 走同一退避入口,而不是立即重开(补 R8)', () async {
      await player.open(lineA);
      // 出帧撤掉 open 末尾挂的看门狗,让下面的 completed 必须自己重挂。
      fake.emitPlaying(true);
      await pumpEventQueue();
      final armedBefore =
          logLines().where((line) => line.contains('stall_watchdog')).length;

      fake.emitCompleted();
      await pumpEventQueue();

      expect(fake.calls, ['open:a.example.com'], reason: 'completed 不得立即重开');
      expect(
        logLines().any((line) => line.contains('reopen_requested')),
        isFalse,
        reason: '退避未走完前不应产生重开请求',
      );
      expect(
        logLines().where((line) => line.contains('stall_watchdog')).length,
        armedBefore + 1,
        reason: 'completed 应重新挂看门狗并等待退避,而非绕开退避',
      );
    });
  });

  group('A7 播放/暂停快照同步(用户口径 2026-09-20 播放暂停判断错)', () {
    test('pause 后快照 playing 立即为 false,不等底层事件回流', () async {
      // 复现真机:控制条点暂停,画面停了但播放/暂停图标不切换 ——
      // 底层(media-kit 假体与真机一致)暂停时不再回流 playing 事件,
      // 快照停留在 true。pause 必须主动发布快照。
      fake.emitPlaying(true);
      await pumpEventQueue();
      expect(snapshots.last.playing, isTrue);

      await player.pause();
      await pumpEventQueue();
      expect(
        snapshots.last.playing,
        isFalse,
        reason: 'pause 后快照 playing 必须立即为 false,不得等待底层回流',
      );
    });

    test('play 后快照 playing 立即为 true,恢复播放图标同源', () async {
      fake.emitPlaying(false);
      await pumpEventQueue();

      await player.play();
      await pumpEventQueue();
      expect(
        snapshots.last.playing,
        isTrue,
        reason: 'play 后快照 playing 必须立即为 true,不得等待底层回流',
      );
    });
  });

  group('A6 音量快照同步(BUG-WIN-VOLUME-002)', () {
    test('setVolume 立即归一到快照,不等底层事件回流', () async {
      // 复现真机:房 A 拖到 36.8,底层已回流,快照停在 36.8。
      fake.emitVolume(36.8);
      await pumpEventQueue();
      expect(snapshots.last.volume, 36.8);

      // 进入从未设置音量的房 B:编排层套默认 100。替身底层不再回流
      //(真机中该回流会被 open 围栏吞掉/因属性幂等而不再发出),
      // setVolume 自己必须把快照推到 100,否则 slider 卡在上一房值。
      await player.setVolume(100);
      await pumpEventQueue();

      expect(
        snapshots.last.volume,
        100,
        reason: 'setVolume 后快照音量必须立即等于目标值,不得等待底层回流',
      );
    });

    test('切房开流窗口内套用新房默认音量,快照不得停留在上一房值', () async {
      // 真 BUG-WIN-VOLUME-002 时序:房 A 36.8 → 离房 → 进全新房 B(默认 100)。
      fake.emitVolume(36.8);
      await pumpEventQueue();

      fake.gateNextOpen();
      final openFuture = player.open(lineB);
      await fake.openStarted.future;

      // 开流前编排层先套一次新房音量(默认 100);此刻 open 在途,
      // 真机上底层即便回流也会被事件围栏丢弃。
      await player.setVolume(100);
      await pumpEventQueue();

      fake.releaseGatedOpen();
      await openFuture;
      await pumpEventQueue();

      expect(
        snapshots.last.volume,
        100,
        reason: 'open/resync 全部落地后快照音量必须是新房目标值,而非上一房残留',
      );
    });

    test('解除静音恢复音量时同样立即归一到快照', () async {
      fake.emitVolume(64);
      await pumpEventQueue();

      await player.setMuted(true);
      // 静音走底层 volume=0,真实 mpv 会把属性变化回流成快照 0。
      fake.emitVolume(0);
      await pumpEventQueue();
      expect(snapshots.last.muted, isTrue);
      expect(snapshots.last.volume, 0);

      // 解除静音会向底层恢复静音前音量;底层不再回流时快照也要跟上。
      await player.setMuted(false);
      await pumpEventQueue();

      expect(snapshots.last.muted, isFalse);
      expect(
        snapshots.last.volume,
        64,
        reason: '解除静音后快照音量必须恢复为静音前值,不得停在静音的 0',
      );
    });
  });

  group('A7 stop 重置重试记账', () {
    test('stop 清失败计数与闩锁,重进房从干净状态开始', () async {
      await player.open(lineA);
      await pumpEventQueue();
      final armedAfterFirstOpen =
          logLines().where((line) => line.contains('stall_watchdog')).length;
      expect(armedAfterFirstOpen, 1);

      await player.stop();
      await pumpEventQueue();
      expect(snapshots.last.error, isNull);
      expect(snapshots.last.retryAttempt, 0);
      expect(snapshots.last.buffering, isFalse);

      // 重进房仍能正常开流并重新挂看门狗(说明 stop 已清掉记账)。
      await player.open(lineB);
      await pumpEventQueue();
      expect(fake.calls.last, 'open:b.example.com');
      expect(
        logLines().where((line) => line.contains('stall_watchdog')).length,
        armedAfterFirstOpen + 1,
      );
    });
  });
}
