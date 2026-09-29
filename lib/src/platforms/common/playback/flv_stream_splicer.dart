/// FLV 流拼接器:本地流代理热切换 upstream 时的字节变换(纯 Dart)。
///
/// 对齐斗鱼官方 PC 客户端 DySDKController 本地代理的行为:mpv 只见一条
/// 从不间断的本地 FLV 流;token 预刷新 / 换节点时,代理层断开旧远端连接、
/// 用新 URL 重连,把新流"拼接"到旧流上。新连接的开头携带完整前导
/// (9B FLV header + PreviousTagSize0 + onMetaData + AAC/AVC sequence
/// header),直接透传会让 mpv 的 flv demuxer 在流中途见到第二个 FLV header
/// 而错乱;新流 tag 时间戳也从新连接起点重新计,直通会造成播放时间轴跳变
/// (seek/卡顿)。本拼接器因此做两件事:
///
/// 1. [feedPrimary](首连接):逐字节透传,同时旁路解析 tag 追踪最后输出的
///    时间戳([lastEmittedTs]);
/// 2. [beginUpstreamSwitch] + [feedSecondary](重连):丢弃全部前导直到
///    首个真正的媒体 tag,此后每个 tag 的时间戳按差值平移到旧时间轴上,
///    保证单调递增。
///
/// 前置 tag 判定(可安全丢弃,解码器配置已在首连接拿到):
/// - type 18(onMetaData script tag);
/// - type 8 且 AAC(soundFormat==10)且 AACPacketType==0(sequence header);
/// - type 9 且 codecId∈{7(AVC),12(HEVC)} 且 AVCPacketType==0(sequence
///   header)。主播中途重配 SPS 的极端场景会花屏到下个关键帧,官方代理同样
/// 取舍;live 流 keyframe 间隔秒级,可接受。
///
/// 防御:secondary 首字节不是 `FLV` 签名(上游返回了错误页/裸流)时切换为
/// 纯透传,让 demuxer 自己报错,绝不静默吞流。
library;

import 'dart:typed_data';

enum _Phase { header, discard, media }

class FlvStreamSplicer {
  _Phase _phase = _Phase.header;
  bool _passthrough = false;
  final List<int> _pending = <int>[];

  /// 旧时间轴上最后输出的 tag 时间戳(ms)。
  int _lastTs = 0;

  /// 本次切换时旧轴的基准(切换瞬间的 [_lastTs])。
  int _switchBase = 0;

  /// 新流首个媒体 tag 的原始时间戳(差值平移的零点)。
  int _secondaryBase = 0;

  /// 已透传(或重写)的最后一个 tag 时间戳;未见过 tag 时为 0。
  int get lastEmittedTs => _lastTs;

  /// 标记:接下来的 [feedSecondary] 输入是一条**新连接**的起点字节,
  /// 需要重新丢弃前导。每次 upstream 热切换调用一次。
  ///
  /// 旧流残留的半个 tag(切换时旧连接已断,本就无法交付完整)一并丢弃,
  /// 避免与新连接字节拼接成错误帧。
  void beginUpstreamSwitch() {
    if (_passthrough) return;
    _phase = _Phase.header;
    _pending.clear();
    _secondaryBase = -1;
    _switchBase = _lastTs;
  }

  /// 首连接输入:原样透传(返回值可能为空,当 chunk 被跨 tag 边界缓冲时)。
  Uint8List feedPrimary(Uint8List chunk) {
    if (_passthrough) return chunk;
    return _feed(chunk, secondary: false);
  }

  /// 重连输入:丢前导 + 时间戳连续化。调用前必须先 [beginUpstreamSwitch]。
  Uint8List feedSecondary(Uint8List chunk) {
    if (_passthrough) return chunk;
    return _feed(chunk, secondary: true);
  }

  Uint8List _feed(Uint8List chunk, {required bool secondary}) {
    if (chunk.isNotEmpty) _pending.addAll(chunk);
    if (_pending.isEmpty) return Uint8List(0);
    final out = BytesBuilderShim();
    var consumed = 0;

    while (true) {
      if (_phase == _Phase.header) {
        final b = _pending;
        // 签名校验只需 3 字节:上游返回的错误页/裸流可能很短,等满 13 字节
        // 会把它无限缓冲成"静默吞流"。
        if (b.length - consumed >= 3 &&
            (b[consumed] != 0x46 || b[consumed + 1] != 0x4C || b[consumed + 2] != 0x56)) {
          // 非 FLV 前导:透传兜底,让 demuxer 报错而不是静默吞流。
          _passthrough = true;
          final rest = Uint8List.fromList(b.sublist(consumed));
          _pending.clear();
          out.add(rest);
          return out.take();
        }
        if (_pending.length - consumed < 13) break;
        if (!secondary) out.addRange(b, consumed, consumed + 13);
        consumed += 13;
        _phase = secondary ? _Phase.discard : _Phase.media;
        continue;
      }
      // tag 阶段:11B 头 + data + 4B prevTagSize。
      final available = _pending.length - consumed;
      if (available < 11) break;
      final b = _pending;
      final type = b[consumed];
      final dataSize = (b[consumed + 1] << 16) |
          (b[consumed + 2] << 8) |
          b[consumed + 3];
      if (dataSize < 0 || available < 11 + dataSize + 4) break;
      final tagEnd = consumed + 11 + dataSize + 4;
      if (!secondary) {
        out.addRange(b, consumed, tagEnd);
        _lastTs = _tagTimestamp(b, consumed);
      } else if (_phase == _Phase.discard && _isPreambleTag(b, consumed, dataSize, type)) {
        // 前导 tag:整段丢弃。
      } else {
        if (_phase == _Phase.discard) {
          _phase = _Phase.media;
          _secondaryBase = _tagTimestamp(b, consumed);
        }
        final rawTs = _tagTimestamp(b, consumed);
        var mapped = _switchBase + 1 + (rawTs - _secondaryBase);
        if (mapped <= _lastTs) mapped = _lastTs + 1;
        out.add(_rewrittenTag(b, consumed, tagEnd, mapped));
        _lastTs = mapped;
      }
      consumed = tagEnd;
    }

    if (consumed > 0) {
      _pending.removeRange(0, consumed);
    }
    return out.take();
  }

  /// 读取 tag 头偏移 4~7 的时间戳(3B + ext 高 8 位)。
  static int _tagTimestamp(List<int> b, int at) =>
      (b[at + 7] << 24) | (b[at + 4] << 16) | (b[at + 5] << 8) | b[at + 6];

  static bool _isPreambleTag(List<int> b, int at, int dataSize, int type) {
    if (type == 18) return true; // onMetaData
    if (dataSize < 2) return false;
    final first = b[at + 11];
    final second = b[at + 12];
    if (type == 8 && (first >> 4) == 10 && second == 0) return true; // AAC seq
    if (type == 9) {
      final codec = first & 0x0F;
      if ((codec == 7 || codec == 12) && second == 0) return true; // AVC/HEVC seq
    }
    return false;
  }

  /// 拷贝整个 tag 并把头部时间戳改写为 [tsMs]。
  static Uint8List _rewrittenTag(List<int> b, int start, int end, int tsMs) {
    final tag = Uint8List.fromList(b.sublist(start, end));
    final ts24 = tsMs & 0xFFFFFF;
    tag[4] = (ts24 >> 16) & 0xFF;
    tag[5] = (ts24 >> 8) & 0xFF;
    tag[6] = ts24 & 0xFF;
    tag[7] = (tsMs >> 24) & 0xFF;
    return tag;
  }
}

/// [BytesBuilder] 属 dart:io,拆出可替换的最小实现保持本文件纯 Dart
/// (解析核心可在任意隔离/平台复用)。
class BytesBuilderShim {
  final List<Uint8List> _chunks = <Uint8List>[];
  int _length = 0;

  void add(Uint8List bytes) {
    if (bytes.isEmpty) return;
    _chunks.add(bytes);
    _length += bytes.length;
  }

  void addRange(List<int> b, int start, int end) {
    add(Uint8List.fromList(b.sublist(start, end)));
  }

  Uint8List take() {
    final result = Uint8List(_length);
    var offset = 0;
    for (final chunk in _chunks) {
      result.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    _chunks.clear();
    _length = 0;
    return result;
  }
}
