/// 斗鱼站点组装:房间解析 + 浏览 + 搜索共享一个 HTTP 实例与密钥缓存。
library;

import 'package:http/http.dart' as http;

import '../../http/danmaku_transport.dart';
import '../../http/parser_http.dart';
import '../../contracts/contracts.dart';
import '../../models/models.dart';
import '../../registry/cached_room_resolver.dart';
import '../../utils/format_online.dart';
import 'browse.dart';
import 'danmaku.dart';
import 'encryption.dart';
import 'hls_preview.dart';
import 'json_utils.dart';
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

class DouyuRoomResolver implements RoomResolver, RoomSummaryRefresher {
  DouyuRoomResolver(this._client);

  final DouyuClient _client;

  /// 轻量刷新:betard(状态/标题/封面/分类)+ m.douyu 房间信息(热度 `hn`)
  /// + 主播资料卡(粉丝/贵宾,失败静默)。
  ///
  /// 只打三个房间信息端点 —— **不取白名单密钥、不请求 getH5PlayV1、
  /// 不做签名、不连弹幕 WS**,因此不能在关注列表定时刷新时顺带拉取流地址。
  /// 口径对齐 web `services/streaming-server/src/follow/status.ts` 的
  /// douyu 快照:`show_status == 1` 且在播时取 `hn` 作热度文案,离线一律
  /// 空串;`fansNum`/`giftCard.total` 作粉丝/贵宾文案(web 真源的贵宾
  /// 实时榜走弹幕 WS oni,此处仅取卡片回退值)。
  @override
  Future<RoomSummary> refreshRoomSummary(RoomRequest request) async {
    final parserHttp = _client.parserHttp;
    final url = normalizeDouyuUrl(request.roomIdOrUrl);
    final rid = await resolveRoomId(parserHttp, url);
    // 房间不存在时 fetchBetard 抛 RoomNotFoundException(调用方按条目隔离)。
    final room = await fetchBetard(parserHttp, rid);
    final mobile = await fetchDouyuMobileRoomInfo(parserHttp, rid);
    final anchorCard = await fetchDouyuAnchorCard(parserHttp, rid);
    final cardRoomInfo = jsonMapOf(anchorCard['roomInfo']);
    final cardFans = formatExactCount(
      cardRoomInfo['fansNum'] ?? anchorCard['fansNum'],
    );
    final cardVip = formatExactCount(
      jsonMapOf(jsonMapOf(anchorCard['functionShow'])['giftCard'])['total'],
    );

    final live = room.showStatus == 1;
    final hn = jsonText(mobile['hn']);
    final mobileTitle = jsonText(mobile['roomName']);
    final mobileAnchor = jsonText(mobile['nickname']);
    return RoomSummary(
      site: kDouyuSiteId,
      roomId: rid,
      title: mobileTitle.isNotEmpty
          ? mobileTitle
          : (room.roomName.isNotEmpty ? room.roomName : room.nickname),
      anchorName: mobileAnchor.isNotEmpty ? mobileAnchor : room.nickname,
      cid: room.cateId,
      category: room.cateName,
      // 热度只在在播时有意义;`hn` 缺失/为 0 时留空。
      online: live && hn.isNotEmpty && hn != '0' ? hn : '',
      cover: room.cover,
      followers: cardFans,
      vip: cardVip,
    );
  }

  /// getH5PlayV1 响应短缓存(60s):同房同档同 CDN 的探测/取流复用同一响应,
  /// 切档/短时间重试不再重复打播放接口;仅缓存成功响应。
  final Map<String, ({DateTime at, PlayV1Response response})> _playCache = {};
  static const Duration _playTtl = Duration(seconds: 60);

  Future<PlayV1Response> _fetchPlay({
    required String rid,
    required String rate,
    required WhiteKey white,
    required String cdn,
  }) async {
    final key = '$rid|$rate|$cdn';
    final cached = _playCache[key];
    if (cached != null && DateTime.now().difference(cached.at) < _playTtl) {
      return cached.response;
    }
    final response = await fetchH5PlayV1(
      _client.parserHttp,
      rid: rid,
      rate: rate,
      white: white,
      cdn: cdn,
    );
    if (response.error == 0) {
      _playCache[key] = (at: DateTime.now(), response: response);
    }
    return response;
  }

  /// [fetchFlvLinesForRate] 的带缓存版本:先按 (rid,rate,cdn) 回填命中,
  /// 取流后把成功响应写回缓存。
  Future<List<DouyuLineDraft>> _fetchLinesForRate({
    required String rid,
    required String rate,
    required WhiteKey white,
    required List<DouyuCdnItem> cdns,
    required Map<String, PlayV1Response> cachedResponses,
  }) async {
    for (final item in cdns) {
      final hit = _playCache['$rid|$rate|${item.cdn}'];
      if (hit != null && DateTime.now().difference(hit.at) < _playTtl) {
        cachedResponses[item.cdn] = hit.response;
      }
    }
    final drafts = await fetchFlvLinesForRate(
      http: _client.parserHttp,
      rid: rid,
      rate: rate,
      white: white,
      cdns: cdns,
      cachedResponses: cachedResponses,
    );
    for (final entry in cachedResponses.entries) {
      if (entry.value.error == 0) {
        _playCache['$rid|$rate|${entry.key}'] = (
          at: DateTime.now(),
          response: entry.value,
        );
      }
    }
    return drafts;
  }

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
    final probe = await _fetchPlay(rid: rid, rate: '0', white: white, cdn: probeCdn);
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

    final preferred = matchQualityPreference(
      multirates,
      request.preferredQuality,
      (item) => item.name,
    );

    final hlsFuture = _loadHlsPreviewUrl(rid);
    final draftsByRate = <int, List<DouyuLineDraft>>{};

    // 懒取流(对齐 SOOP resolveTier):命中偏好档且不是 rate=0 时,只取该档
    // 线路,其余档位以空线路占位供 UI 列出;连 rate=0 的其它 CDN 探测都省掉。
    // 偏好档取流失败则降级为全档枚举(播放侧 _pickQuality 仍可回退首档)。
    int? lazyRate;
    if (preferred != null && preferred.rate != 0) {
      final drafts = await _fetchLinesForRate(
        rid: rid,
        rate: '${preferred.rate}',
        white: white,
        cdns: cdns,
        cachedResponses: <String, PlayV1Response>{},
      );
      if (drafts.isNotEmpty) {
        draftsByRate[preferred.rate] = drafts;
        lazyRate = preferred.rate;
      }
    }

    if (lazyRate == null) {
      // 全档枚举/偏好档降级:补齐 rate=0 的其余 CDN 响应,再按档并行取流。
      final pending = cdns
          .where((item) => !rateZeroCache.containsKey(item.cdn))
          .toList();
      if (pending.isNotEmpty) {
        final loaded = await Future.wait([
          for (final item in pending)
            _fetchPlay(rid: rid, rate: '0', white: white, cdn: item.cdn),
        ]);
        for (var i = 0; i < pending.length; i++) {
          rateZeroCache[pending[i].cdn] = loaded[i];
        }
      }
      final primary = rateZeroCache[activeCdn] ?? rateZeroCache[probeCdn];
      if (primary == null || primary.error != 0) {
        final failure = primary != null && primary.msg.isNotEmpty
            ? primary.msg
            : (probe.msg.isNotEmpty ? probe.msg : 'getH5PlayV1 失败');
        throw ParserHttpException(failure);
      }
      final results = await Future.wait([
        for (final item in multirates)
          _fetchLinesForRate(
            rid: rid,
            rate: '${item.rate}',
            white: white,
            cdns: cdns,
            cachedResponses: item.rate == 0
                ? rateZeroCache
                : <String, PlayV1Response>{},
          ),
      ]);
      for (var i = 0; i < multirates.length; i++) {
        draftsByRate[multirates[i].rate] = results[i];
      }
    }

    final hlsUrl = await hlsFuture;
    // 媒体流请求头:按房间上下文解析一次(Referer 带房间号),整档线路共用。
    final playHeaders = douyuPlaybackHeaders(rid);
    final streams = <StreamQuality>[];
    if (lazyRate != null) {
      // 懒取流:解析出的偏好档放首位(playUrl / 播放侧回退都取 streams.first),
      // 其余档位保持原顺序以空线路占位,点击后再按该档重新解析。
      final target = multirates.firstWhere((item) => item.rate == lazyRate);
      final lines = appendHlsFallbackLine(draftsByRate[lazyRate]!, hlsUrl);
      streams.add(
        StreamQuality(
          name: _douyuTierName(target),
          rate: target.rate,
          lines: [
            for (final draft in lines)
              StreamLine(
                name: draft.name,
                url: draft.url,
                format: draft.format,
                headers: playHeaders,
              ),
          ],
        ),
      );
      for (final item in multirates) {
        if (item.rate == lazyRate) continue;
        streams.add(
          StreamQuality(name: _douyuTierName(item), rate: item.rate, lines: const []),
        );
      }
    } else {
      for (final item in multirates) {
        final drafts = draftsByRate[item.rate];
        if (drafts == null || drafts.isEmpty) continue;
        final lines = appendHlsFallbackLine(drafts, hlsUrl);
        if (lines.isEmpty) continue;
        streams.add(
          StreamQuality(
            name: _douyuTierName(item),
            rate: item.rate,
            lines: [
              for (final draft in lines)
                StreamLine(
                  name: draft.name,
                  url: draft.url,
                  format: draft.format,
                  headers: playHeaders,
                ),
            ],
          ),
        );
      }
    }
    if (streams.isEmpty) {
      throw const ParserHttpException('未获取到可播放的 douyucdn 地址');
    }

    // 懒取流:chips 仍按平台原顺序列出全部档位(占位档点击后按该档重解析);
    // 全档模式保持「列出的档 == 点得动的档」的严格同源契约。
    final availableQualities = lazyRate == null
        ? douyuAvailableQualities(streams)
        : [
            for (final item in multirates)
              QualityOption(name: _douyuTierName(item), rate: item.rate),
          ];

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
      availableQualities: availableQualities,
      startedAt: room.startedAt,
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

/// 档位展示名:上游缺名时回退 `档{rate}`。
String _douyuTierName(DouyuMultirate item) =>
    item.name.isEmpty ? '档${item.rate}' : item.name;

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
    resolver: CachedRoomResolver(DouyuRoomResolver(effectiveClient)),
    browse: DouyuBrowseRepository(effectiveClient.parserHttp),
    search: DouyuSearchRepository(effectiveClient.parserHttp),
    danmaku: DouyuDanmakuConnector(transport: danmakuTransport),
  );
}
