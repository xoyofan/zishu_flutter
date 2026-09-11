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

  /// 档位流地址短缓存(对齐 SF 服务层 tier 缓存 60s):assign/aid 结果在短时间
  /// 重复进房时直接复用,热路径 0 请求。
  final Map<String, ({DateTime at, List<StreamQuality> streams})> _tierCache = {};
  static const Duration _tierTtl = Duration(seconds: 60);

  /// 全档取流封顶(SF MAX_TIERS=4),避免长尾档位放大请求数。
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

    final now = DateTime.now();
    final cachedTiers = _tierCache[roomId];
    if (cachedTiers != null &&
        now.difference(cachedTiers.at) < _tierTtl &&
        cachedTiers.streams.isNotEmpty) {
      return _buildPayload(
        roomId: roomId,
        sourceUrl: sourceUrl,
        detail: detail,
        roomState: RoomState.live,
        streams: cachedTiers.streams,
      );
    }

    // 全档并行取流(SF 同款 Promise.all;单档失败隔离)。
    final tiers = await Future.wait([
      for (final quality in detail.qualities.take(_maxTiers))
        buildSoopTier(_client.parserHttp, detail, quality),
    ]);
    final streams = [
      for (final tier in tiers) ?tier,
    ];
    if (streams.isEmpty) {
      return _buildPayload(
        roomId: roomId,
        sourceUrl: sourceUrl,
        detail: detail,
        roomState: RoomState.offline,
        error: '未获取到可播放地址',
      );
    }
    _tierCache[roomId] = (at: DateTime.now(), streams: streams);
    return _buildPayload(
      roomId: roomId,
      sourceUrl: sourceUrl,
      detail: detail,
      roomState: RoomState.live,
      streams: streams,
    );
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
