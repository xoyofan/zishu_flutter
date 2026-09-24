/// RemoteSiteSource：streaming-server 数据面 → pure_live LiveSite 契约的适配器。
///
/// 每个 siteId 一个实例（见 SiteRegistry）。getRoomDetail 的 RoomPayload 缓存在
/// 实例内，getPlayQualites/getPlayUrls 优先读缓存；generation（防串房 token）
/// 在每次切换房间时递增，进行中的旧房间响应落盘（缓存）前被丢弃。
///
/// URL 一律透传原始 url，不做代理改写（Referer 头线路的 /api/live-stream 代理
/// 由播放层 E6 决定）。
library;

import '../contracts/browse_models.dart';
import '../contracts/room_models.dart';
import '../sites/live_site.dart';
import '../sites/live_danmaku.dart';
import '../sites/models/live_anchor_item.dart';
import '../sites/models/live_area.dart';
import '../sites/models/live_category.dart';
import '../sites/models/live_message.dart';
import '../sites/models/live_play_quality.dart';
import '../sites/models/live_room.dart';
import 'stream_api_client.dart';

class RemoteSiteSource implements LiveSite {
  /// streaming-server 平台 id：douyu/huya/bilibili/douyin/kuaishou/yy/
  /// twitch/soop/youtube/xhs。
  @override
  String id;

  @override
  String name;

  final StreamApiClient client;

  /// 防串房 token：每次 getRoomDetail 切房递增；响应返回时若与当前值不一致
  /// 则视为过期，不写缓存。
  int _generation = 0;

  /// 最近一次成功 getRoomDetail（或同房间画质补拉）的 payload。
  RoomPayload? _payload;

  RemoteSiteSource(this.id, this.client, {String? name}) : name = name ?? id;

  // ---------------------------------------------------------------------------
  // 房间详情 + 播放
  // ---------------------------------------------------------------------------

  @override
  Future<LiveRoom> getRoomDetail({
    required String roomId,
    required String platform,
  }) async {
    final site = platform.trim().isNotEmpty ? platform.trim() : id;
    final gen = ++_generation;
    try {
      final payload = await client.fetchRoom(
        site: site,
        room: roomId,
        mode: 'lazy',
      );
      if (gen != _generation) {
        // 切房后旧响应：丢弃（不写缓存），返回 unknown 占位房间，
        // 调用方（UI 控制器自身的 generation fence）会忽略该结果。
        return _staleRoom(site, roomId);
      }
      _payload = payload;
      return _roomFromPayload(payload);
    } catch (e) {
      if (gen != _generation) {
        // 过期请求的异常同样吞掉，避免误伤新房间的加载状态。
        return _staleRoom(site, roomId);
      }
      rethrow;
    }
  }

  @override
  Future<List<LivePlayQuality>> getPlayQualites({
    required LiveRoom detail,
  }) async {
    final roomId = detail.normalizedRoomId;
    if (roomId.isEmpty) return const [];
    final payload = await _payloadForRoom(roomId);
    final names = payload.qualityNames;
    final qualities = <LivePlayQuality>[];
    for (var i = 0; i < names.length; i++) {
      final name = names[i];
      Object? rate;
      for (final meta in payload.availableQualities) {
        if (meta.name == name) {
          rate = meta.rate;
          break;
        }
      }
      qualities.add(
        LivePlayQuality(quality: name, data: rate, id: name, sort: i),
      );
    }
    return qualities;
  }

  @override
  Future<List<String>> getPlayUrls({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async {
    final roomId = detail.normalizedRoomId;
    if (roomId.isEmpty) return const [];
    final wanted = quality.selectionId.toString();

    var payload = _payload;
    var usable = payload != null && payload.roomId == roomId;
    if (usable && payload.partial && payload.quality != wanted) {
      // lazy 分段解析只解出 payload.quality 这一档，需按目标档补拉。
      usable = false;
    }
    if (!usable) {
      payload = await _fetchAndCache(roomId, quality: wanted);
    }

    var stream = payload!.streamByName(wanted);
    if (stream == null && !payload.partial && payload.streams.isNotEmpty) {
      // 服务端可能只回一档（名称与请求不完全一致），回退到唯一档。
      stream = payload.streamByName(
        payload.quality.isNotEmpty
            ? payload.quality
            : payload.streams.first.name,
      );
    }
    if (stream == null) return const [];
    return [for (final line in stream.lines) line.url];
  }

  @override
  Future<bool> getLiveStatus({
    required String platform,
    required String roomId,
  }) async {
    final site = platform.trim().isNotEmpty ? platform.trim() : id;
    final payload = await client.fetchRoom(
      site: site,
      room: roomId,
      mode: 'lazy',
    );
    return payload.isLive;
  }

  // ---------------------------------------------------------------------------
  // 浏览 / 分类 / 搜索
  // ---------------------------------------------------------------------------

  @override
  Future<List<LiveCategory>> getCategores(int page, int pageSize) async {
    // streaming-server /api/categories 一次返回全量分组，page/pageSize 仅保签名。
    final res = await client.fetchCategories(id);
    return [
      for (final group in res.groups)
        LiveCategory(
          id: group.id,
          name: group.name,
          children: [
            for (final item in group.list)
              LiveArea(
                platform: id,
                areaType: group.id,
                typeName: group.name,
                areaId: item.cid,
                areaName: item.name,
                areaPic: item.pic,
              ),
          ],
        ),
    ];
  }

  @override
  Future<List<LiveRoom>> getCategoryRooms(
    LiveArea category, {
    int page = 1,
    int pageSize = 30,
  }) async {
    final res = await client.fetchCategoryRooms(
      id,
      cid: category.areaId ?? '',
      page: page,
      pid: (category.areaType?.isNotEmpty ?? false) ? category.areaType : null,
    );
    return [for (final item in res.list) _roomFromBrowse(item)];
  }

  @override
  Future<List<LiveRoom>> getRecommendRooms({
    int page = 1,
    int pageSize = 30,
  }) async {
    final res = await client.fetchRecommendRooms(id, page: page);
    return [for (final item in res.list) _roomFromBrowse(item)];
  }

  @override
  Future<List<LiveRoom>> searchRooms(
    String keyword, {
    int page = 1,
    int pageSize = 30,
  }) async {
    final res = await client.search(
      site: id,
      q: keyword,
      limit: pageSize,
      type: 'rooms',
    );
    return [for (final item in res.rooms) _roomFromBrowse(item)];
  }

  @override
  Future<List<LiveAnchorItem>> searchAnchors(
    String keyword, {
    int page = 1,
    int pageSize = 30,
  }) async {
    final res = await client.search(
      site: id,
      q: keyword,
      limit: pageSize,
      type: 'anchors',
    );
    return [
      for (final anchor in res.anchors)
        LiveAnchorItem(
          roomId: anchor.roomId,
          avatar: anchor.avatar,
          userName: anchor.name,
          liveStatus: anchor.isLive,
        ),
    ];
  }

  // ---------------------------------------------------------------------------
  // 未实现能力
  // ---------------------------------------------------------------------------

  /// 弹幕通道不在此实现：E4 由 SSE（/api/{site}/danmaku/stream）+ douyu WS
  /// 直连单独提供通道矩阵，不依赖 LiveDanmaku 接口。调用即抛错。
  @override
  LiveDanmaku getDanmaku() {
    throw UnimplementedError(
      '弹幕由 platforms/danmaku 的 SSE/WS 通道实现（E4），不走 LiveDanmaku 接口',
    );
  }

  /// streaming-server 未提供醒目留言聚合端点，维持契约默认空列表。
  @override
  Future<List<LiveSuperChatMessage>> getSuperChatMessage({
    required String roomId,
  }) async {
    return const [];
  }

  // ---------------------------------------------------------------------------
  // 内部：缓存与映射
  // ---------------------------------------------------------------------------

  /// 取 roomId 对应的 payload：缓存命中（同房间）直接返回——partial payload
  /// 也含完整 available_qualities，getPlayQualites 无需补拉；
  /// getPlayUrls 对 partial 未含档位的补拉在方法内单独处理。
  /// 否则补拉（同一房间才允许写缓存，generation 推进到其它房间后不覆盖）。
  Future<RoomPayload> _payloadForRoom(String roomId) async {
    final cached = _payload;
    if (cached != null && cached.roomId == roomId) {
      return cached;
    }
    return _fetchAndCache(roomId);
  }

  Future<RoomPayload> _fetchAndCache(String roomId, {String? quality}) async {
    final payload = await client.fetchRoom(
      site: id,
      room: roomId,
      mode: 'lazy',
      quality: quality,
    );
    final current = _payload;
    // 只在缓存仍指向同一房间（未切房）时更新，防止串房覆盖。
    if (current == null || current.roomId == roomId) {
      _payload = payload;
    }
    return payload;
  }

  LiveRoom _staleRoom(String site, String roomId) {
    return LiveRoom(
      roomId: roomId,
      platform: site,
      liveStatus: LiveStatus.unknown,
      status: null,
      isRecord: false,
      title: '',
      nick: '',
      cover: '',
      avatar: '',
      watching: '0',
    );
  }

  /// RoomPayload → LiveRoom。
  LiveRoom _roomFromPayload(RoomPayload payload) {
    LiveStatus status;
    switch (payload.roomState) {
      case RoomState.live:
        status = LiveStatus.live;
      case RoomState.offline:
        status = LiveStatus.offline;
      case RoomState.replay:
        status = LiveStatus.replay;
      case RoomState.unknown:
        status = payload.isLive ? LiveStatus.live : LiveStatus.unknown;
    }
    return LiveRoom(
      roomId: payload.roomId,
      platform: payload.site.isNotEmpty ? payload.site : id,
      title: payload.title,
      nick: payload.anchorName,
      cover: payload.cover,
      avatar: payload.avatar,
      area: payload.category,
      liveStatus: status,
      status: payload.isLive,
      isRecord: payload.roomState == RoomState.replay,
    );
  }

  /// BrowseRoomItem → LiveRoom（列表/搜索共用）。
  LiveRoom _roomFromBrowse(BrowseRoomItem item) {
    return LiveRoom(
      roomId: item.roomId,
      platform: item.site.isNotEmpty ? item.site : id,
      title: item.title,
      nick: item.anchorName,
      cover: item.cover,
      avatar: item.avatar,
      area: item.category,
      watching: item.online?.toString() ?? '0',
      liveStatus: item.isLive ? LiveStatus.live : LiveStatus.offline,
      status: item.isLive,
    );
  }
}
