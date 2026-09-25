/// 抖音分类索引、分类房间与首页推荐。
library;

import 'dart:convert';

import '../../contracts/contracts.dart';
import '../../models/models.dart';
import '../../models/room_record.dart';
import '../../registry/category_cache.dart';
import '../../utils/format_online.dart';
import '../douyu/json_utils.dart';
import 'normalize.dart';
import 'room_api.dart';

/// 分区列表单页条数(SFVideoLive 同款)。
const int kDouyinPageSize = 15;

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
  final Set<String> _feedSeenRoomIds = <String>{};

  @override
  Future<CategoryResult> fetchCategories(String site) async {
    final cached = _categoryCache;
    // 空壳分组(有分组无子项)按未命中处理,作废重拉(web e389570 同款校验)。
    if (hasRealCategoryGroups(cached)) {
      return CategoryResult(site: kDouyinSiteId, groups: cached!);
    }

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

    // 空壳分组不落缓存,避免上游异常响应霸占缓存(web e389570 同款语义)。
    // 注意「娱乐」组可能解析出空 items,只要主分组有子项缓存仍有效。
    if (hasRealCategoryGroups(groups)) _categoryCache = groups;
    return CategoryResult(site: kDouyinSiteId, groups: groups);
  }

  @override
  Future<RoomListResult> fetchRooms(RoomListRequest request) async {
    final cid = request.cid;
    if (cid == null || cid.isEmpty || cid == '0') {
      if (request.page <= 1) _feedSeenRoomIds.clear();
      final page = await _fetchDouyinFeedPage(
        _client,
        page: request.page,
        seenRoomIds: _feedSeenRoomIds,
      );
      return page.result;
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

/// 抖音首页推荐流。
///
/// Purelive 当前使用 `/webcast/feed/`，响应是 envelope 列表；旧版响应仍
/// 可能把房间放在 `data.data`。这里集中兼容两种形状，避免首页再次退化为
/// `partition=0` 的分类目录。
Future<RoomListResult> fetchDouyinRecommendRooms(DouyinClient client) async {
  final page = await _fetchDouyinFeedPage(
    client,
    page: 1,
    seenRoomIds: <String>{},
  );
  return page.result;
}

class DouyinFollowLiveResult {
  const DouyinFollowLiveResult({required this.rooms, required this.complete});

  final List<RoomRecord> rooms;

  /// 是否已经完整读取到 `extra.has_more == false`。
  final bool complete;
}

/// 批量读取当前登录账号关注且正在直播的房间。
///
/// 抖音网页使用 `/webcast/feed/follow_top/`；它不是逐房间 enter 查询，
/// 而是直接返回关注直播流。接口通过 follow_session_id/max_time 翻页。
Future<DouyinFollowLiveResult> fetchDouyinFollowLiveRooms(
  DouyinClient client,
) async {
  final rooms = <RoomRecord>[];
  final seenRoomIds = <String>{};
  var followSessionId = '0';
  var maxTime = '0';
  var complete = false;

  for (var page = 0; page < 200; page++) {
    final root = await signedDouyinGet(
      client,
      '/webcast/feed/follow_top/',
      <String, String>{
        'aid': '6383',
        'app_name': 'douyin_web',
        'live_id': '1',
        'device_platform': 'web',
        'language': 'zh-CN',
        'enter_from': 'link_share',
        'cookie_enabled': 'true',
        'screen_width': '1920',
        'screen_height': '1080',
        'browser_language': 'zh-CN',
        'browser_platform': 'Win32',
        'browser_name': 'Chrome',
        'browser_version': '141.0.0.0',
        'os_name': 'Windows',
        'os_version': '10',
        'enter_source': 'homepage_pc_followtop',
        'need_pinned_info': '0',
        'source_key': 'web_homepage_follow_top',
        'webcast_version_code': '170400',
        'version_code': '170400',
        'need_map': '1',
        'follow_session_id': followSessionId,
        'maxtime': maxTime,
        'msToken': randomDouyinMsToken(),
      },
    );
    if (jsonInt(root['status_code']) != 0) {
      throw StateError('抖音关注直播流获取失败');
    }

    final rawData = root['data'];
    final entries = rawData is Map
        ? jsonListOf(rawData['data'])
        : jsonListOf(rawData);
    for (final raw in entries) {
      final summary = _normalizeDouyinFeedRoom(raw);
      if (summary == null || !seenRoomIds.add(summary.roomId)) continue;
      rooms.add(RoomRecord.fromSummary(summary));
    }

    final extra = jsonMapOf(root['extra']);
    if (!jsonBool(extra['has_more'])) {
      complete = true;
      break;
    }
    final nextSessionId = jsonText(extra['follow_session_id']).trim();
    final nextMaxTime = jsonText(extra['max_time']).trim();
    if (nextSessionId.isEmpty || nextMaxTime.isEmpty) break;
    if (nextSessionId == followSessionId && nextMaxTime == maxTime) break;
    followSessionId = nextSessionId;
    maxTime = nextMaxTime;
  }

  return DouyinFollowLiveResult(
    rooms: List.unmodifiable(rooms),
    complete: complete,
  );
}

class _DouyinFeedPage {
  const _DouyinFeedPage({required this.result});

  final RoomListResult result;
}

Future<_DouyinFeedPage> _fetchDouyinFeedPage(
  DouyinClient client, {
  required int page,
  required Set<String> seenRoomIds,
}) async {
  final isFirstPage = page <= 1;
  final root = await signedDouyinGet(
    client,
    '/webcast/feed/',
    <String, String>{
      'aid': '6383',
      'app_name': 'douyin_web',
      'live_id': '1',
      'device_platform': 'web',
      'language': 'zh-CN',
      'enter_from': 'link_share',
      'cookie_enabled': 'true',
      'screen_width': '1920',
      'screen_height': '1080',
      'browser_language': 'zh-CN',
      'browser_platform': 'Win32',
      'browser_name': 'Chrome',
      'browser_version': '141.0.0.0',
      'os_name': 'Windows',
      'os_version': '10',
      'channel': 'channel_pc_web',
      'request_tag_from': 'web',
      'need_map': '1',
      'liveid': '1',
      'is_draw': '1',
      'inner_from_drawer': '0',
      'custom_count': isFirstPage ? '50' : '8',
      'action': 'load_more',
      'action_type': 'loadmore',
      'enter_source': 'web_homepage_hot_web_live_card',
      'source_key': 'web_homepage_hot_web_live_card',
      if (isFirstPage) ...<String, String>{
        'is_ssr': 'true',
        'maxtime': '0',
      },
    },
  );
  if (jsonInt(root['status_code']) != 0) {
    throw StateError('抖音首页推荐获取失败');
  }

  final rawData = root['data'];
  final entries = rawData is Map
      ? jsonListOf(rawData['data'])
      : jsonListOf(rawData);
  final rooms = <RoomSummary>[];
  for (final raw in entries) {
    final room = _normalizeDouyinFeedRoom(raw);
    if (room == null || !seenRoomIds.add(room.roomId)) continue;
    rooms.add(room);
  }
  final extra = jsonMapOf(root['extra']);
  return _DouyinFeedPage(
    result: RoomListResult(
      rooms: rooms.map(RoomRecord.fromSummary).toList(growable: false),
      page: page,
      hasMore: jsonBool(extra['has_more']),
    ),
  );
}

Map<String, dynamic> _decodeDouyinEmbeddedMap(Object? value) {
  final direct = jsonMapOf(value);
  if (direct.isNotEmpty) return direct;
  final text = jsonText(value).trim();
  if (!text.startsWith('{')) return const {};
  try {
    final decoded = jsonDecode(text);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : const {};
  } on FormatException {
    return const {};
  }
}

bool _looksLikeDouyinFeedRoom(Map<String, dynamic> value) =>
    value['owner'] is Map ||
    value['title'] != null ||
    value['id_str'] != null ||
    value['stream_url'] is Map;

String _douyinFeedImage(Object? value) {
  final list = jsonListOf(jsonMapOf(value)['url_list']);
  return list.isEmpty ? '' : httpsDouyinUrl(list.first);
}

String _douyinFeedCategory(
  Map<String, dynamic> envelope,
  Map<String, dynamic> room,
) {
  final direct = _firstNonEmpty([
    jsonText(room['tag_name']),
    jsonText(envelope['tag_name']),
  ]);
  if (direct.isNotEmpty) return direct;
  for (final source in [room['partition_road_map'], envelope['tags']]) {
    for (final rawTag in jsonListOf(source)) {
      final tag = jsonMapOf(rawTag);
      final text = _firstNonEmpty([
        jsonText(tag['title']),
        jsonText(tag['name']),
        jsonText(tag['tag_name']),
      ]);
      if (text.isNotEmpty) return text;
    }
  }
  return '热门推荐';
}

RoomSummary? _normalizeDouyinFeedRoom(Object? raw) {
  final envelope = jsonMapOf(raw);
  final embedded = _decodeDouyinEmbeddedMap(envelope['data']);
  final candidates = <Map<String, dynamic>>[
    embedded,
    jsonMapOf(envelope['room']),
    envelope,
  ];
  final room = candidates.firstWhere(
    _looksLikeDouyinFeedRoom,
    orElse: () => const <String, dynamic>{},
  );
  if (room.isEmpty) return null;

  final owner = room['owner'] is Map
      ? jsonMapOf(room['owner'])
      : jsonMapOf(envelope['owner']);
  final roomId = _firstNonEmpty([
    jsonText(envelope['web_rid']),
    jsonText(owner['web_rid']),
    jsonText(room['web_rid']),
    jsonText(room['id_str']),
    jsonText(room['id']),
  ]);
  if (roomId.isEmpty) return null;

  final nickname = _firstNonEmpty([
    jsonText(owner['nickname']),
    jsonText(envelope['nickname']),
  ]);
  final title = _firstNonEmpty([
    jsonText(room['title']),
    jsonText(envelope['title']),
    nickname,
  ]);
  final cover = _douyinFeedImage(room['cover']);
  final avatar = _firstNonEmpty([
    _douyinFeedImage(owner['avatar_thumb']),
    _douyinFeedImage(owner['avatar_large']),
    _douyinFeedImage(envelope['avatar_thumb']),
  ]);
  return RoomSummary(
    site: kDouyinSiteId,
    roomId: roomId,
    title: title,
    anchorName: nickname,
    cid: '',
    category: _douyinFeedCategory(envelope, room),
    online: formatOnlineCount(douyinOnlineRaw(room)),
    cover: cover.isEmpty ? _douyinFeedImage(envelope['cover']) : cover,
    avatar: avatar,
    roomState: RoomState.live,
  );
}

/// 分区房间列表(分类专用)。
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

  final json = await signedDouyinGet(
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
    rooms: rooms.map(RoomRecord.fromSummary).toList(growable: false),
    page: page,
    hasMore: jsonBool(wrapper['has_more']) || entries.length >= effectiveLimit,
  );
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
    // 直播分区目录 live-only:状态真源(6sol 裁决 Task 4a-i)。
    roomState: RoomState.live,
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
