/// SOOP 站点组装:房间解析 + 分类浏览 + 搜索 + 弹幕,共享一个 HTTP 实例。
library;

import 'package:http/http.dart' as http;

import '../../contracts/contracts.dart';
import '../../http/danmaku_transport.dart';
import '../../http/parser_http.dart';
import '../../models/models.dart';
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
        },
      );

  final ParserHttp parserHttp;

  void close() => parserHttp.close();
}

class SoopRoomResolver implements RoomResolver {
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
    final preferred = _matchQuality(qualities, request.preferredQuality) ??
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
    final streams = [
      for (final quality in qualities)
        if (quality.name == preferred.name)
          tier
        else
          StreamQuality(name: quality.name, rate: quality.rate, lines: const []),
    ];
    return _buildPayload(
      roomId: roomId,
      sourceUrl: sourceUrl,
      detail: detail,
      roomState: RoomState.live,
      streams: streams,
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

  /// 偏好档匹配:精确 → 双向包含(与播放侧 `_pickQuality` 同语义)。
  static SoopQuality? _matchQuality(
    List<SoopQuality> qualities,
    String? preferred,
  ) {
    final name = preferred?.trim() ?? '';
    if (name.isEmpty) return null;
    for (final quality in qualities) {
      if (quality.name == name) return quality;
    }
    for (final quality in qualities) {
      if (name.contains(quality.name) || quality.name.contains(name)) {
        return quality;
      }
    }
    return null;
  }

  RoomPayload _buildPayload({
    required String roomId,
    required String sourceUrl,
    required SoopRoomDetail detail,
    required RoomState roomState,
    List<StreamQuality> streams = const [],
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
    roomState: roomState,
    streams: streams,
    availableQualities: [
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
    resolver: SoopRoomResolver(effectiveClient),
    browse: SoopBrowseRepository(effectiveClient.parserHttp),
    search: SoopSearchRepository(effectiveClient.parserHttp),
    danmaku: SoopDanmakuConnector(
      effectiveClient.parserHttp,
      transport: danmakuTransport,
    ),
  );
}
