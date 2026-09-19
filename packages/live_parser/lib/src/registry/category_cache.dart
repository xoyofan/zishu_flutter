/// 分类缓存有效性校验(对齐 SFVideoLive commit e389570 的 hasRealGroups)。
library;

import '../models/models.dart';

/// 分类缓存「空壳分组」校验:groups 非空且**任一**分组有非空 items 才算有效。
///
/// 上游接口改版可能产出 `{id, name, list: []}` 空壳分组(虎牙分类接口改版
/// 踩过):顶层分组数非空不代表有内容,这类条目按未命中处理,触发重新请求
/// 覆盖缓存,避免空壳霸占缓存导致分类持续不显示。
///
/// - peek(读缓存):空壳按未命中处理,作废重拉;
/// - remember(写缓存):空壳不落缓存,下次请求自愈。
bool hasRealCategoryGroups(List<CategoryGroup>? groups) =>
    groups != null && groups.any((group) => group.items.isNotEmpty);
