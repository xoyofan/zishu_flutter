/// YY 站点组装：房间解析 + 分类浏览 + 搜索。
library;

import 'package:http/http.dart' as http;

import '../../contracts/contracts.dart';
import '../../http/parser_http.dart';
import '../../models/models.dart';
import '../../registry/cached_room_resolver.dart';
import 'biz_names.dart';
import 'browse.dart';
import 'normalize.dart';
import 'room_api.dart';
import 'search.dart';

class YyClient {
  YyClient({http.Client? httpClient})
      : parserHttp = ParserHttp(
          client: httpClient,
          defaultHeaders: const {
            'Referer': 'https://www.yy.com/',
            'Origin': 'https://www.yy.com',
          },
        );

  final ParserHttp parserHttp;

  void close() => parserHttp.close();
}

class YyRoomResolver implements RoomResolver, RoomSummaryRefresher {
  YyRoomResolver(this._client);

  final YyClient _client;

  /// 档位流地址短缓存(60s,对齐 SF tier 缓存):切回同档/重复进房零请求。
  /// 只缓存成功结果,失败不缓存以便立即重试。
  ///
  /// 键 = `roomId + gear`。**必须带 roomId**:resolver 实例与注册表同生命周期,
  /// 此前只按 gear 键控,看过 A 房后再进 B 房会命中 A 房的流地址
  /// (实测表现:「不同房间进去都是同一个房间」)。
  final Map<String, ({DateTime at, StreamQuality tier})> _tierCache = {};
  static const Duration _tierTtl = Duration(seconds: 60);

  /// 轻量刷新:只打 `liveInfoDetail` 房间元信息 HTTP 接口(**官方游客 WS 已
  /// 失效,但该接口仍可用**),不打 stream-manager、不取流、不写任何缓存。
  ///
  /// 口径对齐 web `follow/status.ts` 的 yy 快照:`totalViewer` 在边缘节点间
  /// 闪变(在播房间约半数请求缺省,未开播恒为空),连取最多 3 次任一命中即
  /// 判开播;`data=null`(合法离线响应)不重试直接按离线。房间不存在抛异常。
  @override
  Future<RoomSummary> refreshRoomSummary(RoomRequest request) async {
    final roomId = normalizeYyRoomId(request.roomIdOrUrl);
    var result = await fetchYyRoomDetail(_client.parserHttp, roomId);
    if (result.notFound) {
      throw ParserHttpException('YY 房间不存在: $roomId');
    }
    var detail = result.detail;
    for (var attempt = 0; attempt < 2 && detail != null && detail.totalViewer.isEmpty; attempt++) {
      result = await fetchYyRoomDetail(_client.parserHttp, roomId);
      if (result.notFound) {
        throw ParserHttpException('YY 房间不存在: $roomId');
      }
      detail = result.detail ?? detail;
    }
    final totalViewer = detail?.totalViewer ?? '';
    return RoomSummary(
      site: kYySiteId,
      roomId: roomId,
      title: detail == null
          ? ''
          : (detail.desc.isNotEmpty ? detail.desc : detail.name),
      anchorName: detail?.name ?? '',
      // 与 resolveRoom 同口径:cid 取 ssid。
      cid: detail?.ssid ?? roomId,
      category: detail == null ? '' : (yyBizName(detail.biz) ?? detail.biz),
      // totalViewer 本就是格式化热度串("145.9万"),原样下发;离线空串。
      online: totalViewer,
      cover: detail?.thumb ?? '',
    );
  }

  @override
  Future<RoomPayload> resolveRoom(RoomRequest request) async {
    final roomId = normalizeYyRoomId(request.roomIdOrUrl);
    final sourceUrl = 'https://www.yy.com/$roomId';
    final detailResult = await fetchYyRoomDetail(_client.parserHttp, roomId);
    final detail = detailResult.detail;

    if (detail == null) {
      return RoomPayload(
        site: kYySiteId,
        roomId: roomId,
        sourceUrl: sourceUrl,
        anchorName: '',
        title: '',
        cover: '',
        avatar: '',
        category: '',
        cid: roomId,
        roomState: detailResult.notFound ? RoomState.notFound : RoomState.offline,
        streams: const [],
        availableQualities: const [],
        source: kYySource,
        fetchedAt: DateTime.now(),
        error: detailResult.notFound ? '房间不存在' : null,
      );
    }

    final probe = await fetchYyQualitiesWithProbe(_client.parserHttp, roomId);
    final qualities = probe.qualities;
    if (qualities.isEmpty) {
      return _payload(
        roomId: roomId,
        sourceUrl: sourceUrl,
        detail: detail,
        roomState: RoomState.offline,
      );
    }

    // 懒取流:命中偏好档只取该档,其余档位以空线路占位供 UI 列出;未命中或
    // 取流失败则回退全档并行枚举。
    final preferred = matchQualityPreference(
      qualities,
      request.preferredQuality,
      (quality) => quality.name,
    );
    var streams = <StreamQuality>[];
    var lazy = false;
    if (preferred != null) {
      final tier = await _buildTierCached(
        roomId,
        preferred,
        prefetched: preferred.gear == 1 ? probe.probePayload : null,
      );
      if (tier != null) {
        streams = [
          tier,
          for (final quality in qualities)
            if (quality.gear != preferred.gear)
              StreamQuality(name: quality.name, rate: quality.gear, lines: const []),
        ];
        lazy = true;
      }
    }
    if (streams.isEmpty) {
      final tiers = await Future.wait([
        for (final quality in qualities)
          _buildTierCached(
            roomId,
            quality,
            prefetched: quality.gear == 1 ? probe.probePayload : null,
          ),
      ]);
      streams = [
        for (final tier in tiers) ?tier,
      ];
    }
    if (streams.isEmpty) {
      return _payload(
        roomId: roomId,
        sourceUrl: sourceUrl,
        detail: detail,
        roomState: RoomState.offline,
      );
    }
    return _payload(
      roomId: roomId,
      sourceUrl: sourceUrl,
      detail: detail,
      roomState: RoomState.live,
      streams: streams,
      // 懒取流时 chips 保持平台原顺序;全档模式仍「列出的档 == 点得动的档」。
      qualities: lazy
          ? [
              for (final quality in qualities)
                QualityOption(name: quality.name, rate: quality.gear),
            ]
          : null,
    );
  }

  Future<StreamQuality?> _buildTierCached(
    String roomId,
    YyQuality quality, {
    Object? prefetched,
  }) async {
    final key = '$roomId\u0000${quality.gear}';
    final cached = _tierCache[key];
    if (cached != null && DateTime.now().difference(cached.at) < _tierTtl) {
      return cached.tier;
    }
    final tier = await buildYyTier(
      _client.parserHttp,
      roomId,
      quality,
      prefetched: prefetched,
    );
    if (tier != null) {
      _tierCache[key] = (at: DateTime.now(), tier: tier);
    }
    return tier;
  }

  RoomPayload _payload({
    required String roomId,
    required String sourceUrl,
    required YyRoomDetail detail,
    required RoomState roomState,
    List<StreamQuality> streams = const [],
    List<QualityOption>? qualities,
  }) => RoomPayload(
        site: kYySiteId,
        roomId: roomId,
        sourceUrl: sourceUrl,
        anchorName: detail.name,
        title: detail.desc.isNotEmpty ? detail.desc : detail.name,
        cover: detail.thumb,
        avatar: detail.avatar,
        category: yyBizName(detail.biz) ?? detail.biz,
        cid: detail.ssid,
        roomState: roomState,
        streams: streams,
        availableQualities: qualities ??
            [
              for (final stream in streams)
                QualityOption(name: stream.name, rate: stream.rate),
            ],
        source: kYySource,
        fetchedAt: DateTime.now(),
      );
}

/// YY 注册项。YY 当前只声明 resolve/browse/search，无弹幕 connector。
SiteRegistration buildYyRegistration({
  http.Client? httpClient,
  YyClient? client,
}) {
  final effectiveClient = client ?? YyClient(httpClient: httpClient);
  return SiteRegistration(
    id: kYySiteId,
    name: 'YY',
    capabilities: const SiteCapabilities(
      browse: true,
      roomSearch: true,
      anchorSearch: true,
      multiQuality: true,
      multiLine: true,
    ),
    resolver: CachedRoomResolver(YyRoomResolver(effectiveClient)),
    browse: YyBrowseRepository(effectiveClient.parserHttp),
    search: YySearchRepository(effectiveClient.parserHttp),
  );
}
