/// 恢复重解析时返回的线路序列(升级 re-resolve 与终局恢复共用)。
///
/// 与正常 open 的 [`_fallbackLines`](恒为空、尊重 2026-09-26 单线路决策)不同,
/// 这里**只**在"流已坏、正在恢复"的路径调用:返回该画质下的**全部**兄弟线路
/// (同画质、不同 CDN 节点,如 hwa + huosa),并把与当前失败线路 **不同 host**
/// 的那条排到最前 —— 这样 mpv 下一次 open 直接打在健康节点上,逃离被钉死的
/// 死节点(实测 2026-09-28 斗鱼 9999 的 `hwa.douyucdn2.cn` 故障,单线路重开
/// 永远回到同一死 URL,卡 50~90s)。其余线路作为 mpv 播放列表回退项,主线路
/// 若再抖,mpv 可内部跳到下一条。
///
/// 仅在恢复路径生效,不影响用户手动选线/切档,故不会重现"被自动改线、与用户
/// 选择冲突"的副作用。纯函数便于单测。
library;

import 'package:live_parser/live_parser.dart' show StreamLine, StreamQuality;

List<StreamLine> recoveryLinesFor(
  StreamQuality? quality,
  StreamLine? failedLine,
) {
  final all = quality?.lines ?? const <StreamLine>[];
  if (all.isEmpty) return const [];
  final failedHost = Uri.tryParse(failedLine?.url ?? '')?.host ?? '';
  var primary = all.first;
  if (failedHost.isNotEmpty) {
    // 优先逃离死节点:挑一个不同 host 的兄弟线路做主线路。
    final alt = all.firstWhere(
      (l) => (Uri.tryParse(l.url)?.host ?? '') != failedHost,
      orElse: () => all.first,
    );
    primary = alt;
  }
  final rest = all.where((l) => l != primary).toList();
  return [primary, ...rest];
}

/// URL 预刷新(expire 到点重签)用的线路序列:与 [recoveryLinesFor] 相反,
/// **保持当前 host 优先** —— 预刷新换 host 是服务端正常轮换边缘节点
/// (2026-09-28 实测 scdn 池 -160/-236/-242 随机分配),不是旧节点故障,
/// 沿用当前节点只换 token,避免每次重签在节点池里来回跳(实测 24s TTL 的
/// 短签名流曾因逃逸排序在两个节点间 ping-pong)。当前 host 从候选中消失
/// 时自然顺延下一条。
List<StreamLine> refreshedLinesFor(
  StreamQuality? quality,
  StreamLine? currentLine,
) {
  final all = quality?.lines ?? const <StreamLine>[];
  if (all.isEmpty) return const [];
  final currentHost = Uri.tryParse(currentLine?.url ?? '')?.host ?? '';
  if (currentHost.isEmpty) return all;
  final same = <StreamLine>[];
  final others = <StreamLine>[];
  for (final line in all) {
    ((Uri.tryParse(line.url)?.host ?? '') == currentHost ? same : others)
        .add(line);
  }
  return [...same, ...others];
}
