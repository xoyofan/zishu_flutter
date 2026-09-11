/// 抖音站点组装:房间解析 + 分类浏览 + 搜索 + 弹幕,共享一个 HTTP 实例。
library;

import 'dart:async';

import 'package:http/http.dart' as http;

import '../../contracts/contracts.dart';
import '../../http/danmaku_transport.dart';
import '../../models/models.dart';
import '../../registry/cached_room_resolver.dart';
import '../douyu/json_utils.dart';
import 'browse.dart';
import 'danmaku.dart';
import 'normalize.dart';
import 'room_api.dart';
import 'search.dart';

class DouyinRoomResolver implements RoomResolver {
  DouyinRoomResolver(this._client);

  final DouyinClient _client;

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
    resolver: CachedRoomResolver(DouyinRoomResolver(effectiveClient)),
    browse: DouyinBrowseRepository(effectiveClient),
    search: DouyinSearchRepository(effectiveClient),
    danmaku: DouyinDanmakuConnector(
      effectiveClient,
      transport: danmakuTransport,
    ),
  );
}
