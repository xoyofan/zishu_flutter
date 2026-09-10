/// YY 分类与房间列表浏览。
library;

import 'dart:convert';

import '../../contracts/contracts.dart';
import '../../http/parser_http.dart';
import '../../models/models.dart';
import '../../utils/format_online.dart';
import '../douyu/json_utils.dart';
import 'normalize.dart';

const Map<String, String> _yyBrowseHeaders = {
  'Accept': 'application/json, */*',
  'Origin': 'https://www.yy.com',
  'Referer': 'https://www.yy.com/',
};

class YyBrowseRepository implements BrowseRepository {
  YyBrowseRepository(this._http);

  final ParserHttp _http;
  List<CategoryGroup>? _categoryCache;
  final Map<String, _YyCategoryParams> _categoryParams = {};

  @override
  Future<CategoryResult> fetchCategories(String site) async {
    final cached = _categoryCache;
    if (cached != null) return CategoryResult(site: kYySiteId, groups: cached);

    final header = await _getJson(Uri.parse('https://www.yy.com/yyweb/module/data/header'));
    final tabs = jsonListOf(header['categoryTabs']);
    final groups = <CategoryGroup>[];
    for (final rawTab in tabs) {
      final tab = jsonMapOf(rawTab);
      final tabId = jsonText(tab['id']);
      if (tabId.isEmpty) continue;

      List<Object?> subs = const [];
      try {
        final response = await _getJson(Uri.parse(
          'https://www.yy.com/c/yycom/category/getCategory.action'
          '?parentId=${Uri.encodeQueryComponent(tabId)}',
        ));
        subs = jsonListOf(response['data']);
      } on ParserHttpException {
        // 单个一级分类失败不阻塞其它分组。
      }

      final items = <CategoryItem>[];
      for (final rawSub in subs) {
        final sub = jsonMapOf(rawSub);
        final cid = jsonText(sub['id']);
        final name = jsonText(sub['title']);
        final pageUrl = httpsYyUrl(sub['url']);
        if (cid.isNotEmpty && pageUrl.isNotEmpty) {
          try {
            final html = utf8.decode(
              (await _http.get(Uri.parse(pageUrl), headers: _yyBrowseHeaders)).bodyBytes,
            );
            final params = _parseCategoryPageInfo(html);
            if (params != null) _categoryParams[cid] = params;
          } on Object {
            // 分类页仅用于补充列表参数，抓取失败不影响分类项。
          }
        }
        items.add(CategoryItem(cid: cid, name: name, pic: httpsYyUrl(sub['cover'])));
      }
      if (items.isNotEmpty) {
        groups.add(CategoryGroup(
          id: tabId,
          name: jsonText(tab['title']).isEmpty ? tabId : jsonText(tab['title']),
          items: items,
        ));
      }
    }
    _categoryCache = groups;
    return CategoryResult(site: kYySiteId, groups: groups);
  }

  @override
  Future<RoomListResult> fetchRooms(RoomListRequest request) async {
    final cid = request.cid;
    if (cid != null && cid.isNotEmpty && cid != '0') {
      return _fetchCategoryRooms(cid, request.page, request.limit);
    }
    final data = await _getJson(
      Uri.parse('https://www.yy.com/more/page.action').replace(queryParameters: {
        'page': '${request.page}',
        'pageSize': '${request.limit}',
        'biz': 'other',
        'subBiz': 'idx',
        'moduleId': '-1',
      }),
    );
    final list = jsonListOf(jsonMapOf(data['data'])['data']);
    return _toResult(list, request.page, request.limit);
  }

  Future<RoomListResult> _fetchCategoryRooms(String cid, int page, int limit) async {
    var params = _categoryParams[cid];
    if (params == null) {
      // 从分类索引补齐 category page 的 moduleId/biz/subBiz。
      try {
        await fetchCategories(kYySiteId);
      } on ParserHttpException {
        // 未能获取参数时返回空结果，而不是把页面异常扩散到 UI。
      }
      params = _categoryParams[cid];
    }
    if (params == null) return RoomListResult(rooms: const [], page: page, hasMore: false);

    final data = await _getJson(
      Uri.parse('https://www.yy.com/more/page.action').replace(queryParameters: {
        'page': '$page',
        'pageSize': '$limit',
        'moduleId': params.moduleId,
        'biz': params.biz,
        'subBiz': params.subBiz,
      }),
    );
    final list = jsonListOf(jsonMapOf(data['data'])['data']);
    return _toResult(list, page, limit, cid: cid);
  }

  Future<Map<String, dynamic>> _getJson(Uri url) async {
    final response = await _http.get(url, headers: _yyBrowseHeaders);
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map) throw const ParserHttpException('YY 返回了非对象 JSON');
    return Map<String, dynamic>.from(decoded);
  }

  RoomListResult _toResult(
    List<Object?> raw,
    int page,
    int limit, {
    String? cid,
  }) {
    final rooms = <RoomSummary>[];
    for (final value in raw) {
      final item = jsonMapOf(value);
      final roomId = jsonText(item['sid']);
      if (roomId.isEmpty) continue;
      rooms.add(
        RoomSummary(
          site: kYySiteId,
          roomId: roomId,
          title: jsonText(item['desc']).isNotEmpty
              ? jsonText(item['desc'])
              : jsonText(item['name']),
          anchorName: jsonText(item['name']),
          cid: cid ?? jsonText(item['ssid']),
          category: jsonText(item['biz']),
          online: formatOnlineCount(item['users']),
          cover: httpsYyUrl(item['thumb2'] ?? item['thumb'] ?? item['avatar']),
        ),
      );
      if (rooms.length >= limit) break;
    }
    return RoomListResult(rooms: rooms, page: page, hasMore: raw.length >= limit);
  }

  _YyCategoryParams? _parseCategoryPageInfo(String html) {
    final moduleId = RegExp(r'''moduleId\s*[:=]\s*['"]?(\d+)''').firstMatch(html)?.group(1);
    final biz = RegExp(r'''biz\s*:\s*['"]([^'"]+)''').firstMatch(html)?.group(1);
    final subBiz = RegExp(r'''subBiz\s*:\s*['"]([^'"]+)''').firstMatch(html)?.group(1);
    if (moduleId == null || biz == null || subBiz == null) return null;
    return _YyCategoryParams(moduleId: moduleId, biz: biz, subBiz: subBiz);
  }
}

class _YyCategoryParams {
  const _YyCategoryParams({required this.moduleId, required this.biz, required this.subBiz});

  final String moduleId;
  final String biz;
  final String subBiz;
}
