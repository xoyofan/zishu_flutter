/// YY 站点组装：房间解析 + 分类浏览 + 搜索。
library;

import 'package:http/http.dart' as http;

import '../../contracts/contracts.dart';
import '../../http/parser_http.dart';
import '../../models/models.dart';
import '../../registry/cached_room_resolver.dart';
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

class YyRoomResolver implements RoomResolver {
  YyRoomResolver(this._client);

  final YyClient _client;

  /// 档位流地址短缓存(60s,对齐 SF tier 缓存):切回同档/重复进房零请求。
  /// 只缓存成功结果,失败不缓存以便立即重试。
  final Map<int, ({DateTime at, StreamQuality tier})> _tierCache = {};
  static const Duration _tierTtl = Duration(seconds: 60);

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
    final cached = _tierCache[quality.gear];
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
      _tierCache[quality.gear] = (at: DateTime.now(), tier: tier);
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
        category: detail.biz,
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
