/// 站点无关的搜索命中排序与去重:相关性(精确 100/前缀 80/包含 60)
/// > 直播状态(live>replay>offline)> 主播名。
library;

import '../models/models.dart';

String normSearchText(String text) =>
    text.trim().toLowerCase().replaceAll(RegExp(r'[\s\u3000]+'), '');

int matchScore(String query, String anchor, String title) {
  final q = normSearchText(query);
  if (q.isEmpty) return 0;
  final a = normSearchText(anchor);
  final t = normSearchText(title);
  if (a == q || t == q) return 100;
  if (a.startsWith(q) || t.startsWith(q)) return 80;
  if (a.contains(q) || t.contains(q)) return 60;
  return 0;
}

const List<SearchHitState> _stateOrder = [
  SearchHitState.live,
  SearchHitState.replay,
  SearchHitState.offline,
];

int _stateRank(SearchHitState state) {
  final index = _stateOrder.indexOf(state);
  return index == -1 ? 9 : index;
}

List<SearchHit> sortSearchHits(String query, List<SearchHit> hits) {
  final sorted = [...hits];
  sorted.sort((a, b) {
    final scoreA = matchScore(query, a.anchor, a.title);
    final scoreB = matchScore(query, b.anchor, b.title);
    if (scoreA != scoreB) return scoreB - scoreA;
    final stateCompare = _stateRank(a.state) - _stateRank(b.state);
    if (stateCompare != 0) return stateCompare;
    return a.anchor.compareTo(b.anchor);
  });
  return sorted;
}

List<SearchHit> trimSearchHits(List<SearchHit> hits, int limit) {
  final seen = <String>{};
  final out = <SearchHit>[];
  for (final hit in hits) {
    final id = hit.id.trim();
    if (id.isEmpty || !seen.add(id)) continue;
    out.add(hit);
    if (out.length >= limit) break;
  }
  return out;
}
