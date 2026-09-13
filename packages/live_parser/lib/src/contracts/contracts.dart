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

/// 恢复重解析:播放中断后重新拿一份「可新建连接」的房间结果。
///
/// 为什么必须独立于 [RoomResolver]:签名平台(虎牙等)的播放地址带时效
/// 参数,其生命周期**短于**观看会话。普通解析允许走短缓存(见
/// `CachedRoomResolver`),因为同一入口短时间内重复进房复用地址无害;
/// 但**恢复路径复用缓存地址是有害的** —— 那等于反复重开一个已过期的源,
/// 表现为「流反复中断、每次都在重试却永远起不来」。
///
/// 实现约定(不可协商):
/// * 必须重新获取新连接所需的全部身份 / token / 房间字段,并**绕开任何
///   缓存或已解析结果的复用**;
/// * 返回与 `resolveRoom` 相同形状的 [RoomPayload],宿主据此重建线路;
/// * 不得返回上一次的地址列表 —— 那会让本契约失去意义。
///
/// 参考 pure_live `LivePlayRecoveryResolver` 的语义(仅借鉴契约设计)。
///
/// 继承 [RoomResolver]:恢复者必然也能普通解析(实现方本就两者兼备),
/// 更让调用点的 `is` 能力探测获得类型提升 —— 否则 `RoomResolver` 类型的
/// 变量即使探测通过也调不到 `recoverRoom`。
abstract interface class RoomRecoveryResolver implements RoomResolver {
  Future<RoomPayload> recoverRoom(RoomRequest request);
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
