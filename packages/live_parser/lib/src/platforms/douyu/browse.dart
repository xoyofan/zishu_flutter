/// 斗鱼浏览:m.douyu.com 分类索引 + gapi/rkc/directory/mixList 首页与分类列表。
library;

import 'dart:convert';

import '../../http/parser_http.dart';
import '../../utils/format_online.dart';
import '../../contracts/contracts.dart';
import '../../models/models.dart';
import '../../models/room_record.dart';
import 'json_utils.dart';
import 'promo_tag.dart';
import 'room_api.dart';

const String kDouyuSiteId = 'douyu';

const Map<String, String> _douyuWebHeaders = {
  'Referer': 'https://www.douyu.com/',
};

class DouyuBrowseRepository implements BrowseRepository {
  DouyuBrowseRepository(this._http);

  final ParserHttp _http;

  /// cate2Id -> 展示名缓存,供列表回退分支补分类名。
  Map<String, String>? _cate2Names;

  @override
  Future<CategoryResult> fetchCategories(String site) async {
    final payload = (await _getJson(Uri.parse('https://m.douyu.com/api/cate/list')))['data'];
    final data = jsonMapOf(payload);

    final cate1Names = <String, String>{
      for (final item in jsonListOf(data['cate1Info']).whereType<Map<String, dynamic>>())
        jsonText(item['cate1Id']): jsonText(item['cate1Name']),
    };

    final grouped = <String, CategoryGroup>{};
    final nameIndex = <String, String>{};
    for (final item in jsonListOf(data['cate2Info']).whereType<Map<String, dynamic>>()) {
      final cate1Id = jsonText(item['cate1Id']);
      final cate2Id = jsonText(item['cate2Id']);
      final name = jsonText(item['cate2Name']);
      final group = grouped.putIfAbsent(
        cate1Id,
        () => CategoryGroup(
          id: cate1Id,
          name: cate1Names[cate1Id] ?? '分类',
          items: [],
        ),
      );
      group.items.add(
        CategoryItem(
          cid: cate2Id,
          name: name,
          pic: httpsUrl(jsonText(item['pic'] ?? item['icon'])),
        ),
      );
      nameIndex[cate2Id] = name;
    }

    _cate2Names = nameIndex;
    final groups = grouped.values.where((group) => group.items.isNotEmpty).toList();
    return CategoryResult(site: kDouyuSiteId, groups: groups);
  }

  @override
  Future<RoomListResult> fetchRooms(RoomListRequest request) async {
    final cid = request.cid;
    if (cid != null && cid.isNotEmpty && cid != '0') {
      return _fetchMixList('2_$cid', request.page, request.limit, targetCid: cid);
    }
    try {
      return await _fetchMixList('0_0', request.page, request.limit);
    } on ParserHttpException {
      // mixList 不可用时回退移动端列表。
    }
    return _fetchMobileHomeList(request.page, request.limit);
  }

  Future<Map<String, dynamic>> _getJson(Uri url) async {
    final response = await _http.get(url, headers: _douyuWebHeaders);
    return jsonMapOf(jsonDecode(utf8.decode(response.bodyBytes)));
  }

  /// cate2Id -> 名称索引;拉不到分类索引时返回空(仅影响分类名补全)。
  Future<Map<String, String>> _cate2NameIndex() async {
    final cached = _cate2Names;
    if (cached != null) return cached;
    try {
      await fetchCategories(kDouyuSiteId);
    } on ParserHttpException {
      // 分类名缓存仅用于补字段,失败不阻塞列表。
    }
    return _cate2Names ?? const {};
  }

  Future<RoomListResult> _fetchMixList(
    String directory,
    int page,
    int limit, {
    String? targetCid,
  }) async {
    final data = jsonMapOf(
      (await _getJson(
        Uri.parse('https://www.douyu.com/gapi/rkc/directory/mixList/$directory/$page'),
      ))['data'],
    );
    final items = jsonListOf(data['rl']);
    final rooms = <RoomSummary>[];
    for (final item in items.whereType<Map<String, dynamic>>()) {
      final room = _normalizeMixRoom(item, targetCid);
      if (room == null) continue;
      rooms.add(room);
      if (rooms.length >= limit) break;
    }
    return RoomListResult(
      rooms: rooms.map(RoomRecord.fromSummary).toList(growable: false),
      page: page,
      hasMore: items.isNotEmpty && rooms.length >= limit,
    );
  }

  Future<RoomListResult> _fetchMobileHomeList(int page, int limit) async {
    final data = jsonMapOf(
      (await _getJson(Uri.parse('https://m.douyu.com/api/room/list?page=$page&limit=$limit')))['data'],
    );
    final items = jsonListOf(data['list']);
    final pageCount = jsonInt(data['pageCount']);
    final nowPage = jsonInt(data['nowPage']);
    final hasMoreRaw = data['hasMore'];
    final hasMore = hasMoreRaw != null ? jsonBool(hasMoreRaw) : nowPage < pageCount;

    final rooms = <RoomSummary>[];
    for (final item in items.whereType<Map<String, dynamic>>()) {
      final room = await _normalizeMobileRoom(item);
      if (room.roomId.isNotEmpty) rooms.add(room);
    }
    return RoomListResult(
      rooms: rooms.map(RoomRecord.fromSummary).toList(growable: false),
      page: nowPage == 0 ? page : nowPage,
      hasMore: hasMore,
    );
  }

  RoomSummary? _normalizeMixRoom(Map<String, dynamic> item, String? targetCid) {
    final cid2 = jsonText(item['cid2']);
    if (targetCid != null && cid2.isNotEmpty && cid2 != targetCid) return null;
    final roomId = jsonText(item['rid']);
    if (roomId.isEmpty) return null;
    var cover = jsonText(item['rs16'] ?? item['rs1']);
    if (cover.startsWith('//')) cover = 'https:$cover';
    return RoomSummary(
      site: kDouyuSiteId,
      roomId: roomId,
      title: jsonText(item['rn']),
      anchorName: jsonText(item['nn']),
      cid: cid2,
      category: jsonText(item['c2name'] ?? item['c2name_display']),
      online: formatOnlineCount(item['ol'] ?? item['online']),
      cover: cover,
      promoTag: pickDouyuPromoTag(item),
      // mixList 目录 live-only:状态真源(6sol 裁决 Task 4a-i)。
      roomState: RoomState.live,
    );
  }

  /// 移动端列表条目:hn 优先(已是人类可读),否则格式化数字;分类名缺省时查缓存。
  Future<RoomSummary> _normalizeMobileRoom(Map<String, dynamic> item) async {
    final hn = jsonText(item['hn']).trim();
    var category = jsonText(item['cate2Name'] ?? item['gameName'] ?? item['cate3Name']);
    if (category.isEmpty) {
      final cid = jsonText(item['cate2Id'] ?? item['cate1Id']);
      if (cid.isNotEmpty) {
        category = (await _cate2NameIndex())[cid] ?? '';
      }
    }
    return RoomSummary(
      site: kDouyuSiteId,
      roomId: jsonText(item['rid']),
      title: jsonText(item['roomName']),
      anchorName: jsonText(item['nickname'] ?? item['ownerName']),
      cid: jsonText(item['cate2Id'] ?? item['cate1Id']),
      category: category,
      online: hn.isNotEmpty ? hn : formatOnlineCount(item['online'] ?? item['viewerCount']),
      cover: jsonText(item['roomSrc'] ?? item['verticalSrc']),
      promoTag: pickDouyuPromoTag(item),
      // 移动端列表目录 live-only:状态真源(6sol 裁决 Task 4a-i)。
      roomState: RoomState.live,
    );
  }
}
