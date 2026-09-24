/// 稳定解析契约:UI / server 只依赖这些小接口与 facade,不接触站点实现。
library;

import '../models/models.dart';
import '../models/room_record.dart';

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
  const SearchRequest({
    required this.site,
    required this.query,
    this.limit = 20,
    this.type,
  });

  final String site;
  final String query;
  final int limit;

  /// 搜索档位:anchors = 仅主播、rooms = 仅房间。
  ///
  /// 缺省 `null` = 主播+房间混合 —— 即本契约的历史行为;既有调用方
  /// 不传该参数时路径与结果完全不变(向后兼容)。站点实现按 web 真源
  /// (`SFVideoLive services/streaming-server/src/search/*`)对齐:
  /// 双接口站(douyu/bilibili/douyin/yy)按档位只打对应上游接口,
  /// huya 房间档走 `v=4` 仅房间分区;单一语义站(twitch/soop 等
  /// web 端本就只有一个搜索实现)忽略该字段。
  final SearchType? type;
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

/// 轻量状态刷新:只取房间元信息(在播状态/热度/标题/封面/分类/主播名),
/// **不解析播放地址、不做签名、不写缓存**。
///
/// 与 [RoomResolver] 分离的原因:关注列表与房间卡片刷新只需要元数据,走完整
/// 解析会顺带做取密钥/签名/取流等昂贵步骤;刷新失败(网络抖动)也不应把已有
/// 列表刷成空 —— 由调用方按条目隔离,失败保留旧数据。
///
/// 实现约定(不可协商):
/// * 只打各站最轻的房间信息接口,请求里不得出现取流 / 签名相关调用;
/// * 离线(含平台「未开播」)时 [RoomSummary.online] 必须为空串 —— 宿主以
///   「online 非空」当作在播判据,填占位文案会把离线房间刷成在播;
///   轮播([RoomState.replay],如 bilibili live_status==2 / douyu
///   videoLoop==1 / huya 录播循环)同样**必须留空 online**,由
///   [RoomSummary.roomState] 单独承载 replay 语义;
/// * 房间不存在或上游报错直接抛异常(不得返回伪造的 RoomSummary);
/// * 不做结果缓存:刷新本身就是为了拿最新状态。
///
/// 继承 [RoomResolver]:能力探测 `is` 的类型提升要求子类型关系(与
/// [RoomRecoveryResolver] 同一约定);实现方通常也具备完整解析能力。
abstract interface class RoomSummaryRefresher implements RoomResolver {
  Future<RoomSummary> refreshRoomSummary(RoomRequest request);
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
    this.display = const SiteDisplaySpec(),
  });

  final String id;
  final String name;
  final SiteCapabilities capabilities;
  final RoomResolver resolver;
  final BrowseRepository? browse;
  final SearchRepository? search;
  final DanmakuConnector? danmaku;

  /// UI 共享的平台展示语义,默认不暴露任何统计列。
  final SiteDisplaySpec display;
}

/// 装饰型刷新包装的能力内省(实现者必然同时实现 [RoomSummaryRefresher])。
///
/// `CachedRoomResolver` 这类包装恒实现 [RoomSummaryRefresher](内层缺失时
/// 运行期抛 [UnsupportedError]),单凭 `is` 探测会把「未实现刷新的站点」
/// 误称为支持。注册 [LiveSite] 时按被包装 resolver 的**真实实现**决定
/// [LiveSite.refresher] 是否为 `null`,包装类通过本接口如实上报。
abstract interface class RefreshCapabilityProbe
    implements RoomSummaryRefresher {
  /// 被包装的内层 resolver 是否真实实现 [RoomSummaryRefresher]。
  bool get innerRefreshSupported;
}

/// 统一站点抽象:九站与 Windows 消费层只认这一种站点入口。
///
/// 迁移期约定(2026-09-24 Windows 统一契约):
/// * [resolveRoom] 是唯一强制返回 [RoomRecord] 的出口;可选接口部件
///   ([browse]/[search]/[danmaku]/[refresher]/[recovery])暂时沿用旧类型,
///   由后续任务逐个切换;
/// * 不支持的能力部件返回 `null`(不是空列表/空连接),支持后请求失败
///   必须抛异常 —— [SiteCapabilities] 与部件是否存在保持一致,注册时用
///   契约测试核查;
/// * [recovery] 绕开短缓存重新获取播放地址;[refresher] 只取元信息、不
///   做取流/签名 —— 注册时按内层真实实现判定,未实现刷新的站点即使被
///   装饰成 `RoomSummaryRefresher` 也必须为 `null`。
abstract interface class LiveSite {
  String get id;
  String get name;

  /// UI 能力声明,与下方可空部件保持一致。
  SiteCapabilities get capabilities;

  /// UI 共享的平台展示语义。
  SiteDisplaySpec get display;

  /// 统一房间解析:失败抛异常;「房间不存在」返回
  /// `roomState == notFound` 的记录,不以空房间冒充成功。
  Future<RoomRecord> resolveRoom(RoomRequest request);

  /// 栏目浏览;不支持为 `null`。
  BrowseRepository? get browse;

  /// 搜索;不支持为 `null`。
  SearchRepository? get search;

  /// 弹幕连接;不支持为 `null`(不返回空连接占位)。
  DanmakuConnector? get danmaku;

  /// 轻量状态刷新(只取元信息、不取流不写缓存);未实现为 `null`。
  RoomSummaryRefresher? get refresher;

  /// 恢复重解析(绕开短缓存重新获取地址);不支持为 `null`。
  RoomRecoveryResolver? get recovery;
}

/// [SiteRegistration] 到 [LiveSite] 的薄适配:不改九站 HTTP 逻辑,
/// 只在注册边界转换返回类型与部件可见性。
class _RegistrationLiveSite implements LiveSite {
  _RegistrationLiveSite(this._registration);

  final SiteRegistration _registration;

  @override
  String get id => _registration.id;

  @override
  String get name => _registration.name;

  @override
  SiteCapabilities get capabilities => _registration.capabilities;

  @override
  SiteDisplaySpec get display => _registration.display;

  @override
  Future<RoomRecord> resolveRoom(RoomRequest request) async =>
      RoomRecord.fromPayload(await _registration.resolver.resolveRoom(request));

  @override
  BrowseRepository? get browse => _registration.browse;

  @override
  SearchRepository? get search => _registration.search;

  @override
  DanmakuConnector? get danmaku => _registration.danmaku;

  @override
  RoomSummaryRefresher? get refresher {
    final resolver = _registration.resolver;
    // 短缓存包装恒 `is RoomSummaryRefresher`,必须再问装饰器内层真实能力,
    // 否则未实现刷新的站点会被装饰器误称为支持。
    if (resolver is RefreshCapabilityProbe && !resolver.innerRefreshSupported) {
      return null;
    }
    return resolver is RoomSummaryRefresher ? resolver : null;
  }

  @override
  RoomRecoveryResolver? get recovery {
    final resolver = _registration.resolver;
    return resolver is RoomRecoveryResolver ? resolver : null;
  }
}

/// 站点能力注册表。
class SiteRegistry {
  final Map<String, SiteRegistration> _sites = {};
  final Map<String, LiveSite> _liveSites = {};

  void register(SiteRegistration registration) {
    _sites[registration.id] = registration;
    _liveSites[registration.id] = _RegistrationLiveSite(registration);
  }

  SiteRegistration? byId(String site) => _sites[site];

  /// 统一站点外观:迁移期新消费方(Windows)走这里;
  /// 旧 `operator []` 保留到 Windows 切换为止。
  LiveSite? site(String id) => _liveSites[id];

  Set<String> get supportedSites => _sites.keys.toSet();

  SiteRegistration? operator [](String site) => _sites[site];
}
