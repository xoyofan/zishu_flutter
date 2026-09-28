/// 死节点负缓存契约:恢复逃离的 host 落入负缓存,进房自动选线避让,
/// TTL 过期自动失效,跨会话经 JSON 持久化。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:live_parser/live_parser.dart' show StreamLine;
import 'package:zishu_flutter/src/features/play/application/host_avoidlist.dart';

const _hwa = StreamLine(
  name: 'hwa',
  url: 'https://hwa.douyucdn2.cn/live/9999.flv',
  format: 'flv',
);
const _huosa = StreamLine(
  name: 'huosa',
  url: 'https://huosa.douyucdn2.cn/live/9999.flv',
  format: 'flv',
);
const _hwaHls = StreamLine(
  name: 'hwa-hls',
  url: 'https://hwa.douyucdn2.cn/live/9999.m3u8',
  format: 'hls',
);

void main() {
  group('isHostAvoided', () {
    test('TTL 内命中失败 host 视为避让', () {
      final failedAt = {'hwa.douyucdn2.cn': 1000};
      expect(
        isHostAvoided(failedAt, _hwa.url, nowMs: 1000 + 14 * 60 * 1000),
        isTrue,
      );
    });

    test('TTL 过期不再避让', () {
      final failedAt = {'hwa.douyucdn2.cn': 1000};
      expect(
        isHostAvoided(failedAt, _hwa.url, nowMs: 1000 + 16 * 60 * 1000),
        isFalse,
      );
    });

    test('host 不在表中 / url 非法 / 空表:不避让', () {
      expect(isHostAvoided({}, _hwa.url, nowMs: 0), isFalse);
      expect(isHostAvoided({'a.com': 1}, _huosa.url, nowMs: 0), isFalse);
      expect(isHostAvoided({'hwa.douyucdn2.cn': 1}, null, nowMs: 0), isFalse);
      expect(
        isHostAvoided({'hwa.douyucdn2.cn': 1}, 'not-a-url', nowMs: 0),
        isFalse,
      );
    });
  });

  group('pruneHostAvoidlist', () {
    test('剔除过期条目,保留未过期条目', () {
      final failedAt = {
        'dead.example': 1000,
        'alive.example': 1000 + 20 * 60 * 1000,
      };
      final pruned = pruneHostAvoidlist(failedAt, nowMs: 1000 + 16 * 60 * 1000);
      expect(pruned, {'alive.example': 1000 + 20 * 60 * 1000});
    });

    test('空表原样返回', () {
      expect(pruneHostAvoidlist({}, nowMs: 0), isEmpty);
    });
  });

  group('avoidFlaggedLine', () {
    test('首选 host 被避让:同 format 换到未避让线路', () {
      final failedAt = {'hwa.douyucdn2.cn': 1000};
      final picked = avoidFlaggedLine(
        _hwa,
        [_hwa, _huosa, _hwaHls],
        failedAt,
        nowMs: 2000,
      );
      expect(picked, _huosa, reason: 'hwa 在负缓存内,首选必须换成 huosa');
    });

    test('首选 host 未被避让:保持首选(负缓存不影响正常线路)', () {
      final failedAt = {'other.example': 1000};
      final picked = avoidFlaggedLine(
        _hwa,
        [_hwa, _huosa],
        failedAt,
        nowMs: 2000,
      );
      expect(picked, _hwa);
    });

    test('同 format 全避让:放宽到任意未避让线路(避让是排序而非硬过滤)', () {
      final failedAt = {'hwa.douyucdn2.cn': 1000};
      final otherHls = StreamLine(
        name: 'hw1a-hls',
        url: 'https://hw1a.douyucdn2.cn/live/9999.m3u8',
        format: 'hls',
      );
      final flvHwa2 = StreamLine(
        name: 'hwa2',
        url: 'https://hwa.douyucdn2.cn/live/9999_2.flv',
        format: 'flv',
      );
      final picked = avoidFlaggedLine(
        _hwa,
        [_hwa, flvHwa2, otherHls],
        failedAt,
        nowMs: 2000,
      );
      expect(picked, otherHls, reason: 'FLV 全灭时退到未避让的 HLS,而不是硬拒播');
    });

    test('全部线路被避让:返回原首选(保证永远有线路可播)', () {
      final failedAt = {
        'hwa.douyucdn2.cn': 1000,
        'huosa.douyucdn2.cn': 1000,
      };
      final picked = avoidFlaggedLine(
        _hwa,
        [_hwa, _huosa],
        failedAt,
        nowMs: 2000,
      );
      expect(picked, _hwa);
    });

    test('首选为 null:返回 null(上游无线路,不无中生有)', () {
      expect(avoidFlaggedLine(null, [_hwa], {'hwa.douyucdn2.cn': 1}, nowMs: 2),
          isNull);
    });

    test('首选不在候选列表:仍可按 host 避让语义挑未避让线', () {
      final failedAt = {'hwa.douyucdn2.cn': 1000};
      final picked = avoidFlaggedLine(
        _hwa,
        [_huosa],
        failedAt,
        nowMs: 2000,
      );
      expect(picked, _huosa);
    });
  });

  group('JSON 持久化', () {
    test('编码/解码往返一致', () {
      final failedAt = {
        'hwa.douyucdn2.cn': 1727500000000,
        'huosa.douyucdn2.cn': 1727500009999,
      };
      final decoded = decodeHostAvoidlist(encodeHostAvoidlist(failedAt));
      expect(decoded, failedAt);
    });

    test('损坏内容回退空表,不抛异常', () {
      expect(decodeHostAvoidlist('not json'), isEmpty);
      expect(decodeHostAvoidlist('["array"]'), isEmpty);
      expect(decodeHostAvoidlist('{"host": "not-a-number"}'), isEmpty);
      expect(decodeHostAvoidlist(null), isEmpty);
    });
  });
}
