/// 虎牙推荐角标:sRecommendTagName,截断 6 字。
library;

import '../douyu/json_utils.dart';

String? pickHuyaPromoTag(Map<String, dynamic> item) {
  final text = jsonText(item['sRecommendTagName']).trim();
  if (text.isEmpty) return null;
  return text.length <= 6 ? text : text.substring(0, 6);
}
