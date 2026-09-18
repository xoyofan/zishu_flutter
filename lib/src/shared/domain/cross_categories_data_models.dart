/// 跨平台分类映射条目数据模型。
///
/// 本文件定义 [CrossCategoryEntry] 的字段结构;`lib/src/shared/domain/
/// cross_categories_data.dart` 由 `tool/sync_cross_map.dart` 从
/// `assets/config/cross-categories.json` 生成,**请勿手改**。
///
/// 字段来源与参考实现 `SFVideoLive/apps/web/src/utils/browse/categoryDisplay.ts`
/// 中的 `CrossCategoryEntry` 对齐,但去掉了仅在 web 端用到的 `icon`(图标走
/// 平台图,本端分类显示只需文本),并用 `isGroup` 取代 `kind === "group"` 判定。
library;

/// 一条跨平台分类映射:一个 canonical key + 中文名,关联到各平台的分类 id。
class CrossCategoryEntry {
  /// 跨平台唯一 key(如 `lol` / `huwai` / `group-danji`)。
  final String key;

  /// canonical 中文展示名(如 `英雄联盟`)。
  final String name;

  /// 别名(用于按名子串匹配,如 `League of Legends`)。
  final List<String> aliases;

  /// 各平台分类 cid 列表,key 为平台 id(bilibili/twitch/soop/...)。
  final Map<String, List<String>> siteCids;

  /// 各平台分组 gid,key 为平台 id。
  final Map<String, String> siteGroupIds;

  /// 斗鱼分类 cid(顶层级,不在 [siteCids] 内)。
  final String? douyu;

  /// 虎牙分类 cid(顶层级)。
  final String? huya;

  /// 抖音分类 cid(顶层级)。
  final String? douyin;

  /// 斗鱼分组 gid。
  final String? douyuGroup;

  /// 虎牙分组 gid。
  final String? huyaGroup;

  /// 虎牙分组 tabId。
  final String? huyaTabId;

  /// 抖音分组 id 列表。
  final List<String> douyinGroupIds;

  /// 抖音分区 cid 列表(来自 `douyinPartitions`)。
  final List<String> douyinPartitions;

  /// 是否为分组类(对应参考实现 `kind === "group"`)。
  final bool isGroup;

  const CrossCategoryEntry({
    required this.key,
    required this.name,
    this.aliases = const [],
    this.siteCids = const {},
    this.siteGroupIds = const {},
    this.douyu,
    this.huya,
    this.douyin,
    this.douyuGroup,
    this.huyaGroup,
    this.huyaTabId,
    this.douyinGroupIds = const [],
    this.douyinPartitions = const [],
    this.isGroup = false,
  });
}
