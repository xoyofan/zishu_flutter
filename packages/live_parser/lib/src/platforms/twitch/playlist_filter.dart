/// Twitch media playlist 广告过滤(Twitch SSAI 中插/贴片拼接广告)。
///
/// 纯 Dart 文本变换,无任何 IO/平台依赖:输入上游 media playlist 全文,
/// 输出剔除广告段后的 playlist 与「本次刷新是否存在广告」标记。
///
/// 为什么在解析核心做这件事:Twitch 对 usher 换取的播放会话执行服务端
/// 广告拼接(SSAI)——中插广告的段(常为紫色 "Commercial break in progress"
/// 板)直接出现在 media playlist 里。mpv/ffmpeg 等 demuxer 不识别
/// SCTE-35/DATERANGE 广告标记,会原样播出,表现为"播着播着变成广告板"。
/// 剔除规则对齐 streamlink twitch 插件(其过滤永远开启):
///
/// - 广告 DATERANGE:`CLASS="twitch-stitched-ad"` 或 `ID` 以 `stitched-ad-`
///   开头;广告窗口 = `START-DATE` 起,`DURATION`/`PLANNED-DURATION` 秒
///   (缺省视为列出期间一直生效,对应 END-ON-NEXT 语义)。
/// - 段判定:段的 `#EXT-X-PROGRAM-DATE-TIME` 落入任一广告窗口,或
///   EXTINF 标题含 `Amazon`(大小写不敏感,Twitch 广告素材段的固定标题)。
/// - 剔除段的同时移除广告 DATERANGE 行,并把 `MEDIA-SEQUENCE` 重写为
///   首个保留段的真实序号(MEDIA-SEQUENCE + 段在本次刷新中的位次):
///   播放器据此判定"哪些段是新段",不重写会在剔除后整体漂移,把后续
///   真段误判为已播过而跳过(表现为反复卡住)。全被剔除时保持原值
///   不前推——前推会在广告结束后的下一次刷新里让序号回滚,同样误判;
///   零段窗口对播放器是合法的"暂无新段"。
/// - 相邻 `EXT-X-DISCONTINUITY` 合并:广告块两侧各有一条,剔除段后
///   会背靠背出现,连续两条会触发两次无谓的 demuxer 重置。
///
/// fail-open 口径:判定不了的不剔(无 PDT 且标题非 Amazon 的段保留),
/// 宁可漏一条广告也不误杀直播内容。
library;

import 'dart:convert';

/// 单次过滤结果。[adActive] 为 true 表示本次刷新剔除了至少一个广告段
/// ——播放器层据此豁免缓冲看门狗,把"广告剔除造成的无新段等待"与
/// "真断流"区分开。
class TwitchPlaylistFilterResult {
  const TwitchPlaylistFilterResult({required this.body, required this.adActive});

  final String body;
  final bool adActive;
}

/// 过滤 [body] 中的 Twitch 广告段。非 media playlist(master 清单、错误页)
/// 原样返回。
///
/// PDT 归属采用 streamlink 同款语义:`#EXT-X-PROGRAM-DATE-TIME` 归属于
/// **其后**的段(广告边界的段,上游会把 PDT 放在 EXTINF 之前;正常段放在
/// 上一段 URI 之后,同样作用于下一段)。保留段把其 PDT 回填到 EXTINF 前
/// 一并输出,广告 DATERANGE 行则随广告段移除。
TwitchPlaylistFilterResult filterTwitchMediaPlaylist(String body) {
  // media playlist 必有 EXTINF;master 清单只有 STREAM-INF。快速分流。
  if (!body.contains('#EXTINF')) {
    return TwitchPlaylistFilterResult(body: body, adActive: false);
  }
  final lines = const LineSplitter().convert(body);

  // 第一遍:收集广告窗口(DATERANGE 行按规范出现在段之前)。
  final adWindows = <_AdWindow>[];
  for (final line in lines) {
    if (!line.startsWith('#EXT-X-DATERANGE:')) continue;
    final window = _AdWindow.parse(line);
    if (window != null) adWindows.add(window);
  }

  // 第二遍:重组。段块 = EXTINF(含其前挂靠的 PDT)+ 标签 + URI,读到 URI
  // 即闭合判定;其后的行都属于"段间"(PDT 覆盖 pending 作用于下一段,
  // DATERANGE/DISCONTINUITY 等按块外行处理)。
  final output = <String>[];
  var blockIndex = 0;
  var firstKeptSequence = -1;
  var keptCount = 0;
  var droppedCount = 0;
  var mediaSequence = 0;
  var hasMediaSequence = false;
  String? lastEmitted;
  DateTime? pendingDate;
  _SegmentBlock? block;

  void emit(String line) {
    // 广告块两侧的 DISCONTINUITY 在剔除后会背靠背,合并为一条。
    if (line == '#EXT-X-DISCONTINUITY' && lastEmitted == line) return;
    output.add(line);
    lastEmitted = line;
  }

  void closeBlock(_SegmentBlock segment) {
    final sequence = mediaSequence + blockIndex;
    blockIndex++;
    // PDT 挂靠:块内未显式给出(前置形态)时用 pending(后置归属下一段)。
    segment.programDateTime ??= pendingDate;
    pendingDate = null;
    if (segment.isAd(adWindows)) {
      droppedCount++;
      return;
    }
    if (keptCount == 0) firstKeptSequence = sequence;
    keptCount++;
    for (final line in segment.lines) {
      emit(line);
    }
  }

  for (final line in lines) {
    if (line.startsWith('#EXT-X-PROGRAM-DATE-TIME:')) {
      // 作用于下一段;广告边界处会覆盖上一段 URI 后的先行值(streamlink 同款)。
      pendingDate = DateTime.tryParse(
        line.substring('#EXT-X-PROGRAM-DATE-TIME:'.length).trim(),
      );
      continue;
    }
    final current = block;
    if (current != null) {
      if (line.startsWith('#')) {
        current.preUriLines.add(line);
        continue;
      }
      current.uri = line;
      closeBlock(current);
      block = null;
      continue;
    }
    if (line.startsWith('#EXTINF:')) {
      block = _SegmentBlock(line);
      continue;
    }
    if (line.startsWith('#EXT-X-MEDIA-SEQUENCE:')) {
      mediaSequence = int.tryParse(line.split(':')[1].trim()) ?? 0;
      hasMediaSequence = true;
    }
    if (line.startsWith('#EXT-X-DATERANGE:')) {
      if (_AdWindow.parse(line) != null) continue; // 广告 DATERANGE 随段移除。
    }
    emit(line);
  }
  final pendingBlock = block;
  if (pendingBlock != null) closeBlock(pendingBlock);

  if (hasMediaSequence) {
    final rewritten = keptCount > 0 ? firstKeptSequence : mediaSequence;
    _replaceMediaSequence(output, rewritten);
  }

  return TwitchPlaylistFilterResult(
    body: output.join('\n'),
    adActive: droppedCount > 0,
  );
}

/// 把输出行里的 MEDIA-SEQUENCE 值替换为 [sequence](表头行总在段之前,
/// 全文唯一)。
void _replaceMediaSequence(List<String> lines, int sequence) {
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].startsWith('#EXT-X-MEDIA-SEQUENCE:')) {
      lines[i] = '#EXT-X-MEDIA-SEQUENCE:$sequence';
      return;
    }
  }
}

class _SegmentBlock {
  _SegmentBlock(this.extInfLine) : title = _extInfTitle(extInfLine);

  final String extInfLine;

  /// EXTINF 标题(Twitch 广告素材段为 `Amazon|<id>` 形态,普通段为 `live`)。
  final String title;
  final List<String> preUriLines = [];
  String? uri;
  DateTime? programDateTime;

  /// 输出顺序:挂靠的 PDT → EXTINF → URI 前标签 → URI。
  Iterable<String> get lines sync* {
    final date = programDateTime;
    if (date != null) {
      yield '#EXT-X-PROGRAM-DATE-TIME:${date.toUtc().toIso8601String()}';
    }
    yield extInfLine;
    yield* preUriLines;
    final segmentUri = uri;
    if (segmentUri != null) yield segmentUri;
  }

  bool isAd(List<_AdWindow> windows) {
    if (title.contains('amazon')) return true;
    final date = programDateTime;
    if (date == null) return false;
    for (final window in windows) {
      if (window.contains(date)) return true;
    }
    return false;
  }

  static String _extInfTitle(String line) {
    final comma = line.indexOf(',');
    if (comma == -1) return '';
    return line.substring(comma + 1).trim().toLowerCase();
  }
}

/// 广告窗口:`START-DATE` 起 `DURATION`(或 `PLANNED-DURATION`)秒。
class _AdWindow {
  _AdWindow._(this.start, this.duration);

  /// 非广告 DATERANGE 返回 null(调用方按非广告行放行)。
  static _AdWindow? parse(String line) {
    final className = _attrValue(line, 'CLASS');
    final id = _attrValue(line, 'ID');
    final isAd =
        className == 'twitch-stitched-ad' || (id ?? '').startsWith('stitched-ad-');
    if (!isAd) return null;
    final startText = _attrValue(line, 'START-DATE');
    return _AdWindow._(
      startText == null ? null : DateTime.tryParse(startText),
      _durationOf(_attrValue(line, 'DURATION') ?? _attrValue(line, 'PLANNED-DURATION')),
    );
  }

  final DateTime? start;
  final Duration? duration;

  bool contains(DateTime date) {
    final from = start;
    if (from == null || date.isBefore(from)) return false;
    final until = duration;
    if (until == null) return true; // 缺省视为列出期间持续生效。
    return date.isBefore(from.add(until));
  }

  static Duration? _durationOf(String? text) {
    final seconds = double.tryParse(text ?? '');
    if (seconds == null) return null;
    return Duration(microseconds: (seconds * 1e6).round());
  }
}

/// 按 key 定向提取 DATERANGE 属性值(带引号/不带引号两种形态)。
///
/// 不用通配正则逐属性扫:DATERANGE 的部分属性值(如 trigger URL)可能
/// 内嵌大写 token 与 `=`,通配扫会把值内部的片段误当属性。前缀锚定含
/// `:`——首个属性紧跟 `#EXT-X-DATERANGE:` 之内。
String? _attrValue(String line, String key) {
  final quoted = RegExp('(?:^|[,:])\\s*$key="([^"]*)"').firstMatch(line);
  if (quoted != null) return quoted.group(1);
  final plain = RegExp('(?:^|[,:])\\s*$key=([^,\\s]*)').firstMatch(line);
  if (plain != null) {
    final value = plain.group(1) ?? '';
    return value.isEmpty ? null : value;
  }
  return null;
}
