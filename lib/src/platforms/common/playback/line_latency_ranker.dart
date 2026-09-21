/// 线路延时优选:并发探测候选线路首包延时,最快者优先、抖动离群者剔除。
///
/// 实测依据(2026-09-21,同房间同刻):
/// - twitch tubbo: 1868 / **4903** / 706 / 770 / 827 ms
/// - twitch illojuan: 1164 / 2626 / **4332** / 924 / 927 ms
/// - youtube BH-vjyvJePA: 757 / 463 / 1604 / **2323** / 900 / **2401** ms
///
/// 同一档位内各线路延时差可达 5~6 倍,而解析侧给的顺序是上游声明顺序,
/// 与此刻快慢无关。默认取第一条就可能在一条 4.9s 的线上起播(体感「半天
/// 不出画面」),之后又频繁卡顿。故:开流前并发量一次首包,按实测延时排序,
/// 并把明显离群的线路降级为兜底(不删除 —— 全失败时仍要能播)。
///
/// 纯逻辑 + 注入探测器,便于确定性单测。
library;

import 'package:live_parser/live_parser.dart' show StreamLine;

/// 单条线路探测:返回首包毫秒数;失败/超时返回 null。
typedef LineProbe = Future<int?> Function(String url);

/// 优选结果。
class LineRankResult {
  const LineRankResult({
    required this.ordered,
    required this.latencyMs,
    required this.dropped,
  });

  /// 建议的开流顺序(最快在前;探测全失败时保持原顺序)。
  final List<StreamLine> ordered;

  /// url -> 实测毫秒(诊断/日志用)。
  final Map<String, int> latencyMs;

  /// 被判为离群(过慢)的线路:排在 [ordered] 末尾作兜底,但不再优先使用。
  final List<StreamLine> dropped;
}

/// 默认阈值:最慢不超过 `max(slowestAllowedMs, best * jitterFactor)`。
const int kLineSlowestAllowedMs = 2500;
const double kLineJitterFactor = 3.0;
const int kLineProbeConcurrency = 4;

/// 并发探测并按延时排序。
///
/// - 单条失败/超时 → 视为不可用,排在最后;
/// - 全部失败 → 返回原顺序(绝不因测速把播放搞挂);
/// - [timeout] 到点即算失败,保证整体耗时不失控(用户能接受的最大额外等待)。
Future<LineRankResult> rankLinesByLatency(
  List<StreamLine> lines, {
  required LineProbe probe,
  Duration timeout = const Duration(milliseconds: 2000),
  int concurrency = kLineProbeConcurrency,
  int slowestAllowedMs = kLineSlowestAllowedMs,
  double jitterFactor = kLineJitterFactor,
}) async {
  if (lines.length < 2) {
    return LineRankResult(
      ordered: List<StreamLine>.of(lines),
      latencyMs: const {},
      dropped: const [],
    );
  }

  final latency = <String, int>{};
  var cursor = 0;
  Future<void> worker() async {
    while (true) {
      final index = cursor++;
      if (index >= lines.length) return;
      final url = lines[index].url;
      if (latency.containsKey(url)) continue;
      int? ms;
      try {
        ms = await probe(url).timeout(timeout);
      } on Object {
        ms = null;
      }
      if (ms != null && ms >= 0) latency[url] = ms;
    }
  }

  await Future.wait([
    for (var i = 0; i < concurrency.clamp(1, lines.length); i++) worker(),
  ]);

  final measured = lines.where((l) => latency.containsKey(l.url)).toList()
    ..sort((a, b) => latency[a.url]!.compareTo(latency[b.url]!));
  final unmeasured = lines.where((l) => !latency.containsKey(l.url)).toList();

  if (measured.isEmpty) {
    // 全部探测失败:保持原顺序,交给播放器与看门狗。
    return LineRankResult(
      ordered: List<StreamLine>.of(lines),
      latencyMs: latency,
      dropped: const [],
    );
  }

  final best = latency[measured.first.url]!;
  final threshold = (best * jitterFactor).round();
  final limit = threshold > slowestAllowedMs ? threshold : slowestAllowedMs;

  final keep = <StreamLine>[];
  final dropped = <StreamLine>[];
  for (final line in measured) {
    if (latency[line.url]! <= limit) {
      keep.add(line);
    } else {
      dropped.add(line);
    }
  }

  return LineRankResult(
    ordered: [...keep, ...dropped, ...unmeasured],
    latencyMs: latency,
    dropped: dropped,
  );
}
