/// Twitch 浏览:games 分类索引 + streams 首页/分类房间列表。
library;

import '../../catalog/category_name_remap.dart';
import '../../contracts/contracts.dart';
import '../../models/models.dart';
import '../../registry/category_cache.dart';
import '../../utils/format_online.dart';
import 'gql.dart';
import 'normalize.dart';

/// 首页与分类房间共用的流节点查询片段。
const String _twitchStreamNodeFragment = r'''
id
title
viewersCount
type
broadcaster { id login displayName profileImageURL(width: 300) }
game { id name }
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
      variables: {'limit': 40},
      query: r'''
query BrowsePage_AllDirectories($limit: Int) {
  games(first: $limit) {
    edges { node { id name displayName viewersCount boxArtURL } }
  }
}''',
    );

    final items = [
      for (final node in _nodesOf((data as Map?)?['games']))
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

    final groups = [if (items.isNotEmpty) CategoryGroup(id: 'games', name: '分类', items: items)];
    // 空壳分组不落缓存,避免上游异常响应霸占缓存(web e389570 同款语义)。
    if (hasRealCategoryGroups(groups)) _categoryCache = groups;
    return CategoryResult(site: kTwitchSiteId, groups: groups);
  }

  @override
  Future<RoomListResult> fetchRooms(RoomListRequest request) async {
    final cid = request.cid;
    if (cid != null && cid.isNotEmpty && cid != '0') {
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
      rooms: _roomsOf(nodes),
      page: page,
      // GQL 首页按热度返回,没有稳定分页游标;单页结果即一屏。
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
      rooms: _roomsOf(nodes),
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
      ),
  ]..removeWhere((room) => room.roomId.isEmpty);
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
