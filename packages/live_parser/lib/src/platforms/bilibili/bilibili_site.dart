/// B 站站点组装:房间解析 + 浏览 + 搜索 + 弹幕共享一个 HTTP 实例与凭据缓存。
library;

import 'package:http/http.dart' as http;

import '../../http/danmaku_transport.dart';
import '../../http/parser_http.dart';
import '../../contracts/contracts.dart';
import '../../models/models.dart';
import '../../registry/cached_room_resolver.dart';
import '../../utils/format_online.dart';
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

class BilibiliRoomResolver implements RoomResolver, RoomSummaryRefresher {
  BilibiliRoomResolver(this._client);

  final BilibiliClient _client;

  /// 轻量刷新:只读 `room/get_info`(+ 主播名缺失时的 anchor 兜底),
  /// **不请求 `room/play_info`、不做任何取流与签名**。
  ///
  /// 口径对齐 web `follow/status.ts` 的 bilibili 快照:`live_status == 1`
  /// 为在播,`online` 作热度;粉丝数取同响应的 `attention`(web
  /// `formatCount(info.attention)` 同口径)。轮播(`live_status == 2`,
  /// B 站官方语义)按任务口径(2026-09-19)输出 [RoomState.replay]:
  /// **online 契约同离线一样为空串**,由 [RoomSummary.roomState] 单独
  /// 区分。粉丝勋章/大航海在 web 真源是 anchor/guard 两个额外接口
  /// (`fetchBilibiliFansMedalCount`/`fetchBilibiliGuardInfo`),且 vip 列
  /// 本就为空 —— 此处不再加请求,[RoomSummary.vip] 恒空。
  @override
  Future<RoomSummary> refreshRoomSummary(RoomRequest request) async {
    final http = _client.parserHttp;
    final credentials = _client.credentials;
    final url = normalizeBilibiliUrl(request.roomIdOrUrl);
    final rid = bilibiliRoomIdFromUrl(url);

    final Map<String, dynamic> info;
    try {
      info = await fetchBilibiliRoomInfo(http, credentials, rid);
    } on BilibiliApiException catch (error) {
      if (error.code == 1) {
        throw ParserHttpException('B 站房间不存在: $rid');
      }
      rethrow;
    }

    var anchorName = jsonText(
      info['uname'] ??
          jsonMapOf(jsonMapOf(info['anchor_info'])['base_info'])['uname'],
    );
    final infoAvatar = bilibiliAvatarFromRoom(info);
    var anchorFace = '';
    if (anchorName.isEmpty || infoAvatar.isEmpty) {
      // 仅主播名/头像缺失时才补一次 anchor 接口(与完整解析同一兜底)。
      try {
        final anchor = await fetchBilibiliAnchorInRoom(http, credentials, rid);
        if (anchorName.isEmpty) anchorName = anchor.uname;
        anchorFace = anchor.face;
      } on Object {
        // 兜底失败不影响状态刷新结果。
      }
    }
    // 头像口径与 resolveRoom 一致:get_info 的 face 优先、anchor 接口兜底
    // (web follow/status.ts 的 `avatar: anchor.face || avatarFromRoom(info)`)。
    final avatar = infoAvatar.isEmpty ? anchorFace : infoAvatar;

    // live_status:0 未开播 1 直播 2 轮播(B 站官方语义)。
    final liveStatus = jsonInt(info['live_status']);
    final isLive = liveStatus == 1;
    final isReplay = liveStatus == 2;
    // 大航海人数(web ROOM_STAT_COLUMNS.bilibili 第 3 列 tone=svip
    // field=guard「大航海」,本包统一由 diamondFans 承载):仅在播时取
    // guardTab/topList(web 真源 state==live 门槛),失败/为 0 留空。
    final diamondFans = isLive
        ? formatExactCount(
            await fetchBilibiliGuardTotal(
              http,
              credentials,
              rid,
              jsonInt(info['uid']),
            ),
          )
        : '';
    // 二级分类名优先(web pickText(area_name, parent_area_name) 同口径)。
    final refreshAreaName = jsonText(info['area_name']);
    return RoomSummary(
      site: kBilibiliSiteId,
      roomId: rid,
      title: jsonText(info['title']).isEmpty
          ? anchorName
          : jsonText(info['title']),
      anchorName: anchorName,
      cid: jsonText(info['area_id']),
      category: refreshAreaName.isNotEmpty
          ? refreshAreaName
          : jsonText(info['parent_area_name']),
      online: isLive ? formatOnlineCount(info['online']) : '',
      cover: bilibiliCoverFromRoom(info),
      avatar: avatar,
      followers: formatExactCount(info['attention']),
      diamondFans: diamondFans,
      roomState: isLive
          ? RoomState.live
          : (isReplay ? RoomState.replay : RoomState.offline),
    );
  }

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

    // live_status:0 未开播 1 直播 2 轮播(B 站官方语义);轮播输出
    // replay(web resolve 层把轮播当未播,是有意收紧 —— 轮播流暂不接入,
    // 保持 streams 为空,语义先行)。
    final liveStatus = jsonInt(info['live_status']);
    final isLive = liveStatus == 1;
    final isReplay = liveStatus == 2;

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
    // 懒取流:偏好档(设置里的默认画质,经档位表映射成 qn)直接作为请求
    // 参数,进房即取目标档;匹配不到档位表时回退 10000(原画)。
    final preferredRequestQn = matchQualityPreference(
      kBilibiliQnTiers,
      request.preferredQuality,
      (tier) => tier.name,
    )?.qn;
    final Future<Map<String, dynamic>>? playFuture = isLive
        ? fetchBilibiliRoomPlayInfo(
            http,
            credentials,
            rid,
            qn: preferredRequestQn ?? 10000,
          )
        : null;
    final anchor = anchorFuture == null
        ? (uname: '', face: '')
        : await anchorFuture;
    final anchorName = infoUname.isEmpty ? anchor.uname : infoUname;
    final avatar = infoAvatar.isEmpty ? anchor.face : infoAvatar;
    // 二级分类名优先(web follow/status.ts:pickText(area_name,
    // parent_area_name));parent 是大分类(如「网游」),area 才是细分区。
    final areaName = jsonText(info['area_name']);
    final base = _Base(
      rid: rid,
      sourceUrl: url,
      anchorName: anchorName,
      title: jsonText(info['title']).isEmpty ? anchorName : jsonText(info['title']),
      cover: bilibiliCoverFromRoom(info),
      avatar: avatar,
      category: areaName.isNotEmpty ? areaName : jsonText(info['parent_area_name']),
      cid: jsonText(info['area_id'] ?? ''),
    );

    if (!isLive) {
      return _payload(base, isReplay ? RoomState.replay : RoomState.offline);
    }

    final data = await playFuture!;
    final qualities = bilibiliAvailableQualities(data);
    if (qualities.isEmpty) {
      throw const ParserHttpException('未获取到可播放的 B 站流地址');
    }

    // 懒取流(对齐 soop resolveTier 口径):一次 getRoomPlayInfo 只返回
    // current_qn 单档的真实流。此前把同一批地址经 preferQn 回退复制到全部
    // 档位,画质菜单「多级重复」—— 原画/蓝光/超清/高清四档播放内容完全
    // 相同,切档无效果。现在真实线路只挂服务器实给档(current_qn,可能
    // 因登录态低于请求 qn),其余档位以空线路占位供菜单列出;用户切档时
    // 由播放侧带新的 preferredQuality 重新解析取流。
    final actualQn = bilibiliCurrentQn(data);
    final realTier = qualities.firstWhere(
      (quality) => quality.qn == actualQn,
      orElse: () => matchQualityPreference(qualities, request.preferredQuality,
              (quality) => quality.name) ??
          qualities.first,
    );
    final lines = bilibiliTierLines(data, realTier.qn);
    if (lines == null) {
      throw const ParserHttpException('未获取到可播放的 B 站流地址');
    }

    // 实给档放首位(playUrl / 播放侧选中都取 streams.first);其余档位
    // 官网顺序空线路占位。availableQualities 保持全档官网顺序。
    final streams = <StreamQuality>[
      StreamQuality(
        name: realTier.name,
        rate: realTier.qn,
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
      for (final quality in qualities)
        if (quality.qn != realTier.qn)
          StreamQuality(name: quality.name, rate: quality.qn, lines: const []),
    ];

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
