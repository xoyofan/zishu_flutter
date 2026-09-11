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

  @override
  Future<RoomPayload> resolveRoom(RoomRequest request) async {
    final roomId = normalizeSoopRoomId(request.roomIdOrUrl);
    final sourceUrl = soopSourceUrl(roomId);
    final payload = await fetchSoopPlayerApi(_client.parserHttp, roomId);
    final detail = parseSoopRoomDetail(payload, roomId);

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

    final streams = <StreamQuality>[];
    for (final quality in detail.qualities) {
      final tier = await buildSoopTier(_client.parserHttp, detail, quality);
      if (tier != null) streams.add(tier);
    }
    if (streams.isEmpty) {
      return _buildPayload(
        roomId: roomId,
        sourceUrl: sourceUrl,
        detail: detail,
        roomState: RoomState.offline,
        error: '未获取到可播放地址',
      );
    }
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
