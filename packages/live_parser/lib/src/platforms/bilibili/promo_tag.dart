/// B 站推荐角标:PK 中 > 认证信息关键词。
library;

import '../douyu/json_utils.dart';

const List<String> _bilibiliPromoPatterns = [
  '独家高能主播',
  '直播高能主播',
  '高能主播',
  '年度巅峰主播',
  '知名游戏UP主',
  '知名UP主',
  '官方',
];

String? pickBilibiliPromoTag(Map<String, dynamic> record) {
  final pkId = jsonInt(record['pk_id']);
  if (pkId > 0) return 'PK中';

  final verify = jsonMapOf(record['verify']);
  final desc = jsonText(verify['desc']).trim();
  if (desc.isEmpty) return null;

  for (final pattern in _bilibiliPromoPatterns) {
    if (desc.contains(pattern)) {
      var label = pattern;
      if (label.startsWith('bilibili ')) {
        label = label.substring('bilibili '.length);
      }
      return label.length <= 6 ? label : label.substring(0, 6);
    }
  }
  return null;
}
