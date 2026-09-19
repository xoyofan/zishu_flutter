/// SOOP 分类索引、分类房间与首页推荐。
library;

import '../../catalog/category_name_remap.dart';
import 'zh_categories.dart';
import '../../contracts/contracts.dart';
import '../../http/parser_http.dart';
import '../../models/models.dart';
import '../../utils/format_online.dart';
import '../douyu/json_utils.dart';
import 'normalize.dart';
import 'room_api.dart';

/// 分类索引分页大小与最大翻页数(分类总量有限,避免失控请求)。
const int kSoopCategoryPageSize = 120;
const int kSoopCategoryMaxPages = 3;

/// 首页推荐单页条数上限。
const int kSoopRecommendMaxLimit = 60;

class SoopBrowseRepository implements BrowseRepository {
  SoopBrowseRepository(this._http);

  final ParserHttp _http;
  List<CategoryItem>? _categoryCache;

  @override
  Future<CategoryResult> fetchCategories(String site) async {
    final cached = _categoryCache;
    // 空分类按未命中处理,作废重拉(web e389570 空壳分组同款校验语义)。
    if (cached != null && cached.isNotEmpty) {
      return CategoryResult(
        site: kSoopSiteId,
        groups: [CategoryGroup(id: '1', name: '热门', items: cached)],
      );
    }

    final items = <CategoryItem>[];
    for (var page = 1; page <= kSoopCategoryMaxPages; page++) {
      final list = await _fetchCategoryList(page);
      for (final raw in list) {
        final item = jsonMapOf(raw);
        final cid = jsonText(item['category_no']);
        final name = jsonText(item['category_name']);
        if (cid.isEmpty || name.isEmpty) continue;
        // zh_CN 上游直出中文名:记录 cid→中文,供房间列表反查(web
        // soopZhCategoryMap 同构);remap 仅作归一兜底。
        rememberSoopZhCategory(cid, name);
        items.add(
          CategoryItem(
            cid: cid,
            name: remapCategoryName('soop', name),
            pic: httpsSoopUrl(item['cate_img']),
          ),
        );
      }
      if (list.length < kSoopCategoryPageSize) break;
    }
    // 空分类不落缓存,避免上游异常响应霸占缓存(web e389570 同款语义)。
    if (items.isNotEmpty) _categoryCache = items;
    return CategoryResult(
      site: kSoopSiteId,
      groups: [CategoryGroup(id: '1', name: '热门', items: items)],
    );
  }

  @override
  Future<RoomListResult> fetchRooms(RoomListRequest request) async {
    final cid = request.cid;
    if (cid != null && cid.isNotEmpty && cid != '0') {
      return _fetchCategoryRooms(cid, request.page, request.limit);
    }
    return _fetchRecommend(request.page, request.limit);
  }

  Future<List<Object?>> _fetchCategoryList(int page) async {
    final json = await _getJson(
      Uri.https('sch.sooplive.co.kr', '/api.php', {
        'm': 'categoryList',
        'szKeyword': '',
        'szOrder': 'view_cnt',
        'nPageNo': '$page',
        'nListCnt': '$kSoopCategoryPageSize',
        'nOffset': '0',
        'szPlatform': 'pc',
        // 上游本地化:带 lang 时 categoryList 直出中文 category_name
        // (对齐 web services/streaming-server soop.ts:5-10)。
        'lang': 'zh_CN',
      }),
    );
    return jsonListOf(jsonMapOf(json['data'])['list']);
  }

  Future<RoomListResult> _fetchCategoryRooms(
    String cid,
    int page,
    int limit,
  ) async {
    final effectiveLimit = limit.clamp(1, kSoopRecommendMaxLimit);
    final json = await _getJson(
      Uri.https('sch.sooplive.co.kr', '/api.php', {
        'm': 'categoryContentsList',
        'szType': 'live',
        'nPageNo': '$page',
        'nListCnt': '$effectiveLimit',
        'szPlatform': 'pc',
        'szOrder': 'view_cnt_desc',
        'szCateNo': cid,
      }),
    );
    final list = jsonListOf(jsonMapOf(json['data'])['list']);
    return _toResult(list, page, effectiveLimit, cid: cid);
  }

  Future<RoomListResult> _fetchRecommend(int page, int limit) async {
    final effectiveLimit = limit.clamp(1, kSoopRecommendMaxLimit);
    final json = await _getJson(
      Uri.https('live.sooplive.co.kr', '/api/main_broad_list_api.php', {
        'selectType': 'action',
        'selectValue': 'all',
        'orderType': 'view_cnt',
        'pageNo': '$page',
        'lang': 'ko_KR',
      }),
    );
    final list = jsonListOf(json['broad']);
    return _toResult(
      list,
      page,
      effectiveLimit,
      coverKey: 'broad_thumb',
    );
  }

  Future<Map<String, dynamic>> _getJson(Uri url) async {
    final response = await _http.get(
      url,
      // 缺 Accept-Language 时上游仍返回韩文(soop.ts 注释同款结论)。
      headers: const {
        'Accept': '*/*',
        'Accept-Language': 'zh-CN,zh;q=0.9',
      },
    );
    return _http.jsonMap(response);
  }

  RoomListResult _toResult(
    List<Object?> raw,
    int page,
    int limit, {
    String? cid,
    String coverKey = 'thumbnail',
  }) {
    final rooms = <RoomSummary>[];
    for (final value in raw) {
      final item = jsonMapOf(value);
      final roomId = jsonText(item['user_id']).trim();
      if (roomId.isEmpty) continue;
      // 房间流只有韩文 category_name:优先按 category_no 反查中文名
      // (web soop.ts:111-116 的 zhName 覆盖同构),未命中回退原名+remap。
      final cateNo = jsonText(item['category_no']);
      final zhName = soopZhCategoryName(cateNo);
      final category = zhName ??
          remapCategoryName('soop', jsonText(item['category_name']));
      rooms.add(
        RoomSummary(
          site: kSoopSiteId,
          roomId: roomId,
          title: jsonText(item['broad_title']),
          anchorName: jsonText(item['user_nick']),
          cid: cid ?? '',
          category: category,
          online: formatOnlineCount(soopOnlineViewers(item)),
          cover: httpsSoopUrl(item[coverKey] ?? item['thumbnail']),
        ),
      );
      if (rooms.length >= limit) break;
    }
    return RoomListResult(rooms: rooms, page: page, hasMore: raw.length >= limit);
  }
}
