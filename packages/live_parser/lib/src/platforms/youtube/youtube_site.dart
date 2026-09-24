/// YouTube 站点组装:房间解析(纯 HTTP)+ 直播浏览 + live_chat 弹幕。
library;

import 'dart:async';

import 'package:http/http.dart' as http;

import '../../contracts/contracts.dart';
import '../../models/models.dart';
import '../../registry/cached_room_resolver.dart';
import '../../registry/site_display.dart';
import '../douyu/json_utils.dart';
import 'browse.dart';
import 'danmaku.dart';
import 'dlp.dart';
import 'normalize.dart';
import 'room_api.dart';

class YoutubeRoomResolver implements RoomRecoveryResolver {
  YoutubeRoomResolver(
    this._client, {
    this.dlpExtractor,
    this.dlpAvailableCheck,
  });

  final YoutubeClient _client;
  final YoutubeDlpExtractor? dlpExtractor;
  final YoutubeDlpAvailability? dlpAvailableCheck;

  /// 直播结果短缓存(对齐 SF playlistCache 20s):短时间重复解析不再拉页/跑 dlp。
  final Map<String, ({DateTime at, RoomPayload payload})> _cache = {};
  static const Duration _cacheTtl = Duration(seconds: 20);

  /// dlp 提取结果 60s 缓存(实例级):同视频切档/换偏好档不再重跑 yt-dlp
  /// 子进程(直播 HLS URL 的 expire 通常以小时计,60s 复用安全)。
  final Map<String, ({DateTime at, YoutubeDlpExtract extract})> _dlpCache = {};
  final Map<String, DateTime> _dlpValidatedAt = {};

  /// 后台校验判定不可用的视频(负缓存):本轮改用页面链,避免"dlp 地址无效 →
  /// 播放失败 → 重解析又拿到同一批无效地址"的空转。
  final Map<String, DateTime> _dlpRejectedUntil = {};

  static const Duration _dlpCacheTtl = Duration(seconds: 60);

  @override
  Future<RoomPayload> resolveRoom(RoomRequest request) async {
    final videoId = extractYoutubeVideoId(request.roomIdOrUrl);
    if (videoId == null || !isValidYoutubeVideoId(videoId)) {
      return _buildPayload(
        roomId: request.roomIdOrUrl,
        sourceUrl: request.roomIdOrUrl,
        roomState: RoomState.notFound,
        title: '无法解析 YouTube URL',
        error: '无法解析 YouTube URL',
      );
    }
    final cached = _cache[videoId];
    if (cached != null && DateTime.now().difference(cached.at) < _cacheTtl) {
      return cached.payload;
    }

    final sourceUrl = youtubeSourceUrl(videoId);
    // watch 页与 dlp 提取互不依赖,并行;dlp 内部含首档预校验。
    final ctxFuture = fetchYoutubeWatchPage(_client, videoId);
    final dlpFuture = _tryDlpExtract(videoId);
    final ctx = await ctxFuture;
    final dlpExtract = await dlpFuture;
    final dlpTiers = dlpExtract == null
        ? const <StreamQuality>[]
        : youtubeDlpQualities(dlpExtract.tiers);

    if (!ctx.hasPlayer) {
      return _buildPayload(
        roomId: videoId,
        sourceUrl: sourceUrl,
        roomState: RoomState.offline,
      );
    }

    final title = jsonText(ctx.videoDetails['title']);
    final author = jsonText(ctx.videoDetails['author']);
    final cover = _thumbnailOf(ctx.videoDetails);
    final status = jsonText(ctx.playabilityStatus['status']);

    if (status == 'LOGIN_REQUIRED' || status == 'ERROR') {
      return _buildPayload(
        roomId: videoId,
        sourceUrl: sourceUrl,
        roomState: RoomState.offline,
        title: title,
        anchorName: author,
        cover: cover,
        error: status == 'LOGIN_REQUIRED' ? '需要登录/地区限制' : '视频不可播放',
      );
    }
    if (!ctx.isLiveContent) {
      return _buildPayload(
        roomId: videoId,
        sourceUrl: sourceUrl,
        roomState: RoomState.offline,
        title: title,
        anchorName: author,
        cover: cover,
      );
    }

    // dlp 主路线:数据中心 IP 的分片强制 PO Token,页面链地址会 403,
    // yt-dlp(+Deno/EJS)签出的地址才可播;不可用时回退页面链。
    if (dlpTiers.isNotEmpty) {
      final payload = _buildPayload(
        roomId: videoId,
        sourceUrl: sourceUrl,
        roomState: RoomState.live,
        title: title,
        anchorName: author,
        cover: cover,
        streams: dlpTiers,
        startedAt: _youtubeStartedAt(dlpExtract),
      );
      _cache[videoId] = (at: DateTime.now(), payload: payload);
      // 首档地址链校验放到**后台**:它是纯前置检查,实测经代理要 ~9s
      // (master → variant → 首个分片),占冷解析一半以上。不校验也能播 ——
      // 地址真失效时播放器会报错并走恢复重解析。校验失败则给该视频打上
      // 负标记,后续解析直接走页面链兜底(不重复踩坑)。
      final firstUrl = dlpTiers.first.lines.firstOrNull?.url;
      if (firstUrl != null && !_recentlyValidated(videoId)) {
        unawaited(_validateInBackground(videoId, firstUrl));
      }
      return payload;
    }
    // 后台校验过且失败:直接走页面链,不再重试 dlp 地址。
    if (_dlpRejectedUntil[videoId] != null) {
      _dlpRejectedUntil.remove(videoId);
    }
    var ctxForPage = ctx;
    var tiers = const <StreamQuality>[];
    for (var attempt = 0; attempt < 4; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        final refreshed = await fetchYoutubeWatchPage(_client, videoId);
        if (refreshed.hasPlayer && !refreshed.isLiveContent) break;
        if (refreshed.hasPlayer) ctxForPage = refreshed;
      }

      var master = jsonText(ctxForPage.streamingData['hlsManifestUrl']);
      if (master.isEmpty) {
        master = await resolveYoutubeInnerTubeHls(_client, ctxForPage, videoId);
      }
      if (master.isEmpty) continue;
      if (!await validateYoutubeChain(_client, master)) continue;

      final content = await fetchYoutubePlaylist(_client, master);
      final variants = parseYoutubeMasterPlaylist(content, master);
      tiers = [
        StreamQuality(
          name: '自动',
          rate: 0,
          lines: [
            StreamLine(
              name: '线路',
              url: master,
              format: 'hls',
              headers: youtubePlaybackHeaders,
            ),
          ],
        ),
        ...variants,
      ];
      break;
    }

    if (tiers.isEmpty) {
      return _buildPayload(
        roomId: videoId,
        sourceUrl: sourceUrl,
        roomState: RoomState.offline,
        title: title,
        anchorName: author,
        cover: cover,
        error: '直播中，但流地址被 Google 反爬拦截（可稍后重试）',
      );
    }
    final payload = _buildPayload(
      roomId: videoId,
      sourceUrl: sourceUrl,
      roomState: RoomState.live,
      title: title,
      anchorName: author,
      cover: cover,
      streams: tiers,
    );
    _cache[videoId] = (at: DateTime.now(), payload: payload);
    return payload;
  }

  @override
  Future<RoomPayload> recoverRoom(RoomRequest request) {
    // 恢复契约(RoomRecoveryResolver):不得复用上一次的地址。本解析器有
    // 两级播放缓存(短缓存 20s + dlp 提取 60s),对外层缓存包装的恢复
    // 也只会清它自己那层,不清这里恢复就会拿到完全相同的旧线路。
    // 只清当前视频的两个播放缓存;负缓存(_dlpRejectedUntil)与后台
    // 校验时间戳(_dlpValidatedAt)语义不动 —— 前者避免恢复后立刻重蹈
    // 已判无效的 dlp 地址,后者仍按原 TTL 控制重复校验。
    final videoId = extractYoutubeVideoId(request.roomIdOrUrl);
    if (videoId != null) {
      _cache.remove(videoId);
      _dlpCache.remove(videoId);
    }
    return resolveRoom(request);
  }

  /// 是否已在 [_dlpCacheTtl] 内校验过该视频的地址链(命中则跳过重复校验)。
  bool _recentlyValidated(String videoId) {
    final at = _dlpValidatedAt[videoId];
    return at != null && DateTime.now().difference(at) < _dlpCacheTtl;
  }

  /// 后台校验 dlp 地址链:成功记时间戳;失败则作废该视频的 dlp 缓存与负标记,
  /// 使下一次解析改走页面链。
  Future<void> _validateInBackground(String videoId, String url) async {
    var ok = false;
    try {
      ok = await validateYoutubeChain(_client, url);
    } on Object {
      ok = false;
    }
    if (ok) {
      _dlpValidatedAt[videoId] = DateTime.now();
      return;
    }
    _dlpRejectedUntil[videoId] = DateTime.now();
    _dlpValidatedAt.remove(videoId);
    _dlpCache.remove(videoId);
    _cache.remove(videoId);
  }

  /// dlp 提取 + 首档预校验;任一步失败返回 null 交由页面链兜底。
  ///
  /// 注:首档链校验不再在此阻塞 —— 见 [resolveRoom] 中的后台校验。
  Future<YoutubeDlpExtract?> _tryDlpExtract(String videoId) async {
    try {
      // 后台校验刚判过不可用:本轮直接放弃 dlp,走页面链。
      final rejectedAt = _dlpRejectedUntil[videoId];
      if (rejectedAt != null &&
          DateTime.now().difference(rejectedAt) < _dlpCacheTtl) {
        return null;
      }
      final available = await (dlpAvailableCheck ?? isYoutubeDlpAvailable)();
      if (!available) return null;
      final extract = await (dlpExtractor ?? _defaultDlpExtract)(videoId);
      if (extract == null || extract.tiers.isEmpty) return null;
      return extract;
    } on Object {
      return null;
    }
  }

  Future<YoutubeDlpExtract?> _defaultDlpExtract(String videoId) async {
    final cached = _dlpCache[videoId];
    if (cached != null && DateTime.now().difference(cached.at) < _dlpCacheTtl) {
      return cached.extract;
    }
    final extract = await extractYoutubeViaDlp(videoId);
    if (extract != null) {
      _dlpCache[videoId] = (at: DateTime.now(), extract: extract);
    }
    return extract;
  }

  RoomPayload _buildPayload({
    required String roomId,
    required String sourceUrl,
    required RoomState roomState,
    String title = '',
    String anchorName = '',
    String cover = '',
    List<StreamQuality> streams = const [],
    DateTime? startedAt,
    String? error,
  }) => RoomPayload(
    site: kYoutubeSiteId,
    roomId: roomId,
    sourceUrl: sourceUrl,
    anchorName: anchorName,
    title: title,
    cover: cover,
    avatar: '',
    category: '',
    cid: roomId,
    roomState: roomState,
    streams: streams,
    availableQualities: [
      for (final stream in streams)
        QualityOption(name: stream.name, rate: stream.rate),
    ],
    startedAt: startedAt,
    source: kYoutubeSource,
    fetchedAt: DateTime.now(),
    error: error,
  );
}

DateTime? _youtubeStartedAt(YoutubeDlpExtract? extract) {
  final seconds = extract?.liveStartAtSec ?? 0;
  return seconds > 0
      ? DateTime.fromMillisecondsSinceEpoch(seconds * 1000)
      : null;
}

String _thumbnailOf(Map<String, dynamic> videoDetails) {
  final thumbnails = jsonListOf(
    jsonMapOf(videoDetails['thumbnail'])['thumbnails'],
  );
  if (thumbnails.isEmpty) return '';
  return jsonText(jsonMapOf(thumbnails.last)['url']);
}

/// YouTube 注册项;[httpClient]/[chatFetcher]/[dlpExtractor] 供测试注入。
SiteRegistration buildYoutubeRegistration({
  http.Client? httpClient,
  YoutubeClient? client,
  YoutubeChatFetcher? chatFetcher,
  YoutubeDlpExtractor? dlpExtractor,
  YoutubeDlpAvailability? dlpAvailableCheck,
}) {
  final effectiveClient = client ?? YoutubeClient(httpClient: httpClient);
  return SiteRegistration(
    id: kYoutubeSiteId,
    name: 'YouTube',
    capabilities: const SiteCapabilities(
      browse: true,
      danmaku: true,
      multiQuality: true,
      multiLine: true,
    ),
    display: kYoutubeDisplay,
    resolver: CachedRoomResolver(
      YoutubeRoomResolver(
        effectiveClient,
        dlpExtractor: dlpExtractor,
        dlpAvailableCheck: dlpAvailableCheck,
      ),
    ),
    browse: YoutubeBrowseRepository(effectiveClient.parserHttp),
    danmaku: YoutubeDanmakuConnector(
      effectiveClient.parserHttp,
      fetcher: chatFetcher,
    ),
  );
}
