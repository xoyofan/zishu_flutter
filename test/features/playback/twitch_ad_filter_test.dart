/// Twitch 广告过滤代理端到端单测:本地起上游仿真服务器,验证
/// 改写/过滤/广告态/失效续命/淘汰的完整行为。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_parser/live_parser.dart' show StreamLine;
import 'package:zishu_flutter/src/platforms/common/playback/twitch_ad_filter.dart';

/// 广告期 playlist: stitched-ad 窗口 + Amazon 段 + 一个 live 段。
const _adBody = '''
#EXTM3U
#EXT-X-TARGETDURATION:6
#EXT-X-MEDIA-SEQUENCE:10
#EXT-X-DATERANGE:ID="stitched-ad-1",CLASS="twitch-stitched-ad",START-DATE="2026-09-19T18:40:00.020Z",DURATION=30.235
#EXT-X-PROGRAM-DATE-TIME:2026-09-19T18:40:00.020Z
#EXTINF:2.000,Amazon|123
https://seg.example/v1/segment/ad-11
#EXT-X-PROGRAM-DATE-TIME:2026-09-19T18:40:30.500Z
#EXTINF:2.000,live
https://seg.example/v1/segment/live-12
''';

/// 正常期 playlist。
const _liveBody = '''
#EXTM3U
#EXT-X-TARGETDURATION:6
#EXT-X-MEDIA-SEQUENCE:12
#EXT-X-PROGRAM-DATE-TIME:2026-09-19T18:40:30.500Z
#EXTINF:2.000,live
https://seg.example/v1/segment/live-12
#EXT-X-PROGRAM-DATE-TIME:2026-09-19T18:40:32.500Z
#EXTINF:2.000,live
https://seg.example/v1/segment/live-13
''';

Future<String> _fetch(String url) async {
  final client = HttpClient();
  try {
    final request = await client.openUrl('GET', Uri.parse(url));
    final response = await request.close();
    // 先 await 完整读出再 return:若直接 `return join()`,finally 里的
    // close(force:) 会在 join 完成前执行,把在途响应连接掐断。
    final body = await response.transform(utf8.decoder).join();
    return body;
  } finally {
    client.close(force: true);
  }
}

void main() {
  late HttpServer upstream;
  String upstreamBody = _adBody;
  int upstreamStatus = 200;
  final upstreamRequests = <String>[];

  setUp(() async {
    upstreamBody = _adBody;
    upstreamStatus = 200;
    upstreamRequests.clear();
    upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((request) async {
      upstreamRequests.add(request.headers.value('referer') ?? '');
      request.response.statusCode = upstreamStatus;
      request.response.headers.set(
        HttpHeaders.contentTypeHeader,
        'application/vnd.apple.mpegurl',
      );
      request.response.add(utf8.encode(upstreamBody));
      await request.response.close();
    });
  });

  tearDown(() async {
    await upstream.close(force: true);
  });

  StreamLine upstreamLine() => StreamLine(
    name: '480p',
    url: 'http://127.0.0.1:${upstream.port}/v1/playlist/abc.m3u8',
    format: 'hls',
    headers: const {'Referer': 'https://www.twitch.tv/'},
  );

  TwitchAdFilter filterForUpstream() => TwitchAdFilter(shouldFilter: (_) => true);

  group('wrapLine', () {
    test('非 Twitch 线路原样返回(同一实例)', () async {
      final filter = TwitchAdFilter();
      const line = StreamLine(
        name: 'HLS',
        url: 'https://a.example.com/live.m3u8',
        format: 'hls',
      );
      expect(await filter.wrapLine(line), same(line));
      await filter.dispose();
    });

    test('需过滤线路改写为本地地址,名称/格式/请求头保留', () async {
      final filter = filterForUpstream();
      final wrapped = await filter.wrapLine(upstreamLine());
      final uri = Uri.parse(wrapped.url);
      expect(uri.host, '127.0.0.1');
      expect(uri.pathSegments, hasLength(3));
      expect(uri.pathSegments.first, 's');
      expect(wrapped.name, '480p');
      expect(wrapped.format, 'hls');
      expect(wrapped.headers, upstreamLine().headers);
      await filter.dispose();
    });
  });

  group('本地代理行为', () {
    test('回吐过滤结果并点亮广告态,请求头透传上游', () async {
      final filter = filterForUpstream();
      final wrapped = await filter.wrapLine(upstreamLine());

      final body = await _fetch(wrapped.url);
      expect(body, isNot(contains('ad-11')));
      expect(body, contains('live-12'));
      // 首个块(广告)被剔除 → MEDIA-SEQUENCE 重写为首个保留段(live-12)的真实序号。
      expect(body, contains('#EXT-X-MEDIA-SEQUENCE:11'));
      expect(filter.isAdStalled(wrapped.url), isTrue);
      expect(upstreamRequests.single, 'https://www.twitch.tv/');
      await filter.dispose();
    });

    test('上游恢复正常后广告态熄灭', () async {
      final filter = filterForUpstream();
      final wrapped = await filter.wrapLine(upstreamLine());
      // 首次拉取:广告期内容,广告态点亮。
      await _fetch(wrapped.url);
      expect(filter.isAdStalled(wrapped.url), isTrue);

      // 上游切换为正常内容:下一次拉取后广告态熄灭。
      upstreamBody = _liveBody;
      final body = await _fetch(wrapped.url);
      expect(body, contains('live-13'));
      expect(filter.isAdStalled(wrapped.url), isFalse);
      await filter.dispose();
    });

    test('上游失效回吐最近结果,连续失败后广告态熄灭', () async {
      final filter = filterForUpstream();
      final wrapped = await filter.wrapLine(upstreamLine());
      await _fetch(wrapped.url);
      expect(filter.isAdStalled(wrapped.url), isTrue);

      upstreamStatus = 500;
      final body = await _fetch(wrapped.url);
      // 首次失败仍续命最近结果(已过滤的广告期 playlist),广告态保留。
      expect(body, contains('#EXT-X-MEDIA-SEQUENCE:11'));
      expect(filter.isAdStalled(wrapped.url), isTrue);

      await _fetch(wrapped.url);
      // 连续第二次失败:上游已死,广告态不再豁免看门狗。
      expect(filter.isAdStalled(wrapped.url), isFalse);
      await filter.dispose();
    });

    test('未知地址一律不点亮广告态', () async {
      final filter = filterForUpstream();
      expect(filter.isAdStalled('http://127.0.0.1:1/s/nope/playlist.m3u8'), isFalse);
      expect(filter.isAdStalled('https://a.example.com/live.m3u8'), isFalse);
      expect(filter.isAdStalled('not a url'), isFalse);
      await filter.dispose();
    });

    test('dispose 后本地端口关闭,请求失败', () async {
      final filter = filterForUpstream();
      final wrapped = await filter.wrapLine(upstreamLine());
      await filter.dispose();
      await expectLater(_fetch(wrapped.url), throwsException);
    });
  });
}
