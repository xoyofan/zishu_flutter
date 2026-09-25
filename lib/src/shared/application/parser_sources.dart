/// live_parser 真实数据源适配层。
///
/// 通过 `--dart-define=ZISHU_REAL_PARSER=true` 启用；默认仍使用 fixture，
/// 保证 widget 测试不依赖公网和站点接口状态。
library;

import 'package:live_parser/live_parser.dart';

import 'browse_source.dart';

class ParserBrowseSource implements BrowseSource {
  ParserBrowseSource({SiteRegistry? registry, String douyinCookie = ''})
    : _registry = registry ?? buildSiteRegistry(douyinCookie: douyinCookie);

  final SiteRegistry _registry;

  @override
  Future<CategoryResult> fetchCategories(String site) async {
    final browse = _registry[site]?.browse;
    if (browse == null) {
      throw StateError('站点 $site 不支持分类浏览');
    }
    return browse.fetchCategories(site);
  }

  @override
  Future<RoomListResult> fetchRooms({
    required String site,
    String? cid,
    int page = 1,
  }) async {
    final browse = _registry[site]?.browse;
    if (browse == null) {
      throw StateError('站点 $site 不支持房间浏览');
    }
    return browse.fetchRooms(
      RoomListRequest(site: site, cid: cid, page: page, limit: 30),
    );
  }
}

class ParserRoomSource
    implements
        RoomSource,
        RoomRecoverer,
        RoomRefresher,
        FollowLiveRefresher,
        FollowImportSource {
  ParserRoomSource({SiteRegistry? registry, String douyinCookie = ''})
    : _registry = registry ?? buildSiteRegistry(douyinCookie: douyinCookie),
      _douyinCookie = douyinCookie;

  final SiteRegistry _registry;
  final String _douyinCookie;

  @override
  Future<RoomPayload> resolveRoom({
    required String site,
    required String roomIdOrUrl,
    String? preferredQuality,
  }) async {
    final registration = _registry[site];
    if (registration == null) {
      throw StateError('未注册站点 $site');
    }
    return registration.resolver.resolveRoom(
      RoomRequest(
        site: site,
        roomIdOrUrl: roomIdOrUrl,
        preferredQuality: preferredQuality,
      ),
    );
  }

  /// 恢复重解析:必须绕开短缓存拿全新地址。
  ///
  /// 站点注册项把 resolver 统一包成 `CachedRoomResolver`,它同时实现了
  /// `RoomRecoveryResolver`(先失效键再委托内层),故这里按能力探测即可 ——
  /// 平台侧无需逐个改注册项。极少数未实现该能力的 resolver 退化为普通解析,
  /// 语义仍强于"复用播放器手里的旧地址"。
  @override
  Future<RoomPayload> recoverRoom({
    required String site,
    required String roomIdOrUrl,
    String? preferredQuality,
  }) async {
    final registration = _registry[site];
    if (registration == null) {
      throw StateError('未注册站点 $site');
    }
    final request = RoomRequest(
      site: site,
      roomIdOrUrl: roomIdOrUrl,
      preferredQuality: preferredQuality,
    );
    final resolver = registration.resolver;
    if (resolver is RoomRecoveryResolver) {
      return resolver.recoverRoom(request);
    }
    return resolver.resolveRoom(request);
  }

  /// 轻量状态刷新:只取「此刻在不在播」与元信息,不解析播放地址。
  ///
  /// 站点解析器的能力探测走静态 `is`(解析轨的 `RoomSummaryRefresher` 已落地);
  /// 未实现该能力的站点抛 [StateError],由关注列表按**条目级**隔离并保留旧值。
  /// 注意:注册表出口套了 `CachedRoomResolver`,它已透传该能力且**不走短缓存**,
  /// 因此这里的刷新拿到的总是上游新鲜值。
  @override
  Future<List<RoomSummary>> importDouyinFollows({
    void Function(FollowImportProgress progress)? onProgress,
  }) async {
    return fetchDouyinFollowingAnchors(
      DouyinClient(cookieOverride: _douyinCookie),
      onProgress: (progress) => onProgress?.call(
        FollowImportProgress(
          page: progress.page,
          imported: progress.imported,
          total: progress.total,
        ),
      ),
    );
  }

  @override
  Future<FollowLiveSnapshot> refreshFollowLive() async {
    final result = await fetchDouyinFollowLiveRooms(
      DouyinClient(cookieOverride: _douyinCookie),
    );
    return FollowLiveSnapshot(rooms: result.rooms, complete: result.complete);
  }

  @override
  Future<RoomRecord> refreshRoom({
    required String site,
    required String roomId,
  }) async {
    final registration = _registry[site];
    if (registration == null) {
      throw StateError('未注册站点 $site');
    }
    final resolver = registration.resolver;
    if (resolver is RoomSummaryRefresher) {
      return resolver.refreshRoomSummary(
        RoomRequest(site: site, roomIdOrUrl: roomId),
      );
    }
    throw StateError('站点 $site 不支持状态刷新');
  }
}
