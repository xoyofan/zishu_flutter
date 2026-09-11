/// 快手分类索引、分类房间与首页推荐。
library;

import '../../contracts/contracts.dart';
import '../../http/parser_http.dart';
import '../../models/models.dart';
import '../../utils/format_online.dart';
import '../douyu/json_utils.dart';
import 'normalize.dart';
import 'room_api.dart';

/// 一级分类(type 1-8),与 pure_live 对齐。
const List<({String id, String name})> kKuaishouTopCategories = [
  (id: '1', name: '热门'),
  (id: '2', name: '网游'),
  (id: '3', name: '单机'),
  (id: '4', name: '手游'),
  (id: '5', name: '棋牌'),
  (id: '6', name: '娱乐'),
  (id: '7', name: '综合'),
  (id: '8', name: '文化'),
];

/// 二级分类单页大小与最大翻页数(避免分类索引无限翻页)。
const int kKuaishouCategoryPageSize = 30;
const int kKuaishouCategoryMaxPages = 3;

class KuaishouBrowseRepository implements BrowseRepository {
  KuaishouBrowseRepository(this._http);

  final ParserHttp _http;
  List<CategoryGroup>? _categoryCache;

  @override
  Future<CategoryResult> fetchCategories(String site) async {
    final cached = _categoryCache;
    if (cached != null) return CategoryResult(site: kKuaishouSiteId, groups: cached);

    final groups = <CategoryGroup>[];
    for (final category in kKuaishouTopCategories) {
      final items = <CategoryItem>[];
      for (var page = 1; page <= kKuaishouCategoryMaxPages; page++) {
        final list = await _fetchCategoryList(category.id, page);
        for (final raw in list) {
          final item = jsonMapOf(raw);
          final cid = jsonText(item['id']);
          final name = jsonText(item['name']);
          if (cid.isEmpty || name.isEmpty) continue;
          items.add(
            CategoryItem(
              cid: cid,
              name: name,
              pic: httpsKuaishouUrl(item['poster']),
            ),
          );
        }
        if (list.length < kKuaishouCategoryPageSize) break;
      }
      if (items.isNotEmpty) {
        groups.add(CategoryGroup(id: category.id, name: category.name, items: items));
      }
    }
    _categoryCache = groups;
    return CategoryResult(site: kKuaishouSiteId, groups: groups);
  }

  @override
  Future<RoomListResult> fetchRooms(RoomListRequest request) async {
    final cid = request.cid;
    if (cid != null && cid.isNotEmpty && cid != '0') {
      return _fetchCategoryRooms(cid, request.page, request.limit);
    }
    return _fetchRecommend(request.page, request.limit);
  }

  Future<List<Object?>> _fetchCategoryList(String type, int page) async {
    final json = await _getJson(
      Uri.https('live.kuaishou.com', '/live_api/category/data', {
        'type': type,
        'page': '$page',
        'size': '$kKuaishouCategoryPageSize',
      }),
    );
    return jsonListOf(jsonMapOf(json['data'])['list']);
  }

  Future<RoomListResult> _fetchCategoryRooms(
    String cid,
    int page,
    int limit,
  ) async {
    // 快手按分类 id 长度区分游戏板/非游戏板接口(pure_live 同款判据)。
    final api = cid.length < 7 ? '/live_api/gameboard/list' : '/live_api/non-gameboard/list';
    final json = await _getJson(
      Uri.https('live.kuaishou.com', api, {
        'filterType': '0',
        'pageSize': '$limit',
        'gameId': cid,
        'page': '$page',
      }),
    );
    final list = jsonListOf(jsonMapOf(json['data'])['list']);
    final rooms = <RoomSummary>[];
    for (final raw in list) {
      final item = jsonMapOf(raw);
      final author = jsonMapOf(item['author']);
      final gameInfo = jsonMapOf(item['gameInfo']);
      final roomId = jsonText(author['id']).trim();
      if (roomId.isEmpty) continue;
      rooms.add(
        RoomSummary(
          site: kKuaishouSiteId,
          roomId: roomId,
          title: jsonText(item['caption']),
          anchorName: jsonText(author['name']),
          cid: cid,
          category: jsonText(gameInfo['name']),
          online: formatOnlineCount(item['watchingCount']),
          cover: kuaishouPosterUrl(item['poster']),
        ),
      );
      if (rooms.length >= limit) break;
    }
    return RoomListResult(rooms: rooms, page: page, hasMore: list.length >= limit);
  }

  Future<RoomListResult> _fetchRecommend(int page, int limit) async {
    // home/list 不翻页(上游无 page 参数),仅首页一次拉取。
    final json = await _getJson(
      Uri.https('live.kuaishou.com', '/live_api/home/list'),
    );
    final rooms = <RoomSummary>[];
    for (final raw in jsonListOf(jsonMapOf(json['data'])['list'])) {
      final group = jsonMapOf(raw);
      for (final rawGame in jsonListOf(group['gameLiveInfo'])) {
        final game = jsonMapOf(rawGame);
        for (final rawLive in jsonListOf(game['liveInfo'])) {
          final live = jsonMapOf(rawLive);
          final author = jsonMapOf(live['author']);
          final gameInfo = jsonMapOf(live['gameInfo']);
          final roomId = jsonText(author['id']).trim();
          if (roomId.isEmpty) continue;
          final description = jsonText(author['description']).replaceAll('\n', ' ');
          rooms.add(
            RoomSummary(
              site: kKuaishouSiteId,
              roomId: roomId,
              title: description,
              anchorName: jsonText(author['name']),
              cid: '',
              category: jsonText(gameInfo['name']),
              online: formatOnlineCount(live['watchingCount']),
              cover: kuaishouPosterUrl(gameInfo['poster']),
            ),
          );
          if (rooms.length >= limit) {
            return RoomListResult(rooms: rooms, page: page, hasMore: false);
          }
        }
      }
    }
    return RoomListResult(rooms: rooms, page: page, hasMore: false);
  }

  Future<Map<String, dynamic>> _getJson(Uri url) async {
    final response = await _http.get(url, headers: kuaishouHeaders());
    return _http.jsonMap(response);
  }
}
