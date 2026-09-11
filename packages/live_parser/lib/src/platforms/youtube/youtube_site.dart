/// YouTube 站点组装:房间解析(纯 HTTP)+ 直播浏览 + live_chat 弹幕。
library;

import 'package:http/http.dart' as http;

import '../../contracts/contracts.dart';
import '../../models/models.dart';
import '../douyu/json_utils.dart';
import 'browse.dart';
import 'danmaku.dart';
import 'dlp.dart';
import 'normalize.dart';
import 'room_api.dart';

class YoutubeRoomResolver implements RoomResolver {
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
    final dlpFuture = _tryDlpTiers(videoId);
    final ctx = await ctxFuture;
    final dlpTiers = await dlpFuture;

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
    if (dlpTiers != null && dlpTiers.isNotEmpty) {
      final payload = _buildPayload(
        roomId: videoId,
        sourceUrl: sourceUrl,
        roomState: RoomState.live,
        title: title,
        anchorName: author,
        cover: cover,
        streams: dlpTiers,
      );
      _cache[videoId] = (at: DateTime.now(), payload: payload);
      return payload;
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
          lines: [StreamLine(name: '线路', url: master, format: 'hls')],
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

  /// dlp 提取 + 首档预校验;任一步失败返回 null 交由页面链兜底。
  Future<List<StreamQuality>?> _tryDlpTiers(String videoId) async {
    try {
      final available = await (dlpAvailableCheck ?? isYoutubeDlpAvailable)();
      if (!available) return null;
      final extract = await (dlpExtractor ?? _defaultDlpExtract)(videoId);
      if (extract == null || extract.tiers.isEmpty) return null;
      final firstUrl = extract.tiers.first.url;
      if (!await validateYoutubeChain(_client, firstUrl)) return null;
      return youtubeDlpQualities(extract.tiers);
    } on Object {
      return null;
    }
  }

  Future<YoutubeDlpExtract?> _defaultDlpExtract(String videoId) =>
      extractYoutubeViaDlp(videoId);

  RoomPayload _buildPayload({
    required String roomId,
    required String sourceUrl,
    required RoomState roomState,
    String title = '',
    String anchorName = '',
    String cover = '',
    List<StreamQuality> streams = const [],
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
    source: kYoutubeSource,
    fetchedAt: DateTime.now(),
    error: error,
  );
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
    resolver: YoutubeRoomResolver(
      effectiveClient,
      dlpExtractor: dlpExtractor,
      dlpAvailableCheck: dlpAvailableCheck,
    ),
    browse: YoutubeBrowseRepository(effectiveClient.parserHttp),
    danmaku: YoutubeDanmakuConnector(
      effectiveClient.parserHttp,
      fetcher: chatFetcher,
    ),
  );
}
