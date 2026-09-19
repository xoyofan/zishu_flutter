/// YY biz → 中文名反查表(soop zh_categories 同款模式)。
///
/// YY 上游房间数据的 `biz` 是英文业务键(如 `other`),不是分类中文名;
/// 中文名来自分类树(getCategory 的 title)。分类索引解析时在此登记
/// biz→分类名,房间列表/详情/搜索按 biz 反查,未命中回退原值。
library;

final Map<String, String> _bizToName = <String, String>{};

/// biz 键归一:trim + 小写(上游 'other'/'Other' 视为同一键)。
String yyBizKey(String raw) => raw.trim().toLowerCase();

/// 分类树解析时登记一条 biz→分类中文名;同 biz 多分类时保留首个。
void rememberYyBizName(String biz, String name) {
  final key = yyBizKey(biz);
  if (key.isEmpty || name.isEmpty) return;
  _bizToName.putIfAbsent(key, () => name);
}

/// 按 biz 反查中文名;未命中返回 null。
String? yyBizName(String biz) => _bizToName[yyBizKey(biz)];
