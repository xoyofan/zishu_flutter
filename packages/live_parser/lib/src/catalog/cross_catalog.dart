/// 跨平台分类映射(cross-map)。
///
/// 全平台首页(`site = all`)需要把斗鱼、虎牙、B站各自独立的分类名与 cid
/// 归一到一套通用 key,如 `/all/category/lol`。
///
/// 匹配优先级:站点 cid 白名单 > 名称全等(归一化) > 名称包含;排除词最先生效。
/// cid 只在确有把握时登记,名称匹配是主要手段,避免 cid 漂移导致整类丢失。
library;

import '../models/models.dart';

/// 全平台聚合站点的 site id。
const String kCrossSiteId = 'all';

/// 分类名归一化:小写 + 去除空格与常见分隔符,保留中英文与数字。
String normalizeCategoryName(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[\s\-_·、:：.。()（）[\]【】]+'), '');

/// 一个跨平台分类。
class CrossCategory {
  const CrossCategory({
    required this.key,
    required this.name,
    this.aliases = const [],
    this.contains = const [],
    this.siteCids = const {},
    this.excludes = const [],
  });

  /// 路由与 API 使用的稳定 key,如 `lol`。
  final String key;

  /// 中文展示名。
  final String name;

  /// 归一化后**全等**即命中,用于 `lol`、`cs2` 这类短名,避免误包含。
  final List<String> aliases;

  /// 归一化后**包含**即命中,用于「王者荣耀手游」这类带前后缀的名称。
  final List<String> contains;

  /// 站点 cid 白名单:`site -> [cid, ...]`。
  final Map<String, List<String>> siteCids;

  /// 归一化后包含任一排除词则不命中,用于把「lol云顶之弈」从 LOL 中剔除。
  final List<String> excludes;

  /// 判断某平台的某条房间分类是否归入本类。
  bool matches({
    required String site,
    required String cid,
    required String categoryName,
  }) {
    final cids = siteCids[site];
    if (cids != null && cid.isNotEmpty && cids.contains(cid)) return true;

    final name = normalizeCategoryName(categoryName);
    if (name.isEmpty) return false;

    for (final exclude in excludes) {
      final token = normalizeCategoryName(exclude);
      if (token.isNotEmpty && name.contains(token)) return false;
    }
    for (final alias in aliases) {
      if (name == normalizeCategoryName(alias)) return true;
    }
    for (final part in contains) {
      final token = normalizeCategoryName(part);
      if (token.isNotEmpty && name.contains(token)) return true;
    }
    return false;
  }
}

/// 默认跨平台分类表:与 SFVideoLive 全平台热门分类对齐,顺序即展示顺序。
const List<CrossCategory> kDefaultCrossCategories = [
  CrossCategory(
    key: 'lol',
    name: '英雄联盟',
    aliases: ['英雄联盟', 'lol', 'leagueoflegends', '英雄联盟手游'],
    siteCids: {'douyu': ['1'], 'huya': ['1']},
    excludes: ['云顶', '下棋', '自走棋'],
  ),
  CrossCategory(
    key: 'wangzhe',
    name: '王者荣耀',
    aliases: ['王者荣耀', '王者'],
    contains: ['王者荣耀'],
    siteCids: {'huya': ['2336']},
  ),
  CrossCategory(
    key: 'heping',
    name: '和平精英',
    aliases: ['和平精英', '刺激战场', 'pubgmobile'],
    contains: ['和平精英'],
    siteCids: {'huya': ['3203']},
  ),
  CrossCategory(
    key: 'csgo',
    name: 'CS2',
    aliases: ['cs2', 'csgo', '反恐精英', 'counterstrike'],
    contains: ['反恐精英'],
    siteCids: {'huya': ['862']},
  ),
  CrossCategory(
    key: 'dota2',
    name: 'DOTA2',
    aliases: ['dota2', '刀塔2', '刀塔'],
    contains: ['dota'],
  ),
  CrossCategory(
    key: 'valorant',
    name: '无畏契约',
    aliases: ['无畏契约', 'valorant', '瓦罗兰特'],
    contains: ['无畏契约'],
    siteCids: {'huya': ['5937']},
  ),
  CrossCategory(
    key: 'genshin',
    name: '原神',
    aliases: ['原神', 'genshinimpact', 'genshin'],
    contains: ['原神'],
  ),
  CrossCategory(
    key: 'minecraft',
    name: '我的世界',
    aliases: ['我的世界', 'minecraft'],
    contains: ['我的世界'],
  ),
  CrossCategory(
    key: 'crossfire',
    name: '穿越火线',
    aliases: ['穿越火线', 'crossfire'],
    contains: ['穿越火线'],
    siteCids: {'douyu': ['4'], 'huya': ['4']},
  ),
  CrossCategory(
    key: 'chess',
    name: '棋牌桌游',
    aliases: ['云顶之弈', 'lol云顶之弈', '云顶', '自走棋', '棋牌', '炉石传说'],
    contains: ['云顶', '自走棋', '棋牌', '炉石', '三国杀', '斗地主'],
    siteCids: {'huya': ['5485', '393']},
  ),
  CrossCategory(
    key: 'sports',
    name: '体育',
    aliases: ['体育', '足球', '篮球', 'nba'],
    contains: ['体育', '足球', '篮球', 'nba', '斯诺克', '台球'],
  ),
  CrossCategory(
    key: 'outdoor',
    name: '户外',
    aliases: ['户外', '户外直播'],
    contains: ['户外'],
  ),
  CrossCategory(
    key: 'food',
    name: '美食',
    aliases: ['美食', '吃播'],
    contains: ['美食', '吃播'],
  ),
  CrossCategory(
    key: 'chat',
    name: '星秀娱乐',
    aliases: ['星秀', '娱乐', '颜值', '聊天', '交友', '音乐', '唱跳'],
    contains: ['星秀', '颜值', '聊天', '交友', '电台', '陪玩'],
    siteCids: {'huya': ['1663']},
  ),
  CrossCategory(
    key: 'acg',
    name: '二次元',
    aliases: ['二次元', 'acg', '动漫', '虚拟主播', '虚拟偶像'],
    contains: ['二次元', '虚拟主播', '虚拟偶像', '动漫'],
  ),
];

/// 跨平台分类目录:匹配与分类索引的单一入口。
class CrossCatalog {
  const CrossCatalog({this.categories = kDefaultCrossCategories});

  final List<CrossCategory> categories;

  /// 按 key 查找;未命中返回 null(宿主可回退到平台原生分类)。
  CrossCategory? byKey(String? key) {
    if (key == null || key.isEmpty) return null;
    for (final category in categories) {
      if (category.key == key) return category;
    }
    return null;
  }

  /// 把某平台房间的分类归入跨平台分类;无匹配返回 null。
  CrossCategory? match({
    required String site,
    required String cid,
    required String categoryName,
  }) {
    for (final category in categories) {
      if (category.matches(site: site, cid: cid, categoryName: categoryName)) {
        return category;
      }
    }
    return null;
  }

  /// 全平台分类索引:以 `hot` 为单一分组,item.cid 即跨平台 key。
  CategoryResult toCategoryResult({String site = kCrossSiteId}) => CategoryResult(
    site: site,
    groups: [
      CategoryGroup(
        id: 'hot',
        name: '热门分类',
        items: [
          for (final category in categories)
            CategoryItem(cid: category.key, name: category.name, pic: ''),
        ],
      ),
    ],
  );
}
