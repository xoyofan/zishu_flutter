/// 抽屉(首页左侧边栏)与顶部导航 hover 浮层**共用**的一级分区 + 二级分类
/// 构建逻辑。Dart 移植自参考实现
/// `SFVideoLive/apps/web/src/utils/browse/drawerCategories.ts`
/// (该文件注释原文:「一级分区 + 二级游戏列表(抽屉 / 导航分类栏共用)」)。
///
/// 用户口径(2026-09-27):侧栏点平台后与顶栏 hover 浮层共用同一分级逻辑
/// —— 显示一级分类后二级分类,不平铺;**不设每区条数上限**
/// (参考实现的 18 条 limit 不采用)。
///
/// 纯函数、无 IO,分类数据来自 [browseCategoriesProvider](fixture/真实解析
/// 双轨同一入口)。
library;

import 'package:live_parser/live_parser.dart' show CategoryGroup, CategoryItem;

/// 不展示的非游戏一级分区(对齐参考 `DRAWER_EXCLUDED_GROUP`)。
final RegExp _kDrawerExcludedGroup = RegExp(r'颜值|正能量|语音|科技文化');

/// 一级分区排序(其余非排除分区排在后面;按平台原生一级 id)。
const Map<String, List<String>> _kDrawerGroupOrder = {
  'douyu': ['1', '15', '9', '22', '2'],
  'huya': ['1', '3', '8', '2'],
  'douyin': ['1', '2', '3', '4', '5', '6', '7', 'yule'],
};

/// 过滤非游戏一级分区与空组(对齐参考 `filterDrawerCategoryGroups`)。
List<CategoryGroup> filterDrawerCategoryGroups(List<CategoryGroup> groups) => [
  for (final group in groups)
    if (!_kDrawerExcludedGroup.hasMatch(group.name) && group.items.isNotEmpty)
      group,
];

/// 一级分区排序:douyu/huya/douyin 按 [_kDrawerGroupOrder],组内同序号按
/// 组名 zh 序;无排序表的平台保持原序(对齐参考 `sortDrawerCategoryGroups`)。
List<CategoryGroup> sortDrawerCategoryGroups(
  String site,
  List<CategoryGroup> groups,
) {
  final order = _kDrawerGroupOrder[site];
  if (order == null || order.isEmpty) return groups;
  final rank = <String, int>{
    for (var i = 0; i < order.length; i++) order[i]: i,
  };
  return [...groups]..sort((a, b) {
    final left = rank[a.id] ?? 999;
    final right = rank[b.id] ?? 999;
    if (left != right) return left - right;
    return a.name.compareTo(b.name);
  });
}

/// 斗鱼/虎牙/抖音:过滤并排序;其余平台原样返回(对齐参考
/// `normalizeBrowseCategoryGroups`)。
List<CategoryGroup> normalizeDrawerCategoryGroups(
  String site,
  List<CategoryGroup> groups,
) {
  if (site == 'douyin') return sortDrawerCategoryGroups(site, groups);
  if (site != 'douyu' && site != 'huya') return groups;
  return sortDrawerCategoryGroups(site, filterDrawerCategoryGroups(groups));
}

/// 平台只有一个大组(twitch/soop/快手等无一级分区结构)→ 隐藏组标题
/// 平铺渲染(对齐参考 `isFlatCategoryGroups`)。
bool isFlatCategoryGroups(List<CategoryGroup> groups) => groups.length == 1;

/// 一级分区:组名(一级分类)+ 该组下的二级分类条目。
class CategorySection {
  const CategorySection({
    required this.id,
    required this.name,
    required this.items,
  });

  /// 平台原生一级分区 id。
  final String id;

  /// 一级分区名。
  final String name;

  /// 二级分类条目(不限条数)。
  final List<CategoryItem> items;
}

/// 一级分区 + 二级分类列表(抽屉 / 导航分类栏共用同一入口)。
List<CategorySection> buildCategorySections(
  String site,
  List<CategoryGroup> groups,
) {
  final normalized = normalizeDrawerCategoryGroups(site, groups);
  return [
    for (final group in normalized)
      if (group.items.isNotEmpty)
        CategorySection(
          id: group.id,
          name: group.name.trim(),
          items: group.items,
        ),
  ];
}
