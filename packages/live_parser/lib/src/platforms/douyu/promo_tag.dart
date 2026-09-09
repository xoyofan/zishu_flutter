/// 斗鱼推荐/运营角标:roomLabel 首项 > copilotLabel > 认证信息 > 贵族。
library;

import 'json_utils.dart';

String? pickDouyuPromoTag(Map<String, dynamic> item) {
  final labels = item['roomLabel'];
  if (labels is List && labels.isNotEmpty) {
    final first = jsonText(labels.first).trim();
    if (first.isNotEmpty) return truncatePromoTag(first);
  }
  final copilot = jsonText(item['copilotLabel']).trim();
  if (copilot.isNotEmpty) return truncatePromoTag(copilot);

  final auth = jsonMapOf(item['authInfo']);
  final desc = jsonText(auth['descV2'] ?? auth['desc']).trim();
  if (desc.isNotEmpty) return truncatePromoTag(desc);

  if (jsonInt(item['vipId']) > 0) return '贵族';
  return null;
}

String truncatePromoTag(String text, [int maxLen = 6]) {
  final raw = text.trim();
  if (raw.isEmpty) return '';
  if (raw.length <= maxLen) return raw;
  return raw.substring(0, maxLen);
}
