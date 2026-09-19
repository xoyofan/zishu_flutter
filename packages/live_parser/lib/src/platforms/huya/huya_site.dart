/// 虎牙站点组装:房间解析 + 浏览 + 搜索 + 弹幕共享一个 HTTP 实例。
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
import 'huya_wup.dart';
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
      ),
      // wup 贵宾查询与元信息接口共享注入的 httpClient(测试 fake 生效);
      // 各自只在「自有 client」时负责关闭。
      wup = HuyaWupClient(httpClient: httpClient);

  final ParserHttp parserHttp;
  final HuyaWupClient wup;

  void close() {
    parserHttp.close();
    wup.close();
  }
}

/// 虎牙房间解析。
///
/// 同时实现 [RoomRecoveryResolver]:虎牙播放地址带时效签名,恢复时必须拿到
/// **全新**的 anti_code 与流名。本实现不保存任何地址状态 —— `resolveRoom`
/// 每次都重新走 `resolveHuyaNumericRoomId` → `fetchHuyaWebStreamData` →
/// `buildHuyaAntiCode` 重新签名,故恢复语义与普通解析同源,单点维护避免漂移。
class HuyaRoomResolver implements RoomResolver, RoomRecoveryResolver, RoomSummaryRefresher {
  HuyaRoomResolver(this._client);

  final HuyaClient _client;

  /// 轻量刷新:只读 mp.huya.com profileRoom(必要时补一次房间页 TT_ROOM_DATA
  /// 判定录播/下播边界),**不做 anti-code 签名、不构造任何播放地址**。
  ///
  /// 口径对齐 web `follow/status.ts` 的 huya 快照:
  /// `huyaRoomState` 判在播,`formatOnline(totalCount|userCount)` 作热度;
  /// 粉丝数取 `profileInfo.activityCount ?? liveData.activityCount`(同一
  /// 响应内,零额外请求);`replay` 在本仓契约里归 offline([RoomState] 无
  /// replay),故 online 留空。
  ///
  /// 贵宾数([RoomSummary.vip],SideHeader「贵宾」行):仅在播时按 web
  /// 真源 `follow/huya-wup.ts` 走 Tars wup 协议 `liveui/getVipBarList`
  /// (见 [HuyaWupClient]),presenterUid 取 `profileInfo.uid ?? liveData.uid`、
  /// channelId 取 `liveData.liveChannel ?? liveData.channel ?? uid`;
  /// wup 失败/为 0 一律留空(数据诚实性:不伪造)。超粉(svip tone 行)
  /// web 侧走 getSuperFansInfo,本轮未实现。
  @override
  Future<RoomSummary> refreshRoomSummary(RoomRequest request) async {
    final http = _client.parserHttp;
    final url = normalizeHuyaUrl(request.roomIdOrUrl);
    final rid = await resolveHuyaNumericRoomId(http, url);
    final profile = await fetchHuyaProfileRoomData(http, rid);
    if (profile == null) {
      throw ParserHttpException('虎牙房间不存在: $rid');
    }
    // 仅在「无 FLV 流且疑似录播」时才补页面探测(与完整解析同一条边界)。
    final pageFlags = profileNeedsPageCheck(profile)
        ? await fetchHuyaPageRoomFlags(http, rid)
        : null;
    final state = huyaRoomState(profile, pageFlags);
    final liveData = jsonMapOf(profile['liveData']);
    final profileInfo = jsonMapOf(profile['profileInfo']);

    final anchorName = _profileAnchorName(profile);
    final title = _firstText(
      [liveData['introduction'], liveData['roomName']],
      anchorName,
    );
    // 2026-09 真实探针(tool/_probe_huya_cid.dart)实证:profileRoom 的
    // liveData 已不再下发 `sGameFullName`(字段整体消失),中文名在
    // `gameFullName`(如「英雄联盟」),`gameHostName` 是缩写(如 lol)。
    // sGameFullName 保留在链尾兼容旧缓存形态。归一(缩写/cid → 中文)由
    // 宿主 app 侧 displayCategoryName 完成,本层只负责带回原始名。
    final category = _firstText(
      [
        liveData['gameFullName'],
        liveData['sGameFullName'],
        liveData['gameHostName'],
        profileInfo['gameHostName'],
      ],
      '',
    );
    // cid = 虎牙分区 gid(与 browse/进房 payload 同源)。实证 `gameId` 不是
    // 分区 id(取值 0 或 IntegerId 820),只能作末位兜底;0 视为缺失。
    final cid = _firstNonZeroText([
      liveData['gid'],
      liveData['iGid'],
      liveData['gameId'],
      profileInfo['gameId'],
    ]);

    // 贵宾数(web fetchHuyaVipCount 口径:仅 isLive 时查询,失败/0 留空)。
    final presenterUid = _firstPositiveInt([
      profileInfo['uid'],
      liveData['uid'],
    ]);
    final channelId = _firstPositiveInt([
      liveData['liveChannel'],
      liveData['channel'],
    ]);
    var vip = '';
    if (state == HuyaRoomState.live && presenterUid > 0) {
      final count = await _client.wup.fetchVipBarCount(
        presenterUid: presenterUid,
        channelId: channelId > 0 ? channelId : presenterUid,
      );
      if (count != null && count > 0) {
        vip = '$count';
      }
    }

    return RoomSummary(
      site: kHuyaSiteId,
      roomId: rid,
      title: title,
      anchorName: anchorName,
      cid: cid,
      category: category,
      // 只有明确在播才给热度;录播/下播一律空串(契约:空串即未开播)。
      online: state == HuyaRoomState.live
          ? formatOnlineCount(liveData['totalCount'] ?? liveData['userCount'])
          : '',
      cover: httpsHuyaUrl(jsonText(liveData['cover'] ?? liveData['screenshot'])),
      // 粉丝数(web formatCount 口径:完整数字,0/缺失留空)。
      followers: formatExactCount(
        profileInfo['activityCount'] ?? liveData['activityCount'],
      ),
      vip: vip,
    );
  }

  @override
  Future<RoomPayload> recoverRoom(RoomRequest request) => resolveRoom(request);

  @override
  Future<RoomPayload> resolveRoom(RoomRequest request) async {
    final http = _client.parserHttp;
    final url = normalizeHuyaUrl(request.roomIdOrUrl);
    final rid = await resolveHuyaNumericRoomId(http, url);
    final canonicalUrl = 'https://www.huya.com/$rid';
    final playHeaders = huyaPlaybackHeaders(rid);

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
      final appStreams = _appFallbackStreams(profileData, playHeaders);
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
          lines.add(
            StreamLine(
              name: '$lineName HLS',
              url: hls,
              format: 'hls',
              headers: playHeaders,
            ),
          );
        }
        if (flv != null) {
          lines.add(
            StreamLine(
              name: '$lineName FLV',
              url: flv,
              format: 'flv',
              headers: playHeaders,
            ),
          );
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
  List<StreamQuality>? _appFallbackStreams(
    Map<String, dynamic>? profileData,
    Map<String, String> playHeaders,
  ) {
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
      StreamLine(
        name: '线路1 FLV',
        url: httpsHuyaUrl(selectedFlv),
        format: 'flv',
        headers: playHeaders,
      ),
      if (selectedHls != null)
        StreamLine(
          name: '线路1 HLS',
          url: httpsHuyaUrl(selectedHls),
          format: 'hls',
          headers: playHeaders,
        ),
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

  /// 取第一个可解析且 >0 的整数(uid/liveChannel 等主键类字段,0 视为缺失)。
  int _firstPositiveInt(List<Object?> values) {
    for (final value in values) {
      final parsed = int.tryParse(jsonText(value));
      if (parsed != null && parsed > 0) return parsed;
    }
    return 0;
  }

  /// 首个非空且非 '0' 的字段文本(上游用 0 表示「无此 id」)。
  String _firstNonZeroText(List<Object?> values) {
    for (final value in values) {
      final text = jsonText(value);
      if (text.isNotEmpty && text != '0') return text;
    }
    return '';
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
