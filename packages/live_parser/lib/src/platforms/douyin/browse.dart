/// 抖音分类索引、分类房间与首页推荐。
library;

import 'dart:convert';

import '../../contracts/contracts.dart';
import '../../models/models.dart';
import '../../utils/format_online.dart';
import '../douyu/json_utils.dart';
import 'ab_sign.dart';
import 'normalize.dart';
import 'room_api.dart';

/// 分区列表单页条数(SFVideoLive 同款)。
const int kDouyinPageSize = 15;

const String _kRecommendPartition = '0';
const String _kDefaultGamePartition = '1010045';
const String _kDefaultPartitionType = '1';
const String _kEntertainmentPartitionType = '4';
const String _kEntertainmentGroupId = 'yule';

const List<String> _kEntertainmentTabOrder = [
  '聊天',
  '音乐',
  '二次元',
  '舞蹈',
  '文化',
  '生活',
  '运动',
];

const String _kGameTreeMarker = '\\"title\\":\\"游戏\\"},\\"sub_partition\\":';

final RegExp _kEntertainmentTabRe = RegExp(
  r'\\"id_str\\":\\"(\d+)\\",\\"type\\":4,\\"title\\":\\"([^"\\]+)\\"',
);

const List<({String cid, String name})> _kFallbackEntertainmentTabs = [
  (cid: '101', name: '聊天'),
  (cid: '102', name: '音乐'),
  (cid: '104', name: '二次元'),
  (cid: '105', name: '舞蹈'),
  (cid: '106', name: '文化'),
  (cid: '107', name: '生活'),
  (cid: '108', name: '运动'),
];

const List<({String id, String name, List<({String cid, String name})> items})>
_kFallbackGameGroups = [
  (
    id: '1',
    name: '射击游戏',
    items: [
      (cid: '1010032', name: '和平精英'),
      (cid: '1010017', name: '无畏契约'),
      (cid: '1010003', name: 'CSGO'),
      (cid: '1011032', name: '三角洲行动'),
      (cid: '1010037', name: '穿越火线'),
      (cid: '1010026', name: '绝地求生'),
    ],
  ),
  (
    id: '2',
    name: '竞技游戏',
    items: [
      (cid: '1010045', name: '王者荣耀'),
      (cid: '1010014', name: '英雄联盟'),
      (cid: '1010016', name: '永劫无间'),
      (cid: '1010041', name: '第五人格'),
      (cid: '1010055', name: '金铲铲之战'),
    ],
  ),
  (
    id: '3',
    name: '单机游戏',
    items: [
      (cid: '1010358', name: '黑神话：悟空'),
      (cid: '1010250', name: '星际战甲'),
    ],
  ),
  (
    id: '4',
    name: '角色扮演',
    items: [
      (cid: '1010039', name: '原神'),
      (cid: '1010053', name: '梦幻西游'),
      (cid: '1010150', name: '魔兽世界'),
    ],
  ),
];

class DouyinBrowseRepository implements BrowseRepository {
  DouyinBrowseRepository(this._client);

  final DouyinClient _client;
  List<CategoryGroup>? _categoryCache;

  @override
  Future<CategoryResult> fetchCategories(String site) async {
    final cached = _categoryCache;
    if (cached != null) return CategoryResult(site: kDouyinSiteId, groups: cached);

    String html = '';
    try {
      final response = await _client.parserHttp.get(
        Uri.parse('https://live.douyin.com/'),
        headers: douyinPcHeaders(),
      );
      html = utf8.decode(response.bodyBytes);
    } on Object {
      // 首页不可用时使用静态兜底分组。
    }

    var groups = _parseGameTreeFromHtml(html);
    if (groups.isEmpty) groups = _parseGameCategoriesLegacy(html);
    if (groups.isEmpty) {
      groups = [
        for (final group in _kFallbackGameGroups)
          CategoryGroup(
            id: group.id,
            name: group.name,
            items: [
              for (final item in group.items)
                CategoryItem(cid: item.cid, name: item.name, pic: ''),
            ],
          ),
      ];
    }
    groups = [
      ...groups,
      CategoryGroup(
        id: _kEntertainmentGroupId,
        name: '娱乐',
        items: _parseEntertainmentTabs(html),
      ),
    ];

    _categoryCache = groups;
    return CategoryResult(site: kDouyinSiteId, groups: groups);
  }

  @override
  Future<RoomListResult> fetchRooms(RoomListRequest request) async {
    final cid = request.cid;
    if (cid == null || cid.isEmpty || cid == '0') {
      try {
        return await fetchDouyinPartitionRooms(
          _client,
          partition: _kRecommendPartition,
          page: request.page,
          limit: request.limit,
          partitionName: '推荐',
        );
      } on Object {
        return fetchDouyinPartitionRooms(
          _client,
          partition: _kDefaultGamePartition,
          page: request.page,
          limit: request.limit,
          partitionName: '王者荣耀',
        );
      }
    }
    return fetchDouyinPartitionRooms(
      _client,
      partition: cid,
      page: request.page,
      limit: request.limit,
      partitionName: _cachedCategoryName(cid),
    );
  }

  /// 分类页房间 chip:从已缓存的分类树反查分区名。
  ///
  /// 只读缓存不触发网络 —— UI 流程必然先加载分类页;未命中时 chip 留空,
  /// 与 web `roomCategoryLabel` 对未知 cid 的空值口径一致。列表接口
  /// (`partition/detail/room/v2`)响应不带分区数据,只能靠请求侧补名。
  String _cachedCategoryName(String cid) {
    for (final group in _categoryCache ?? const <CategoryGroup>[]) {
      for (final item in group.items) {
        if (item.cid == cid) return item.name;
      }
    }
    return '';
  }

  List<CategoryItem> _parseEntertainmentTabs(String html) {
    final byName = <String, CategoryItem>{};
    for (final match in _kEntertainmentTabRe.allMatches(html)) {
      final name = match.group(2) ?? '';
      if (!_kEntertainmentTabOrder.contains(name) || byName.containsKey(name)) {
        continue;
      }
      final cid = match.group(1) ?? '';
      if (cid.isEmpty) continue;
      byName[name] = CategoryItem(cid: cid, name: name, pic: '');
    }
    final items = <CategoryItem>[
      for (final name in _kEntertainmentTabOrder)
        if (byName[name] != null) byName[name]!,
    ];
    if (items.isNotEmpty) return items;
    return [
      for (final item in _kFallbackEntertainmentTabs)
        CategoryItem(cid: item.cid, name: item.name, pic: ''),
    ];
  }

  List<CategoryGroup> _parseGameTreeFromHtml(String html) {
    final markerIndex = html.indexOf(_kGameTreeMarker);
    if (markerIndex < 0) return const [];
    final arrayStart = markerIndex + _kGameTreeMarker.length;
    final rawArray = _extractBalancedArray(html, arrayStart);
    if (rawArray.isEmpty) return const [];
    try {
      final decoded = jsonDecode(_unescapeEmbeddedJson(rawArray));
      if (decoded is! List) return const [];
      final groups = <CategoryGroup>[];
      for (final rawNode in decoded) {
        final node = jsonMapOf(rawNode);
        final groupPart = jsonMapOf(node['partition']);
        final groupId = jsonText(groupPart['id_str']).trim();
        if (groupId.isEmpty) continue;
        final seen = <String>{};
        final items = <CategoryItem>[];
        for (final rawChild in jsonListOf(node['sub_partition'])) {
          final part = jsonMapOf(jsonMapOf(rawChild)['partition']);
          final id = jsonText(part['id_str']).trim();
          if (id.isEmpty || !seen.add(id)) continue;
          items.add(CategoryItem(cid: id, name: jsonText(part['title']), pic: ''));
        }
        if (items.isNotEmpty) {
          groups.add(
            CategoryGroup(
              id: groupId,
              name: jsonText(groupPart['title']).isEmpty
                  ? '游戏'
                  : jsonText(groupPart['title']),
              items: items,
            ),
          );
        }
      }
      return groups;
    } on FormatException {
      return const [];
    }
  }

  /// legacy 兜底:从带 parent 关系的 partition 三元组中提取游戏分组。
  List<CategoryGroup> _parseGameCategoriesLegacy(String html) {
    final regex = RegExp(
      r'\{\\"partition\\":\{\\"id_str\\":\\"(\d+)\\",\\"type\\":(\d+),'
      r'\\"title\\":\\"([^"\\]+)\\"\},\\"has_parent_node\\":true,'
      r'\\"second_node\\":\{\\"id_str\\":\\"(\d+)\\",\\"type\\":(\d+),'
      r'\\"title\\":\\"([^"\\]+)\\"\},\\"first_node\\":\{\\"id_str\\":\\"(\d+)\\",'
      r'\\"type\\":(\d+),\\"title\\":\\"([^"\\]+)\\"\}',
    );
    final grouped = <String, List<CategoryItem>>{};
    final groupNames = <String, String>{};
    final seen = <String>{};
    for (final match in regex.allMatches(html)) {
      if ((match.group(9) ?? '') != '游戏') continue;
      final id = match.group(1) ?? '';
      if (id.isEmpty || !seen.add(id)) continue;
      final groupId = match.group(4) ?? '';
      grouped.putIfAbsent(groupId, () => []).add(
        CategoryItem(cid: id, name: match.group(3) ?? '', pic: ''),
      );
      groupNames[groupId] = match.group(6) ?? '';
    }
    return [
      for (final entry in grouped.entries)
        CategoryGroup(
          id: entry.key,
          name: groupNames[entry.key] ?? '',
          items: entry.value,
        ),
    ];
  }
}

/// 分区房间列表(推荐与分类共用同一接口)。
Future<RoomListResult> fetchDouyinPartitionRooms(
  DouyinClient client, {
  required String partition,
  required int page,
  required int limit,
  String partitionName = '',
}) async {
  final effectivePartition = partition.trim().isEmpty
      ? _kDefaultGamePartition
      : partition.trim();
  final effectiveLimit = limit.clamp(1, 60);
  final partitionType = _resolvePartitionType(effectivePartition);
  final offset = (page < 1 ? 0 : page - 1) * effectiveLimit;

  final json = await _signedGet(
    client,
    '/webcast/web/partition/detail/room/v2/',
    <String, String>{
      'aid': '6383',
      'app_name': 'douyin_web',
      'live_id': '1',
      'device_platform': 'web',
      'language': 'zh-CN',
      'enter_from': 'web_homepage_hot',
      'cookie_enabled': 'true',
      'screen_width': '1920',
      'screen_height': '1080',
      'browser_language': 'zh-CN',
      'browser_platform': 'Win32',
      'browser_name': 'Chrome',
      'browser_version': '141.0.0.0',
      'count': '$effectiveLimit',
      'offset': '$offset',
      'partition': effectivePartition,
      'partition_type': partitionType,
      'req_from': '2',
      'msToken': '',
    },
  );
  if (jsonInt(json['status_code']) != 0) {
    throw StateError('抖音游戏直播列表获取失败');
  }
  final wrapper = jsonMapOf(json['data']);
  final entries = jsonListOf(wrapper['data']);
  final rooms = <RoomSummary>[];
  for (final raw in entries) {
    final room = _normalizePartitionRoom(
      jsonMapOf(raw),
      effectivePartition,
      partitionName,
    );
    if (room != null) rooms.add(room);
  }
  return RoomListResult(
    rooms: rooms,
    page: page,
    hasMore: jsonBool(wrapper['has_more']) || entries.length >= effectiveLimit,
  );
}

Future<Map<String, dynamic>> _signedGet(
  DouyinClient client,
  String path,
  Map<String, String> params,
) async {
  Object? lastError;
  for (var attempt = 0; attempt < 2; attempt++) {
    final cookie = await client.sessionCookie(force: attempt > 0);
    final query = serializeDouyinQuery(
      params.entries.map((entry) => MapEntry(entry.key, entry.value)).toList(),
    );
    final abogus = douyinAbSign(query, kDouyinUserAgent);
    final uri = Uri.parse(
      'https://live.douyin.com$path?$query&a_bogus=${Uri.encodeComponent(abogus)}',
    );
    try {
      final response = await client.parserHttp.get(
        uri,
        headers: douyinPcHeaders(cookie: cookie),
      );
      final text = utf8.decode(response.bodyBytes);
      if (text.trim().isEmpty || text.trim().startsWith('<!DOCTYPE')) {
        lastError = const FormatException('抖音列表接口触发风控');
        continue;
      }
      final decoded = jsonDecode(text);
      if (decoded is! Map) {
        throw const FormatException('抖音列表接口返回非对象 JSON');
      }
      return Map<String, dynamic>.from(decoded);
    } on Object catch (error) {
      lastError = error;
      if (attempt == 0) continue;
    }
  }
  throw StateError(lastError?.toString() ?? '抖音列表接口触发风控');
}

String _resolvePartitionType(String cid) {
  final numeric = int.tryParse(cid);
  if (numeric != null && numeric >= 100 && numeric <= 199) {
    return _kEntertainmentPartitionType;
  }
  return _kDefaultPartitionType;
}

RoomSummary? _normalizePartitionRoom(
  Map<String, dynamic> entry,
  String partitionId,
  String partitionName,
) {
  final room = jsonMapOf(entry['room']);
  var webRid = jsonText(entry['web_rid']).trim();
  if (webRid.isEmpty) webRid = jsonText(room['id_str']).trim();
  if (webRid.isEmpty || room.isEmpty) return null;

  final owner = jsonMapOf(room['owner']);
  final nickname = _firstNonEmpty([
    jsonText(room['anchor_name']),
    jsonText(owner['nickname']),
    jsonText(owner['nick_name']),
  ]);
  final title = _firstNonEmpty([jsonText(room['title']), nickname]);
  final coverList = jsonListOf(jsonMapOf(room['cover'])['url_list']);
  return RoomSummary(
    site: kDouyinSiteId,
    roomId: webRid,
    title: title,
    anchorName: nickname,
    cid: partitionId,
    category: partitionName,
    online: formatOnlineCount(douyinOnlineRaw(room)),
    cover: coverList.isEmpty ? '' : httpsDouyinUrl(coverList.first),
  );
}

String _firstNonEmpty(List<String> values) {
  for (final value in values) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty) return trimmed;
  }
  return '';
}

String _extractBalancedArray(String text, int start) {
  var depth = 0;
  for (var i = start; i < text.length; i++) {
    final ch = text[i];
    if (ch == '[') {
      depth += 1;
    } else if (ch == ']') {
      depth -= 1;
      if (depth == 0) return text.substring(start, i + 1);
    }
  }
  return '';
}

String _unescapeEmbeddedJson(String text) =>
    text.replaceAll(r'\"', '"').replaceAll(r'\\', r'\');
