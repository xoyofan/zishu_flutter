/// 斗鱼运营角标兜底:copilotLabel > 认证信息 > 贵族。
///
/// 不再取 `roomLabel` 首项 —— 2026-09 起 roomLabel 整体编入卡片 chips 行
/// (见 `card_tags.dart`),重复当 promoTag 会在同一张卡上显示两遍。
library;

import 'json_utils.dart';

String? pickDouyuPromoTag(Map<String, dynamic> item) {
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
