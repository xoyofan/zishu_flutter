/// 跨平台分类显示映射(纯函数,Dart 移植自参考实现
/// `SFVideoLive/apps/web/src/utils/browse/categoryDisplay.ts`)。
///
/// 设计约束:分类显示名遍布房间卡/分类页/侧栏/关注卡/时间线/播放页头部等
/// **同步**渲染路径,因此这里全部是同步纯函数,不触碰 IO、不 async。
/// 数据来源是内置常量表 `kCrossCategories`(由 `tool/sync_cross_map.dart`
/// 生成),与服务端下发的 `loadCategoryCrossMap` 机制无关,本端直接内置。
///
/// 语义与 web 保持一致:命中跨平台映射用 canonical 中文名,否则回落平台原名。
library;

import 'cross_categories_data.dart';
import 'cross_categories_data_models.dart';

/// 历史/自动生成的冗长 key → 当前简短 key(兼容旧链接与本地缓存)。
const Map<String, String> _kCrossKeyAliases = {
  'g4133_9449_1011032_878': 'sjz',
  'g4133_9449_1011032': 'sjz',
  '3': 'jx3',
  'g1227_6219_1010016_666': 'yjwj',
  'g1227_6219_1010016': 'yjwj',
  'g1223_5489_1010039_321': 'ys',
  'g1223_5489_1010039': 'ys',
  'g3379_7349_1010043_549': 'bhxy',
  'g3379_7349_1010043': 'bhxy',
  'g3133_7209_1010018_502': 'aqtw',
  'g3133_7209_1010018': 'aqtw',
  'g3358_6909_1010011_571': 'dzpd',
  'g3358_6909_1010011': 'dzpd',
  'g356_3115_1010041_163': 'dwrg',
  'g356_3115_1010041': 'dwrg',
  'g2075_6111_1010358_804': 'hmwk',
  'g2075_6111_1010358': 'hmwk',
  'g2556_7185_1010055_514': 'jcc',
  'g2556_7185_1010055': 'jcc',
  'g3671_7711_1010155_662': 'jql',
  'g3671_7711_1010155': 'jql',
  'g201_2168_145': 'yanzhi',
  'ZJGAME': 'host',
  'zjgame': 'host',
};

/// 各平台 cid 不同,跨平台 key 对应斗鱼 cid 需手工校正。
const Map<String, String> _kCrossDouyuCidPatch = {
  'dnf': '40',
};

/// 虎牙同义 gid:分类页 100032 与直播 ZJGAME(1964) 均为主机游戏。
const Map<String, String> _kHuyaCidAliases = {
  '100032': 'host',
  '1964': 'host',
};

/// 历史/自动生成的冗长 key → 当前简短 key(兼容旧链接与本地缓存)。
String resolveCrossCategoryKey(String? key) {
  final text = (key ?? '').toString().trim();
  if (text.isEmpty) return '';
  return _kCrossKeyAliases[text] ?? text;
}

/// 两个 key 是否指向同一跨平台分类(经 alias 归一后比较)。
bool crossCategoryKeysEqual(String? a, String? b) {
  final left = resolveCrossCategoryKey(a);
  final right = resolveCrossCategoryKey(b);
  return left.isNotEmpty && right.isNotEmpty && left == right;
}

/// 按 key 查找跨平台分类(经 alias 归一;命中后应用斗鱼 cid 校正 patch)。
CrossCategoryEntry? findCrossCategoryByKey(String? key) {
  final text = resolveCrossCategoryKey(key);
  if (text.isEmpty) return null;
  final entry = _findByKey(text) ?? _findByKeyFallback(text);
  if (entry == null) return null;
  final patchDouyu = _kCrossDouyuCidPatch[text];
  if (patchDouyu != null && entry.douyu != patchDouyu) {
    return CrossCategoryEntry(
      key: entry.key,
      name: entry.name,
      aliases: entry.aliases,
      siteCids: entry.siteCids,
      siteGroupIds: entry.siteGroupIds,
      douyu: patchDouyu,
      huya: entry.huya,
      douyin: entry.douyin,
      douyuGroup: entry.douyuGroup,
      huyaGroup: entry.huyaGroup,
      huyaTabId: entry.huyaTabId,
      douyinGroupIds: entry.douyinGroupIds,
      douyinPartitions: entry.douyinPartitions,
      isGroup: entry.isGroup,
    );
  }
  return entry;
}

CrossCategoryEntry? _findByKey(String text) =>
    kCrossCategories.cast<CrossCategoryEntry?>().firstWhere(
          (e) => e?.key == text,
          orElse: () => null,
        );

// 内置表已是唯一数据源,FALLBACK 与正式表同源,此处回落到同一常量表。
CrossCategoryEntry? _findByKeyFallback(String text) => _findByKey(text);

/// 跨平台 key → 斗鱼分类 cid(无则回落 fallback)。
String douyuCidForCrossKey(String? key, [Object? fallback]) {
  final entry = findCrossCategoryByKey(key);
  if (entry?.douyu != null && entry!.douyu!.isNotEmpty) {
    return entry.douyu!;
  }
  return fallback?.toString() ?? '';
}

/// 跨平台 key → 虎牙分类 cid(无则回落 fallback)。
String huyaCidForCrossKey(String? key, [Object? fallback]) {
  final entry = findCrossCategoryByKey(key);
  if (entry?.huya != null && entry!.huya!.isNotEmpty) return entry.huya!;
  final iconMeta = crossCategoryIconMeta(entry);
  if (iconMeta.huyaCid.isNotEmpty) return iconMeta.huyaCid;
  final refs = entry == null ? null : entry.siteCids['huya'];
  if (refs != null && refs.isNotEmpty) return refs.first;
  return fallback?.toString() ?? '';
}

/// 取分类图标元信息(本端数据不含 icon 字段,统一返回空)。
({String pic, String huyaCid}) crossCategoryIconMeta(CrossCategoryEntry? entry) {
  // 本端数据模型不含 `icon`,图标走平台图,仅返回空占位以保持与 web 同签名。
  return (pic: '', huyaCid: '');
}

String _norm(String? text) =>
    (text ?? '').toString().trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');

String? _gameCidForSite(CrossCategoryEntry entry, String site) {
  final ref = entry.siteCids[site];
  if (ref != null && ref.isNotEmpty) return ref.first;
  if (site == 'douyu') return entry.douyu;
  if (site == 'huya') return entry.huya;
  if (site == 'douyin') return entry.douyin;
  return null;
}

String? _groupCidForSite(CrossCategoryEntry entry, String site) {
  final ref = entry.siteGroupIds[site];
  if (ref != null && ref.isNotEmpty) return ref;
  if (site == 'douyu') return entry.douyuGroup;
  if (site == 'huya') return entry.huyaGroup;
  return null;
}

List<String> _siteCidsForEntry(CrossCategoryEntry entry, String siteId) {
  final refs = entry.siteCids[siteId];
  if (refs != null && refs.isNotEmpty) return refs;
  final mapped = _gameCidForSite(entry, siteId);
  return mapped != null && mapped.isNotEmpty ? [mapped] : const [];
}

/// 按平台 + cid 查找跨平台分类(先非分组精确 cid,再分组 gid/tabId)。
CrossCategoryEntry? matchCrossCategoryByCid(String siteId, String cidText) {
  if (siteId == 'huya' && _kHuyaCidAliases[cidText] != null) {
    final aliasKey = _kHuyaCidAliases[cidText]!;
    final hit = _findByKey(aliasKey) ?? _findByKeyFallback(aliasKey);
    if (hit != null) return hit;
  }
  for (final entry in kCrossCategories) {
    if (entry.isGroup) continue;
    if (_siteCidsForEntry(entry, siteId).contains(cidText)) return entry;
    if (siteId == 'douyin' && entry.douyinPartitions.contains(cidText)) {
      return entry;
    }
  }
  for (final entry in kCrossCategories) {
    if (!entry.isGroup) continue;
    final groupCid = _groupCidForSite(entry, siteId);
    if (groupCid != null && groupCid == cidText) return entry;
    if (siteId == 'huya' && entry.huyaTabId != null && entry.huyaTabId == cidText) {
      return entry;
    }
    if (siteId == 'douyin') {
      if (entry.douyinGroupIds.contains(cidText)) return entry;
      if (entry.douyinPartitions.contains(cidText)) return entry;
    }
  }
  return null;
}

/// 别名是否匹配分类名(>=4 字符才允许子串包含,避免短别名误抢)。
bool aliasMatchesName(String name, String alias) {
  final a = _norm(alias);
  if (a.isEmpty) return false;
  if (name == a) return true;
  if (a.length >= 4 && name.contains(a)) return true;
  if (name.length >= 4 && a.contains(name)) return true;
  return false;
}

/// 按分类名(含别名子串)查找跨平台分类。
/// 三遍匹配:先全池精确同名,再全池精确别名,最后退回别名子串(>=4 字符)。
/// 先精确别名再子串,可避免 `league of legends` 因子串命中
/// `League of Legends: Wild Rift`(英雄联盟手游)而被抢走;
/// 也保证 `英雄联盟` 不会被子串抢成 `英雄联盟手游`。
CrossCategoryEntry? matchCrossCategoryByName(String? categoryName) {
  final name = _norm(categoryName);
  if (name.isEmpty) return null;
  final byKey = findCrossCategoryByKey(categoryName ?? '');
  if (byKey != null) return byKey;

  CrossCategoryEntry? matchExactName(List<CrossCategoryEntry> pool) {
    for (final entry in pool) {
      if (_norm(entry.name) == name) return entry;
    }
    return null;
  }

  CrossCategoryEntry? matchExactAlias(List<CrossCategoryEntry> pool) {
    for (final entry in pool) {
      for (final alias in entry.aliases) {
        if (_norm(alias) == name) return entry;
      }
    }
    return null;
  }

  CrossCategoryEntry? matchSubstring(List<CrossCategoryEntry> pool) {
    for (final entry in pool) {
      for (final alias in entry.aliases) {
        if (aliasMatchesName(name, alias)) return entry;
      }
    }
    return null;
  }

  return matchExactName(kCrossCategories) ??
      matchExactName(_fallbackPool()) ??
      matchExactAlias(kCrossCategories) ??
      matchExactAlias(_fallbackPool()) ??
      matchSubstring(kCrossCategories) ??
      matchSubstring(_fallbackPool());
}

// 内置表已是唯一数据源,FALLBACK 与正式表同源。
List<CrossCategoryEntry> _fallbackPool() => kCrossCategories;

/// 统一查找:综合 cid 与分类名,返回最优跨平台分类。
CrossCategoryEntry? findCrossCategory(
  String? site,
  String? categoryName,
  Object? cid,
) {
  final siteId = (site ?? '').toString().trim();
  final cidText = (cid ?? '').toString().trim();
  final byCid =
      cidText.isNotEmpty && siteId.isNotEmpty ? matchCrossCategoryByCid(siteId, cidText) : null;
  final byName = matchCrossCategoryByName(categoryName);
  final rawName = _norm(categoryName);

  if (siteId == 'douyin') {
    if (byName != null) return byName;
    if (rawName.isEmpty) return null;
    if (byCid != null && !byCid.isGroup) return null;
    return byCid;
  }
  if (byCid != null && byName != null && byCid.key != byName.key) {
    return byName;
  }
  return byCid ?? byName;
}

/// 平台分类项 → 跨平台收藏 key;无映射时返回空字符串。
String crossKeyForPlatformCategory(
  String? site,
  String? cid,
  String? name,
) {
  final siteId = (site ?? '').toString().trim();
  final cidText = (cid ?? '').toString().trim();
  final nameText = (name ?? '').toString().trim();
  if (siteId.isEmpty || (cidText.isEmpty && nameText.isEmpty)) return '';
  final entry = findCrossCategory(siteId, nameText, cidText);
  if (entry?.key == null || entry!.key.isEmpty) return '';
  return resolveCrossCategoryKey(entry.key);
}

/// 统一展示名:命中跨平台映射用 canonical name,否则用平台原名。
String displayCategoryName(
  String? site,
  String? categoryName, [
  Object? cid,
]) {
  final raw = (categoryName ?? '').toString().trim();
  final siteId = (site ?? '').toString().trim();
  if (raw.isEmpty) return '';
  if (siteId == 'douyin') {
    final byName = findCrossCategory(siteId, raw, '');
    if (byName == null) return raw;
    if (_norm(byName.name) == _norm(raw)) return byName.name;
    return raw;
  }
  // 全平台(cross site)索引里的 name 已经是跨平台映射表的 canonical 中文名,
  // 参考实现渲染该列表时从不以 `all` 调用本函数(只对平台站调用),故此处恒等返回。
  // 若仍走名称映射,「体育」会被登记为「户外」的别名而互相抢占:
  // 侧栏出现两个「户外」、「体育」整项消失。
  if (siteId == 'all') return raw;
  final entry = findCrossCategory(site, raw, cid);
  if (entry?.name != null && entry!.name.isNotEmpty) return entry.name;
  return raw;
}

/// 播放页标题:中文优先;跨平台 key(如 huwai)→ 中文名;有原生中文则保留。
String formatCategoryHeaderLabel(
  String? site,
  String? categoryName, [
  Object? cid,
]) {
  final raw = (categoryName ?? '').toString().trim();
  if (raw.isEmpty) return displayCategoryName(site, '', cid);
  final byKey = findCrossCategoryByKey(raw);
  if (byKey?.name != null && byKey!.name.isNotEmpty) return byKey.name;
  if (RegExp(r'[\u4e00-\u9fff]').hasMatch(raw)) return raw;
  final mapped = displayCategoryName(site, raw, cid);
  if (mapped.isNotEmpty && mapped != raw) return mapped;
  return raw;
}

/// 房间角标/列表:原生分类名经跨平台映射后展示(如虎牙 lol → 英雄联盟)。
String roomCategoryLabel(
  String? site, {
  required String? nativeCategory,
  String? cid,
}) {
  final siteId = (site ?? '').toString().trim();
  final native = (nativeCategory ?? '').toString().trim();
  if (native.isNotEmpty) {
    return formatCategoryHeaderLabel(siteId, native, cid).isNotEmpty
        ? formatCategoryHeaderLabel(siteId, native, cid)
        : native;
  }
  return displayCategoryName(siteId, '', cid);
}

/// 分组名展示:抖音/斗鱼/虎牙/哔哩哔哩直接用平台原名(这些平台分组名已是中文
/// 或平台原生),其余才走跨平台映射。
String displayCategoryGroupName(
  String? site,
  String? categoryName, [
  Object? cid,
]) {
  final raw = (categoryName ?? '').toString().trim();
  if (raw.isEmpty) return '';
  if (site == 'douyin' ||
      site == 'douyu' ||
      site == 'huya' ||
      site == 'bilibili') {
    return raw;
  }
  return displayCategoryName(site, raw, cid);
}
