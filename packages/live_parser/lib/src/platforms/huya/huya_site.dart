/// 虎牙站点组装:房间解析 + 浏览 + 搜索 + 弹幕共享一个 HTTP 实例。
library;

import 'package:http/http.dart' as http;

import '../../http/danmaku_transport.dart';
import '../../http/parser_http.dart';
import '../../contracts/contracts.dart';
import '../../models/models.dart';
import '../../registry/cached_room_resolver.dart';
import 'browse.dart';
import 'danmaku.dart';
import '../douyu/json_utils.dart';
import 'normalize.dart';
import 'room_api.dart';
import 'search.dart';

/// 虎牙解析源标识。
const String kHuyaSource = 'live_parser/huya';

class HuyaClient {
  HuyaClient({http.Client? httpClient})
    : parserHttp = ParserHttp(
        client: httpClient,
        defaultHeaders: const {'Referer': 'https://www.huya.com/'},
      );

  final ParserHttp parserHttp;

  void close() => parserHttp.close();
}

class HuyaRoomResolver implements RoomResolver {
  HuyaRoomResolver(this._client);

  final HuyaClient _client;

  @override
  Future<RoomPayload> resolveRoom(RoomRequest request) async {
    final http = _client.parserHttp;
    final url = normalizeHuyaUrl(request.roomIdOrUrl);
    final rid = await resolveHuyaNumericRoomId(http, url);
    final canonicalUrl = 'https://www.huya.com/$rid';

    // 页面与 profile 互不依赖(仅需 rid):并行发,页面失败仍可用 profile 判三态。
    final profileFuture = fetchHuyaProfileBrief(http, rid)..ignore();
    HuyaWebStreamData? webData;
    try {
      webData = await fetchHuyaWebStreamData(http, canonicalUrl);
    } on ParserHttpException catch (error) {
      // 页面缺失(如房间不存在)时交给 profileRoom 判定三态。
      if (error.statusCode == null) rethrow;
    }
    final profile = await profileFuture;
    final profileData = profile.data;

    final gameInfo = webData?.gameLiveInfo ?? const <String, dynamic>{};
    final anchorName = jsonText(gameInfo['nick']).isNotEmpty
        ? jsonText(gameInfo['nick'])
        : _profileAnchorName(profileData);
    final title = _firstText([gameInfo['introduction'], gameInfo['roomName']], anchorName);
    final cover = httpsHuyaUrl(jsonText(gameInfo['screenshot']));

    final baseInfo = _baseRoomInfo(
      rid: rid,
      sourceUrl: url,
      anchorName: anchorName,
      title: title,
      cover: cover,
      avatar: profile.avatar,
      category: jsonText(gameInfo['gameFullName']),
      cid: jsonText(gameInfo['gid']),
      isLive: false,
    );

    // 页面无流数据:三态判定完全依赖 profileRoom。
    if (webData == null || webData.streamInfoList.isEmpty) {
      final appStreams = _appFallbackStreams(profileData);
      if (appStreams == null) {
        if (profileData == null && webData == null) {
          return _payload(baseInfo, RoomState.notFound, error: '房间不存在');
        }
        return _payload(baseInfo, RoomState.offline);
      }
      return _payload(
        baseInfo,
        RoomState.live,
        streams: appStreams,
        qualities: const [HuyaQualityItem(name: '默认', rate: 0)],
      );
    }

    final qualities = huyaQualityItems(webData);
    final streams = <StreamQuality>[];
    for (final quality in qualities) {
      final lines = <StreamLine>[];
      for (final streamInfo in webData.streamInfoList) {
        final lineName = huyaLineName(streamInfo);
        final hls = buildHuyaHlsUrl(streamInfo, quality.rate);
        final flv = buildHuyaFlvUrl(streamInfo, quality.rate);
        if (hls != null) {
          lines.add(StreamLine(name: '$lineName HLS', url: hls, format: 'hls'));
        }
        if (flv != null) {
          lines.add(StreamLine(name: '$lineName FLV', url: flv, format: 'flv'));
        }
      }
      if (lines.isNotEmpty) {
        streams.add(StreamQuality(name: quality.name, rate: quality.rate, lines: lines));
      }
    }
    if (streams.isEmpty) {
      throw const ParserHttpException('未获取到可播放的虎牙 FLV 地址');
    }

    return _payload(
      baseInfo,
      RoomState.live,
      streams: streams,
      qualities: qualities,
    );
  }

  /// profileRoom 流列表兜底(TX 优先,ctype/fs 换 webh5 参数)。
  List<StreamQuality>? _appFallbackStreams(Map<String, dynamic>? profileData) {
    if (profileData == null) return null;
    if (huyaRoomState(profileData, null) != HuyaRoomState.live) return null;
    final baseList = jsonMapOfList(jsonMapOf(profileData['stream'])['baseSteamInfoList']);
    if (baseList.isEmpty) return null;

    String? selectedFlv;
    String? selectedHls;
    Map<String, dynamic>? selected;
    for (final item in baseList) {
      if (jsonText(item['sCdnType']) == 'TX') {
        selected = item;
        break;
      }
    }
    selected ??= baseList.first;

    final streamName = jsonText(selected['sStreamName']);
    final flvUrl = jsonText(selected['sFlvUrl']);
    final hlsUrl = jsonText(selected['sHlsUrl']);
    final flvAntiCode = jsonText(selected['sFlvAntiCode']);
    final hlsAntiCode = jsonText(selected['sHlsAntiCode']);
    if (streamName.isEmpty || flvUrl.isEmpty) return null;

    selectedFlv = '$flvUrl/$streamName.flv?$flvAntiCode';
    if (hlsUrl.isNotEmpty) {
      selectedHls = '$hlsUrl/$streamName.m3u8?$hlsAntiCode';
    }
    final cdnType = jsonText(selected['sCdnType']);
    if (cdnType == 'TX' || cdnType == 'HW') {
      selectedFlv = selectedFlv
          .replaceFirst('&ctype=tars_mp', '&ctype=huya_webh5')
          .replaceFirst('&fs=bhct', '&fs=bgct');
      selectedHls = selectedHls
          ?.replaceFirst('&ctype=tars_mp', '&ctype=huya_webh5')
          .replaceFirst('&fs=bhct', '&fs=bgct');
    }

    final lines = <StreamLine>[
      StreamLine(name: '线路1 FLV', url: httpsHuyaUrl(selectedFlv), format: 'flv'),
      if (selectedHls != null)
        StreamLine(name: '线路1 HLS', url: httpsHuyaUrl(selectedHls), format: 'hls'),
    ];
    return [StreamQuality(name: '默认', rate: 0, lines: lines)];
  }

  String _profileAnchorName(Map<String, dynamic>? profileData) {
    if (profileData == null) return '';
    final profile = jsonMapOf(profileData['profileInfo']);
    final liveData = jsonMapOf(profileData['liveData']);
    return jsonText(profile['nick'] ?? liveData['nick']);
  }

  String _firstText(List<Object?> values, String fallback) {
    for (final value in values) {
      final text = jsonText(value);
      if (text.isNotEmpty) return text;
    }
    return fallback;
  }

  _HuyaRoomBaseInfo _baseRoomInfo({
    required String rid,
    required String sourceUrl,
    required String anchorName,
    required String title,
    required String cover,
    required String avatar,
    required String category,
    required String cid,
    required bool isLive,
  }) {
    return _HuyaRoomBaseInfo(
      rid: rid,
      sourceUrl: sourceUrl,
      anchorName: anchorName,
      title: title,
      cover: cover,
      avatar: avatar,
      category: category,
      cid: cid,
    );
  }

  RoomPayload _payload(
    _HuyaRoomBaseInfo info,
    RoomState state, {
    List<StreamQuality>? streams,
    List<HuyaQualityItem>? qualities,
    String? error,
  }) {
    return RoomPayload(
      site: kHuyaSiteId,
      roomId: info.rid,
      sourceUrl: info.sourceUrl,
      anchorName: info.anchorName,
      title: info.title,
      cover: info.cover,
      avatar: info.avatar,
      category: info.category,
      cid: info.cid,
      roomState: state,
      streams: streams ?? const [],
      availableQualities: [
        for (final quality in qualities ?? const <HuyaQualityItem>[])
          QualityOption(name: quality.name, rate: quality.rate),
      ],
      source: kHuyaSource,
      fetchedAt: DateTime.now(),
      error: error,
    );
  }
}

class _HuyaRoomBaseInfo {
  const _HuyaRoomBaseInfo({
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

/// 组装虎牙注册项;[httpClient]/[danmakuTransport] 供测试注入 fake。
SiteRegistration buildHuyaRegistration({
  http.Client? httpClient,
  HuyaClient? client,
  DanmakuTransport? danmakuTransport,
}) {
  final effectiveClient = client ?? HuyaClient(httpClient: httpClient);
  return SiteRegistration(
    id: kHuyaSiteId,
    name: '虎牙',
    capabilities: const SiteCapabilities(
      browse: true,
      roomSearch: true,
      anchorSearch: true,
      danmaku: true,
      multiQuality: true,
      multiLine: true,
    ),
    resolver: CachedRoomResolver(HuyaRoomResolver(effectiveClient)),
    browse: HuyaBrowseRepository(effectiveClient.parserHttp),
    search: HuyaSearchRepository(effectiveClient.parserHttp),
    danmaku: HuyaDanmakuConnector(
      parserHttp: effectiveClient.parserHttp,
      transport: danmakuTransport,
    ),
  );
}
