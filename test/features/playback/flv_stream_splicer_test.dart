/// FLV 流拼接器单测(纯 Dart)。
///
/// 本地流代理在 upstream 热切换(token 预刷新 / 换节点)时,新连接的开头
/// 携带完整 FLV 前导(header + onMetaData + AAC/AVC sequence header),直接
/// 透传会让 mpv 的 demuxer 在流中途见到第二个 FLV header 而错乱;新流的
/// tag 时间戳也从头计,直通会造成时间轴跳变。拼接器的职责:
/// 1. 首连接(primary)原样透传,同时逐 tag 解析追踪最后输出时间戳;
/// 2. 重连(secondary)跳过全部前导,直到首个真正的媒体 tag;
/// 3. secondary 的每个 tag 重写时间戳,拼到旧时间轴上单调连续。
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zishu_flutter/src/platforms/common/playback/flv_stream_splicer.dart';

Uint8List _bytes(List<int> values) => Uint8List.fromList(values);

/// FLV9 字节头 + PreviousTagSize0。
Uint8List _flvHeader() => _bytes([
      0x46, 0x4C, 0x56, 0x01, 0x05, 0x00, 0x00, 0x00, 0x09, //
      0x00, 0x00, 0x00, 0x00,
    ]);

/// 构造一个完整 FLV tag:11B 头 + data + 4B prevTagSize。
Uint8List _tag(int type, List<int> data, int tsMs) {
  final size = data.length;
  final ts24 = tsMs & 0xFFFFFF;
  final tsExt = (tsMs >> 24) & 0xFF;
  return _bytes([
    type,
    (size >> 16) & 0xFF, (size >> 8) & 0xFF, size & 0xFF,
    (ts24 >> 16) & 0xFF, (ts24 >> 8) & 0xFF, ts24 & 0xFF,
    tsExt,
    0x00, 0x00, 0x00,
    ...data,
    ((11 + size) >> 24) & 0xFF, ((11 + size) >> 16) & 0xFF,
    ((11 + size) >> 8) & 0xFF, (11 + size) & 0xFF,
  ]);
}

/// onMetaData script tag(type 18)。
Uint8List _metaTag(int tsMs) => _tag(18, [0x02, 0x00, 0x0A, '@'.codeUnitAt(0), 'o'.codeUnitAt(0)], tsMs);

/// AAC sequence header:audio tag,data[0]=0xAF(AAC/44k/16bit/stereo),data[1]=0(seq header)。
Uint8List _audioSeqTag(int tsMs) => _tag(8, [0xAF, 0x00, 0x12, 0x10], tsMs);

/// AVC sequence header:video tag,data[0]=0x17(keyframe+AVC),data[1]=0(seq header)。
Uint8List _videoSeqTag(int tsMs) => _tag(9, [0x17, 0x00, 0x01, 0x64, 0x00], tsMs);

/// 普通音频媒体 tag(AACPacketType=1)。
Uint8List _audioMediaTag(int tsMs, [int len = 8]) =>
    _tag(8, [0xAF, 0x01, ...List.filled(len, 0xAA)], tsMs);

/// 普通视频媒体 tag(AVC NALU,keyframe 0x17 / interframe 0x27)。
Uint8List _videoMediaTag(int tsMs, {bool key = true, int len = 10}) =>
    _tag(9, [key ? 0x17 : 0x27, 0x01, ...List.filled(len, 0xBB)], tsMs);

/// 从 tag 字节里取时间戳(头偏移 4~7:3B + ext)。
int _tagTs(Uint8List tag) =>
    (tag[7] << 24) | (tag[4] << 16) | (tag[5] << 8) | tag[6];

/// 取 tag 的 type(偏移 0)。
int _tagType(Uint8List tag) => tag[0];

void main() {
  group('primary(首连接):原样透传 + 时间戳追踪', () {
    test('整段透传,不丢字节不改字节;lastEmittedTs 跟随最后一个 tag', () {
      final splicer = FlvStreamSplicer();
      final stream = <Uint8List>[
        _flvHeader(),
        _metaTag(0),
        _audioSeqTag(0),
        _videoSeqTag(0),
        _videoMediaTag(1200, key: true),
        _audioMediaTag(1230),
        _videoMediaTag(1266, key: false),
      ];
      final input = Uint8List.fromList(stream.expand((c) => c).toList());
      final out = splicer.feedPrimary(input);

      expect(out.length, input.length, reason: 'primary 必须逐字节透传');
      expect(out, equals(input));
      expect(splicer.lastEmittedTs, 1266);
    });

    test('跨 chunk 分段透传,追踪不中断', () {
      final splicer = FlvStreamSplicer();
      final chunk1 = Uint8List.fromList([
        ..._flvHeader(),
        ..._metaTag(0),
        ..._videoSeqTag(0),
      ]);
      final chunk2 = Uint8List.fromList([
        ..._videoMediaTag(500),
        ..._audioMediaTag(533),
      ]);
      final out1 = splicer.feedPrimary(chunk1);
      final out2 = splicer.feedPrimary(chunk2);
      expect(out1, equals(chunk1));
      expect(out2, equals(chunk2));
      expect(splicer.lastEmittedTs, 533);
    });
  });

  group('secondary(重连):跳前导 + 时间戳连续化', () {
    test('跳过 header/metadata/seq header,只输出媒体 tag,ts 拼接单调', () {
      final splicer = FlvStreamSplicer();
      // 首连接播到 ts=1000。
      splicer.feedPrimary(Uint8List.fromList([
        ..._flvHeader(),
        ..._metaTag(0),
        ..._videoSeqTag(0),
        ..._videoMediaTag(1000, key: true),
      ]));
      expect(splicer.lastEmittedTs, 1000);

      // 重连:新流从 0 起,前导齐全,首个媒体 tag 是关键帧 ts=0。
      splicer.beginUpstreamSwitch();
      final out = splicer.feedSecondary(Uint8List.fromList([
        ..._flvHeader(),
        ..._metaTag(0),
        ..._audioSeqTag(0),
        ..._videoSeqTag(0),
        ..._videoMediaTag(0, key: true),
        ..._audioMediaTag(30),
        ..._videoMediaTag(66, key: false),
      ]));

      // 输出应只含 3 个媒体 tag;第一个 ts 必须 > 1000(拼到旧轴上)。
      final firstTag = out.sublist(0, 11);
      expect(_tagType(firstTag), 9, reason: '首输出必须是视频媒体 tag,前导全部丢弃');
      final firstTs = _tagTs(firstTag);
      expect(firstTs, greaterThan(1000));
      final secondTs = _tagTs(out.sublist(11 + _tag(9, [0x17, 0x01], 0).length - 15, out.length).sublist(0, 11));
      expect(secondTs, greaterThan(firstTs), reason: '输出时间轴单调递增');
      expect(out, isNot(contains(0x46)), reason: '输出不得混入 FLV header 的 F 字节痕迹');
    });

    test('重连后续 chunk 持续重写时间戳,保持连续映射', () {
      final splicer = FlvStreamSplicer();
      splicer.feedPrimary(Uint8List.fromList([
        ..._flvHeader(),
        ..._videoMediaTag(2000, key: true),
      ]));
      splicer.beginUpstreamSwitch();
      final head = splicer.feedSecondary(Uint8List.fromList([
        ..._flvHeader(),
        ..._videoSeqTag(0),
        ..._videoMediaTag(0, key: true),
      ]));
      final headTs = _tagTs(head.sublist(0, 11));

      // 新流后续 tag ts=40 → 输出 = headTs + 40(差值平移)。
      final tail = splicer.feedSecondary(_audioMediaTag(40));
      final tailTs = _tagTs(tail.sublist(0, 11));
      expect(tailTs - headTs, 40, reason: 'secondary 时间戳按差值平移到旧轴');
    });

    test('前导被 chunk 边界切开:正确缓冲拼接,不误吞媒体字节', () {
      final splicer = FlvStreamSplicer();
      splicer.feedPrimary(Uint8List.fromList([
        ..._flvHeader(),
        ..._videoMediaTag(800, key: true),
      ]));
      splicer.beginUpstreamSwitch();
      final whole = Uint8List.fromList([
        ..._flvHeader(),
        ..._metaTag(0),
        ..._videoSeqTag(0),
        ..._videoMediaTag(0, key: true),
        ..._audioMediaTag(30),
      ]);
      // 在 FLV header 中间(第 5 字节)与首个媒体 tag 中间各切一刀。
      final a = splicer.feedSecondary(whole.sublist(0, 5));
      final b = splicer.feedSecondary(whole.sublist(5, 30));
      final c = splicer.feedSecondary(whole.sublist(30));
      final joined = Uint8List.fromList([...a, ...b, ...c]);
      final firstTs = _tagTs(joined.sublist(0, 11));
      expect(firstTs, greaterThan(800), reason: '跨边界缓冲后仍要正确识别并跳过前导');
      expect(joined.length, _videoMediaTag(0).length + _audioMediaTag(30).length,
          reason: '只应剩两个媒体 tag 的字节');
    });

    test('时间戳跨 24 位边界(>0xFFFFFF)仍连续', () {
      final splicer = FlvStreamSplicer();
      // 旧轴推到 0x1000100(16,777,472)附近,超过 24 位。
      splicer.feedPrimary(Uint8List.fromList([
        ..._flvHeader(),
        ..._videoMediaTag(0x1000100, key: true),
      ]));
      splicer.beginUpstreamSwitch();
      final out = splicer.feedSecondary(Uint8List.fromList([
        ..._flvHeader(),
        ..._videoSeqTag(0),
        ..._videoMediaTag(0, key: true),
      ]));
      final ts = _tagTs(out.sublist(0, 11));
      expect(ts, greaterThan(0x1000100), reason: 'ext 字节参与拼接,不回绕到小值');
    });
  });

  group('防御', () {
    test('secondary 遇非 FLV 前导(上游返回错误页):原样透传,让 demuxer 报错', () {
      final splicer = FlvStreamSplicer();
      splicer.feedPrimary(_flvHeader());
      splicer.beginUpstreamSwitch();
      final garbage = _bytes([0x3C, 0x68, 0x74, 0x6D, 0x6C, 0x3E, 0x65, 0x72, 0x72]);
      final out = splicer.feedSecondary(garbage);
      expect(out, equals(garbage), reason: '无法识别的前导按透传处理,不静默吞流');
    });
  });
}
