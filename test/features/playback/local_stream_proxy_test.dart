/// 本地流代理单测(真实 loopback IO,回环在 flutter_test_config 已放行)。
///
/// 对齐官方 DySDKController(127.0.0.1:5001)的架构:mpv 只见本地稳定流,
/// 远端断开/换源由代理层消化。覆盖:透传、upstream 热切换无缝拼接
/// (无第二个 FLV header、时间轴单调)、上游失败断开下游、资源清理。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zishu_flutter/src/platforms/common/playback/local_stream_proxy.dart';

Uint8List _bytes(List<int> v) => Uint8List.fromList(v);

Uint8List _flvHeader() => _bytes([
      0x46, 0x4C, 0x56, 0x01, 0x05, 0, 0, 0, 9, 0, 0, 0, 0,
    ]);

Uint8List _tag(int type, List<int> data, int tsMs) {
  final size = data.length;
  final ts24 = tsMs & 0xFFFFFF;
  return _bytes([
    type,
    (size >> 16) & 0xFF, (size >> 8) & 0xFF, size & 0xFF,
    (ts24 >> 16) & 0xFF, (ts24 >> 8) & 0xFF, ts24 & 0xFF,
    (tsMs >> 24) & 0xFF,
    0, 0, 0,
    ...data,
    ((11 + size) >> 24) & 0xFF, ((11 + size) >> 16) & 0xFF,
    ((11 + size) >> 8) & 0xFF, (11 + size) & 0xFF,
  ]);
}

Uint8List _metaTag() => _tag(18, [0x02, 0x00, 0x0A, 0x40, 0x6F], 0);
Uint8List _seqTag() => _tag(9, [0x17, 0x00, 0x01, 0x64, 0x00], 0);
Uint8List _videoTag(int ts) => _tag(9, [0x17, 0x01, 0xC0, 0x00], ts);
Uint8List _audioTag(int ts) => _tag(8, [0xAF, 0x01, 0x2A], ts);

int _tsAt(Uint8List b, int i) => (b[i + 7] << 24) | (b[i + 4] << 16) | (b[i + 5] << 8) | b[i + 6];

void main() {
  HttpServer? upstreamA;
  HttpServer? upstreamB;
  late LocalStreamProxy proxy;

  setUp(() async {
    proxy = LocalStreamProxy();
    await proxy.start();
  });

  tearDown(() async {
    await proxy.stop();
    await upstreamA?.close(force: true);
    await upstreamB?.close(force: true);
    upstreamA = null;
    upstreamB = null;
  });

  /// 占一个必然拒绝的端口:bind 后立即关闭 → 连接被拒。
  Future<int> deadPort() async {
    final dead = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = dead.port;
    await dead.close();
    return port;
  }

  /// 假上游:把 [script] 的字节分段写出;[closeAfter] 段写完后正常关闭连接
  /// (不设则挂 30s,模拟直播永续流,由测试侧或代理层终止)。
  Future<HttpServer> fakeUpstream(
    List<List<int>> script, {
    int? closeAfter,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final response = request.response;
      response.bufferOutput = false;
      response.headers.contentType = ContentType(
        'video',
        'x-flv',
      );
      for (var i = 0; i < script.length; i++) {
        response.add(_bytes(script[i]));
        await response.flush();
        if (closeAfter != null && i + 1 == closeAfter) {
          await response.close();
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 15));
      }
      await Future<void>.delayed(const Duration(seconds: 30));
      await response.close();
    });
    return server;
  }

  /// 客户端读 [url] 直到连接关闭(或超时),返回全部字节。
  Future<Uint8List> readAll(Uri url, {Duration timeout = const Duration(seconds: 5)}) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(url).timeout(timeout);
      final response = await request.close().timeout(timeout);
      final builder = BytesBuilder();
      await for (final chunk in response) {
        builder.add(chunk);
      }
      return builder.takeBytes();
    } finally {
      client.close(force: true);
    }
  }

  test('透传:上游字节原样到达客户端', () async {
    final payload = <List<int>>[
      [..._flvHeader(), ..._metaTag(), ..._seqTag()],
      [..._videoTag(0), ..._audioTag(30)],
    ];
    upstreamA = await fakeUpstream(payload, closeAfter: payload.length);
    final session = proxy.openSession(
      'http://127.0.0.1:${upstreamA!.port}/live.flv',
    );
    final received = await readAll(Uri.parse(session.localUrl));
    expect(
      received,
      equals(_bytes(payload.expand((c) => c).toList())),
      reason: '无切换时代理必须逐字节透传',
    );
    session.dispose();
  });

  test('热切换:换上游后无第二个 FLV header,时间轴单调连续', () async {
    // A:header + 前导 + 两个媒体 tag(ts 0/30)。
    final scriptA = <List<int>>[
      [..._flvHeader(), ..._metaTag(), ..._seqTag()],
      [..._videoTag(0), ..._audioTag(30)],
    ];
    // B:从零起的新流(前导齐全)。
    final scriptB = <List<int>>[
      [..._flvHeader(), ..._metaTag(), ..._seqTag()],
      [..._videoTag(0), ..._audioTag(40), ..._videoTag(80)],
    ];
    upstreamA = await fakeUpstream(scriptA);
    upstreamB = await fakeUpstream(scriptB);

    final session = proxy.openSession(
      'http://127.0.0.1:${upstreamA!.port}/live.flv',
    );
    final done = readAll(Uri.parse(session.localUrl));

    // 等 A 的两段到达后热切换到 B。
    await Future<void>.delayed(const Duration(milliseconds: 120));
    await session.switchUpstream(
      'http://127.0.0.1:${upstreamB!.port}/live.flv',
    );
    // B 走完后 readAll 因 A/B 连接保持而未结束:此测试里让 B 也掐掉。
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await session.dispose();

    final received = await done;
    // 解析输出:首 13B 是 FLV header(唯一一个),其后必须是媒体 tag 序列。
    expect(_bytes(received.sublist(0, 3)), equals([0x46, 0x4C, 0x56]));
    expect(
      received.sublist(13),
      isNot(contains(0x46)),
      reason: '切换后不得再出现 FLV header 的 F 字节(0x46 仅 header 首字节用)',
    );
    // 逐 tag 验证时间轴单调(只对媒体 tag 断言;首连接透传的前导
    // meta/seq tag ts 恒为 0,属正常)。
    var offset = 13;
    var lastTs = -1;
    var mediaTags = 0;
    while (offset + 15 <= received.length) {
      final type = received[offset];
      final size = (received[offset + 1] << 16) |
          (received[offset + 2] << 8) |
          received[offset + 3];
      final tagLen = 11 + size + 4;
      if (offset + tagLen > received.length) break;
      final isPreamble = type == 18 ||
          (size >= 2 && received[offset + 12] == 0 && (type == 8 || type == 9));
      if (!isPreamble) {
        final ts = _tsAt(received, offset);
        expect(ts, greaterThan(lastTs), reason: '媒体 tag#$mediaTags ts 必须严格递增');
        lastTs = ts;
        mediaTags++;
      }
      offset += tagLen;
    }
    expect(mediaTags, 5, reason: 'A 的 2 个 + B 的 3 个媒体 tag 全部到达');
  });

  test('上游连不上:客户端连接被关闭,字节只有已发部分', () async {
    final scriptA = <List<int>>[
      [..._flvHeader(), ..._seqTag()],
      [..._videoTag(0)],
    ];
    upstreamA = await fakeUpstream(scriptA);

    final session = proxy.openSession(
      'http://127.0.0.1:${upstreamA!.port}/live.flv',
    );
    final done = readAll(Uri.parse(session.localUrl));
    await Future<void>.delayed(const Duration(milliseconds: 120));
    await session.switchUpstream('http://127.0.0.1:${await deadPort()}/live.flv');
    final received = await done;
    expect(received.length, _flvHeader().length + _seqTag().length + _videoTag(0).length,
        reason: '切换失败时客户端只收到旧流已发字节,随后连接被断开');
    session.dispose();
  });
}
