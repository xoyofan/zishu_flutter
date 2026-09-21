/// 线路延时优选单测:最快优先、抖动离群降级、全失败不破坏播放。
///
/// 阈值规则:保留 `延时 <= max(2500ms, 最快 × 3)` 的线路。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:live_parser/live_parser.dart' show StreamLine;
import 'package:zishu_flutter/src/platforms/common/playback/line_latency_ranker.dart';

StreamLine _line(String host) =>
    StreamLine(name: host, url: 'https://$host/live.m3u8', format: 'hls');

void main() {
  test('按实测延时升序排列(解析顺序与快慢无关)', () async {
    final lines = [_line('a'), _line('b'), _line('c')];
    final result = await rankLinesByLatency(
      lines,
      probe: (url) async => switch (url) {
        'https://a/live.m3u8' => 900,
        'https://b/live.m3u8' => 200,
        _ => 500,
      },
    );

    expect(result.ordered.map((l) => l.url).toList(), [
      'https://b/live.m3u8',
      'https://c/live.m3u8',
      'https://a/live.m3u8',
    ]);
    expect(result.dropped, isEmpty);
  });

  test('抖动离群线降级为兜底:实测 tubbo 分布下 4.9s 那条不再优先', () async {
    // 实测:1868 / 4903 / 706 / 770 / 827 ms。
    final lines = [
      _line('l1'),
      _line('l2'),
      _line('l3'),
      _line('l4'),
      _line('l5'),
    ];
    const latency = {
      'https://l1/live.m3u8': 1868,
      'https://l2/live.m3u8': 4903,
      'https://l3/live.m3u8': 706,
      'https://l4/live.m3u8': 770,
      'https://l5/live.m3u8': 827,
    };
    final result = await rankLinesByLatency(
      lines,
      probe: (url) async => latency[url],
    );

    expect(result.ordered.first.url, 'https://l3/live.m3u8', reason: '最快者优先');
    expect(result.dropped.map((l) => l.url).toList(), [
      'https://l2/live.m3u8',
    ], reason: '4903ms 超过 max(2500, 706*3=2118) → 判为离群');
    expect(
      result.ordered.last.url,
      'https://l2/live.m3u8',
      reason: '离群线仍留在末尾作兜底,不能直接删',
    );
  });

  test('失败/超时的线路排到最后,不参与优选', () async {
    final lines = [_line('bad'), _line('good')];
    final result = await rankLinesByLatency(
      lines,
      probe: (url) async => url.contains('bad') ? null : 300,
    );

    expect(result.ordered.first.url, 'https://good/live.m3u8');
    expect(result.ordered.last.url, 'https://bad/live.m3u8');
  });

  test('探测抛异常按失败处理,不影响其余线路', () async {
    final lines = [_line('boom'), _line('ok')];
    final result = await rankLinesByLatency(
      lines,
      probe: (url) async {
        if (url.contains('boom')) throw StateError('probe failed');
        return 400;
      },
    );

    expect(result.ordered.first.url, 'https://ok/live.m3u8');
  });

  test('全部失败时保持原顺序(绝不因测速把播放搞挂)', () async {
    final lines = [_line('a'), _line('b')];
    final result = await rankLinesByLatency(lines, probe: (_) async => null);

    expect(result.ordered.map((l) => l.url).toList(), [
      'https://a/live.m3u8',
      'https://b/live.m3u8',
    ]);
    expect(result.dropped, isEmpty);
  });

  test('单条线路不做探测(无对比对象,省一次往返)', () async {
    var probed = 0;
    final result = await rankLinesByLatency(
      [_line('only')],
      probe: (_) async {
        probed++;
        return 100;
      },
    );

    expect(probed, 0);
    expect(result.ordered, hasLength(1));
  });

  test('探测超时按失败处理,整体耗时不失控', () async {
    final lines = [_line('slow'), _line('fast')];
    final sw = Stopwatch()..start();
    final result = await rankLinesByLatency(
      lines,
      timeout: const Duration(milliseconds: 120),
      probe: (url) async {
        if (url.contains('slow')) {
          await Future<void>.delayed(const Duration(seconds: 2));
          return 10;
        }
        return 50;
      },
    );
    sw.stop();

    expect(result.ordered.first.url, 'https://fast/live.m3u8');
    expect(sw.elapsedMilliseconds, lessThan(1200), reason: '超时即判失败');
  });

  test('阈值随最快线路放宽:整体偏慢但相对均匀时不误杀', () async {
    final lines = [_line('a'), _line('b'), _line('c')];
    const latency = {
      'https://a/live.m3u8': 2400,
      'https://b/live.m3u8': 2500,
      'https://c/live.m3u8': 2600,
    };
    final result = await rankLinesByLatency(
      lines,
      probe: (url) async => latency[url],
    );

    expect(result.dropped, isEmpty, reason: '2600 <= max(2500, 2400*3)');
    expect(result.ordered.first.url, 'https://a/live.m3u8');
  });
}
