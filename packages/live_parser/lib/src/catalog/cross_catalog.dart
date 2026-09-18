/// 跨平台分类映射(cross-map)。
///
/// 全平台首页(`site = all`)需要把斗鱼、虎牙、B站各自独立的分类名与 cid
/// 归一到一套通用 key,如 `/all/category/lol`。
///
/// 匹配优先级:站点 cid 白名单 > 名称全等(归一化) > 名称包含;排除词最先生效。
/// cid 只在确有把握时登记,名称匹配是主要手段,避免 cid 漂移导致整类丢失。
library;

import '../models/models.dart';
import 'cross_hot_categories_generated.dart';

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

/// 默认跨平台分类表:键集 / 顺序 / 展示名均与 SFVideoLive 全平台热门分类对齐。
///
/// 数据真源是 `assets/config/cross-categories.json`(再上游对齐 web 的
/// `HOT_CROSS_CATEGORY_KEYS`);匹配规则由生成脚本 `tool/sync_cross_map.dart`
/// 产出到 `cross_hot_categories_generated.dart`(25 个 HOT key 的
/// `{key, name, aliases, siteCids}`),本文件只在其上叠加**手工调优**的精细规则
/// ([_kCrossHotOverlay]),避免把第二份手写表带进来。
///
/// 旧 cross key(如 `wangzhe`/`heping`/`csgo`)不再进索引,但经 [_kCrossKeyAliases]
/// 归一后仍可被 [CrossCatalog.byKey] 命中,保证旧 deeplink / 本地缓存不静默失效。
/// web 无对应物的 `minecraft/sports/food/chess/acg` 已移出索引(见报告说明)。
///
/// 注意此处是 `final` 而非 `const`:Dart 的常量表达式不支持 `for` 元素、
/// 也不支持对 const Map 做下标取值,因此「生成数据 + overlay 合成」只能在
/// 运行期做一次。为保住 `const CrossCatalog()` 这种零成本默认构造,
/// [CrossCatalog] 用可空字段 + getter 承接本表(见其 `categories` getter)。
final List<CrossCategory> kDefaultCrossCategories = List<CrossCategory>.unmodifiable([
  for (final seed in kGeneratedHotCrossCategories)
    CrossCategory(
      key: seed.key,
      name: seed.name,
      aliases: seed.aliases,
      siteCids: seed.siteCids,
      contains: _kCrossHotOverlay[seed.key]?.contains ?? const [],
      excludes: _kCrossHotOverlay[seed.key]?.excludes ?? const [],
    ),
]);

/// 旧 cross key → 当前 key(兼容旧 deeplink / 本地缓存)。
/// web 无对应物的 `minecraft/sports/food/chess/acg` 已不再进入全平台索引,
/// 此处仅保留「旧名 → 新名」的归一能力(wangzhe→wzry 等),[CrossCatalog.byKey]
/// 归一后仍可命中新 key。
const Map<String, String> _kCrossKeyAliases = {
  'wangzhe': 'wzry',
  'heping': 'hpjy',
  'csgo': 'cs2',
  'genshin': 'ys',
  'crossfire': 'cf',
  'outdoor': 'huwai',
  'chat': 'xingxiu',
};

String _resolveCrossKey(String key) => _kCrossKeyAliases[key] ?? key;

/// 手工 overlay:在生成数据之上补充 / 覆盖精细匹配规则。
///
/// 原因:生成数据只含 JSON 直出的 `aliases` / `siteCids`,部分分类需要
///  - [HotOverlay.excludes]:把同根但不同类的板块剔除(如 `lol` 的云顶之弈 / 自走棋);
///  - [HotOverlay.contains]:补充名称子串匹配,覆盖「王者荣耀手游」这类带前后缀的名称。
/// 这些是手工调优过、无法从 JSON 自动派生、且易误伤的规则,集中放此处便于审查与回滚。
class HotOverlay {
  const HotOverlay({this.contains = const [], this.excludes = const []});

  final List<String> contains;
  final List<String> excludes;
}

const Map<String, HotOverlay> _kCrossHotOverlay = {
  // 云顶之弈 / 自走棋 与 LOL 同根,必须剔除,否则 lol 会把云顶的房间一并吞下。
  'lol': HotOverlay(excludes: ['云顶', '下棋', '自走棋']),
  // 以下 contains 还原旧手写表对「带前后缀名称」的子串匹配召回。
  'wzry': HotOverlay(contains: ['王者荣耀']),
  'hpjy': HotOverlay(contains: ['和平精英']),
  'cs2': HotOverlay(contains: ['反恐精英']),
  'ys': HotOverlay(contains: ['原神']),
  'cf': HotOverlay(contains: ['穿越火线']),
  'valorant': HotOverlay(contains: ['无畏契约']),
  'huwai': HotOverlay(contains: ['户外']),
  'xingxiu': HotOverlay(contains: ['星秀', '颜值', '聊天', '交友', '电台', '陪玩']),
  'wudao': HotOverlay(contains: ['舞蹈']),
};

/// 跨平台分类目录:匹配与分类索引的单一入口。
class CrossCatalog {
  const CrossCatalog({List<CrossCategory>? categories}) : _injected = categories;

  /// 显式注入的分类表(测试/自定义场景);为 null 表示用默认表。
  /// 字段名刻意与构造参数不同名,避免 `prefer_initializing_formals`
  /// 建议一个 Dart 不允许的「私有命名初始化形参」。
  final List<CrossCategory>? _injected;

  /// 实际使用的分类表:未显式注入时用 [kDefaultCrossCategories]。
  ///
  /// 用 getter 而非构造参数默认值,是为了让 [kDefaultCrossCategories] 可以是
  /// 运行期合成的 `final` 表(常量表达式无法表达合成逻辑),同时保住
  /// `const CrossCatalog()` 这种零成本默认构造。
  List<CrossCategory> get categories => _injected ?? kDefaultCrossCategories;

  /// 按 key 查找;未命中返回 null(宿主可回退到平台原生分类)。
  /// 先经 [_kCrossKeyAliases] 归一旧 key(如 `wangzhe`→`wzry`),兼容旧 deeplink。
  CrossCategory? byKey(String? key) {
    if (key == null || key.isEmpty) return null;
    final resolved = _resolveCrossKey(key);
    for (final category in categories) {
      if (category.key == resolved) return category;
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
