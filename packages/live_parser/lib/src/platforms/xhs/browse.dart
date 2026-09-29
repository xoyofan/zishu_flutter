/// 小红书分类索引与房间列表(live-room.xiaohongshu.com API,需 a1 +
/// web_session Cookie,经 [XhsSigner] 签名)。
///
/// 链路与字段口径对齐参考实现(SFVideoLive services/streaming-server
/// src/resolve/xhs/categories.ts + browse/xhs.ts):
/// * 分类:GET `/api/sns/red/live/web/feed/category`,扁平列表放单组平铺;
/// * 列表:GET `/api/sns/red/live/web/feed/v1/squarefeed`,参数
///   `category/cursorScore/source=13/size`;
/// * `code == -101` 表示 Cookie 过期,抛 [XhsCookieExpiredException];
/// * 首页推荐(cid 空)= squarefeed 带 `category=0`(参考实现
///   fetchXhsRecommendRooms 同款),不另行请求推荐接口。
///
/// 分页语义(上游只有 cursorScore 游标,契约 [RoomListRequest] 只有
/// page/limit):page N = 从 `cursorScore=0` 链式重放 N 次上游请求(按
/// roomId 去重、上限 [kXhsMaxPages],参考实现 XHS_MAX_PAGES 同款),
/// 返回去重后累计列表的第 N 个 `size` 窗口 —— 状态无关、确定性可重放,
/// 每页窗口语义与 kuaishou/douyin 各站一致。`hasMore` = 累计去重条数
/// 已覆盖 `page × size`(参考实现出口同款判据)。
library;

import '../../catalog/category_name_remap.dart';
import '../../contracts/contracts.dart';
import '../../models/models.dart';
import '../../models/room_record.dart';
import '../../registry/category_cache.dart';
import '../douyu/json_utils.dart';
import 'room_api.dart';

/// 上游单页条数(参考实现 XHS_PAGE_SIZE=30;请求侧 limit 夹取到 1..30)。
const int kXhsPageSize = 30;

/// 链式翻页上限:page N 需要顺序请求 N 次上游,封顶防深翻页拖垮接口。
const int kXhsMaxPages = 5;

/// 分类列表接口路径。
const String kXhsCategoryPath = '/api/sns/red/live/web/feed/category';

/// 分类/首页房间列表接口路径。
const String kXhsSquarefeedPath = '/api/sns/red/live/web/feed/v1/squarefeed';

/// 首页推荐流在上游 squarefeed 里的 category 取值(参考实现同款)。
const String kXhsHomeCategoryId = '0';

/// source 固定 13(web 端 squarefeed 请求同款)。
const int kXhsFeedSource = 13;

class XhsBrowseRepository implements BrowseRepository {
  XhsBrowseRepository(this._client);

  final XhsClient _client;
  List<CategoryGroup>? _categoryCache;

  @override
  Future<CategoryResult> fetchCategories(String site) async {
    final cached = _categoryCache;
    // 空分类按未命中处理,作废重拉(web e389570 空壳分组同款校验语义)。
    if (hasRealCategoryGroups(cached)) {
      return CategoryResult(site: kXhsSiteId, groups: cached!);
    }

    final json = await _client.getSignedJson(kXhsCategoryPath, const {});
    _ensureNotCookieExpired(json, '分类列表');
    final categories = jsonListOf(jsonMapOf(json['data'])['categories']);
    // XHS 分类是扁平列表,统一放入一个组内平铺展示(web browse/xhs.ts 同款;
    // UI 侧单组即平铺渲染,组名留空不展示)。
    final items = <CategoryItem>[];
    for (final raw in categories) {
      final item = jsonMapOf(raw);
      final cid = jsonText(item['id']);
      final name = remapCategoryName(kXhsSiteId, jsonText(item['desc']));
      if (cid.isEmpty || name.isEmpty) continue;
      items.add(CategoryItem(cid: cid, name: name, pic: ''));
    }
    final groups = <CategoryGroup>[CategoryGroup(id: '', name: '', items: items)];
    // 空分类不落缓存,避免上游异常响应霸占缓存(web e389570 同款语义)。
    if (hasRealCategoryGroups(groups)) _categoryCache = groups;
    return CategoryResult(site: kXhsSiteId, groups: groups);
  }

  @override
  Future<RoomListResult> fetchRooms(RoomListRequest request) async {
    final cid = request.cid;
    final hasCategory = cid != null && cid.isNotEmpty && cid != '0';
    return _fetchFeedPage(
      categoryId: hasCategory ? cid : kXhsHomeCategoryId,
      page: request.page,
      limit: request.limit,
      // feed 不带分类名:按 cid 从已缓存分类索引反查(douyin browse 同款,
      // 只读缓存不触发网络;UI 流程必然先加载分类页)。
      categoryName: hasCategory ? _cachedCategoryName(cid) : '',
    );
  }

  Future<RoomListResult> _fetchFeedPage({
    required String categoryId,
    required int page,
    required int limit,
    String categoryName = '',
  }) async {
    final size = limit.clamp(1, kXhsPageSize);
    final pages = page < 1 ? 1 : (page > kXhsMaxPages ? kXhsMaxPages : page);
    final collected = <RoomRecord>[];
    final seen = <String>{};
    var cursor = '0';
    for (var fetched = 0; fetched < pages; fetched++) {
      final json = await _client.getSignedJson(kXhsSquarefeedPath, <String, Object?>{
        'category': categoryId,
        'cursorScore': cursor,
        'source': kXhsFeedSource,
        'size': size,
      });
      _ensureNotCookieExpired(json, '房间列表');
      if (!jsonBool(json['success'])) break;
      final feeds = jsonListOf(jsonMapOf(json['data'])['feeds']);
      var batch = 0;
      for (final raw in feeds) {
        final feed = jsonMapOf(raw);
        final live = jsonMapOf(feed['live']);
        if (live.isEmpty) continue; // 无 live 字段的条目(笔记等)跳过(web 同款 filter)
        final summary = _normalizeFeedRoom(live, categoryId, categoryName);
        if (summary == null || !seen.add(summary.roomId)) continue;
        collected.add(RoomRecord.fromSummary(summary));
        batch++;
      }
      // 下一页游标 = 最后一个 feed 的 cursor_score;条目不满一页或无游标
      // 即终止(参考实现 fetchLiveRoomsByCategory 末行口径)。
      final nextCursor = feeds.isEmpty
          ? ''
          : jsonText(jsonMapOf(feeds.last)['cursor_score']).trim();
      if (batch < size || nextCursor.isEmpty) break;
      cursor = nextCursor;
    }

    // page N = 累计去重列表的第 N 个窗口(不足时为剩余条目)。
    final start = (pages - 1) * size;
    final end = (start + size).clamp(start, collected.length);
    final window = start < collected.length
        ? collected.sublist(start, end)
        : const <RoomRecord>[];
    return RoomListResult(
      rooms: List.unmodifiable(window),
      page: page,
      hasMore: collected.length >= pages * size,
    );
  }

  /// feeds[].live → [RoomSummary];字段映射对齐参考实现
  /// fetchLiveRoomsByCategory:roomId 取 room_id_str(缺省回退 room_id),
  /// 观众数取 display_count(缺省回退 member_count,原样字符串不二次格式化)。
  RoomSummary? _normalizeFeedRoom(
    Map<String, dynamic> live,
    String categoryId,
    String categoryName,
  ) {
    final host = jsonMapOf(live['t_live_host_info']);
    final room = jsonMapOf(live['t_room_info']);
    final roomIdStr = jsonText(room['room_id_str']).trim();
    final roomId = roomIdStr.isNotEmpty ? roomIdStr : jsonText(room['room_id']).trim();
    if (roomId.isEmpty) return null;
    return RoomSummary(
      site: kXhsSiteId,
      roomId: roomId,
      title: jsonText(room['name']),
      anchorName: jsonText(host['nickname']),
      // 首页推荐流(category=0)无分类归属,cid 留空。
      cid: categoryId == kXhsHomeCategoryId ? '' : categoryId,
      category: categoryName,
      online: jsonText(room['display_count'] ?? room['member_count']),
      cover: jsonText(room['cover']),
      avatar: jsonText(host['avatar']),
      // 分类目录/首页推荐流 live-only:状态真源(与各站口径一致)。
      roomState: RoomState.live,
    );
  }

  String _cachedCategoryName(String cid) {
    for (final group in _categoryCache ?? const <CategoryGroup>[]) {
      for (final item in group.items) {
        if (item.cid == cid) return item.name;
      }
    }
    return '';
  }

  /// `-101` = session 过期(Cookie 失效),抛专用异常;其余业务码不在此
  /// 拦截(空数据按空结果处理,对齐参考实现 checkApiResponse 口径)。
  void _ensureNotCookieExpired(Map<String, dynamic> json, String action) {
    if (jsonInt(json['code']) == -101) {
      final msg = jsonText(json['msg']).trim();
      throw XhsCookieExpiredException(
        '小红书 Cookie 已过期($action 失败:${msg.isEmpty ? '无登录信息' : msg})',
      );
    }
  }
}
