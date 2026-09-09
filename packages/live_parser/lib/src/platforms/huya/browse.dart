/// 虎牙浏览:gameList 分类(HTML/兜底降级)+ getLiveList 分类房间列表。
library;

import 'dart:convert';

import '../../http/parser_http.dart';
import '../../utils/format_online.dart';
import '../../contracts/contracts.dart';
import '../../models/models.dart';
import '../douyu/json_utils.dart';
import 'promo_tag.dart';
import 'room_api.dart';

const Map<String, String> _huyaWebHeaders = {
  'Referer': 'https://www.huya.com/',
};

const String _huyaGamePic = 'https://huyaimg.msstatic.com/cdnimage/game/{cid}-MS.jpg';

/// bussType → 与虎牙官网分类 Tab 一致。
const List<({String id, String name, int bussType})> _huyaBussGroups = [
  (id: '1', name: '网游', bussType: 1),
  (id: '3', name: '手游', bussType: 3),
  (id: '8', name: '娱乐', bussType: 8),
  (id: '2', name: '单机', bussType: 2),
];

/// 拉取失败时的兜底热门分区。
const List<Map<String, dynamic>> _huyaFallbackGroups = [
  {
    'id': '1',
    'name': '热门',
    'list': [
      {'cid': 1, 'name': '英雄联盟'},
      {'cid': 862, 'name': 'CS2'},
      {'cid': 2336, 'name': '王者荣耀'},
      {'cid': 3203, 'name': '和平精英'},
      {'cid': 5937, 'name': '无畏契约'},
      {'cid': 5485, 'name': 'lol云顶之弈'},
      {'cid': 4, 'name': '穿越火线'},
      {'cid': 393, 'name': '炉石传说'},
      {'cid': 7, 'name': 'DOTA2'},
      {'cid': 2, 'name': '地下城与勇士'},
      {'cid': 802, 'name': '坦克世界'},
      {'cid': 1663, 'name': '星秀'},
      {'cid': 2135, 'name': '一起看'},
    ],
  },
];

String _huyaPic(Object? cid) => _huyaGamePic.replaceFirst('{cid}', '$cid');

class HuyaBrowseRepository implements BrowseRepository {
  HuyaBrowseRepository(this._http);

  final ParserHttp _http;
  List<CategoryGroup>? _categoryCache;

  @override
  Future<CategoryResult> fetchCategories(String site) async {
    final cached = _categoryCache;
    if (cached != null) {
      return CategoryResult(site: kHuyaSiteId, groups: cached);
    }

    var groups = <CategoryGroup>[];
    try {
      groups = await _categoriesFromApi();
    } on ParserHttpException {
      // 降级 HTML 页面解析。
    }
    if (groups.isEmpty) {
      try {
        groups = await _categoriesFromHtml();
      } on ParserHttpException {
        // 使用兜底列表。
      }
    }
    if (groups.isEmpty) {
      groups = _groupsFromMaps(_huyaFallbackGroups);
    }

    _categoryCache = groups;
    return CategoryResult(site: kHuyaSiteId, groups: groups);
  }

  @override
  Future<RoomListResult> fetchRooms(RoomListRequest request) async {
    final gid = (request.cid == null || request.cid!.isEmpty || request.cid == '0')
        ? '1'
        : request.cid!;
    final page = request.page;
    final response = await _http.get(
      Uri.parse(
        'https://live.huya.com/liveHttpUI/getLiveList?iGid=$gid&iPageNo=$page'
        '&iPageSize=${request.limit}',
      ),
      headers: _huyaWebHeaders,
    );
    final data = jsonMapOf(jsonDecode(utf8.decode(response.bodyBytes)));
    final items = jsonListOf(data['vList']);
    final totalPage = jsonInt(data['iTotalPage']);

    final rooms = <RoomSummary>[];
    for (final item in items.whereType<Map<String, dynamic>>()) {
      final room = _normalizeRoom(item);
      if (room.roomId.isNotEmpty) rooms.add(room);
    }
    return RoomListResult(rooms: rooms, page: page, hasMore: page < totalPage);
  }

  Future<List<CategoryGroup>> _categoriesFromApi() async {
    final response = await _http.get(
      Uri.parse('https://mp.huya.com/cache.php?m=Game&do=gameList&game_type=1'),
      headers: _huyaWebHeaders,
    );
    final payload = jsonMapOf(jsonDecode(utf8.decode(response.bodyBytes)));
    final games = jsonListOf(payload['data']).whereType<Map<String, dynamic>>().toList();
    if (jsonInt(payload['status']) != 200 || games.isEmpty) {
      throw const ParserHttpException('empty game list');
    }

    final buckets = <int, List<CategoryItem>>{};
    for (final game in games) {
      if (game['isHide'] != null && game['isHide'] != 0) continue;
      final cid = jsonInt(game['gid']);
      final name = jsonText(game['gameFullName']).trim();
      if (cid == 0 || name.isEmpty) continue;
      buckets.putIfAbsent(jsonInt(game['bussType']), () => []).add(
        CategoryItem(cid: '$cid', name: name, pic: _huyaPic(cid)),
      );
    }

    final groups = [
      for (final group in _huyaBussGroups)
        if ((buckets[group.bussType] ?? const <CategoryItem>[]).isNotEmpty)
          CategoryGroup(id: group.id, name: group.name, items: buckets[group.bussType]!),
    ];
    if (groups.isEmpty) {
      throw const ParserHttpException('no category groups');
    }
    return groups;
  }

  Future<List<CategoryGroup>> _categoriesFromHtml() async {
    final urls = {
      for (final group in _huyaBussGroups)
        group.id: group.bussType == 1
            ? 'https://www.huya.com/g_ol'
            : switch (group.bussType) {
                2 => 'https://www.huya.com/g_pc',
                3 => 'https://www.huya.com/g_sy',
                _ => 'https://www.huya.com/g_yl',
              },
    };
    final groups = <CategoryGroup>[];
    for (final entry in urls.entries) {
      final response = await _http.get(Uri.parse(entry.value), headers: _huyaWebHeaders);
      final html = utf8.decode(response.bodyBytes);
      final items = <CategoryItem>[];
      final regex = RegExp('data-gid="(\\d+)" title=([^>]+)');
      for (final match in regex.allMatches(html)) {
        final cid = match.group(1)!;
        final name = match.group(2)!.trim().replaceAll(RegExp('^"|"'), '');
        items.add(CategoryItem(cid: cid, name: name, pic: _huyaPic(cid)));
      }
      final name = _huyaBussGroups.firstWhere((g) => g.id == entry.key).name;
      if (items.isNotEmpty) {
        groups.add(CategoryGroup(id: entry.key, name: name, items: items));
      }
    }
    return groups;
  }

  List<CategoryGroup> _groupsFromMaps(List<Map<String, dynamic>> source) => [
    for (final group in source)
      CategoryGroup(
        id: jsonText(group['id']),
        name: jsonText(group['name']),
        items: [
          for (final item in jsonListOf(group['list']).whereType<Map<String, dynamic>>())
            CategoryItem(
              cid: jsonText(item['cid']),
              name: jsonText(item['name']),
              pic: _huyaPic(item['cid']),
            ),
        ],
      ),
  ];

  RoomSummary _normalizeRoom(Map<String, dynamic> item) {
    final roomId = jsonText(item['lProfileRoom'] ?? item['lChannel'] ?? item['lUid']);
    var cover = jsonText(item['sScreenshot'] ?? item['sPreviewUrl']);
    if (cover.startsWith('//')) cover = 'https:$cover';
    return RoomSummary(
      site: kHuyaSiteId,
      roomId: roomId,
      title: jsonText(item['sIntroduction'] ?? item['sRoomName']),
      anchorName: jsonText(item['sNick']),
      cid: jsonText(item['iGid'] ?? item['iGameId']),
      category: jsonText(item['sGameFullName']),
      online: formatOnlineCount(item['lTotalCount'] ?? item['lUserCount']),
      cover: cover,
      promoTag: pickHuyaPromoTag(item),
    );
  }
}
