/// 小红书站点组装:房间解析(iOS UA 直抓直播间页)+ 分类浏览
/// (live-room 签名 API),共享一个 HTTP 实例。
///
/// 能力口径:
/// * browse = true(分类 + 列表;需要用户配置 Cookie,-101 抛专用异常);
/// * 搜索未接入(上游无公开搜索接口)→ 不注册 search 部件;
/// * 弹幕未接入(上游无公开协议)→ 不注册 danmaku 部件;
/// * 取流不需要签名;resolver 经 `CachedRoomResolver` 包装,同时如实
///   暴露 refresher(房间页本身就是最轻的元信息接口)与 recovery。
library;

import 'package:http/http.dart' as http;

import '../../contracts/contracts.dart';
import '../../http/parser_http.dart';
import '../../models/models.dart';
import '../../models/room_record.dart';
import '../../registry/cached_room_resolver.dart';
import 'browse.dart';
import 'room_api.dart';

/// 小红书房间解析器:直播间页一次抓取同时承载取流与元信息。
class XhsRoomResolver implements RoomResolver, RoomSummaryRefresher {
  XhsRoomResolver(this._client);

  final XhsClient _client;

  /// 轻量刷新:只拉一次直播间页 SSR,**不构造任何播放档位/线路**。
  ///
  /// 房间不存在(初始状态缺失/未找到直播间)按刷新契约抛异常,不返回
  /// 伪造的空房间记录;主播主页形态的短链解析为合法离线快照。
  @override
  Future<RoomRecord> refreshRoomSummary(RoomRequest request) async {
    final roomId = normalizeXhsRoomId(request.roomIdOrUrl);
    if (roomId.isEmpty) {
      throw ParserHttpException('未识别的小红书房间号: ${request.roomIdOrUrl}');
    }
    final context = await _client.fetchLiveContext(roomId);
    if (context.roomMissing) {
      throw ParserHttpException(
        '小红书房间不存在: $roomId(${context.errorMessage})',
      );
    }
    return RoomRecord.fromSummary(_toSummary(context, fallbackRoomId: roomId));
  }

  @override
  Future<RoomPayload> resolveRoom(RoomRequest request) async {
    final roomId = normalizeXhsRoomId(request.roomIdOrUrl);
    final sourceUrl = xhsSourceUrl(roomId);
    if (roomId.isEmpty) {
      return _buildPayload(
        roomId: roomId,
        sourceUrl: sourceUrl,
        context: _emptyContext(roomId),
        roomState: RoomState.notFound,
        error: '未识别的房间号: ${request.roomIdOrUrl}',
      );
    }

    final context = await _client.fetchLiveContext(roomId);

    if (context.roomMissing) {
      return _buildPayload(
        roomId: roomId,
        sourceUrl: sourceUrl,
        context: context,
        roomState: RoomState.notFound,
        error: context.errorMessage,
      );
    }
    if (!context.live) {
      return _buildPayload(
        roomId: roomId,
        sourceUrl: sourceUrl,
        context: context,
        roomState: RoomState.offline,
        error: context.errorMessage,
      );
    }
    // 画质两档:原画 = pullConfig 原链;高清 = 同 URL 加 `_hcv520`
    // (低码率转码流,个别特殊房间可能无效,上游不回档位枚举)。
    final streams = [
      StreamQuality(name: kXhsDefaultQuality, rate: 0, lines: context.lines),
      StreamQuality(name: kXhsHdQuality, rate: 0, lines: xhsHdLines(context.lines)),
    ];
    return _buildPayload(
      roomId: roomId,
      sourceUrl: sourceUrl,
      context: context,
      roomState: RoomState.live,
      streams: streams,
    );
  }

  XhsPageContext _emptyContext(String roomId) => XhsPageContext(
    roomId: roomId,
    live: false,
    roomMissing: true,
    lines: const [],
    anchorName: '',
    title: '',
    cover: '',
    avatar: '',
    hostId: '',
    viewerCount: '',
    errorMessage: '未识别的房间号',
  );

  RoomSummary _toSummary(XhsPageContext context, {required String fallbackRoomId}) =>
      RoomSummary(
        site: kXhsSiteId,
        roomId: context.roomId.isNotEmpty ? context.roomId : fallbackRoomId,
        title: context.title,
        anchorName: context.anchorName,
        // 与 resolveRoom 同口径:房间页无分类信息,cid 即房间号。
        cid: context.roomId.isNotEmpty ? context.roomId : fallbackRoomId,
        category: '',
        // 观众数取上游已格式化字符串(如「1万+」),原样保留;离线为空串。
        online: context.live ? context.viewerCount : '',
        cover: context.cover,
        avatar: context.avatar,
        // 状态真源:liveStatus==success 且派生出线路判在播(不从热度推断)。
        roomState: context.live ? RoomState.live : RoomState.offline,
      );

  RoomPayload _buildPayload({
    required String roomId,
    required String sourceUrl,
    required XhsPageContext context,
    required RoomState roomState,
    List<StreamQuality> streams = const [],
    String? error,
  }) => RoomPayload(
    site: kXhsSiteId,
    roomId: context.roomId.isNotEmpty ? context.roomId : roomId,
    sourceUrl: sourceUrl,
    anchorName: context.anchorName,
    title: context.title,
    cover: context.cover,
    avatar: context.avatar,
    category: '',
    cid: context.roomId.isNotEmpty ? context.roomId : roomId,
    roomState: roomState,
    streams: streams,
    availableQualities: [
      for (final stream in streams) QualityOption(name: stream.name, rate: stream.rate),
    ],
    source: kXhsSource,
    fetchedAt: DateTime.now(),
    error: error,
  );
}

/// 小红书注册项;[httpClient]/[client] 供测试注入,[credential] 为用户
/// 凭证(整串 Cookie 或 `a1=...; web_session=...`,live-room API 需要)。
SiteRegistration buildXhsRegistration({
  http.Client? httpClient,
  XhsClient? client,
  String credential = '',
}) {
  final effectiveClient =
      client ?? XhsClient(httpClient: httpClient, credential: credential);
  return SiteRegistration(
    id: kXhsSiteId,
    name: '小红书',
    capabilities: const SiteCapabilities(
      browse: true,
      multiQuality: true,
      multiLine: true,
      // live-room 分类/列表接口需要 a1 + web_session,过期返回 -101。
      requiresCookie: true,
    ),
    resolver: CachedRoomResolver(XhsRoomResolver(effectiveClient)),
    browse: XhsBrowseRepository(effectiveClient),
  );
}
