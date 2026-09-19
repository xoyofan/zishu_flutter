/// 快手站点组装:房间解析 + 分类浏览 + feed 弹幕,共享一个 HTTP 实例。
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../contracts/contracts.dart';
import '../../http/parser_http.dart';
import '../../models/models.dart';
import '../../registry/cached_room_resolver.dart';
import 'browse.dart';
import 'danmaku.dart';
import 'normalize.dart';
import 'room_api.dart';
import 'search.dart';

/// 快手底层客户端:持有会话 cookie(房间页 Set-Cookie 透传后续请求)。
class KuaishouClient {
  KuaishouClient({http.Client? httpClient})
    : parserHttp = ParserHttp(client: httpClient);

  final ParserHttp parserHttp;

  String _cookie = '';

  String get cookie => _cookie;

  /// 拉取并解析房间页(同时捕获上游下发的会话 cookie)。
  Future<KuaishouRoomDetail> fetchRoom(String roomId) async {
    final response = await parserHttp.get(
      Uri.parse(kuaishouSourceUrl(roomId)),
      headers: kuaishouHeaders(cookie: _cookie),
    );
    _captureCookie(response.headers['set-cookie']);
    return parseKuaishouInitialState(
      utf8.decode(response.bodyBytes),
      fallbackRoomId: roomId,
    );
  }

  Future<String> fetchLiveStreamId(String roomId) async =>
      (await fetchRoom(roomId)).liveStreamId;

  void _captureCookie(String? setCookie) {
    if (setCookie == null || setCookie.trim().isEmpty) return;
    final added = <String>[];
    // 仅取 name=value;按「逗号 + 新 cookie 名」切分,避免拆坏 Expires 日期。
    for (final part in setCookie.split(RegExp(r',(?=[^;,=\s]+=)'))) {
      final pair = part.split(';').first.trim();
      if (pair.contains('=')) added.add(pair);
    }
    if (added.isEmpty) return;
    final existing = _cookie
        .split(';')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    for (final pair in added) {
      final name = pair.substring(0, pair.indexOf('='));
      existing.removeWhere((item) => item.startsWith('$name='));
      existing.add(pair);
    }
    _cookie = existing.join('; ');
  }

  void close() => parserHttp.close();
}

class KuaishouRoomResolver implements RoomResolver, RoomSummaryRefresher {
  KuaishouRoomResolver(this._client);

  final KuaishouClient _client;

  /// 轻量刷新:只拉一次房间页 SSR(`__INITIAL_STATE__`,与 web `load_meta`
  /// 同源的最轻元信息接口,快手无免签名的 JSON 房间接口),**不解析
  /// playUrls、不构造任何播放线路**。
  ///
  /// 口径对齐 web 关注快照的 kuaishou 语义:`isLiving` 判在播,热度取
  /// `watchingCount`(detail 构建时已 formatOnlineCount);离线一律空串。
  @override
  Future<RoomSummary> refreshRoomSummary(RoomRequest request) async {
    final roomId = normalizeKuaishouRoomId(request.roomIdOrUrl);
    final KuaishouRoomDetail detail;
    try {
      detail = await _client.fetchRoom(roomId);
    } on FormatException {
      throw ParserHttpException('快手房间不存在: $roomId');
    }
    return RoomSummary(
      site: kKuaishouSiteId,
      roomId: detail.roomId.isNotEmpty ? detail.roomId : roomId,
      title: detail.title.isNotEmpty ? detail.title : detail.anchorName,
      anchorName: detail.anchorName,
      // 与 resolveRoom 同口径:快手无二级分类 id,cid 即房间号。
      cid: roomId,
      category: detail.category,
      // 离线(或观看数字段缺失)一律空串,契约以「online 非空」作在播判据。
      online: detail.isLive ? detail.viewers : '',
      cover: detail.cover,
    );
  }

  @override
  Future<RoomPayload> resolveRoom(RoomRequest request) async {
    final roomId = normalizeKuaishouRoomId(request.roomIdOrUrl);
    final sourceUrl = kuaishouSourceUrl(roomId);

    final KuaishouRoomDetail detail;
    try {
      detail = await _client.fetchRoom(roomId);
    } on FormatException {
      return _buildPayload(
        roomId: roomId,
        sourceUrl: sourceUrl,
        detail: null,
        roomState: RoomState.notFound,
        error: '快手房间不存在或已下播',
      );
    }

    if (!detail.isLive) {
      return _buildPayload(
        roomId: roomId,
        sourceUrl: sourceUrl,
        detail: detail,
        roomState: RoomState.offline,
      );
    }

    final streams = parseKuaishouQualities(detail.playUrls);
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
    required KuaishouRoomDetail? detail,
    required RoomState roomState,
    List<StreamQuality> streams = const [],
    String? error,
  }) => RoomPayload(
    site: kKuaishouSiteId,
    roomId: roomId,
    sourceUrl: sourceUrl,
    anchorName: detail?.anchorName ?? '',
    title: detail?.title ?? '',
    cover: detail?.cover ?? '',
    avatar: detail?.avatar ?? '',
    category: detail?.category ?? '',
    cid: roomId,
    roomState: roomState,
    streams: streams,
    availableQualities: [
      for (final stream in streams)
        QualityOption(name: stream.name, rate: stream.rate),
    ],
    source: kKuaishouSource,
    fetchedAt: DateTime.now(),
    error: error,
  );
}

/// 快手注册项;[httpClient] 与 [streamIdFetcher]/[feedFetcher] 供测试注入。
SiteRegistration buildKuaishouRegistration({
  http.Client? httpClient,
  KuaishouClient? client,
  KuaishouLiveStreamIdFetcher? streamIdFetcher,
  KuaishouFeedFetcher? feedFetcher,
}) {
  final effectiveClient = client ?? KuaishouClient(httpClient: httpClient);
  return SiteRegistration(
    id: kKuaishouSiteId,
    name: '快手',
    capabilities: const SiteCapabilities(
      browse: true,
      danmaku: true,
      multiQuality: true,
      multiLine: true,
    ),
    resolver: CachedRoomResolver(KuaishouRoomResolver(effectiveClient)),
    browse: KuaishouBrowseRepository(effectiveClient.parserHttp),
    search: const KuaishouSearchRepository(),
    danmaku: KuaishouDanmakuConnector(
      effectiveClient.parserHttp,
      streamIdFetcher: streamIdFetcher,
      feedFetcher: feedFetcher,
    ),
  );
}
