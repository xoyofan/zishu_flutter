/// 稳定解析契约:UI / server 只依赖这些小接口与 facade,不接触站点实现。
library;

import '../models/models.dart';

/// 房间解析请求:房间号或完整 URL 二选一,由站点实现归一。
class RoomRequest {
  const RoomRequest({required this.site, required this.roomIdOrUrl, this.preferredQuality});

  final String site;
  final String roomIdOrUrl;
  final String? preferredQuality;
}

/// 房间列表请求。
class RoomListRequest {
  const RoomListRequest({required this.site, this.cid, this.page = 1, this.limit = 30});

  final String site;

  /// 为空/`0` 表示平台首页推荐流。
  final String? cid;
  final int page;
  final int limit;
}

/// 搜索请求。
class SearchRequest {
  const SearchRequest({required this.site, required this.query, this.limit = 20});

  final String site;
  final String query;
  final int limit;
}

/// 房间解析:输入房间号或 URL,输出标准 RoomPayload。
abstract interface class RoomResolver {
  Future<RoomPayload> resolveRoom(RoomRequest request);
}

/// 栏目浏览:分类索引 + 分类/首页房间列表。
abstract interface class BrowseRepository {
  Future<CategoryResult> fetchCategories(String site);
  Future<RoomListResult> fetchRooms(RoomListRequest request);
}

/// 主播/房间搜索。
abstract interface class SearchRepository {
  Future<SearchResult> search(SearchRequest request);
}

/// 弹幕会话连接:connect 返回的 session 生命周期由调用方管理(close 后不再发消息)。
abstract interface class DanmakuConnector {
  SiteCapabilities get capabilities;
  Future<DanmakuSession> connect(DanmakuSessionRequest request);
}

/// 弹幕连接请求。
class DanmakuSessionRequest {
  const DanmakuSessionRequest({required this.site, required this.roomId});

  final String site;
  final String roomId;
}

/// 一场已建立的弹幕会话:订阅 messages / states,close 释放底层连接。
abstract interface class DanmakuSession {
  Stream<DanmakuMessage> get messages;
  Stream<DanmakuSessionState> get states;
  Future<void> close();
}

/// 站点注册项:能力 + 中文 branding + 各接口工厂。
class SiteRegistration {
  const SiteRegistration({
    required this.id,
    required this.name,
    required this.capabilities,
    required this.resolver,
    this.browse,
    this.search,
    this.danmaku,
  });

  final String id;
  final String name;
  final SiteCapabilities capabilities;
  final RoomResolver resolver;
  final BrowseRepository? browse;
  final SearchRepository? search;
  final DanmakuConnector? danmaku;
}

/// 站点能力注册表。
class SiteRegistry {
  final Map<String, SiteRegistration> _sites = {};

  void register(SiteRegistration registration) => _sites[registration.id] = registration;

  SiteRegistration? byId(String site) => _sites[site];

  Set<String> get supportedSites => _sites.keys.toSet();

  SiteRegistration? operator [](String site) => _sites[site];
}
