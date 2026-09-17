/// B 站站点组装:房间解析 + 浏览 + 搜索 + 弹幕共享一个 HTTP 实例与凭据缓存。
library;

import 'package:http/http.dart' as http;

import '../../http/danmaku_transport.dart';
import '../../http/parser_http.dart';
import '../../contracts/contracts.dart';
import '../../models/models.dart';
import '../../registry/cached_room_resolver.dart';
import '../../utils/header_sanitizer.dart';
import 'browse.dart';
import 'danmaku.dart';
import '../douyu/json_utils.dart';
import 'normalize.dart';
import 'room_api.dart';
import 'search.dart';
import 'wbi.dart';

/// B 站解析源标识。
const String kBilibiliSource = 'live_parser/bilibili';

/// B 站直播流(HLS/FLV)请求头:CDN 以 Referer/Origin 做防盗链,
/// 与解析请求头(BilibiliClient.defaultHeaders)同源。
/// 默认不带 Cookie —— 匿名即可取流,也避免单测噪声;
/// 若上层配置了登录 Cookie,由调用方按需追加。
final Map<String, String> bilibiliPlaybackHeaders = sanitizeHeaders(const {
  'referer': 'https://live.bilibili.com/',
  'origin': 'https://live.bilibili.com',
});

class BilibiliClient {
  BilibiliClient({
    http.Client? httpClient,
    String? cookie,
    BilibiliCredentials? credentials,
  }) : parserHttp = ParserHttp(
         client: httpClient,
         defaultHeaders: {
           'Referer': 'https://live.bilibili.com/',
           if (cookie != null && cookie.isNotEmpty) 'Cookie': cookie,
         },
       ),
       credentials = credentials ?? BilibiliCredentials();

  final ParserHttp parserHttp;
  final BilibiliCredentials credentials;

  void close() => parserHttp.close();
}

class BilibiliRoomResolver implements RoomResolver {
  BilibiliRoomResolver(this._client);

  final BilibiliClient _client;

  @override
  Future<RoomPayload> resolveRoom(RoomRequest request) async {
    final http = _client.parserHttp;
    final credentials = _client.credentials;
    final url = normalizeBilibiliUrl(request.roomIdOrUrl);
    final rid = bilibiliRoomIdFromUrl(url);

    Map<String, dynamic> info;
    try {
      info = await fetchBilibiliRoomInfo(http, credentials, rid);
    } on BilibiliApiException catch (error) {
      if (error.code == 1) {
        return _notFoundPayload(rid, url);
      }
      rethrow;
    }

    final infoUname = jsonText(
      info['uname'] ?? jsonMapOf(jsonMapOf(info['anchor_info'])['base_info'])['uname'],
    );
    final infoAvatar = bilibiliAvatarFromRoom(info);

    // live_status:0 未开播 1 直播 2 轮播;契约无 replay,轮播/未播归 offline。
    final isLive = jsonInt(info['live_status']) == 1;

    // get_anchor_in_room 只在 get_info 缺主播名/头像时兜底(通常不需要),
    // 且与 play 数据并行,不再阻塞在序列前面。
    final Future<({String uname, String face})>? anchorFuture =
        infoUname.isEmpty || infoAvatar.isEmpty
        ? () async {
            try {
              return await fetchBilibiliAnchorInRoom(http, credentials, rid);
            } on Object {
              return (uname: '', face: '');
            }
          }()
        : null;
    final Future<Map<String, dynamic>>? playFuture = isLive
        ? fetchBilibiliRoomPlayInfo(http, credentials, rid)
        : null;
    final anchor = anchorFuture == null
        ? (uname: '', face: '')
        : await anchorFuture;
    final anchorName = infoUname.isEmpty ? anchor.uname : infoUname;
    final avatar = infoAvatar.isEmpty ? anchor.face : infoAvatar;
    final base = _Base(
      rid: rid,
      sourceUrl: url,
      anchorName: anchorName,
      title: jsonText(info['title']).isEmpty ? anchorName : jsonText(info['title']),
      cover: bilibiliCoverFromRoom(info),
      avatar: avatar,
      category: jsonText(info['parent_area_name'] ?? info['area_name']),
      cid: jsonText(info['area_id'] ?? ''),
    );

    if (!isLive) {
      return _payload(base, RoomState.offline);
    }

    final data = await playFuture!;
    final qualities = bilibiliAvailableQualities(data);
    if (qualities.isEmpty) {
      throw const ParserHttpException('未获取到可播放的 B 站流地址');
    }

    final streams = <StreamQuality>[];
    for (final quality in qualities) {
      final lines = bilibiliTierLines(data, quality.qn);
      if (lines == null) continue;
      streams.add(
        StreamQuality(
          name: quality.name,
          rate: quality.qn,
          lines: [
            for (final line in lines)
              StreamLine(
                name: line.name,
                url: line.url,
                format: line.format,
                headers: bilibiliPlaybackHeaders,
              ),
          ],
        ),
      );
    }
    if (streams.isEmpty) {
      throw const ParserHttpException('未获取到可播放的 B 站流地址');
    }

    return _payload(
      base,
      RoomState.live,
      streams: streams,
      qualities: [
        for (final quality in qualities) QualityOption(name: quality.name, rate: quality.qn),
      ],
    );
  }

  RoomPayload _notFoundPayload(String rid, String url) => _payload(
    _Base(
      rid: rid,
      sourceUrl: url,
      anchorName: '',
      title: '',
      cover: '',
      avatar: '',
      category: '',
      cid: '',
    ),
    RoomState.notFound,
    error: '房间不存在',
  );

  RoomPayload _payload(
    _Base base,
    RoomState state, {
    List<StreamQuality>? streams,
    List<QualityOption>? qualities,
    String? error,
  }) {
    return RoomPayload(
      site: kBilibiliSiteId,
      roomId: base.rid,
      sourceUrl: base.sourceUrl,
      anchorName: base.anchorName,
      title: base.title,
      cover: base.cover,
      avatar: base.avatar,
      category: base.category,
      cid: base.cid,
      roomState: state,
      streams: streams ?? const [],
      availableQualities: qualities ?? const [],
      source: kBilibiliSource,
      fetchedAt: DateTime.now(),
      error: error,
    );
  }
}

class _Base {
  const _Base({
    required this.rid,
    required this.sourceUrl,
    required this.anchorName,
    required this.title,
    required this.cover,
    required this.avatar,
    required this.category,
    required this.cid,
  });

  final String rid;
  final String sourceUrl;
  final String anchorName;
  final String title;
  final String cover;
  final String avatar;
  final String category;
  final String cid;
}

/// 组装 B 站注册项;[httpClient]/[danmakuTransport]/[cookie] 供测试与登录态注入。
SiteRegistration buildBilibiliRegistration({
  http.Client? httpClient,
  BilibiliClient? client,
  DanmakuTransport? danmakuTransport,
  String? cookie,
}) {
  final effectiveClient = client ?? BilibiliClient(httpClient: httpClient, cookie: cookie);
  return SiteRegistration(
    id: kBilibiliSiteId,
    name: 'B站',
    capabilities: const SiteCapabilities(
      browse: true,
      roomSearch: true,
      anchorSearch: true,
      danmaku: true,
      multiQuality: true,
      multiLine: true,
    ),
    resolver: CachedRoomResolver(BilibiliRoomResolver(effectiveClient)),
    browse: BilibiliBrowseRepository(effectiveClient.parserHttp, effectiveClient.credentials),
    search: BilibiliSearchRepository(effectiveClient.parserHttp, effectiveClient.credentials),
    danmaku: BilibiliDanmakuConnector(
      parserHttp: effectiveClient.parserHttp,
      transport: danmakuTransport,
      credentials: effectiveClient.credentials,
    ),
  );
}
