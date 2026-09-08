// E6 generation fence 测试：切源/切房时旧后端的乱序事件不得回调。
// 目标文件 lib/engine/playback/web_video_player_adapter.dart。
// VM 运行：backendFactory/surfaceFactory 注入 fake（条件导出走 stub，真实 JS 侧不参与）。
import 'dart:async';

import 'package:flutter/widgets.dart' show BoxFit, SizedBox, Widget;
import 'package:flutter_test/flutter_test.dart';
import 'package:zishu_flutter/engine/playback/web_player_backend.dart';
import 'package:zishu_flutter/engine/playback/web_video_player_adapter.dart';

/// Fake 后端：可挂起 open（openGate）、可注入 dispose 期间的“临终”事件。
class FakeBackend extends WebPlayerBackendBase {
  final List<String> calls = [];
  Completer<void>? openGate;
  void Function()? onDispose;
  Object? lastMediaElement;
  String? lastUrl;
  String? lastFormat;
  bool disposed = false;

  @override
  Future<void> open(String url, {required String format, Object? mediaElement}) async {
    calls.add('open:$format:$url');
    lastUrl = url;
    lastFormat = format;
    lastMediaElement = mediaElement;
    final gate = openGate;
    if (gate != null) await gate.future;
  }

  @override
  Future<void> play() async => calls.add('play');
  @override
  Future<void> pause() async => calls.add('pause');
  @override
  Future<void> stop() async => calls.add('stop');
  @override
  Future<void> setVolume(double volume) async => calls.add('volume:$volume');

  @override
  Future<void> dispose() async {
    calls.add('dispose');
    disposed = true;
    onDispose?.call();
    await closeEventHub();
  }

  // 测试注入事件
  void emitPlayingNow(bool v) => emitPlaying(v);
  void emitBufferingNow(bool v) => emitBuffering(v);
  void emitErrorNow(String m) => emitError(m);
  void emitCompletedNow() => emitCompleted(true);
  void emitSizeNow(VideoSize s) => emitSize(s);
}

class FakeSurface implements WebVideoSurface {
  final Object element = Object();
  int disposed = 0;
  @override
  Widget buildWidget(BoxFit fit) => const SizedBox.shrink();
  @override
  Object? get mediaElement => element;
  @override
  Future<void> dispose() async => disposed++;
}

Future<void> _pump() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  test('setDataSource：headers 非空改写代理；空则直连；kind 选对后端', () async {
    final backend = FakeBackend();
    final surface = FakeSurface();
    final adapter = WebVideoPlayerAdapter(
      backendFactory: (_) => backend,
      surfaceFactory: () => surface,
      resolveStreamApiBaseUrl: () => 'http://srv:8080/',
    );
    await adapter.init();

    // 1) 带 Referer 的斗鱼 FLV → 代理改写 + flv 后端（mpegts.js）
    await adapter.setDataSource(
      'https://a.b/x.flv?wsSecret=1',
      const [],
      const {'Referer': 'https://www.douyu.com/'},
      site: 'douyu',
      roomId: '123',
    );
    final expectedProxy = 'http://srv:8080/api/live-stream'
        '?site=douyu&room=123&url=${Uri.encodeQueryComponent('https://a.b/x.flv?wsSecret=1')}';
    expect(backend.lastFormat, 'flv');
    expect(backend.lastUrl, expectedProxy);
    expect(backend.lastMediaElement, surface.mediaElement);
    expect(adapter.state, PlayerState.ready);

    // 2) bilibili HLS 无 headers → 直连 + hls 后端
    await adapter.setDataSource('https://a.b/x.m3u8', const [], const {}, site: 'bilibili');
    expect(backend.lastFormat, 'hls');
    expect(backend.lastUrl, 'https://a.b/x.m3u8');
    expect(adapter.state, PlayerState.ready);

    // 3) IPTV ts → mpegts 后端
    await adapter.setDataSource('http://a.b/x.ts', const [], const {});
    expect(backend.lastFormat, 'mpegts');

    // 4) play/pause 透传
    await adapter.play();
    await adapter.pause();
    await adapter.setVolume(0.5);
    expect(backend.calls, containsAll(['play', 'pause', 'volume:0.5']));
  });

  test('备用线路：首选 other 格式时回退 playUrls 中第一个可判定格式', () async {
    final backend = FakeBackend();
    final adapter = WebVideoPlayerAdapter(
      backendFactory: (_) => backend,
      surfaceFactory: () => FakeSurface(),
      resolveStreamApiBaseUrl: () => 'http://srv:8080',
    );
    await adapter.init();
    await adapter.setDataSource(
      'https://a.b/x.mp4', // 首选不支持
      const ['https://a.b/y.flv'],
      const {},
    );
    expect(backend.lastFormat, 'flv');
    expect(backend.lastUrl, 'https://a.b/y.flv');
  });

  test('不支持格式：不创建后端，报 error', () async {
    var factoryCalls = 0;
    final adapter = WebVideoPlayerAdapter(
      backendFactory: (_) {
        factoryCalls++;
        return FakeBackend();
      },
      surfaceFactory: () => FakeSurface(),
    );
    await adapter.init();

    final errors = <PlaybackException>[];
    adapter.onError.listen(errors.add);
    final states = <PlayerState>[];
    adapter.onStateChanged.listen(states.add);

    await adapter.setDataSource('https://a.b/x.mp4', const [], const {});
    await _pump();
    expect(factoryCalls, 0);
    expect(errors, hasLength(1));
    expect(errors.first.code, 'format');
    expect(states, contains(PlayerState.error));
    expect(adapter.state, PlayerState.error);
  });

  test('generation fence：迟到的旧后端 open 完成 → 强制回收，不污染新会话', () async {
    final surface = FakeSurface();
    final b1 = FakeBackend()..openGate = Completer<void>();
    final b2 = FakeBackend();
    final queue = [b1, b2];
    final adapter = WebVideoPlayerAdapter(
      backendFactory: (_) => queue.removeAt(0),
      surfaceFactory: () => surface,
      resolveStreamApiBaseUrl: () => 'http://srv:8080',
    );
    await adapter.init();

    final errors = <PlaybackException>[];
    adapter.onError.listen(errors.add);
    final playing = <bool>[];
    adapter.onPlaying.listen(playing.add);

    // 会话1：open 被挂起（不 await —— open 在飞行中，用户此刻切源）
    final open1 = adapter.setDataSource('https://a/1.m3u8', const [], const {});
    await _pump();
    expect(adapter.state, PlayerState.preparing);

    // 会话2：切源（b1 被 dispose，b2 打开成功）
    await adapter.setDataSource('https://a/2.flv', const [], const {});
    expect(b1.disposed, isTrue);
    expect(adapter.state, PlayerState.ready);
    expect(playing, [false, false]);

    // 迟到：会话1的 open 才完成
    b1.openGate!.complete();
    await open1;
    await _pump();

    expect(b1.calls.where((c) => c == 'dispose'), hasLength(2), reason: 'teardown + 迟到回收');
    expect(errors, isEmpty, reason: '旧会话事件不得回调');
    expect(adapter.state, PlayerState.ready);
    expect(adapter.isPlayingNow, isFalse);
  });

  test('generation fence：旧后端 dispose 期间的“临终”错误不得回调新会话', () async {
    final surface = FakeSurface();
    final b1 = FakeBackend();
    final b2 = FakeBackend();
    final queue = [b1, b2];
    final adapter = WebVideoPlayerAdapter(
      backendFactory: (_) => queue.removeAt(0),
      surfaceFactory: () => surface,
      resolveStreamApiBaseUrl: () => 'http://srv:8080',
    );
    await adapter.init();

    final errors = <PlaybackException>[];
    adapter.onError.listen(errors.add);
    final states = <PlayerState>[];
    adapter.onStateChanged.listen(states.add);

    await adapter.setDataSource('https://a/1.flv', const [], const {});
    expect(adapter.state, PlayerState.ready);

    // 旧后端在 dispose 里同步吐 error（模拟 flv.js 切房死亡回调）
    b1.onDispose = () => b1.emitErrorNow('dying gasp');
    await adapter.setDataSource('https://a/2.flv', const [], const {});
    await _pump();

    expect(errors, isEmpty, reason: '旧会话临终事件必须被 token 过滤');
    expect(adapter.state, PlayerState.ready);
  });

  test('新会话正常事件照常回调；切源后尺寸复位', () async {
    final surface = FakeSurface();
    final b1 = FakeBackend();
    final b2 = FakeBackend();
    final queue = [b1, b2];
    final adapter = WebVideoPlayerAdapter(
      backendFactory: (_) => queue.removeAt(0),
      surfaceFactory: () => surface,
      resolveStreamApiBaseUrl: () => 'http://srv:8080',
    );
    await adapter.init();

    final playing = <bool>[];
    adapter.onPlaying.listen(playing.add);
    final widths = <int?>[];
    adapter.width.listen(widths.add);

    await adapter.setDataSource('https://a/1.flv', const [], const {});
    b1.emitSizeNow(const VideoSize(1920, 1080));
    await _pump();
    expect(widths, contains(1920));

    // 切源：尺寸复位为 null，随后新后端事件生效
    await adapter.setDataSource('https://a/2.flv', const [], const {});
    expect(widths.last, isNull);

    b2.emitPlayingNow(true);
    await _pump();
    expect(adapter.isPlayingNow, isTrue);
    expect(adapter.state, PlayerState.playing);

    // 旧后端此刻再吐事件 → 丢弃
    b1.emitPlayingNow(false);
    b1.emitErrorNow('stale error');
    await _pump();
    expect(adapter.isPlayingNow, isTrue);
    expect(adapter.state, PlayerState.playing);
  });

  test('hardDispose：终止会话、关闭流，之后事件静默', () async {
    final surface = FakeSurface();
    final b1 = FakeBackend();
    final adapter = WebVideoPlayerAdapter(
      backendFactory: (_) => b1,
      surfaceFactory: () => surface,
      resolveStreamApiBaseUrl: () => 'http://srv:8080',
    );
    await adapter.init();
    await adapter.setDataSource('https://a/1.flv', const [], const {});

    await adapter.hardDispose();
    expect(b1.disposed, isTrue);
    expect(surface.disposed, 1);
    expect(adapter.state, PlayerState.disposed);
    expect(adapter.isInitialized, isFalse);

    // dispose 后 setDataSource / play 均为 no-op
    await adapter.setDataSource('https://a/2.flv', const [], const {});
    await adapter.play();
    expect(backendCalls(b1).any((c) => c.startsWith('open:flv:https://a/2.flv')), isFalse);
  });
}

List<String> backendCalls(FakeBackend b) => b.calls;
