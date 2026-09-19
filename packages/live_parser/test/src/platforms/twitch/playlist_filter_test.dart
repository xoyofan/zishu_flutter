/// Twitch media playlist 广告过滤单测。
///
/// 过滤口径对齐 streamlink 的 twitch 插件(其广告过滤永远开启):
/// 广告 DATERANGE(`CLASS="twitch-stitched-ad"` 或 `ID` 以 `stitched-ad-`
/// 开头)圈出的 PROGRAM-DATE-TIME 区间内的段、以及 EXTINF 标题含 Amazon 的
/// 段,全部剔除;MEDIA-SEQUENCE 重写为首个保留段的真实序号,保证播放器侧
/// "新段"判定与上游真实序号对齐(不重写会在段被剔除后整体漂移,把后续
/// 真段误判为已播过而跳过,表现为反复卡住)。PDT 归属其后的段(streamlink
/// 同款),保留段把 PDT 回填到 EXTINF 前输出。
library;

import 'dart:convert';
import 'dart:io';

import 'package:live_parser/src/platforms/twitch/playlist_filter.dart';
import 'package:test/test.dart';

String _fixture(String name) =>
    File('test/fixtures/twitch/$name').readAsStringSync();

List<String> _lines(String body) => const LineSplitter().convert(body);

List<String> _segments(String body) =>
    _lines(body).where((line) => line.startsWith('https://')).toList();

void main() {
  group('非广告 playlist', () {
    test('无广告时:段序/表头不变,adActive 为 false', () {
      final body = _fixture('media_playlist_live.m3u8');
      final result = filterTwitchMediaPlaylist(body);
      expect(result.adActive, isFalse);
      // 段完整保留且顺序不变。
      expect(_segments(result.body), _segments(body));
      // MEDIA-SEQUENCE 与 DATERANGE 原样保留。
      expect(result.body, contains('#EXT-X-MEDIA-SEQUENCE:18225'));
      expect(result.body, contains('CLASS="twitch-session"'));
      // 剔除了 0 个块,不应凭空出现/丢失 EXTINF。
      expect(
        _lines(result.body).where((line) => line.startsWith('#EXTINF')).length,
        3,
      );
    });

    test('master 清单 / 非 m3u8 文本原样返回(含换行符原样)', () {
      final master = _fixture('usher_master.m3u8');
      final result = filterTwitchMediaPlaylist(master);
      expect(result.adActive, isFalse);
      expect(result.body, master);

      const junk = 'Not Found';
      expect(filterTwitchMediaPlaylist(junk).body, junk);
    });
  });

  group('广告剔除(手工结构 fixture:后置 PDT + 广告边界)', () {
    late TwitchPlaylistFilterResult result;

    setUp(() {
      result = filterTwitchMediaPlaylist(_fixture('media_playlist_ad.m3u8'));
    });

    test('标记广告激活', () {
      expect(result.adActive, isTrue);
    });

    test('广告段被剔除,live 段保留', () {
      expect(result.body, contains('live-18230'));
      expect(result.body, contains('live-18231'));
      expect(result.body, contains('live-18234'));
      expect(result.body, isNot(contains('ad-18232')));
      expect(result.body, isNot(contains('ad-18233')));
    });

    test('广告 DATERANGE 行被剔除,非广告 DATERANGE 保留', () {
      expect(result.body, isNot(contains('twitch-stitched-ad')));
      expect(result.body, contains('twitch-session'));
      expect(result.body, contains('CLASS="timestamp"'));
    });

    test('MEDIA-SEQUENCE 保持首个保留段的真实序号', () {
      // 首个块(18230)未被剔除,序号无需改写。
      expect(result.body, contains('#EXT-X-MEDIA-SEQUENCE:18230'));
    });

    test('广告块剔除后相邻 DISCONTINUITY 合并为一条', () {
      final discontinuities = _lines(
        result.body,
      ).where((line) => line == '#EXT-X-DISCONTINUITY').length;
      expect(discontinuities, 1);
    });
  });

  group('广告剔除(真实抓取样本结构:游离 PDT/无引号 DURATION/Amazon|id)', () {
    late TwitchPlaylistFilterResult result;

    setUp(() {
      result = filterTwitchMediaPlaylist(_fixture('media_playlist_ad_real.m3u8'));
    });

    test('标记广告激活,广告段全部剔除', () {
      expect(result.adActive, isTrue);
      expect(result.body, isNot(contains('ad-2921')));
      expect(result.body, isNot(contains('ad-2922')));
    });

    test('live 段保留且顺序不变', () {
      expect(_segments(result.body), [
        'https://seg.example/v1/segment/live-2919.ts?dna=token',
        'https://seg.example/v1/segment/live-2920.ts?dna=token',
        'https://seg.example/v1/segment/live-2923.ts?dna=token',
      ]);
    });

    test('只剔除 stitched-ad 的 DATERANGE,quartile/source 类保留', () {
      expect(result.body, isNot(contains('twitch-stitched-ad')));
      expect(result.body, contains('twitch-ad-quartile'));
      expect(result.body, contains('twitch-stream-source'));
    });

    test('MEDIA-SEQUENCE 不变(首个保留段即首块),DISCONTINUITY 合并为一条', () {
      expect(result.body, contains('#EXT-X-MEDIA-SEQUENCE:2919'));
      final discontinuities = _lines(
        result.body,
      ).where((line) => line == '#EXT-X-DISCONTINUITY').length;
      expect(discontinuities, 1);
    });

    test('保留段把挂靠的 PDT 回填到 EXTINF 前(时间锚不丢)', () {
      final body = result.body;
      final pdtIndex = body.indexOf(
        '#EXT-X-PROGRAM-DATE-TIME:2026-09-19T19:02:51.744',
      );
      final extInfIndex = body.indexOf(
        '#EXTINF:2.000,live\nhttps://seg.example/v1/segment/live-2923',
      );
      expect(pdtIndex, greaterThanOrEqualTo(0));
      expect(extInfIndex, greaterThan(pdtIndex));
    });
  });

  group('MEDIA-SEQUENCE 重写与边界', () {
    const adDaterange =
        '#EXT-X-DATERANGE:ID="stitched-ad-1",CLASS="twitch-stitched-ad",'
        'START-DATE="2026-09-19T18:40:00.020Z",DURATION="60.000"';

    List<String> segmentLines(String body) => _lines(
      body,
    ).where((line) => line.startsWith('https://')).toList();

    test('首块是广告时 MEDIA-SEQUENCE 重写为首个保留段序号', () {
      final body = [
        '#EXTM3U',
        '#EXT-X-MEDIA-SEQUENCE:18230',
        adDaterange,
        '#EXT-X-PROGRAM-DATE-TIME:2026-09-19T18:40:00.020Z',
        '#EXTINF:30.000,Amazon',
        'https://seg.example/v1/segment/ad-18230',
        '#EXT-X-PROGRAM-DATE-TIME:2026-09-19T18:41:00.020Z',
        '#EXTINF:2.000,live',
        'https://seg.example/v1/segment/live-18231',
        '#EXT-X-PROGRAM-DATE-TIME:2026-09-19T18:41:02.020Z',
        '#EXTINF:2.000,live',
        'https://seg.example/v1/segment/live-18232',
      ].join('\n');

      final result = filterTwitchMediaPlaylist(body);
      expect(result.adActive, isTrue);
      expect(result.body, contains('#EXT-X-MEDIA-SEQUENCE:18231'));
      expect(segmentLines(result.body), [
        'https://seg.example/v1/segment/live-18231',
        'https://seg.example/v1/segment/live-18232',
      ]);
    });

    test('全广告窗口:输出零段且 MS 不前推(防下次刷新序号回滚)', () {
      final body = [
        '#EXTM3U',
        '#EXT-X-MEDIA-SEQUENCE:18230',
        adDaterange,
        '#EXTINF:30.000,Amazon',
        'https://seg.example/v1/segment/ad-18230',
        '#EXT-X-PROGRAM-DATE-TIME:2026-09-19T18:40:00.020Z',
        '#EXTINF:30.000,Amazon',
        'https://seg.example/v1/segment/ad-18231',
        '#EXT-X-PROGRAM-DATE-TIME:2026-09-19T18:40:30.020Z',
      ].join('\n');

      final result = filterTwitchMediaPlaylist(body);
      expect(result.adActive, isTrue);
      expect(segmentLines(result.body), isEmpty);
      expect(result.body, contains('#EXT-X-MEDIA-SEQUENCE:18230'));
    });

    test('PDT 恰在窗口终点不被剔除,起点及其后被剔除(广告边界 PDT 前置形态)', () {
      // 窗口 [18:40:00.020, 18:41:00.020):起点段剔除,终点段保留。
      final body = [
        '#EXTM3U',
        '#EXT-X-MEDIA-SEQUENCE:100',
        adDaterange,
        '#EXT-X-PROGRAM-DATE-TIME:2026-09-19T18:40:00.020Z',
        '#EXTINF:30.000,live',
        'https://seg.example/v1/segment/at-start',
        '#EXT-X-PROGRAM-DATE-TIME:2026-09-19T18:41:00.020Z',
        '#EXTINF:30.000,live',
        'https://seg.example/v1/segment/at-end',
      ].join('\n');

      final result = filterTwitchMediaPlaylist(body);
      expect(segmentLines(result.body), ['https://seg.example/v1/segment/at-end']);
      // 首块被剔除 → MS 重写为 101。
      expect(result.body, contains('#EXT-X-MEDIA-SEQUENCE:101'));
    });

    test('EXTINF 标题含 Amazon(大小写不敏感)即剔除', () {
      final body = [
        '#EXTM3U',
        '#EXT-X-MEDIA-SEQUENCE:200',
        '#EXTINF:30.000,amazon',
        'https://seg.example/v1/segment/ad-title',
        '#EXT-X-PROGRAM-DATE-TIME:2026-09-19T18:40:00.020Z',
        '#EXTINF:2.000,live',
        'https://seg.example/v1/segment/live',
        '#EXT-X-PROGRAM-DATE-TIME:2026-09-19T18:40:02.020Z',
      ].join('\n');

      final result = filterTwitchMediaPlaylist(body);
      expect(result.adActive, isTrue);
      expect(result.body, isNot(contains('ad-title')));
      expect(result.body, contains('segment/live'));
    });

    test('无 PDT 且标题非 Amazon 的段保留(fail-open)', () {
      final body = [
        '#EXTM3U',
        '#EXT-X-MEDIA-SEQUENCE:300',
        adDaterange,
        '#EXTINF:2.000,live',
        'https://seg.example/v1/segment/no-pdt',
      ].join('\n');

      final result = filterTwitchMediaPlaylist(body);
      expect(result.body, contains('no-pdt'));
    });
  });
}
