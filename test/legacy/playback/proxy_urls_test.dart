// E6 纯逻辑测试：format 判定 / 代理改写 / 线路挑选。
// 目标文件 lib/legacy/web_platform/playback/proxy_urls.dart（纯 Dart，无 JS 依赖）。
import 'package:flutter_test/flutter_test.dart';
import 'package:zishu_flutter/legacy/core/contracts/room_models.dart';
import 'package:zishu_flutter/legacy/web_platform/playback/proxy_urls.dart';

void main() {
  group('playbackUrlKind（对齐 playUrlKind）', () {
    test('hls：.m3u8 直链（含 query）', () {
      expect(playbackUrlKind('https://a.b/x.m3u8'), 'hls');
      expect(playbackUrlKind('https://a.b/x.m3u8?token=1'), 'hls');
      expect(playbackUrlKind('HTTPS://A.B/X.M3U8'), 'hls');
    });

    test('flv：.flv 结尾，query 前置', () {
      expect(playbackUrlKind('https://a.b/x.flv'), 'flv');
      expect(playbackUrlKind('https://a.b/x.flv?wsSecret=a'), 'flv');
    });

    test('mpegts：.ts 直链', () {
      expect(playbackUrlKind('http://a.b/x.ts'), 'mpegts');
      expect(playbackUrlKind('http://a.b/x.ts?token=1'), 'mpegts');
    });

    test('other：mp4 等不支持格式', () {
      expect(playbackUrlKind('https://a.b/x.mp4'), 'other');
      expect(playbackUrlKind(''), 'other');
    });

    test('.ts 出现在路径中间不算 mpegts（.tsx?/ 语义）', () {
      expect(playbackUrlKind('https://a.b/x.ts/y.flv'), 'flv');
    });

    test('代理地址解包后再判 kind', () {
      final inner = 'https://a.b/x.flv?wsSecret=1';
      final proxied =
          'http://srv:8080/api/live-stream?site=douyu&room=1&url=${Uri.encodeQueryComponent(inner)}';
      expect(playbackUrlKind(proxied), 'flv');

      final hls = 'https://a.b/x.m3u8';
      final proxiedHls =
          'http://srv:8080/api/live-stream?site=bilibili&room=2&url=${Uri.encodeQueryComponent(hls)}';
      expect(playbackUrlKind(proxiedHls), 'hls');
    });
  });

  group('proxyUrl / unwrapProxiedStreamUrl', () {
    test('改写为 {base}/api/live-stream?site=&room=&url=（编码）', () {
      final out = proxyUrl(
        'http://srv:8080/',
        'https://a.b/x.flv?wsSecret=1&wsTime=2',
        site: 'douyu',
        room: '123',
      );
      expect(out.startsWith('http://srv:8080/api/live-stream?'), isTrue);
      expect(out.contains('site=douyu'), isTrue);
      expect(out.contains('room=123'), isTrue);
      final uri = Uri.parse(out);
      expect(
        uri.queryParameters['url'],
        'https://a.b/x.flv?wsSecret=1&wsTime=2',
      );
    });

    test('base 尾部斜杠归一化', () {
      final out = proxyUrl('http://srv:8080///', 'https://a.b/x.flv');
      expect(out.startsWith('http://srv:8080/api/live-stream'), isTrue);
    });

    test('已是代理地址 → 幂等原样返回', () {
      final already =
          'http://srv:8080/api/live-stream?site=douyu&room=1&url=https%3A%2F%2Fa.b%2Fx.flv';
      expect(proxyUrl('http://srv:8080', already), already);
    });

    test('base 为空 → 相对路径（同源部署）', () {
      final out = proxyUrl('', 'https://a.b/x.flv', site: 'huya', room: '9');
      expect(out.startsWith('/api/live-stream?'), isTrue);
    });

    test('空 url 原样返回', () {
      expect(proxyUrl('http://srv', ''), '');
    });

    test('unwrap 往返一致；非代理地址原样', () {
      const direct = 'https://a.b/x.m3u8';
      expect(unwrapProxiedStreamUrl(direct), direct);
      final proxied = proxyUrl('http://srv:8080', direct, site: 's', room: 'r');
      expect(unwrapProxiedStreamUrl(proxied), direct);
    });
  });

  group('needsProxy（headers 非空必须走代理）', () {
    test('headers 空 → false', () {
      const line = StreamLine(name: 'l1', url: 'https://a.b/x.m3u8');
      expect(needsProxy(line), isFalse);
    });

    test('含 Referer → true（浏览器无法自定义该头）', () {
      const line = StreamLine(
        name: 'l1',
        url: 'https://a.b/x.flv',
        headers: {'Referer': 'https://www.douyu.com/'},
      );
      expect(needsProxy(line), isTrue);
    });
  });

  group('pickLines（对齐 visibleStreamLines）', () {
    const hls1 = StreamLine(name: 'h1', url: 'https://a/1.m3u8', format: 'hls');
    const hls2 = StreamLine(name: 'h2', url: 'https://a/2.m3u8', format: '');
    // url 含 .flv 但 format 未标注 —— 应按 url 判定为 flv
    const flv1 = StreamLine(name: 'f1', url: 'https://a/1.flv', format: '');
    const flv2 = StreamLine(name: 'f2', url: 'https://a/2.flv', format: 'flv');
    const ts = StreamLine(name: 't1', url: 'https://a/1.ts', format: 'mpegts');

    test('preferHls=false：优先 FLV 线路', () {
      final picked = pickLines(
        const QualityStream(name: '原画', lines: [hls1, flv1, ts]),
      );
      expect(picked.map((e) => e.name), ['f1']);
    });

    test('preferHls=false：无 FLV → 全部线路（含 mpegts）', () {
      final picked = pickLines(
        const QualityStream(name: '原画', lines: [hls1, ts]),
      );
      expect(picked.map((e) => e.name), ['h1', 't1']);
    });

    test('preferHls=true：优先 HLS 线路（format 空但 url 带 .m3u8 也算 HLS）', () {
      final picked = pickLines(
        const QualityStream(name: '原画', lines: [hls1, hls2, flv1, ts]),
        preferHls: true,
      );
      expect(picked.map((e) => e.name), ['h1', 'h2']);
    });

    test('preferHls=true：无 HLS → 回退 FLV', () {
      final picked = pickLines(
        const QualityStream(name: '原画', lines: [flv1, flv2, ts]),
      );
      expect(picked.map((e) => e.name), ['f1', 'f2']);
    });

    test('preferHls=true：HLS+FLV 均无 → 上游 quirk 返回空（调用方需兜底）', () {
      final picked = pickLines(
        const QualityStream(name: '原画', lines: [ts]),
        preferHls: true,
      );
      expect(picked, isEmpty);
    });

    test('format 字段优先于 url 形态（preferHls=true 时认出非 .m3u8 的 HLS）', () {
      // format=hls 的地址即使不带 .m3u8 也算 HLS
      const fmtHls = StreamLine(
        name: 'fh',
        url: 'https://a/index',
        format: 'hls',
      );
      final picked = pickLines(
        const QualityStream(name: '原画', lines: [flv1, fmtHls]),
        preferHls: true,
      );
      expect(picked.map((e) => e.name), ['fh']);
    });

    test('空档位/空线路 → 空列表', () {
      expect(pickLines(null), isEmpty);
      expect(pickLines(const QualityStream(name: 'x', lines: [])), isEmpty);
    });

    test('按 url 判定的混合大小写', () {
      const upper = StreamLine(name: 'u', url: 'https://a/1.FLV');
      final picked = pickLines(const QualityStream(name: '原画', lines: [upper]));
      expect(picked.map((e) => e.name), ['u']);
    });
  });
}
