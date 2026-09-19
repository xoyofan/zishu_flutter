/// 跨平台分类映射表生成器:`assets/config/cross-categories.json` → Dart 常量表。
///
/// 用法(仓库根目录):
///   dart run tool/sync_cross_map.dart
///
/// 为什么生成而不是运行时读 asset:分类显示名遍布房间卡/分类页/侧栏等**同步**
/// 渲染路径,若把它做成 async 加载,首帧会闪出平台原文再跳中文,且 widget 测试
/// 要额外挂 asset bundle。生成常量表后调用点保持纯函数、可单测、零 IO。
///
/// 数据真源是参考实现 `packages/shared/src/data/cross-categories.json`
/// (328 条;字段 key/name/aliases/sites/douyu/huya/douyin/...)。同步上游后重跑本脚本。
///
/// 本脚本产出两份产物:
///  1. app 侧全量映射表 `lib/src/shared/domain/cross_categories_data.dart`
///     (328 条,供 displayCategoryName 等显示逻辑做名称/图标映射)。
///  2. parser 侧热门 25 key `packages/live_parser/lib/src/catalog/
///     cross_hot_categories_generated.dart`(仅对齐 web HOT_CROSS_CATEGORY_KEYS
///     的 25 个 key,供全平台(all)分类索引与 `/all/category/<key>` 过滤规则)。
///
/// 分层语义(改表时勿混淆):
///  - 第一层 remap(`packages/live_parser/.../category_name_remap.dart`)负责
///    海外平台原始名 → 中文(display 中文名);
///  - 第二层 cross 全量(产物 1)是 `displayCategoryName` 的兜底池,必须**全量**
///    328 条 —— 非热门分类(复古游戏/艾尔登法环/阿尔比恩等 303 条)的跨平台
///    归一全靠它,缺条目即回归;
///  - 产物 2 的 25 热门 key 只服务于 all 站分类索引,刻意不扩全量(web 同款)。
library;

import 'dart:convert';
import 'dart:io';

const String _kSource = 'assets/config/cross-categories.json';
const String _kAppTarget = 'lib/src/shared/domain/cross_categories_data.dart';
const String _kParserTarget =
    'packages/live_parser/lib/src/catalog/cross_hot_categories_generated.dart';

/// 全平台热门分类 key(顺序即展示顺序),对齐 web 的
/// `apps/web/src/config/hotCrossCategories.js` 的 `HOT_CROSS_CATEGORY_KEYS`。
/// web 改这个列表时,同步此处;生成器会校验源数据是否 25/25 命中。
const List<String> _kHotCrossCategoryKeys = [
  'lol',
  'sjz',
  'jx3',
  'wzry',
  'hpjy',
  'cs2',
  'dota2',
  'cf',
  'yjwj',
  'ys',
  'bhxy',
  'aqtw',
  'tft',
  'hs',
  'valorant',
  'dnf',
  'dzpd',
  'dwrg',
  'hmwk',
  'jcc',
  'jql',
  'wudao',
  'huwai',
  'xingxiu',
  'yanzhi',
];

Future<void> main() async {
  final raw = await File(_kSource).readAsString();
  final decoded = jsonDecode(raw);
  if (decoded is! List) {
    stderr.writeln('源数据不是数组:$_kSource');
    exitCode = 1;
    return;
  }
  final entries = [
    for (final item in decoded)
      if (item is Map) Map<String, dynamic>.from(item),
  ];
  if (!_validate(entries)) {
    exitCode = 1;
    return;
  }

  _generateApp(entries);
  await _generateParser(entries);
}

/// fail-fast 源数据校验:空表、缺 key/name、重复 key 一律拒绝生成,
/// 避免半残数据静默替换线上常量表(displayCategoryName 第二层兜底池)。
bool _validate(List<Map<String, dynamic>> entries) {
  var ok = true;
  if (entries.isEmpty) {
    stderr.writeln('源数据为空:$_kSource');
    return false;
  }
  final seen = <String>{};
  final dup = <String>{};
  for (var i = 0; i < entries.length; i++) {
    final e = entries[i];
    final key = _str(e['key']);
    final name = _str(e['name']);
    if (key.isEmpty || name.isEmpty) {
      stderr.writeln('第 $i 条缺 key/name: ${e.keys.toList()}');
      ok = false;
      continue;
    }
    if (!seen.add(key)) dup.add(key);
  }
  if (dup.isNotEmpty) {
    stderr.writeln('源数据存在重复 key: ${dup.toList()}');
    ok = false;
  }
  if (ok) {
    stdout.writeln('源数据校验通过:${entries.length} 条(全量;displayCategoryName '
        '第二层兜底池必须与源等条数)');
  }
  return ok;
}

/// 1) app 侧全量映射表(按 key 排序,保证生成结果稳定)。
void _generateApp(List<Map<String, dynamic>> entries) {
  final sorted = [...entries]
    ..sort((a, b) => (a['key'] ?? '').toString().compareTo((b['key'] ?? '').toString()));

  final buffer = StringBuffer()
    ..writeln('/// 跨平台分类映射表(由 `tool/sync_cross_map.dart` 从')
    ..writeln('/// `assets/config/cross-categories.json` 生成,**请勿手改**)。')
    ..writeln('///')
    ..writeln('/// 同步上游后可重跑脚本:`dart run tool/sync_cross_map.dart`。')
    ..writeln('library;')
    ..writeln()
    ..writeln("import 'cross_categories_data_models.dart';")
    ..writeln()
    ..writeln('/// ${sorted.length} 条跨平台分类映射(按 key 排序,保证生成结果稳定)。')
    ..writeln('const List<CrossCategoryEntry> kCrossCategories = [');
  for (final entry in sorted) {
    buffer.writeln(_emitEntry(entry));
  }
  buffer.writeln('];');

  File(_kAppTarget).writeAsStringSync(buffer.toString());
  stdout.writeln('生成 ${sorted.length} 条 → $_kAppTarget');
}

/// 2) parser 侧热门 25 key(保持 HOT 顺序,由生成数据派生匹配规则)。
Future<void> _generateParser(List<Map<String, dynamic>> entries) async {
  final byKey = {for (final e in entries) _str(e['key']): e};
  final missing = [
    for (final key in _kHotCrossCategoryKeys)
      if (!byKey.containsKey(key)) key,
  ];
  if (missing.isNotEmpty) {
    stderr.writeln('HOT key 在源数据缺失: $missing');
    exitCode = 1;
    return;
  }

  final buffer = StringBuffer()
    ..writeln('/// 本文件由 `tool/sync_cross_map.dart` 从')
    ..writeln('/// `assets/config/cross-categories.json` 自动生成,**请勿手改**。')
    ..writeln('///')
    ..writeln('/// 仅含全平台热门 25 key(对齐 web 的 `HOT_CROSS_CATEGORY_KEYS`,')
    ..writeln('/// 顺序即展示顺序)的基础匹配数据 `{key, name, aliases, siteCids}`;')
    ..writeln('/// 精细匹配规则(contains/excludes)由 `cross_catalog.dart` 的')
    ..writeln('/// `_kCrossHotOverlay` 按 key 覆盖。改 web 的 `hotCrossCategories.js`')
    ..writeln('/// 或 `assets/config/cross-categories.json` 后重跑本脚本。')
    ..writeln('library;')
    ..writeln()
    ..writeln('/// 全平台热门分类种子:可由 JSON 派生的最小匹配数据。')
    ..writeln('class HotCrossSeed {')
    ..writeln('  const HotCrossSeed({')
    ..writeln('    required this.key,')
    ..writeln('    required this.name,')
    ..writeln('    required this.aliases,')
    ..writeln('    required this.siteCids,')
    ..writeln('  });')
    ..writeln()
    ..writeln('  final String key;')
    ..writeln('  final String name;')
    ..writeln('  final List<String> aliases;')
    ..writeln('  final Map<String, List<String>> siteCids;')
    ..writeln('}')
    ..writeln()
    ..writeln('/// 25 个 HOT key(顺序即展示顺序,与 web 一致)。请勿手改;')
    ..writeln('/// 改 JSON 后重跑 `dart run tool/sync_cross_map.dart`。')
    ..writeln('const List<HotCrossSeed> kGeneratedHotCrossCategories = [');
  for (final key in _kHotCrossCategoryKeys) {
    buffer.writeln(_emitHot(byKey[key]!));
  }
  buffer.writeln('];');

  await File(_kParserTarget).writeAsString(buffer.toString());
  stdout.writeln('生成 ${_kHotCrossCategoryKeys.length} 条 → $_kParserTarget');
}

String _emitHot(Map<String, dynamic> e) {
  final key = _str(e['key']);
  final name = _str(e['name']);
  final aliases = _strList(e['aliases']);
  final siteCids = _siteCidsForEntry(e);
  final parts = <String>[
    'key: ${_lit(key)}',
    'name: ${_lit(name)}',
    if (aliases.isNotEmpty) 'aliases: ${_litList(aliases)}',
    if (siteCids.isNotEmpty) 'siteCids: ${_litMap(siteCids)}',
  ];
  return '  HotCrossSeed(\n    ${parts.join(',\n    ')},\n  ),';
}

/// 从 JSON 抽取站点 cid 白名单:仅取聚合站(douyu/huya/bilibili)与海外站
/// (twitch/soop)的真实分类 cid;斗鱼/虎牙取顶层字段,其余取 `sites.*.cid`。
Map<String, List<String>> _siteCidsForEntry(Map<String, dynamic> e) {
  final map = <String, List<String>>{};
  void add(String site, String cid) {
    final v = cid.trim();
    if (v.isNotEmpty) map[site] = [v];
  }

  add('douyu', _str(e['douyu']));
  add('huya', _str(e['huya']));
  final sites = e['sites'];
  if (sites is Map) {
    for (final site in const ['bilibili', 'twitch', 'soop']) {
      final ref = sites[site];
      if (ref is Map) add(site, _str(ref['cid']));
    }
  }
  return map;
}

String _emitEntry(Map<String, dynamic> e) {
  final key = _str(e['key']);
  final name = _str(e['name']);
  final aliases = _strList(e['aliases']);
  final sites = <String, List<String>>{};
  final groupIds = <String, String>{};
  final rawSites = e['sites'];
  if (rawSites is Map) {
    for (final site in rawSites.keys) {
      final ref = rawSites[site];
      if (ref is! Map) continue;
      final cids = <String>[];
      final cid = _str(ref['cid']);
      if (cid.isNotEmpty) cids.add(cid);
      final refs = ref['refs'];
      if (refs is List) {
        for (final r in refs) {
          if (r is Map) {
            final refCid = _str(r['cid']);
            if (refCid.isNotEmpty && !cids.contains(refCid)) cids.add(refCid);
          }
        }
      }
      if (cids.isNotEmpty) sites[site.toString()] = cids;
      final groupId = _str(ref['groupId']);
      if (groupId.isNotEmpty) groupIds[site.toString()] = groupId;
    }
  }

  final parts = <String>[
    'key: ${_lit(key)}',
    'name: ${_lit(name)}',
    if (aliases.isNotEmpty) 'aliases: ${_litList(aliases)}',
    if (sites.isNotEmpty) 'siteCids: ${_litMap(sites)}',
    if (groupIds.isNotEmpty) 'siteGroupIds: ${_litMap2(groupIds)}',
    if (_str(e['douyu']).isNotEmpty) 'douyu: ${_lit(_str(e['douyu']))}',
    if (_str(e['huya']).isNotEmpty) 'huya: ${_lit(_str(e['huya']))}',
    if (_str(e['douyin']).isNotEmpty) 'douyin: ${_lit(_str(e['douyin']))}',
    if (_str(e['douyuGroup']).isNotEmpty) 'douyuGroup: ${_lit(_str(e['douyuGroup']))}',
    if (_str(e['huyaGroup']).isNotEmpty) 'huyaGroup: ${_lit(_str(e['huyaGroup']))}',
    if (_str(e['huyaTabId']).isNotEmpty) 'huyaTabId: ${_lit(_str(e['huyaTabId']))}',
    if (_strList(e['douyinGroupIds']).isNotEmpty)
      'douyinGroupIds: ${_litList(_strList(e['douyinGroupIds']))}',
    if (_strList(e['douyinPartitions']).isNotEmpty)
      'douyinPartitions: ${_litList(_strList(e['douyinPartitions']))}',
    if (_str(e['kind']) == 'group') 'isGroup: true',
  ];
  return '  CrossCategoryEntry(\n    ${parts.join(',\n    ')},\n  ),';
}

String _str(Object? value) => value?.toString().trim() ?? '';

/// `douyinPartitions` 既可能是 `['cid']` 也可能是 `[{cid: 'x'}]`。
List<String> _strList(Object? value) {
  if (value is! List) return const [];
  final out = <String>[];
  for (final item in value) {
    final text = item is Map ? _str(item['cid']) : _str(item);
    if (text.isNotEmpty && !out.contains(text)) out.add(text);
  }
  return out;
}

String _lit(String value) => "'${value.replaceAll(r'\', r'\\').replaceAll("'", r"\'").replaceAll(r'$', r'\$')}'";

String _litList(List<String> values) =>
    '[${values.map(_lit).join(', ')}]';

String _litMap(Map<String, List<String>> values) =>
    '{${values.entries.map((e) => '${_lit(e.key)}: ${_litList(e.value)}').join(', ')}}';

String _litMap2(Map<String, String> values) =>
    '{${values.entries.map((e) => '${_lit(e.key)}: ${_lit(e.value)}').join(', ')}}';
