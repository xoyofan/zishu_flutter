/// streaming-server browse/search 契约模型。
/// 字段对齐 `SFVideoLive/contracts/browse.schema.json`。
library;

/// 分类项（扁平 CategoryItem）。
class CategoryItem {
  final String cid;
  final String name;
  final String pic;
  final String pid;

  const CategoryItem({
    required this.cid,
    required this.name,
    this.pic = '',
    this.pid = '',
  });

  factory CategoryItem.fromJson(Map<String, dynamic> json) => CategoryItem(
    cid: json['cid']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    pic: json['pic']?.toString() ?? '',
    pid: json['pid']?.toString() ?? '',
  );
}

/// 分类分组（CategoryGroup：id + name + list）。
class CategoryGroup {
  final String id;
  final String name;
  final List<CategoryItem> list;

  const CategoryGroup({
    required this.id,
    required this.name,
    this.list = const [],
  });

  factory CategoryGroup.fromJson(Map<String, dynamic> json) => CategoryGroup(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    list: (json['list'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(CategoryItem.fromJson)
        .toList(),
  );
}

/// /api/categories 响应：categories 可能是新式 Group[]，也可能是旧式扁平 Item[]。
class CategoriesResponse {
  final bool ok;
  final String site;
  final List<CategoryGroup> groups;
  final String error;

  const CategoriesResponse({
    required this.ok,
    required this.site,
    this.groups = const [],
    this.error = '',
  });

  factory CategoriesResponse.fromJson(Map<String, dynamic> json) {
    final raw = json['categories'] as List<dynamic>? ?? [];
    final groups = <CategoryGroup>[];
    for (final entry in raw.whereType<Map<String, dynamic>>()) {
      if (entry.containsKey('list')) {
        groups.add(CategoryGroup.fromJson(entry));
      } else {
        // 旧扁平结构：整表合成一个默认分组
        groups.add(
          CategoryGroup(id: '', name: '', list: [CategoryItem.fromJson(entry)]),
        );
      }
    }
    return CategoriesResponse(
      ok: json['ok'] == true,
      site: json['site']?.toString() ?? '',
      groups: groups,
      error: json['error']?.toString() ?? '',
    );
  }
}

/// 列表房间项（BrowseRoomItem：room.schema 的浏览投影）。
class BrowseRoomItem {
  final String site;
  final String roomId;
  final String title;
  final String anchorName;
  final String cover;
  final String avatar;
  final String category;
  final Object? online;
  final bool isLive;
  final List<String> tags;

  const BrowseRoomItem({
    required this.site,
    required this.roomId,
    required this.title,
    this.anchorName = '',
    this.cover = '',
    this.avatar = '',
    this.category = '',
    this.online,
    this.isLive = true,
    this.tags = const [],
  });

  factory BrowseRoomItem.fromJson(Map<String, dynamic> json) => BrowseRoomItem(
    site: json['site']?.toString() ?? '',
    roomId: json['room_id']?.toString() ?? '',
    title: json['title']?.toString() ?? '',
    anchorName: json['anchor_name']?.toString() ?? '',
    cover: json['cover']?.toString() ?? '',
    avatar: json['avatar']?.toString() ?? '',
    category: json['category']?.toString() ?? '',
    online: json['online'],
    isLive: json['is_live'] != false,
    tags: (json['tags'] as List<dynamic>? ?? [])
        .map((e) => e?.toString() ?? '')
        .toList(),
  );
}

/// /api/rooms 响应。
class RoomsResponse {
  final bool ok;
  final String site;
  final List<BrowseRoomItem> list;
  final bool hasMore;
  final int page;
  final String error;

  const RoomsResponse({
    required this.ok,
    required this.site,
    this.list = const [],
    this.hasMore = false,
    this.page = 1,
    this.error = '',
  });

  factory RoomsResponse.fromJson(Map<String, dynamic> json) => RoomsResponse(
    ok: json['ok'] == true,
    site: json['site']?.toString() ?? '',
    list: (json['list'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(BrowseRoomItem.fromJson)
        .toList(),
    hasMore: json['has_more'] == true,
    page: (json['page'] as num?)?.toInt() ?? 1,
    error: json['error']?.toString() ?? '',
  );
}

/// /api/search 响应（rooms / anchors 两种结果，宽松解析）。
class SearchResponse {
  final bool ok;
  final List<BrowseRoomItem> rooms;
  final List<SearchAnchorItem> anchors;
  final String error;

  const SearchResponse({
    required this.ok,
    this.rooms = const [],
    this.anchors = const [],
    this.error = '',
  });

  factory SearchResponse.fromJson(Map<String, dynamic> json) {
    // 服务端可能返回 {rooms:[...]} / {anchors:[...]} / {results:{rooms,anchors}}
    final root = json['results'] is Map<String, dynamic>
        ? json['results'] as Map<String, dynamic>
        : json;
    return SearchResponse(
      ok: json['ok'] == true,
      rooms: (root['rooms'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(BrowseRoomItem.fromJson)
          .toList(),
      anchors: (root['anchors'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(SearchAnchorItem.fromJson)
          .toList(),
      error: json['error']?.toString() ?? '',
    );
  }
}

/// 搜索到的主播项。
class SearchAnchorItem {
  final String site;
  final String anchorId;
  final String name;
  final String avatar;
  final String roomId;
  final bool isLive;

  const SearchAnchorItem({
    required this.site,
    required this.anchorId,
    required this.name,
    this.avatar = '',
    this.roomId = '',
    this.isLive = false,
  });

  factory SearchAnchorItem.fromJson(Map<String, dynamic> json) =>
      SearchAnchorItem(
        site: json['site']?.toString() ?? '',
        anchorId: (json['anchor_id'] ?? json['id'])?.toString() ?? '',
        name:
            (json['name'] ?? json['nickname'] ?? json['anchor_name'])
                ?.toString() ??
            '',
        avatar: (json['avatar'] ?? json['avatar_url'])?.toString() ?? '',
        roomId: (json['room_id'] ?? json['roomId'])?.toString() ?? '',
        isLive: json['is_live'] == true || json['live_state'] == 'live',
      );
}
