/// 播放器 × 本地流代理接线单测(fake platform + 真 loopback 代理)。
///
/// 断言:代理启用时 FLV 直链的 mpv 打开地址是本地 URL(记账/日志仍是远端
/// host);switchStreamSource 热切换不触发 mpv 重开;非 FLV 线路与未启用
/// 代理的播放器行为与原先完全一致(直连远端)。
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_parser/live_parser.dart' show StreamLine;
import 'package:media_kit/media_kit.dart';
import 'package:zishu_flutter/src/platforms/common/playback/local_stream_proxy.dart';
import 'package:zishu_flutter/src/platforms/common/playback/media_kit_live_player.dart';
import 'package:zishu_flutter/src/platforms/common/playback/playback_log.dart';

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
}

void main() {
  late Directory tempDir;
  late String logPath;
  late _FakePlatformPlayer fake;
  late MediaKitLivePlayer player;
  late LocalStreamProxy proxy;
  late HttpServer upstream;

  const flvLine = StreamLine(
    name: 'A',
    url: 'http://a.example.com/live.flv',
    format: 'flv',
  );
  const hlsLine = StreamLine(
    name: 'H',
    url: 'https://h.example.com/live.m3u8',
    format: 'hls',
  );

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('proxy_wire_test');
    logPath = '${tempDir.path}${Platform.pathSeparator}playback.log';
    PlaybackLog.initForTest(logPath);
    proxy = LocalStreamProxy();
    await proxy.start();
    // 假上游:写一段 FLV 头字节后挂 30s —— 响应头随首字节立刻提交
    // (空 flush 不发 headers,dart:io 实测),模拟"已建连的慢直播流"。
    final flvHeader = Uint8List.fromList(
      [0x46, 0x4C, 0x56, 1, 5, 0, 0, 0, 9, 0, 0, 0, 0],
    );
    upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((request) async {
      final response = request.response
        ..bufferOutput = false
        ..headers.contentType = ContentType('video', 'x-flv');
      response.add(flvHeader);
      await response.flush();
      await Future<void>.delayed(const Duration(seconds: 30));
      await response.close();
    });
    fake = _FakePlatformPlayer();
    player = MediaKitLivePlayer(
      player: Player(platformPlayer: fake),
      streamProxy: proxy,
    );
  });

  tearDown(() async {
    player.dispose();
    await proxy.stop();
    await upstream.close(force: true);
    PlaybackLog.resetForTest();
    tempDir.deleteSync(recursive: true);
  });

  List<String> logLines() {
    final file = File(logPath);
    if (!file.existsSync()) return const [];
    return file.readAsLinesSync().where((line) => line.isNotEmpty).toList();
  }

  test('FLV 直链:mpv 打开本地地址,日志 host 归因仍是远端', () async {
    final line = StreamLine(
      name: 'A',
      url: 'http://127.0.0.1:${upstream.port}/live.flv',
      format: 'flv',
    );
    await player.open(line);
    await pumpEventQueue();

    expect(fake.calls.single, 'open:127.0.0.1',
        reason: 'mpv 收到的必须是本地代理地址(远端 host 不得直接出现)');
    expect(
      logLines().any((l) => l.contains('proxy_line_wrap') && l.contains('host=127.0.0.1')),
      isTrue,
      reason: '代理包装必须留痕',
    );
    expect(
      logLines().any((l) => l.contains('open cat=') && l.contains('host=127.0.0.1')),
      isTrue,
      reason: 'open 埋点按远端线路归因 host,不得是本地端口',
    );
  });

  test('switchStreamSource 热切换:mpv 不重开,会话 upstream 已更换', () async {
    final line = StreamLine(
      name: 'A',
      url: 'http://127.0.0.1:${upstream.port}/live.flv',
      format: 'flv',
    );
    await player.open(line);
    await pumpEventQueue();
    expect(fake.calls, hasLength(1));
    // fake 后端不会真正拉流:模拟 mpv 对本地地址发起 GET,让代理会话
    // 建立 client(热切换的前提)。
    final puller = HttpClient();
    final pull = puller.getUrl(Uri.parse(player.debugProxySession!.localUrl));
    unawaited(pull.then((r) => r.close()).then((r) => r.drain<void>().catchError((_) {})));
    // 真实 TCP 往返需要事件循环轮次,微任务 flush 不够。
    await Future<void>.delayed(const Duration(milliseconds: 150));
    await pumpEventQueue();

    final ok = await player.switchStreamSource(line);
    expect(ok, isTrue, reason: 'FLV + 活跃会话必须支持热切换');
    expect(fake.calls, hasLength(1), reason: '热切换不得触发 mpv 重开');
    expect(
      logLines().any((l) => l.contains('proxy_upstream_switch')),
      isTrue,
      reason: 'upstream 切换必须留痕',
    );
    puller.close(force: true);
  });

  test('HLS 线路:不进代理,mpv 直连远端', () async {
    await player.open(hlsLine);
    await pumpEventQueue();
    expect(fake.calls.single, 'open:h.example.com',
        reason: '非 FLV 直链必须保持直连(代理只服务 FLV)');
    expect(
      await player.switchStreamSource(hlsLine),
      isFalse,
      reason: 'HLS 不支持热切换,调用方应回退整组重开',
    );
  });

  test('未启用代理(null):行为与原先完全一致', () async {
    final bare = MediaKitLivePlayer(player: Player(platformPlayer: fake));
    await bare.open(flvLine);
    await pumpEventQueue();
    expect(fake.calls.single, 'open:a.example.com');
    expect(await bare.switchStreamSource(flvLine), isFalse);
    bare.dispose();
  });
}
