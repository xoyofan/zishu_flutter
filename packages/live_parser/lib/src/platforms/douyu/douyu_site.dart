/// 斗鱼站点组装:房间解析 + 浏览 + 搜索共享一个 HTTP 实例与密钥缓存。
library;

import 'package:http/http.dart' as http;

import '../../http/danmaku_transport.dart';
import '../../http/parser_http.dart';
import '../../contracts/contracts.dart';
import '../../models/models.dart';
import 'browse.dart';
import 'danmaku.dart';
import 'encryption.dart';
import 'hls_preview.dart';
import 'lines.dart';
import 'multirates.dart';
import 'normalize.dart';
import 'play_api.dart';
import 'room_api.dart';
import 'search.dart';

/// 斗鱼解析源标识。
const String kDouyuSource = 'live_parser/douyu';

/// 斗鱼底层客户端:白名单密钥 TTL 缓存 + HLS preview 开关。
class DouyuClient {
  DouyuClient({
    http.Client? httpClient,
    Duration whiteKeyTtl = const Duration(seconds: 60),
    this.hlsPreviewEnabled = true,
  }) : _http = ParserHttp(
         client: httpClient,
         defaultHeaders: const {'Referer': 'https://www.douyu.com/'},
       ),
       whiteKeyCache = WhiteKeyCache(ttl: whiteKeyTtl);

  final ParserHttp _http;
  final WhiteKeyCache whiteKeyCache;

  /// preview m3u8 属非公开接口,站点开关保留降级余地。
  final bool hlsPreviewEnabled;

  ParserHttp get parserHttp => _http;

  Future<WhiteKey> fetchWhiteKey() => whiteKeyCache.fetch(_http);

  void close() => _http.close();
}

class DouyuRoomResolver implements RoomResolver {
  DouyuRoomResolver(this._client);

  final DouyuClient _client;

  @override
  Future<RoomPayload> resolveRoom(RoomRequest request) async {
    final parserHttp = _client.parserHttp;
    final url = normalizeDouyuUrl(request.roomIdOrUrl);
    final rid = await resolveRoomId(parserHttp, url);

    final BetardRoom room;
    try {
      room = await fetchBetard(parserHttp, rid);
    } on RoomNotFoundException {
      return _notFoundPayload(rid, url);
    }

    var avatar = room.avatar;
    if (avatar.isEmpty) {
      avatar = await fetchRoomAvatarFallback(parserHttp, rid);
    }

    if (room.showStatus != 1) {
      return RoomPayload(
        site: kDouyuSiteId,
        roomId: rid,
        sourceUrl: url,
        anchorName: room.nickname,
        title: room.roomName.isNotEmpty ? room.roomName : room.nickname,
        cover: room.cover,
        avatar: avatar,
        category: room.cateName,
        cid: room.cateId,
        roomState: RoomState.offline,
        streams: const [],
        availableQualities: const [],
        source: kDouyuSource,
        fetchedAt: DateTime.now(),
      );
    }

    final white = await _client.fetchWhiteKey();
    const probeCdn = 'hw-h5';
    final probe = await fetchH5PlayV1(parserHttp, rid: rid, rate: '0', white: white, cdn: probeCdn);
    if (probe.error != 0) {
      throw ParserHttpException(
        probe.msg.isNotEmpty ? probe.msg : 'getH5PlayV1 失败',
      );
    }
    final probeData = probe.data;
    final multirates = probeData?.multirates ?? const <DouyuMultirate>[];
    if (multirates.isEmpty) {
      throw const ParserHttpException('未返回 multirates 档位信息');
    }

    final cdns = parseDouyuCdnList(probeData);
    final activeCdn = preferredDouyuCdnCode(cdns, probeCdn);
    final rateZeroCache = <String, PlayV1Response>{probeCdn: probe};

    final pending = cdns.where((item) => !rateZeroCache.containsKey(item.cdn)).toList();
    final loaded = await Future.wait([
      _loadHlsPreviewUrl(rid),
      for (final item in pending)
        fetchH5PlayV1(parserHttp, rid: rid, rate: '0', white: white, cdn: item.cdn),
    ]);
    final hlsUrl = loaded.first as String;
    for (var i = 0; i < pending.length; i++) {
      rateZeroCache[pending[i].cdn] = loaded[i + 1] as PlayV1Response;
    }
    final primary = rateZeroCache[activeCdn] ?? rateZeroCache[probeCdn];
    if (primary == null || primary.error != 0) {
      final failure = primary != null && primary.msg.isNotEmpty
          ? primary.msg
          : (probe.msg.isNotEmpty ? probe.msg : 'getH5PlayV1 失败');
      throw ParserHttpException(failure);
    }

    final streams = <StreamQuality>[];
    for (final item in multirates) {
      final rate = '${item.rate}';
      final drafts = await fetchFlvLinesForRate(
        http: parserHttp,
        rid: rid,
        rate: rate,
        white: white,
        cdns: cdns,
        cachedResponses: rate == '0'
            ? rateZeroCache
            : <String, PlayV1Response>{},
      );
      if (drafts.isEmpty) continue;
      final lines = appendHlsLine(drafts, hlsUrl);
      streams.add(
        StreamQuality(
          name: item.name.isEmpty ? '档${item.rate}' : item.name,
          rate: item.rate,
          lines: [
            for (final draft in lines)
              StreamLine(name: draft.name, url: draft.url, format: draft.format),
          ],
        ),
      );
    }
    if (streams.isEmpty) {
      throw const ParserHttpException('未获取到可播放的 douyucdn 地址');
    }

    return RoomPayload(
      site: kDouyuSiteId,
      roomId: rid,
      sourceUrl: url,
      anchorName: room.nickname,
      title: room.roomName.isNotEmpty ? room.roomName : room.nickname,
      cover: room.cover,
      avatar: avatar,
      category: room.cateName,
      cid: room.cateId,
      roomState: RoomState.live,
      streams: streams,
      availableQualities: douyuAvailableQualities(multirates),
      source: kDouyuSource,
      fetchedAt: DateTime.now(),
    );
  }

  RoomPayload _notFoundPayload(String rid, String url) => RoomPayload(
    site: kDouyuSiteId,
    roomId: rid,
    sourceUrl: url,
    anchorName: '',
    title: '',
    cover: '',
    avatar: '',
    category: '',
    cid: '',
    roomState: RoomState.notFound,
    streams: const [],
    availableQualities: const [],
    source: kDouyuSource,
    fetchedAt: DateTime.now(),
    error: '房间不存在',
  );

  /// preview m3u8 属非公开接口,任何失败都静默降级为纯 FLV。
  Future<String> _loadHlsPreviewUrl(String rid) async {
    if (!_client.hlsPreviewEnabled) return '';
    try {
      final preview = await fetchHlsH5Preview(_client.parserHttp, rid: rid);
      if (preview.error != 0) return '';
      final url = hlsFromPreviewData(preview.data);
      return isDouyuHlsUrl(url) ? url : '';
    } on ParserHttpException {
      return '';
    }
  }
}

/// 组装斗鱼注册项;[httpClient] 供测试注入 fake。
SiteRegistration buildDouyuRegistration({
  http.Client? httpClient,
  DouyuClient? client,
  DanmakuTransport? danmakuTransport,
}) {
  final effectiveClient = client ?? DouyuClient(httpClient: httpClient);
  return SiteRegistration(
    id: kDouyuSiteId,
    name: '斗鱼',
    capabilities: const SiteCapabilities(
      browse: true,
      roomSearch: true,
      anchorSearch: true,
      danmaku: true,
      multiQuality: true,
      multiLine: true,
    ),
    resolver: DouyuRoomResolver(effectiveClient),
    browse: DouyuBrowseRepository(effectiveClient.parserHttp),
    search: DouyuSearchRepository(effectiveClient.parserHttp),
    danmaku: DouyuDanmakuConnector(transport: danmakuTransport),
  );
}
