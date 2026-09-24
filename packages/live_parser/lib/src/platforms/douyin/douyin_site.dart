/// 抖音站点组装:房间解析 + 分类浏览 + 搜索 + 弹幕,共享一个 HTTP 实例。
library;

import 'dart:async';

import 'package:http/http.dart' as http;

import '../../contracts/contracts.dart';
import '../../http/danmaku_transport.dart';
import '../../models/models.dart';
import '../../registry/cached_room_resolver.dart';
import '../../registry/site_display.dart';
import '../../utils/format_online.dart';
import '../douyu/json_utils.dart';
import 'browse.dart';
import 'danmaku.dart';
import 'normalize.dart';
import 'room_api.dart';
import 'search.dart';

class DouyinRoomResolver implements RoomResolver, RoomSummaryRefresher {
  DouyinRoomResolver(this._client);

  final DouyinClient _client;

  /// 轻量刷新:只读一次房间进入数据(`webcast/room/web/enter`,失败时回退
  /// 房间页 HTML),**不构造任何播放档位/地址**。
  ///
  /// 口径对齐 web `follow/status.ts` 的 douyin 快照:`status == 4` 为未开播,
  /// 其余视为在播;热度取 `douyinOnlineRaw`(user_count_str/stats 口径);
  /// 粉丝数取 enter 响应内 `owner.follow_info.follower_count`(web
  /// `fetchDouyinSnapshot` 的首选路径,零额外请求;缺失时 web 会再打
  /// 用户 follow_info 接口,此处不再追加 —— 拿不到就留空)。
  /// 「会员」计数在 web 真源走带签名的主播资料卡接口
  /// (`follow/douyin-extras.ts` 的 `/webcast/user/profile/`),仅播时取
  /// `subscribe_info.member_count` 回填 [RoomSummary.diamondFans]
  /// (web `ROOM_STAT_COLUMNS.douyin` 第 3 列 tone=svip field=vip「会员」,
  /// 本包统一由 diamondFans 承载);未开播/拿不到一律留空。
  /// 注:`status != 4` 但无流的情况只有拿档位后才知,轻量刷新不为此多打请求,
  /// 由播放侧开流时自会纠偏。
  @override
  Future<RoomSummary> refreshRoomSummary(RoomRequest request) async {
    final webRid = normalizeDouyinRoomId(request.roomIdOrUrl);
    final room = await fetchDouyinWebStreamData(_client, webRid);
    final anchor = jsonText(room['anchor_name']);
    final title = jsonText(room['title']);
    final live = jsonInt(room['status']) != 4;
    final owner = jsonMapOf(room['owner']);
    // web 真源 `fetchDouyinAudienceExtras` 的 `status == 2` 门槛(在播)。
    final diamondFans = jsonInt(room['status']) == 2
        ? await fetchDouyinAnchorMemberCount(_client, room, webRid)
        : '';
    return RoomSummary(
      site: kDouyinSiteId,
      roomId: webRid,
      title: title.isNotEmpty ? title : anchor,
      anchorName: anchor,
      // 与 resolveRoom 同口径:抖音无二级分类 id,cid 即房间号。
      cid: webRid,
      category: douyinCategoryOf(room),
      online: live ? formatOnlineCount(douyinOnlineRaw(room)) : '',
      cover: douyinCoverOf(room),
      // 头像(web 快照同源:owner.avatar_thumb 首项,零额外请求)。
      avatar: douyinAvatarOf(room),
      // 状态真源:web 同口径 status==4 未开播,其余在播(不从热度推断)。
      roomState: live ? RoomState.live : RoomState.offline,
      followers: formatExactCount(
        jsonMapOf(owner['follow_info'])['follower_count'],
      ),
      diamondFans: diamondFans,
    );
  }

  @override
  Future<RoomPayload> resolveRoom(RoomRequest request) async {
    final webRid = normalizeDouyinRoomId(request.roomIdOrUrl);
    final sourceUrl = douyinSourceUrl(webRid);
    final room = await fetchDouyinWebStreamData(_client, webRid);
    final status = jsonInt(room['status']);
    final streams = status == 4 ? const <StreamQuality>[] : buildDouyinTiers(room);

    if (status == 4) {
      return _buildPayload(
        webRid: webRid,
        sourceUrl: sourceUrl,
        room: room,
        roomState: RoomState.offline,
      );
    }
    if (streams.isEmpty) {
      return _buildPayload(
        webRid: webRid,
        sourceUrl: sourceUrl,
        room: room,
        roomState: RoomState.offline,
        error: '未获取到可播放地址',
      );
    }
    return _buildPayload(
      webRid: webRid,
      sourceUrl: sourceUrl,
      room: room,
      roomState: RoomState.live,
      streams: streams,
    );
  }

  RoomPayload _buildPayload({
    required String webRid,
    required String sourceUrl,
    required Map<String, dynamic> room,
    required RoomState roomState,
    List<StreamQuality> streams = const [],
    String? error,
  }) {
    final anchor = jsonText(room['anchor_name']);
    final title = jsonText(room['title']);
    return RoomPayload(
      site: kDouyinSiteId,
      roomId: webRid,
      sourceUrl: sourceUrl,
      anchorName: anchor,
      title: title.isNotEmpty ? title : anchor,
      cover: douyinCoverOf(room),
      avatar: douyinAvatarOf(room),
      category: douyinCategoryOf(room),
      cid: webRid,
      roomState: roomState,
      streams: streams,
      availableQualities: [
        for (final stream in streams)
          QualityOption(name: stream.name, rate: stream.rate),
      ],
      source: kDouyinSource,
      fetchedAt: DateTime.now(),
      error: error,
    );
  }
}

/// 抖音注册项;[httpClient]/[danmakuTransport] 供测试注入。
SiteRegistration buildDouyinRegistration({
  http.Client? httpClient,
  DouyinClient? client,
  DanmakuTransport? danmakuTransport,
}) {
  final effectiveClient = client ?? DouyinClient(httpClient: httpClient);
  return SiteRegistration(
    id: kDouyinSiteId,
    name: '抖音',
    capabilities: const SiteCapabilities(
      browse: true,
      roomSearch: true,
      anchorSearch: true,
      danmaku: true,
      multiQuality: true,
      multiLine: true,
    ),
    display: kDouyinDisplay,
    resolver: CachedRoomResolver(DouyinRoomResolver(effectiveClient)),
    browse: DouyinBrowseRepository(effectiveClient),
    search: DouyinSearchRepository(effectiveClient),
    danmaku: DouyinDanmakuConnector(
      effectiveClient,
      transport: danmakuTransport,
    ),
  );
}
