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
library;

import 'dart:convert';
import 'dart:io';

const String _kSource = 'assets/config/cross-categories.json';
const String _kTarget = 'lib/src/shared/domain/cross_categories_data.dart';

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
  ]..sort((a, b) => (a['key'] ?? '').toString().compareTo((b['key'] ?? '').toString()));

  final buffer = StringBuffer()
    ..writeln('/// 跨平台分类映射表(由 `tool/sync_cross_map.dart` 从')
    ..writeln('/// `assets/config/cross-categories.json` 生成,**请勿手改**)。')
    ..writeln('///')
    ..writeln('/// 同步上游后可重跑脚本:`dart run tool/sync_cross_map.dart`。')
    ..writeln('library;')
    ..writeln()
    ..writeln('import \'cross_categories_data_models.dart\';')
    ..writeln()
    ..writeln('/// ${entries.length} 条跨平台分类映射(按 key 排序,保证生成结果稳定)。')
    ..writeln('const List<CrossCategoryEntry> kCrossCategories = [');
  for (final entry in entries) {
    buffer.writeln(_emitEntry(entry));
  }
  buffer.writeln('];');

  await File(_kTarget).writeAsString(buffer.toString());
  stdout.writeln('生成 ${entries.length} 条 → $_kTarget');
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
