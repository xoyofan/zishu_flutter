/// 虎牙平台身份/榜单标签:sRecommendTagName(如「超级明星」),截断 6 字。
///
/// 卡片封面右上角线框 tag 的数据源([RoomRecord.identityLabel]);
/// 不填 promoTag —— 同一信息不在右上角与 chips 行重复出现。
library;

import '../douyu/json_utils.dart';

String? pickHuyaIdentityLabel(Map<String, dynamic> item) {
  final text = jsonText(item['sRecommendTagName']).trim();
  if (text.isEmpty) return null;
  return text.length <= 6 ? text : text.substring(0, 6);
}
