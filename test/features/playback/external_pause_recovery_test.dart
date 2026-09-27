/// 外部自暂停死锁修复单测(WIN-PAUSE-DEADLOCK)。
///
/// 复现 `playback.log` 16:33:14 的死锁签名:
/// `playing=false`(source=external,无 play_cmd)→ `buffering=true`(挂看门狗)
/// → `buffering=false`(看门狗被立即取消,stall_end ms=0)→ 永久卡 paused
/// (playing=false 事件无恢复路径)。
///
/// 断言:外部自暂停现在会挂一个**独立**恢复计时器(不被 buffering 翻面取消),
/// 到期仍 paused 则整组轮转重连,破解死锁;而用户主动 pause / mpv 自行在退避
/// 窗内恢复都不应触发重开。
///
/// 为什么注入假后端:VM 测试无法加载原生 libmpv,同 `video_kick_test.dart`。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_parser/live_parser.dart' show StreamLine;
import 'package:media_kit/media_kit.dart';
import 'package:zishu_flutter/src/platforms/common/playback/live_player.dart';
import 'package:zishu_flutter/src/platforms/common/playback/media_kit_live_player.dart';
import 'package:zishu_flutter/src/platforms/common/playback/player_error.dart';
import 'package:zishu_flutter/src/platforms/common/playback/playback_log.dart';
import 'package:zishu_flutter/src/platforms/common/playback/playback_retry.dart';

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
  }) => state = state.copyWith(
    playing: playing,
    buffering: buffering,
    width: width,
    height: height,
  );

  void emitPlaying(bool value) => playingController.add(value);

  void emitBuffering(bool value) => bufferingController.add(value);

  void emitError(String value) => errorController.add(value);

  void emitWarn(String prefix, String text) =>
      logController.add(PlayerLog(prefix: prefix, level: 'warn', text: text));

  void emitWidth(int? value) => widthController.add(value);

  void emitVideoParams({int? width}) =>
      videoParamsController.add(VideoParams(w: width));

  void emitHeight(int? value) => heightController.add(value);

  /// 播放时钟采样桩:非 null 时 getProperty('time-pos') 返回它,
  /// 其余属性照旧抛错(模拟不支持)。PlatformPlayer 未声明 getProperty,
  /// 这里是新方法而非 override,供生产侧动态分发调用。
  double? fakeTimePos;

  Future<String> getProperty(String property) async {
    final value = fakeTimePos;
    if (property == 'time-pos' && value != null) return '$value';
    throw UnimplementedError(property);
  }
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

  // 退避压到 150ms,留余量观察到期;maxDelay 同步压住避免增长。
  final fastPolicy = PlaybackRetryPolicy(
    baseDelay: const Duration(milliseconds: 150),
    maxDelay: const Duration(milliseconds: 150),
  );
  const settle = Duration(milliseconds: 350);

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('ext_pause_test');
    logPath = '${tempDir.path}${Platform.pathSeparator}playback.log';
    PlaybackLog.initForTest(logPath);
    fake = _FakePlatformPlayer();
    player = MediaKitLivePlayer(
      player: Player(platformPlayer: fake),
      policy: fastPolicy,
    );
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

  /// 进房并起播(playing + 尺寸齐全),模拟稳定直播中。
  Future<void> enterPlaying() async {
    await player.open(lineA);
    await pumpEventQueue();
    fake.setStateValues(playing: true, width: 1920, height: 1080);
    fake.emitPlaying(true);
    await pumpEventQueue();
  }

  /// 复现死锁签名:外部 playing=false + buffering 翻面(stop 被立刻取消)。
  Future<void> emitDeadlockSignature() async {
    fake.setStateValues(playing: false);
    fake.emitPlaying(false);
    fake.emitBuffering(true);
    fake.emitBuffering(false);
    await pumpEventQueue();
  }

  /// 轮询等待条件成立(事件循环繁忙时替代固定 sleep,消除时序抖动)。
  Future<void> waitFor(
    bool Function() predicate, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!predicate()) {
      if (DateTime.now().isAfter(deadline)) {
        throw Exception('timeout waiting for condition');
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await pumpEventQueue();
    }
  }

  group('外部自暂停死锁恢复', () {
    test('死锁签名:到期仍 paused → 整组轮转重连(破解卡死)', () async {
      await enterPlaying();
      await emitDeadlockSignature();

      // 退避窗内看门狗不被 buffering 翻面取消;到期读底层仍 paused → 重开。
      // 轮询等待重开真正发生(事件循环繁忙时计时器到期略晚,固定 sleep 会抖)。
      await waitFor(() => fake.calls.length >= 2);
      expect(fake.calls, [
        'open:a.example.com',
        'open:a.example.com',
      ], reason: '外部自暂停死锁必须被重开破解,否则会卡在 paused');

      // 模型:重开成功出帧 → 状态翻 true,撤销后续恢复计时器,不再空转。
      fake.setStateValues(playing: true);
      fake.emitPlaying(true);
      await pumpEventQueue();
      await waitFor(() => logLines().any((l) => l.contains('play_state')));
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(fake.calls, [
        'open:a.example.com',
        'open:a.example.com',
      ], reason: '重开成功后应稳定出帧,不得反复重开');
      expect(
        logLines().any((l) => l.contains('external_pause_watchdog')),
        isTrue,
        reason: '必须挂起独立恢复计时器(证据)',
      );
      expect(
        logLines().any((l) => l.contains('external_pause_recover')),
        isTrue,
        reason: '到期仍 paused 必须触发重连',
      );
      // 确认不是 buffering 看门狗在兜底:死锁签名里 buffering 翻面会落
      // `stall_end`(卡顿被立即结算),但恢复来自独立的外部暂停计时器
      // (`external_pause_recover`),而非 stall 看门狗(它已被 buffering=false 取消)。
      expect(
        logLines().any((l) => l.contains('stall_end')),
        isTrue,
        reason: '死锁签名里 buffering 翻面被结算(stall_end),但恢复由外部暂停计时器驱动',
      );
    });

    test('mpv 在退避窗内自行恢复 → 只补快照,不重开', () async {
      await enterPlaying();
      await emitDeadlockSignature();

      // mpv 自行 resume(playing 翻 true)——看门狗应被撤销。
      fake.setStateValues(playing: true);
      fake.emitPlaying(true);
      await pumpEventQueue();

      await Future<void>.delayed(settle);

      expect(fake.calls, ['open:a.example.com'], reason: '自行恢复不应触发重开(避免误伤正常流)');
      expect(
        logLines().any((l) => l.contains('external_pause_watchdog')),
        isTrue,
        reason: '看门狗仍应挂起(证据),但随后被恢复事件撤销',
      );
      expect(
        logLines().any((l) => l.contains('external_pause_recover')),
        isFalse,
        reason: '自行恢复后不得重开',
      );
    });

    test('用户主动 pause → 不挂外部恢复(避免误重开)', () async {
      await enterPlaying();
      // 用户点暂停:play_cmd action=pause + _pauseReason='ui',mpv 随后 ack。
      await player.pause();
      await pumpEventQueue();
      fake.setStateValues(playing: false);
      fake.emitPlaying(false);
      await pumpEventQueue();

      await Future<void>.delayed(settle);

      expect(fake.calls, [
        'open:a.example.com',
        'pause',
      ], reason: '用户 pause 只应记录 pause,不得触发自动重开');
      expect(
        logLines().any((l) => l.contains('external_pause_watchdog')),
        isFalse,
        reason: '本地指令触发的暂停不应挂外部恢复计时器',
      );
      expect(
        logLines().any((l) => l.contains('play_cmd')),
        isTrue,
        reason: '用户暂停必须留 play_cmd 证据(区别于后端自暂停)',
      );
    });
  });

  group('mpv warn 噪音抑制(数字归一化)', () {
    test('同型不同 offset 的重连行只落一条,其余汇总为 mpv_log_suppressed', () async {
      await enterPlaying();
      // 复现 2026-09-27 19:16 刷屏:每行 byte offset 不同,严格相等 distinct
      // 与逐字去重都拦不住;归一化(数字→#)后应折叠为 1 条原文 + 抑制汇总。
      for (var i = 0; i < 10; i++) {
        fake.emitWarn(
          'ffmpeg',
          'https: Will reconnect at ${100000 + i} in 0 second(s), error=I/O error.',
        );
      }
      // 换型行触发汇总落盘。
      fake.emitWarn(
        'ffmpeg',
        'tls: mbedtls_ssl_read reported connection reset by peer',
      );
      await pumpEventQueue();

      final mpvLogs = logLines().where(
        (l) => l.contains('mpv_log prefix=ffmpeg'),
      );
      expect(
        mpvLogs.where((l) => l.contains('Will reconnect')).length,
        1,
        reason: '同型重连行(仅 offset 不同)只允许落第一条原文',
      );
      expect(
        logLines().any(
          (l) => l.contains('mpv_log_suppressed') && l.contains('count=9'),
        ),
        isTrue,
        reason: '被抑制的 9 条必须以汇总形式留痕',
      );
      expect(
        logLines().where((l) => l.contains('transport_flap')).length,
        0,
        reason: '10 条未达风暴阈值(50),不得升级 transport_flap',
      );
    });

    test('时间戳混沌型合计 ≥12/5s 升级 decode_flap(解码级劣化标记)', () async {
      await enterPlaying();
      // 复现 2026-09-27 19:55 线上卡顿档:CDN 数据涓流把 FLV 时间戳打乱,
      // cplayer/ad 的 timestamp 类 warn 持续出现,mpv 反复 playback reset。
      // 流 technically 在播,看门狗不触发——只能靠观测事件量化。
      // 混沌计数逐行累计(含各型首条):7+7=14,新型收尾触发结算。
      for (var i = 0; i < 7; i++) {
        fake.emitWarn(
          'cplayer',
          'Invalid video timestamp: ${50 + i}.348000 -> 4$i.582000',
        );
      }
      for (var i = 0; i < 7; i++) {
        fake.emitWarn(
          'cplayer',
          'Reset playback due to audio timestamp reset.',
        );
      }
      fake.emitWarn('ffmpeg', 'other diagnostic');
      await pumpEventQueue();

      final flap = logLines().where((l) => l.contains('decode_flap')).toList();
      expect(flap, hasLength(1), reason: '混沌合计达阈值必须落一次 decode_flap');
      expect(flap.first, contains('count=14'));
      expect(flap.first, contains('host='));
    });

    test('两种型 A/B 交替刷屏时,每型仍只落一条原文(单键版翻车回归)', () async {
      await enterPlaying();
      // 复现 2026-09-27 19:41 线上翻车:cplayer 的 Invalid video timestamp
      // 与 ad 的 Invalid audio PTS 交替出现,单键 last-key 版本每次换型都把
      // 新型当首条原文落盘 → 全部刷屏。按型独立计数后应各落一条。
      for (var i = 0; i < 6; i++) {
        fake.emitWarn(
          'cplayer',
          'Invalid video timestamp: ${50 + i}.348000 -> 4$i.582000',
        );
        fake.emitWarn(
          'ad',
          'Invalid audio PTS: ${48 + i}.234000 -> 4$i.168000',
        );
      }
      // 收尾再引一条新型触发汇总(线上等价于 5s 稳定性采样的 flush 时机)。
      fake.emitWarn(
        'ffmpeg',
        'tls: mbedtls_ssl_read reported connection reset by peer',
      );
      await pumpEventQueue();

      final mpvLogs = logLines().where((l) => l.contains('mpv_log prefix='));
      expect(
        mpvLogs.where((l) => l.contains('Invalid video timestamp')).length,
        1,
        reason: 'cplayer 型只允许落第一条原文',
      );
      expect(
        mpvLogs.where((l) => l.contains('Invalid audio PTS')).length,
        1,
        reason: 'ad 型只允许落第一条原文,不得因换型反复重打',
      );
      expect(
        logLines()
            .where(
              (l) => l.contains('mpv_log_suppressed') && l.contains('count=5'),
            )
            .length,
        2,
        reason: '两型各 5 条被抑制,汇总各留痕一次',
      );
    });

    test('5s 窗口同型 ≥50 条升级 transport_flap(重连风暴标记)', () async {
      await enterPlaying();
      // 首条落原文,其余 50 条计入抑制 → count=50 恰好达到阈值。
      for (var i = 0; i < 51; i++) {
        fake.emitWarn(
          'ffmpeg',
          'https: Will reconnect at $i in 0 second(s), error=I/O error.',
        );
      }
      // 换型行触发汇总。
      fake.emitWarn('ffmpeg', 'other diagnostic');
      await pumpEventQueue();

      final flap = logLines()
          .where((l) => l.contains('transport_flap'))
          .toList();
      expect(flap, hasLength(1), reason: '达到阈值必须落一次 transport_flap');
      expect(flap.first, contains('count=50'));
    });
  });

  group('source_open 立即升级 re-resolve', () {
    final freshLine = StreamLine(
      name: 'B',
      url: 'https://b.example.com/live.m3u8',
      format: 'hls',
    );

    test('首次终局 source_open 失败 → 立即重新解析,不重开旧签名地址', () async {
      // 复现 2026-09-27 18:23 虎牙事故:签名 URL 失效后,旧逻辑盲重开同一
      // wsSecret 4 次(白烧 39s)才升级 re-resolve。现在第 1 次失败就必须
      // 直接向宿主要新地址。
      var resolveCount = 0;
      player.setLineRecovery(() async {
        resolveCount++;
        return [freshLine];
      });
      await enterPlaying();
      fake.setStateValues(playing: false, width: null, height: null);
      fake.emitError('server returned 403');
      await pumpEventQueue();

      await waitFor(() => resolveCount == 1);
      await waitFor(() => fake.calls.contains('open:b.example.com'));

      expect(fake.calls, [
        'open:a.example.com',
        'open:b.example.com',
      ], reason: '终局 source_open 失败不得先盲重开旧 URL,必须直接 re-resolve');
      expect(
        logLines().any((l) => l.contains('source_open_failure')),
        isTrue,
        reason: '失败必须留证据',
      );
      expect(
        logLines().any((l) => l.contains('recover_early')),
        isTrue,
        reason: '首次失败即升级恢复(recover_early)必须留证据',
      );
      expect(
        logLines().any((l) => l.contains('recover_ok')),
        isTrue,
        reason: '拿到新地址必须留 recover_ok 证据',
      );
    });

    test('假阳性 playing(先 playing 后终局诊断)撤销未确认康复记账', () async {
      // mpv 对打不开的源也会先发 playing(旧帧/vo 复位),99ms 后才报终局
      // 失败 —— 实测 18:23:58 playing_ok 误报。断言:未确认的康复记账在
      // 恢复入口被显式撤销(playing_ok_revoked),且恢复照常进行。
      var resolveCount = 0;
      player.setLineRecovery(() async {
        resolveCount++;
        return [freshLine];
      });
      await enterPlaying();
      // 死锁签名触发重开(此时 retries>0),随后出帧:playing_ok 记账建立。
      await emitDeadlockSignature();
      await waitFor(() => fake.calls.length >= 2);
      fake.setStateValues(playing: true);
      fake.emitPlaying(true);
      await pumpEventQueue();

      // 紧跟终局 source_open 诊断 —— 刚才的 playing 是假阳性。
      fake.setStateValues(playing: false, width: null, height: null);
      fake.emitError('server returned 403');
      await pumpEventQueue();

      await waitFor(() => resolveCount >= 1);
      expect(
        logLines().any((l) => l.contains('playing_ok_revoked')),
        isTrue,
        reason: '健康观察窗未走完就收到终局错误,必须撤销假阳性 playing_ok',
      );
      expect(
        logLines().any((l) => l.contains('recover_ok')),
        isTrue,
        reason: '撤销后恢复路径照常拿新地址',
      );
    });

    test('恢复在途时重复终局诊断不并发 re-resolve(在途闩锁)', () async {
      var resolveCount = 0;
      player.setLineRecovery(() async {
        resolveCount++;
        return [freshLine];
      });
      await enterPlaying();
      fake.setStateValues(playing: false, width: null, height: null);
      // 同一死源的重复诊断(mpv 会反复吐同一条)。
      fake.emitError('server returned 403');
      fake.emitError('server returned 403');
      fake.emitError('server returned 403');
      await pumpEventQueue();

      await waitFor(() => fake.calls.contains('open:b.example.com'));
      await Future<void>.delayed(settle);

      expect(resolveCount, 1, reason: '在途闩锁必须生效:多条终局诊断只允许发起一次 re-resolve');
      expect(fake.calls.where((c) => c.contains('a.example.com')), [
        'open:a.example.com',
      ], reason: '不得因重复诊断连环重开旧地址(在途期间的重开全部被拦)');
    });
  });

  group('卡顿浮层 X:取消自动重连(cancelRecovery)', () {
    int openCount() => fake.calls.where((c) => c.startsWith('open:')).length;

    test('取消后停止重试、不轮转线路、置闩锁;手动 open 解除', () async {
      await enterPlaying();
      // 触发外部自暂停死锁签名 → 看门狗 150ms 后整组重开(同一线路)。
      await emitDeadlockSignature();
      await waitFor(() => openCount() >= 2);
      final opensAtCancel = openCount();

      player.cancelRecovery();
      await pumpEventQueue();

      // 快照立即给出"已取消"错误卡片(带手动重试入口),notice 归位。
      final cancelled = snapshots.last;
      expect(cancelled.error, '已取消自动重连，点击重试恢复播放');
      expect(cancelled.errorKind, PlayerErrorKind.network);
      expect(cancelled.notice, PlaybackNotice.none);
      expect(cancelled.retryAttempt, 0);
      expect(
        logLines().any((l) => l.contains('recovery_cancelled')),
        isTrue,
        reason: '取消动作必须留审计日志',
      );

      // 闩锁置位:再来一次死锁签名,看门狗不武装、无任何新增重开
      // (不轮转线路 = 不出现其他 host,也不重开当前线路)。
      await emitDeadlockSignature();
      await Future<void>.delayed(settle);
      await pumpEventQueue();
      expect(openCount(), opensAtCancel, reason: '取消后不得再有任何重开(不换线路、不重试)');
      expect(
        fake.calls
            .where((c) => c.startsWith('open:'))
            .every((c) => c.contains('a.example.com')),
        isTrue,
        reason: '全程不得出现其他线路的 host',
      );

      // 手动 open(resetRetries: true) 是唯一解除点:恢复自动重连。
      await player.open(lineA);
      await pumpEventQueue();
      final opensAfterManual = openCount();
      // 重开 → 流起播(playing 已是 false,必须先翻 true 否则事件被去重)。
      fake.setStateValues(playing: true);
      fake.emitPlaying(true);
      await pumpEventQueue();
      await emitDeadlockSignature();
      await waitFor(() => openCount() > opensAfterManual);
    });

    test('取消时在途的 re-resolve 完成后不得开新地址', () async {
      var resolveCount = 0;
      player.setLineRecovery(() async {
        resolveCount++;
        await Future<void>.delayed(const Duration(milliseconds: 120));
        return [
          const StreamLine(
            name: 'B',
            url: 'https://b.example.com/live.m3u8',
            format: 'hls',
          ),
        ];
      });
      await enterPlaying();
      // 终局诊断 → 立即 re-resolve(在途 120ms);在 await 期间用户取消。
      fake.emitError('Failed to open https://a.example.com/live.m3u8');
      await pumpEventQueue();
      await waitFor(() => resolveCount == 1);
      player.cancelRecovery();

      // resolve 完成:因闩锁置位,新地址 B 不得被打开。
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await pumpEventQueue();
      expect(
        fake.calls.where((c) => c.startsWith('open:')),
        everyElement(contains('a.example.com')),
        reason: '取消后在途 re-resolve 的结果必须被丢弃,不得切到新地址',
      );
      expect(
        logLines().any(
          (l) => l.contains('recover_fail') && l.contains('cancelled_by_user'),
        ),
        isTrue,
      );
    });
  });

  group('死开流看门狗(video_params 黑屏)', () {
    // 宽限期压到 120ms;open 后 mpv 起播但永远不出画面 → 同线路重开。
    final deadOpenPolicy = PlaybackRetryPolicy(
      baseDelay: const Duration(milliseconds: 150),
      maxDelay: const Duration(milliseconds: 150),
      deadOpenGrace: const Duration(milliseconds: 120),
    );

    setUp(() {
      // 覆盖外层默认 player:死开流用例需要专用策略。
      // fake 被 dispose 后控制器已关闭,必须连同后端一起重建。
      player.dispose();
      fake = _FakePlatformPlayer();
      player = MediaKitLivePlayer(
        player: Player(platformPlayer: fake),
        policy: deadOpenPolicy,
      );
      snapshots = <PlayerSnapshot>[];
      snapshotSub = player.snapshots.listen(snapshots.add);
    });

    test('起播但无视频参数超宽限期 → 同线路重开;参数到达即复位', () async {
      // 起播(playing=true)但不发 videoParams:gen1 死开流签名。
      await player.open(lineA);
      await pumpEventQueue();
      fake.setStateValues(playing: true);
      fake.emitPlaying(true);
      await pumpEventQueue();

      // 宽限 120ms 到期 → dead_open_reopen,同线路第二次 open。
      await waitFor(() => fake.calls.where((c) => c.startsWith('open:')).length >= 2);
      expect(
        fake.calls.where((c) => c.startsWith('open:')),
        everyElement(contains('a.example.com')),
        reason: '死开流重开只重开同一线路,不轮转、不换 host',
      );
      expect(logLines().any((l) => l.contains('dead_open_reopen')), isTrue);

      // 新会话参数到达 → dead_open_resolved,计数复位(后续超时重新数)。
      fake.emitVideoParams(width: 1920);
      await pumpEventQueue();
      expect(
        logLines().any((l) => l.contains('dead_open_resolved')),
        isTrue,
        reason: '参数到达必须落 resolved 事件并清零重试计数',
      );
    });

    test('参数按时到达 → 不触发死开流重开', () async {
      await player.open(lineA);
      await pumpEventQueue();
      fake.emitVideoParams(width: 1920);
      fake.setStateValues(playing: true, width: 1920);
      fake.emitPlaying(true);
      await pumpEventQueue();

      await Future<void>.delayed(const Duration(milliseconds: 300));
      await pumpEventQueue();
      expect(
        fake.calls.where((c) => c.startsWith('open:')),
        hasLength(1),
        reason: '健康开流不得被死开流看门狗误伤',
      );
      expect(logLines().any((l) => l.contains('dead_open_reopen')), isFalse);
    });

    test('用户主动暂停期间宽限期到期 → 不重开(管辖权归暂停路径)', () async {
      // 先起播(与真实用户暂停一致),再暂停:mpv playing=false。
      await enterPlaying();
      await player.pause();
      await pumpEventQueue();
      fake.setStateValues(playing: false);
      fake.emitPlaying(false);
      await pumpEventQueue();

      await Future<void>.delayed(const Duration(milliseconds: 300));
      await pumpEventQueue();
      expect(
        fake.calls.where((c) => c.startsWith('open:')),
        hasLength(1),
        reason: '用户暂停的黑屏等待不得被死开流看门狗打断',
      );
    });
  });

  group('解码混沌观测(decode_flap,不自动重开)', () {
    setUp(() {
      player.dispose();
      // 采样周期 80ms:混沌累计快速结算;宽限同步拉长避免死开流路径抢戏。
      fake = _FakePlatformPlayer();
      player = MediaKitLivePlayer(
        player: Player(platformPlayer: fake),
        policy: const PlaybackRetryPolicy(
          baseDelay: Duration(milliseconds: 150),
          maxDelay: Duration(milliseconds: 150),
          deadOpenGrace: Duration(seconds: 9),
        ),
        stabilityInterval: const Duration(milliseconds: 80),
      );
      snapshots = <PlayerSnapshot>[];
      snapshotSub = player.snapshots.listen(snapshots.add);
    });

    test('混沌累计达阈值 → 落 decode_flap 观测,但不重开', () async {
      await enterPlaying();
      // 45 条同型混沌跨越多个 80ms tick:每 tick ≥12 条即记 decode_flap。
      // 对齐 pure_live(2026-09-27 晚间):自动重试类操作全部下线,观测
      // 事件只做事后归因,绝不触发重开。
      for (var i = 0; i < 45; i++) {
        fake.emitWarn(
          'cplayer',
          'Invalid video timestamp: ${100 + i}.0 -> ${90 + i}.0',
        );
      }
      await waitFor(
        () => logLines().any((l) => l.contains('decode_flap')),
      );
      final opens = fake.calls.where((c) => c.startsWith('open:')).length;
      expect(opens, 1, reason: '混沌只观测,不得自动重开');
      expect(
        logLines().any((l) => l.contains('decode_storm_reopen')),
        isFalse,
        reason: '风暴重开机制已下线,不得出现在日志里',
      );
    });
  });

  group('播放时钟回跳观测(time_pos_regression,不自动重开)', () {
    setUp(() {
      player.dispose();
      // 采样周期 80ms:回跳在 1-2 个 tick 内被捕获;宽限同步拉长避免
      // 死开流路径抢戏。
      fake = _FakePlatformPlayer();
      player = MediaKitLivePlayer(
        player: Player(platformPlayer: fake),
        policy: const PlaybackRetryPolicy(
          baseDelay: Duration(milliseconds: 150),
          maxDelay: Duration(milliseconds: 150),
          deadOpenGrace: Duration(seconds: 9),
        ),
        stabilityInterval: const Duration(milliseconds: 80),
      );
      snapshots = <PlayerSnapshot>[];
      snapshotSub = player.snapshots.listen(snapshots.add);
    });

    test('time-pos 回跳 >2s → 落观测事件,不重开', () async {
      await enterPlaying();
      fake.fakeTimePos = 100.0;
      await Future<void>.delayed(const Duration(milliseconds: 200));
      // 5s 采样窗内回跳 5s:只有上游重发旧数据(重放)才可能出现,
      // 网络抖动只会让播放位置停滞或缓慢推进,不会倒退。
      fake.fakeTimePos = 95.0;
      await waitFor(
        () => logLines().any((l) => l.contains('time_pos_regression')),
      );
      final opens = fake.calls.where((c) => c.startsWith('open:')).length;
      expect(opens, 1, reason: '对齐 pure_live:回跳只观测,不得自动重开');
    });

    test('小幅回跳(<2s)不落观测事件', () async {
      await enterPlaying();
      fake.fakeTimePos = 100.0;
      await Future<void>.delayed(const Duration(milliseconds: 200));
      // 1s 回跳在阈值(2s)之下:PTS 微调/时钟校正范围内的正常波动。
      fake.fakeTimePos = 99.0;
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final opens = fake.calls.where((c) => c.startsWith('open:')).length;
      expect(opens, 1, reason: '阈值下的回跳不该打断播放');
      expect(
        logLines().any((l) => l.contains('time_pos_regression')),
        isFalse,
        reason: '阈值下的回跳属 PTS 微调,不落观测事件',
      );
    });
  });
}
