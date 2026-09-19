/// SOOP 分类 cid → 中文名映射(web `soopZhCategoryMap` 同构)。
///
/// web 真源:`services/streaming-server/src/browse/soop.ts` —— 分类列表
/// categoryList 带 `lang=zh_CN` 直出中文;房间流(main_broad_list_api.php)
/// 只有韩文 category_name,web 用 zh_CN 分类表构建 category_no→中文名
/// 进程内缓存,以 zhName 覆盖房间分类名(soop.ts:57-65, 111-116)。
/// 本模块即该缓存:分类树拉取时填充,房间列表/详情读取。
library;

final Map<String, String> _cidToZh = <String, String>{};

/// 分类树(zh_CN)解析时记录一条 cid→中文名。
void rememberSoopZhCategory(String cid, String zhName) {
  if (cid.isEmpty || zhName.isEmpty) return;
  _cidToZh[cid] = zhName;
}

/// 房间列表/详情按 category_no 反查中文名;未命中返回 null(调用方回退
/// 原名 + remap 归一,与 web 原名回退一致)。
String? soopZhCategoryName(String cid) => _cidToZh[cid];
