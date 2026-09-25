/// Twitch 浏览:games 分类索引(+标签组) + streams 首页/分类/标签房间列表。
library;

import 'dart:convert';

import '../../catalog/category_name_remap.dart';
import '../../contracts/contracts.dart';
import '../../models/models.dart';
import '../../models/room_record.dart';
import '../../registry/category_cache.dart';
import '../../utils/format_online.dart';
import 'gql.dart';
import 'normalize.dart';

/// 首页与分类房间共用的流节点查询片段。
///
/// `broadcastLanguage` 与 `game.tags` 供卡片 chip 用(见 [_chipsOf])。
const String _twitchStreamNodeFragment = r'''
id
title
viewersCount
type
broadcastLanguage
broadcaster { id login displayName profileImageURL(width: 300) }
game {
  id
  name
  tags(tagType: CONTENT) { ... on Tag { id localizedName } }
}
previewImageURL
''';

class TwitchBrowseRepository implements BrowseRepository {
  TwitchBrowseRepository(this._gql);

  final TwitchGqlClient _gql;

  List<CategoryGroup>? _categoryCache;

  @override
  Future<CategoryResult> fetchCategories(String site) async {
    final cached = _categoryCache;
    // 空壳分组(有分组无子项)按未命中处理,作废重拉(web e389570 同款校验)。
    if (hasRealCategoryGroups(cached)) {
      return CategoryResult(site: kTwitchSiteId, groups: cached!);
    }

    final data = await _gql.query(
      operationName: 'BrowsePage_AllDirectories',
      // games(first:) GQL 硬上限 100(实测 200 被上游拒绝)。
      variables: {'limit': 100},
      query: r'''
query BrowsePage_AllDirectories($limit: Int) {
  games(first: $limit) {
    edges { node {
      id name displayName viewersCount boxArtURL
      tags(tagType: CONTENT) { ... on Tag { id localizedName } }
    } }
  }
}''',
    );

    final nodes = _nodesOf((data as Map?)?['games']);
    final items = [
      for (final node in nodes)
        CategoryItem(
          cid: _text(node['id']),
          // 分类名:优先中文 displayName(带 Accept-Language 后上游直出),
          // 再经 web 真源归一组兜底(Just Chatting→聊天 等)。
          name: remapCategoryName(
            'twitch',
            _text(node['displayName']).isNotEmpty
                ? _text(node['displayName'])
                : _text(node['name']),
          ),
          pic: fillTwitchImageTemplate(
            _text(node['boxArtURL']),
            width: 285,
            height: 380,
          ),
        ),
    ]..removeWhere((item) => item.cid.isEmpty || item.name.isEmpty);

    final tagItems = _tagItemsOf(nodes);
    final groups = [
      if (items.isNotEmpty) CategoryGroup(id: 'games', name: '分类', items: items),
      if (tagItems.isNotEmpty) CategoryGroup(id: 'tags', name: '标签', items: tagItems),
    ];
    // 空壳分组不落缓存,避免上游异常响应霸占缓存(web e389570 同款语义)。
    if (hasRealCategoryGroups(groups)) _categoryCache = groups;
    return CategoryResult(site: kTwitchSiteId, groups: groups);
  }

  /// 聚合所有游戏的 tags:按 id 去重、`localizedName` 为展示名,
  /// 按出现游戏数降序、同数按名称稳定排序;空 id/空名不产出。
  ///
  /// items 的 cid 带 `tag:` 前缀与游戏 id 区分;可点语义由前缀分流
  /// (见 [fetchRooms]),chips 字段无需填。
  List<CategoryItem> _tagItemsOf(List<Map<String, dynamic>> gameNodes) {
    final names = <String, String>{};
    final counts = <String, int>{};
    for (final node in gameNodes) {
      final tags = node['tags'];
      if (tags is! List) continue;
      for (final raw in tags) {
        final tag = _mapOf(raw);
        final id = _text(tag?['id']);
        final name = _text(tag?['localizedName']);
        if (id.isEmpty || name.isEmpty) continue;
        names.putIfAbsent(id, () => name);
        counts[id] = (counts[id] ?? 0) + 1;
      }
    }
    final ids = counts.keys.toList()
      ..sort((a, b) {
        final byCount = counts[b]!.compareTo(counts[a]!);
        // 同数按名称稳定排序(Dart sort 不稳定,名称相同时再按 id 钉住)。
        return byCount != 0
            ? byCount
            : (names[a]!.compareTo(names[b]!) != 0
                  ? names[a]!.compareTo(names[b]!)
                  : a.compareTo(b));
      });
    return [
      for (final id in ids)
        CategoryItem(cid: 'tag:$id', name: names[id]!, pic: ''),
    ];
  }

  @override
  Future<RoomListResult> fetchRooms(RoomListRequest request) async {
    final cid = request.cid;
    if (cid != null && cid.isNotEmpty && cid != '0') {
      if (cid.startsWith('tag:')) {
        final tagId = cid.substring('tag:'.length);
        if (tagId.isEmpty) {
          throw const TwitchGqlException('标签 id 为空');
        }
        return _fetchTagRooms(tagId: tagId, page: request.page, limit: request.limit);
      }
      return _fetchGameRooms(cid: cid, page: request.page, limit: request.limit);
    }
    return _fetchHomeRooms(page: request.page, limit: request.limit);
  }

  Future<RoomListResult> _fetchHomeRooms({required int page, required int limit}) async {
    final data = await _gql.query(
      operationName: 'BrowsePage_Popular',
      variables: {'limit': limit},
      query: '''
query BrowsePage_Popular(\$limit: Int) {
  streams(first: \$limit) {
    edges { node { $_twitchStreamNodeFragment } }
  }
}''',
    );
    final nodes = _nodesOf((data as Map?)?['streams']);
    return RoomListResult(
      rooms: _roomsOf(nodes).map(RoomRecord.fromSummary).toList(growable: false),
      page: page,
      // GQL 首页按热度返回,没有稳定分页游标;单页结果即一屏。
      hasMore: page <= 1 && nodes.length >= limit,
    );
  }

  /// 按标签过滤的房间列表(`streams(tags:)`,实测支持)。
  ///
  /// tag id 内联为 JSON 字符串字面量(经 [jsonEncode] 转义);上游无
  /// 稳定分页游标,口径同 [_fetchHomeRooms]。
  Future<RoomListResult> _fetchTagRooms({
    required String tagId,
    required int page,
    required int limit,
  }) async {
    final data = await _gql.query(
      operationName: 'BrowsePage_Tags',
      variables: {'limit': limit},
      query: '''
query BrowsePage_Tags(\$limit: Int) {
  streams(first: \$limit, tags: [${jsonEncode(tagId)}]) {
    edges { node { $_twitchStreamNodeFragment } }
  }
}''',
    );
    final nodes = _nodesOf((data as Map?)?['streams']);
    return RoomListResult(
      rooms: _roomsOf(nodes).map(RoomRecord.fromSummary).toList(growable: false),
      page: page,
      hasMore: page <= 1 && nodes.length >= limit,
    );
  }

  Future<RoomListResult> _fetchGameRooms({
    required String cid,
    required int page,
    required int limit,
  }) async {
    final data = await _gql.query(
      operationName: 'DirectoryPage_Game',
      variables: {'id': cid, 'limit': limit},
      query: '''
query DirectoryPage_Game(\$id: ID!, \$limit: Int) {
  game(id: \$id) {
    id
    name
    streams(first: \$limit) {
      edges { node { $_twitchStreamNodeFragment } }
    }
  }
}''',
    );
    final game = _mapOf((data as Map?)?['game']);
    if (game == null) {
      throw const TwitchGqlException('分类不存在');
    }
    final nodes = _nodesOf(game['streams']);
    return RoomListResult(
      rooms: _roomsOf(nodes).map(RoomRecord.fromSummary).toList(growable: false),
      page: page,
      hasMore: page <= 1 && nodes.length >= limit,
    );
  }

  List<RoomSummary> _roomsOf(List<Map<String, dynamic>> nodes) => [
    for (final node in nodes)
      RoomSummary(
        site: kTwitchSiteId,
        roomId: _text(_mapOf(node['broadcaster'])?['login']),
        title: _text(node['title']),
        anchorName: _text(_mapOf(node['broadcaster'])?['displayName']),
        cid: _text(_mapOf(node['game'])?['id']),
        category: remapCategoryName('twitch', _text(_mapOf(node['game'])?['name'])),
        online: formatOnlineCount(node['viewersCount']),
        cover: fillTwitchImageTemplate(_text(node['previewImageURL'])),
        // streams 连接 live-only:状态真源(6sol 裁决 Task 4a-i)。
        roomState: RoomState.live,
        chips: _chipsOf(node),
      ),
  ]..removeWhere((room) => room.roomId.isEmpty);

  /// 卡片 chips:游戏 tags(可点,filterCid=tag id) + broadcastLanguage
  /// (仅展示不可点——`streams(broadcastLanguage:)` 过滤不支持)。
  List<SiteChip> _chipsOf(Map<String, dynamic> node) {
    final chips = <SiteChip>[];
    final gameTags = _mapOf(node['game'])?['tags'];
    if (gameTags is List) {
      for (final raw in gameTags) {
        final tag = _mapOf(raw);
        final id = _text(tag?['id']);
        final name = _text(tag?['localizedName']);
        if (id.isEmpty || name.isEmpty) continue;
        // filterCid 必须是可直接传给 fetchRooms 的 cid：标签分支以
        // `tag:` 前缀分流（见 fetchRooms），UI 不应知道平台前缀规则。
        chips.add(
          SiteChip(
            id: id,
            name: name,
            kind: SiteChipKind.tag,
            filterCid: 'tag:$id',
          ),
        );
      }
    }
    final language = _text(node['broadcastLanguage']);
    if (language.isNotEmpty) {
      chips.add(
        SiteChip(
          id: language,
          name: twitchLanguageName(language),
          kind: SiteChipKind.language,
        ),
      );
    }
    return chips;
  }
}

List<Map<String, dynamic>> _nodesOf(Object? connection) {
  final edges = _mapOf(connection)?['edges'];
  if (edges is! List) return const [];
  return [for (final edge in edges) ?_mapOf(_mapOf(edge)?['node'])];
}

Map<String, dynamic>? _mapOf(Object? value) => value is Map<String, dynamic>
    ? value
    : (value is Map ? Map<String, dynamic>.from(value) : null);

String _text(Object? value) => value?.toString() ?? '';
