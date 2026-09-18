/// 播放档位/线路选择单测:确定「默认画质偏好」与「线路格式偏好」的落点。
///
/// 这两条偏好此前在播放侧**完全不生效**(内联实现只做精确同名 + 首档 +
/// 硬编码 HLS 优先),设置页的「线路格式」是死设置。本套用例钉住行为。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:live_parser/live_parser.dart'
    show RoomPayload, RoomState, StreamLine, StreamQuality;
import 'package:zishu_flutter/src/features/play/application/play_selection.dart';

RoomPayload payloadOf(List<StreamQuality> streams) => RoomPayload(
  site: 'douyu',
  roomId: '1',
  sourceUrl: '',
  anchorName: '主播',
  title: '标题',
  cover: '',
  avatar: '',
  category: '',
  cid: '',
  roomState: RoomState.live,
  streams: streams,
  availableQualities: const [],
  source: 'test',
  fetchedAt: DateTime.fromMillisecondsSinceEpoch(0),
);

StreamQuality qualityOf(String name, List<StreamLine> lines) =>
    StreamQuality(name: name, rate: 0, lines: lines);

StreamLine lineOf(String format, String url) =>
    StreamLine(name: format.toUpperCase(), url: url, format: format);

void main() {
  group('pickPlayQuality', () {
    test('精确同名优先', () {
      final payload = payloadOf([
        qualityOf('蓝光', const []),
        qualityOf('高清', const []),
      ]);

      expect(pickPlayQuality(payload, '高清')?.name, '高清');
    });

    test('档名带后缀时双向包含命中(真实平台档名)', () {
      final payload = payloadOf([
        qualityOf('原画1080P60', const []),
        qualityOf('高清', const []),
      ]);

      expect(pickPlayQuality(payload, '原画')?.name, '原画1080P60');
    });

    test('偏好名包含档名时命中', () {
      final payload = payloadOf([
        qualityOf('蓝光', const []),
        qualityOf('流畅', const []),
      ]);

      expect(pickPlayQuality(payload, '蓝光8M')?.name, '蓝光');
    });

    test('未命中回退首档,null/空名也取首档', () {
      final payload = payloadOf([
        qualityOf('流畅', const []),
        qualityOf('高清', const []),
      ]);

      expect(pickPlayQuality(payload, '不存在')?.name, '流畅');
      expect(pickPlayQuality(payload, null)?.name, '流畅');
      expect(pickPlayQuality(payload, '')?.name, '流畅');
    });

    test('无画质返回 null', () {
      expect(pickPlayQuality(payloadOf(const []), '高清'), isNull);
    });
  });

  group('pickStreamLine', () {
    test('auto/null 维持契约首选(HLS 优先)', () {
      final quality = qualityOf('高清', [
        lineOf('flv', 'https://cdn/a.flv'),
        lineOf('hls', 'https://cdn/a.m3u8'),
      ]);

      expect(pickStreamLine(quality, null)?.format, 'hls');
      expect(pickStreamLine(quality, 'auto')?.format, 'hls');
    });

    test('指定 flv 时优先 flv(设置页「线路格式」真正生效)', () {
      final quality = qualityOf('高清', [
        lineOf('hls', 'https://cdn/a.m3u8'),
        lineOf('flv', 'https://cdn/a.flv'),
      ]);

      expect(pickStreamLine(quality, 'flv')?.format, 'flv');
    });

    test('指定 hls 时优先 hls', () {
      final quality = qualityOf('高清', [
        lineOf('flv', 'https://cdn/a.flv'),
        lineOf('hls', 'https://cdn/a.m3u8'),
      ]);

      expect(pickStreamLine(quality, 'hls')?.format, 'hls');
    });

    test('指定格式无命中时回退契约首选', () {
      final quality = qualityOf('高清', [lineOf('hls', 'https://cdn/a.m3u8')]);

      expect(pickStreamLine(quality, 'flv')?.format, 'hls');
    });

    test('空线路返回 null', () {
      expect(pickStreamLine(qualityOf('高清', const []), 'hls'), isNull);
      expect(pickStreamLine(null, 'hls'), isNull);
    });
  });
}
