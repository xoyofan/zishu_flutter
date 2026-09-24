/// SOOP 站点组装:房间解析 + 分类浏览 + 搜索 + 弹幕,共享一个 HTTP 实例。
library;

import 'package:http/http.dart' as http;

import '../../contracts/contracts.dart';
import '../../http/danmaku_transport.dart';
import '../../http/parser_http.dart';
import '../../models/models.dart';
import '../../registry/cached_room_resolver.dart';
import '../../registry/site_display.dart';
import '../../utils/format_online.dart';
import 'browse.dart';
import 'danmaku.dart';
import 'normalize.dart';
import 'room_api.dart';
import 'search.dart';

class SoopClient {
  SoopClient({http.Client? httpClient})
    : parserHttp = ParserHttp(
        client: httpClient,
        defaultHeaders: const {
          'Referer': 'https://www.sooplive.co.kr/',
          'Origin': 'https://www.sooplive.co.kr',
          // 与 lang=zh_CN 搭配 categoryList 才返回中文分类名(缺该头时上游仍
          // 返回韩文,web 真源 soop.ts HEADERS 同款)。
          'Accept-Language': 'zh-CN,zh;q=0.9',
        },
      );

  final ParserHttp parserHttp;

  void close() => parserHttp.close();
}

class SoopRoomResolver implements RoomResolver, RoomSummaryRefresher {
  SoopRoomResolver(this._client);

  final SoopClient _client;

  /// 房间详情短缓存(对齐 SF soopCache:进房重试/短时间回访不再打 player_live_api)。
  final Map<String, ({DateTime at, SoopRoomDetail detail})> _detailCache = {};
  static const Duration _detailTtl = Duration(seconds: 60);

  /// 档位流地址短缓存(对齐 SF 服务层 tier 缓存 60s):按档缓存 assign/aid 结果,
  /// 懒取流后短时间切回同档/重复进房零请求。
  final Map<String, ({DateTime at, Map<String, StreamQuality> byName})> _tierCache = {};
  static const Duration _tierTtl = Duration(seconds: 60);

  /// 档位列表封顶(SF MAX_TIERS=4),避免长尾档位放大 UI/缓存。
  static const int _maxTiers = 4;

  /// 轻量刷新:只打一次 `player_live_api(type=live)` 房间信息(**绕开
  /// `_detailCache` 也不写任何缓存**(刷新就是为了拿最新状态)),在播再并行
  /// 补 dashboard(粉丝/订阅)与分类列表观看数,不做 assign/aid 取流。
  ///
  /// 口径对齐 web `follow/status.ts` 的 soop 快照:
  /// - **在播只认 `RESULT == 1`**;观看数只在在播补(离线房间无观看数
  ///   语义,空串在播判据);
  /// - 观看数取自分类列表 API(`fetchSoopCategoryViewers`,`player_live_api`
  ///   已不下发观看数字段,CTUSER 是占位值),未命中/失败回退
  ///   [kSoopLiveOnlineFallback] —— 宿主以「online 非空」为在播判据,
  ///   空串会把在播房间刷成离线(2026-09 关注页 soop 全离线的根因);
  /// - 粉丝/订阅取 `fetchSoopDashboard`(`upd.fanCnt`/`subscription.total`,
  ///   web formatCount 口径:完整数字);与开播状态无关,离线/受限(-6)
  ///   也补 dashboard(播放页主播卡对离线房间同样展示;dashboard 失败
  ///   静默为空,不伪造)。
  /// 封禁(-2)按「房间不存在」抛异常。
  @override
  Future<RoomSummary> refreshRoomSummary(RoomRequest request) async {
    final roomId = normalizeSoopRoomId(request.roomIdOrUrl);
    final payload = await fetchSoopPlayerApi(_client.parserHttp, roomId);
    final detail = parseSoopRoomDetail(payload, roomId);
    if (detail.isBanned) {
      throw ParserHttpException('房间已被封禁: $roomId');
    }
    if (!detail.isLive) {
      // 离线/受限也补 dashboard:粉丝/订阅与开播状态无关(2026-09 探针实测
      // 离线房间 dashboard 照常 200 且 upd.fanCnt / subscription.total 齐全),
      // 播放页主播卡对离线房间同样要展示;只把 online 留空(在播判据),
      // 也不补分类列表观看数(离线房间无观看数语义)。
      final dashboard = await fetchSoopDashboard(_client.parserHttp, roomId);
      return RoomSummary(
        site: kSoopSiteId,
        roomId: detail.roomId.isNotEmpty ? detail.roomId : roomId,
        title: detail.title.isNotEmpty ? detail.title : detail.nick,
        anchorName: detail.nick,
        // 与 resolveRoom 同口径:SOOP 无二级分类 id,cid 即房间号。
        cid: roomId,
        category: detail.category,
        online: '',
        cover: soopCoverUrl(detail.bno),
        // 头像:station LOGO 确定性 URL(web fetchSoopRoomStats 同源)。
        avatar: soopAvatarUrl(detail.roomId),
        followers: formatExactCount(dashboard.fans),
        // SOOP 的 vip 列在 web 真源是「订阅」(ROOM_STAT_COLUMNS.soop)。
        vip: formatExactCount(dashboard.subscribers),
        startedAt: dashboard.startedAt,
        roomState: RoomState.offline,
      );
    }
    final results = await Future.wait<Object?>([
      fetchSoopDashboard(_client.parserHttp, roomId),
      fetchSoopCategoryViewers(_client.parserHttp, roomId, detail.cateNo),
    ]);
    final dashboard =
        results[0] as ({int fans, int subscribers, DateTime? startedAt});
    final viewers = results[1] as int;
    return RoomSummary(
      site: kSoopSiteId,
      roomId: detail.roomId.isNotEmpty ? detail.roomId : roomId,
      title: detail.title.isNotEmpty ? detail.title : detail.nick,
      anchorName: detail.nick,
      // 与 resolveRoom 同口径:SOOP 无二级分类 id,cid 即房间号。
      cid: roomId,
      category: detail.category,
      // 在播:观看数缺失时给兜底文案而非空串(宿主在播判据);
      // 有真实观看数时经 formatOnlineCount 展示。
      online: viewers > 0
          ? formatOnlineCount(viewers)
          : kSoopLiveOnlineFallback,
      cover: soopCoverUrl(detail.bno),
      // 头像:station LOGO 确定性 URL(web fetchSoopRoomStats 同源)。
      avatar: soopAvatarUrl(detail.roomId),
      followers: formatExactCount(dashboard.fans),
      // SOOP 的 vip 列在 web 真源是「订阅」(ROOM_STAT_COLUMNS.soop)。
      vip: formatExactCount(dashboard.subscribers),
      startedAt: dashboard.startedAt,
      roomState: RoomState.live,
    );
  }

  @override
  Future<RoomPayload> resolveRoom(RoomRequest request) async {
    final roomId = normalizeSoopRoomId(request.roomIdOrUrl);
    final sourceUrl = soopSourceUrl(roomId);

    final cached = _detailCache[roomId];
    final SoopRoomDetail detail;
    if (cached != null && DateTime.now().difference(cached.at) < _detailTtl) {
      detail = cached.detail;
    } else {
      final payload = await fetchSoopPlayerApi(_client.parserHttp, roomId);
      detail = parseSoopRoomDetail(payload, roomId);
      _detailCache[roomId] = (at: DateTime.now(), detail: detail);
    }

    if (detail.isBanned) {
      return _buildPayload(
        roomId: roomId,
        sourceUrl: sourceUrl,
        detail: detail,
        roomState: RoomState.notFound,
        error: '房间已被封禁',
      );
    }
    if (!detail.isLive) {
      final error = switch (detail.resultCode) {
        kSoopResultOffline => null,
        kSoopResultNeedLogin => '该房间需要登录(SOOP 受限直播)',
        _ => 'SOOP 返回业务码 ${detail.resultCode}',
      };
      return _buildPayload(
        roomId: roomId,
        sourceUrl: sourceUrl,
        detail: detail,
        roomState: RoomState.offline,
        error: error,
      );
    }

    // 懒取流(对齐 SF resolveTier):只取偏好档(默认清晰度),其余档位以空线路
    // 占位供 UI 列出;用户切档时由播放侧带新的 preferredQuality 重新解析,再取该档。
    final qualities = detail.qualities.take(_maxTiers).toList();
    final preferred =
        matchQualityPreference(
          qualities,
          request.preferredQuality,
          (quality) => quality.name,
        ) ??
        (qualities.isEmpty ? null : qualities.first);
    if (preferred == null) {
      return _buildPayload(
        roomId: roomId,
        sourceUrl: sourceUrl,
        detail: detail,
        roomState: RoomState.offline,
        error: '未获取到可播放地址',
      );
    }

    final tier = await _fetchTier(roomId, detail, preferred);
    if (tier == null) {
      return _buildPayload(
        roomId: roomId,
        sourceUrl: sourceUrl,
        detail: detail,
        roomState: RoomState.offline,
        error: '未获取到可播放地址',
      );
    }
    // 偏好档放首位(playUrl / 播放侧回退都取 streams.first),其余档位原顺序占位;
    // availableQualities 保持平台原顺序(chips 顺序不因默认档变化)。
    final streams = [
      tier,
      for (final quality in qualities)
        if (quality.name != preferred.name)
          StreamQuality(name: quality.name, rate: quality.rate, lines: const []),
    ];
    return _buildPayload(
      roomId: roomId,
      sourceUrl: sourceUrl,
      detail: detail,
      roomState: RoomState.live,
      streams: streams,
      qualities: [
        for (final quality in qualities)
          QualityOption(name: quality.name, rate: quality.rate),
      ],
    );
  }

  /// 取某档流地址(命中 60s 档位缓存则 0 请求)。
  Future<StreamQuality?> _fetchTier(
    String roomId,
    SoopRoomDetail detail,
    SoopQuality quality,
  ) async {
    final cached = _tierCache[roomId];
    if (cached != null && DateTime.now().difference(cached.at) < _tierTtl) {
      final hit = cached.byName[quality.name];
      if (hit != null) return hit;
    } else {
      _tierCache[roomId] = (at: DateTime.now(), byName: {});
    }
    final tier = await buildSoopTier(_client.parserHttp, detail, quality);
    if (tier != null) {
      _tierCache[roomId]!.byName[quality.name] = tier;
    }
    return tier;
  }

  RoomPayload _buildPayload({
    required String roomId,
    required String sourceUrl,
    required SoopRoomDetail detail,
    required RoomState roomState,
    List<StreamQuality> streams = const [],
    List<QualityOption>? qualities,
    String? error,
  }) => RoomPayload(
    site: kSoopSiteId,
    roomId: roomId,
    sourceUrl: sourceUrl,
    anchorName: detail.nick,
    title: detail.title.isNotEmpty ? detail.title : detail.nick,
    cover: soopCoverUrl(detail.bno),
    avatar: soopAvatarUrl(detail.roomId),
    category: detail.category,
    cid: roomId,
    // cid 是房间号(soop 无二级分类 id);真实分类号单独透出,收藏分类
    // 等场景按 cateNo 取,不得拿 cid 冒充。
    cateNo: detail.cateNo,
    roomState: roomState,
    streams: streams,
    availableQualities: qualities ??
        [
          for (final stream in streams)
            QualityOption(name: stream.name, rate: stream.rate),
        ],
    source: kSoopSource,
    fetchedAt: DateTime.now(),
    error: error,
  );
}

/// SOOP 注册项;[httpClient] 与 [danmakuTransport] 供测试注入 fake。
SiteRegistration buildSoopRegistration({
  http.Client? httpClient,
  SoopClient? client,
  DanmakuTransport? danmakuTransport,
}) {
  final effectiveClient = client ?? SoopClient(httpClient: httpClient);
  return SiteRegistration(
    id: kSoopSiteId,
    name: 'SOOP',
    capabilities: const SiteCapabilities(
      browse: true,
      roomSearch: true,
      anchorSearch: true,
      danmaku: true,
      multiQuality: true,
      multiLine: true,
    ),
    display: kSoopDisplay,
    resolver: CachedRoomResolver(SoopRoomResolver(effectiveClient)),
    browse: SoopBrowseRepository(effectiveClient.parserHttp),
    search: SoopSearchRepository(effectiveClient.parserHttp),
    danmaku: SoopDanmakuConnector(
      effectiveClient.parserHttp,
      transport: danmakuTransport,
    ),
  );
}
