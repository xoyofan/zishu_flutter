/// [recoveryLinesFor] 契约测试:恢复重解析时返回全部兄弟线路,并逃离死节点。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:live_parser/live_parser.dart'
    show StreamLine, StreamQuality;
import 'package:zishu_flutter/src/features/play/application/recovery_lines.dart';

StreamQuality quality(List<StreamLine> lines) => StreamQuality(
      name: '1080p',
      rate: 0,
      lines: lines,
    );

const hwa = StreamLine(
  name: 'hwa',
  url: 'https://hwa.douyucdn2.cn/live/9999.flv',
  format: 'flv',
);
const huosa = StreamLine(
  name: 'huosa',
  url: 'https://huosa.douyucdn2.cn/live/9999.flv',
  format: 'flv',
);

void main() {
  test('多线路:优先逃离死节点,把不同 host 的线路排到最前', () {
    final q = quality([hwa, huosa]);
    final result = recoveryLinesFor(q, hwa); // 当前失败的是 hwa 死节点
    expect(result, hasLength(2));
    expect(result.first, huosa, reason: '失败节点为 hwa 时,主线路必须换成 huosa');
    expect(result.skip(1).toList(), [hwa], reason: '原死节点降为 mpv 播放列表回退项');
  });

  test('多线路:失败线路是 huosa 时,主线路换成 hwa', () {
    final q = quality([hwa, huosa]);
    final result = recoveryLinesFor(q, huosa);
    expect(result.first, hwa);
    expect(result.skip(1).toList(), [huosa]);
  });

  test('全部同 host:无法逃离,保持原序但仍是全部线路', () {
    final a = StreamLine(name: 'a', url: 'https://hwa.x.com/1.flv', format: 'flv');
    final b = StreamLine(name: 'b', url: 'https://hwa.x.com/2.flv', format: 'flv');
    final q = quality([a, b]);
    final result = recoveryLinesFor(q, a);
    expect(result, [a, b], reason: '同 host 无备选,原序返回全部线路');
  });

  test('单线路:无论失败谁,只返回那一条(无备选可逃)', () {
    final q = quality([hwa]);
    expect(recoveryLinesFor(q, hwa), [hwa]);
    expect(recoveryLinesFor(q, null), [hwa]);
  });

  test('画质无线路 / null:返回空(交由播放器走放弃分支)', () {
    expect(recoveryLinesFor(quality(const []), hwa), isEmpty);
    expect(recoveryLinesFor(null, hwa), isEmpty);
  });

  test('失败线路为 null:无已知死节点,主线路取首个(保持确定性)', () {
    final q = quality([hwa, huosa]);
    final result = recoveryLinesFor(q, null);
    expect(result.first, hwa);
    expect(result, hasLength(2));
  });

  test('乱序输入:逃逸选择只看 host 不看列表位置', () {
    final q = quality([huosa, hwa]); // 死节点 hwa 在末尾
    final result = recoveryLinesFor(q, hwa);
    expect(result.first, huosa, reason: 'host 命中优先,与列表中位置无关');
  });

  group('refreshedLinesFor(预刷新:保持当前 host 优先)', () {
    test('当前 host 在候选中:同 host 排最前,只换 token 不换节点', () {
      final hwaNew = StreamLine(
        name: 'hwa',
        url: 'https://hwa.douyucdn2.cn/live/9999.flv?token=NEW',
        format: 'flv',
      );
      final q = quality([huosa, hwaNew]);
      final result = refreshedLinesFor(q, hwa);
      expect(result.first, hwaNew, reason: '预刷新沿用当前节点的新 token URL');
      expect(result, hasLength(2));
    });

    test('当前 host 消失:顺延候选原序(不逃逸、不跳节点)', () {
      final hw3 = StreamLine(
        name: 'hw3',
        url: 'https://hw3.douyucdn2.cn/live/9999.flv',
        format: 'flv',
      );
      final q = quality([huosa, hw3]);
      final result = refreshedLinesFor(q, hwa);
      expect(result, [huosa, hw3], reason: '当前 host 不在候选中时保持原序');
    });

    test('画质无线路 / 当前线为 null:返回空/原序', () {
      expect(refreshedLinesFor(quality(const []), hwa), isEmpty);
      expect(refreshedLinesFor(null, hwa), isEmpty);
      final q = quality([hwa, huosa]);
      expect(refreshedLinesFor(q, null), [hwa, huosa]);
    });
  });
}
