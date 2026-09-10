/// YY 站点组装：房间解析 + 分类浏览 + 搜索。
library;

import 'package:http/http.dart' as http;

import '../../contracts/contracts.dart';
import '../../http/parser_http.dart';
import '../../models/models.dart';
import 'browse.dart';
import 'normalize.dart';
import 'room_api.dart';
import 'search.dart';

class YyClient {
  YyClient({http.Client? httpClient})
      : parserHttp = ParserHttp(
          client: httpClient,
          defaultHeaders: const {
            'Referer': 'https://www.yy.com/',
            'Origin': 'https://www.yy.com',
          },
        );

  final ParserHttp parserHttp;

  void close() => parserHttp.close();
}

class YyRoomResolver implements RoomResolver {
  YyRoomResolver(this._client);

  final YyClient _client;

  @override
  Future<RoomPayload> resolveRoom(RoomRequest request) async {
    final roomId = normalizeYyRoomId(request.roomIdOrUrl);
    final sourceUrl = 'https://www.yy.com/$roomId';
    final detailResult = await fetchYyRoomDetail(_client.parserHttp, roomId);
    final detail = detailResult.detail;

    if (detail == null) {
      return RoomPayload(
        site: kYySiteId,
        roomId: roomId,
        sourceUrl: sourceUrl,
        anchorName: '',
        title: '',
        cover: '',
        avatar: '',
        category: '',
        cid: roomId,
        roomState: detailResult.notFound ? RoomState.notFound : RoomState.offline,
        streams: const [],
        availableQualities: const [],
        source: kYySource,
        fetchedAt: DateTime.now(),
        error: detailResult.notFound ? '房间不存在' : null,
      );
    }

    final qualities = await fetchYyQualities(_client.parserHttp, roomId);
    if (qualities.isEmpty) {
      return _payload(
        roomId: roomId,
        sourceUrl: sourceUrl,
        detail: detail,
        roomState: RoomState.offline,
      );
    }

    final streams = <StreamQuality>[];
    for (final quality in qualities) {
      final tier = await buildYyTier(_client.parserHttp, roomId, quality);
      if (tier != null) streams.add(tier);
    }
    if (streams.isEmpty) {
      return _payload(
        roomId: roomId,
        sourceUrl: sourceUrl,
        detail: detail,
        roomState: RoomState.offline,
      );
    }
    return _payload(
      roomId: roomId,
      sourceUrl: sourceUrl,
      detail: detail,
      roomState: RoomState.live,
      streams: streams,
    );
  }

  RoomPayload _payload({
    required String roomId,
    required String sourceUrl,
    required YyRoomDetail detail,
    required RoomState roomState,
    List<StreamQuality> streams = const [],
  }) => RoomPayload(
        site: kYySiteId,
        roomId: roomId,
        sourceUrl: sourceUrl,
        anchorName: detail.name,
        title: detail.desc.isNotEmpty ? detail.desc : detail.name,
        cover: detail.thumb,
        avatar: detail.avatar,
        category: detail.biz,
        cid: detail.ssid,
        roomState: roomState,
        streams: streams,
        availableQualities: [
          for (final stream in streams)
            QualityOption(name: stream.name, rate: stream.rate),
        ],
        source: kYySource,
        fetchedAt: DateTime.now(),
      );
}

/// YY 注册项。YY 当前只声明 resolve/browse/search，无弹幕 connector。
SiteRegistration buildYyRegistration({
  http.Client? httpClient,
  YyClient? client,
}) {
  final effectiveClient = client ?? YyClient(httpClient: httpClient);
  return SiteRegistration(
    id: kYySiteId,
    name: 'YY',
    capabilities: const SiteCapabilities(
      browse: true,
      roomSearch: true,
      anchorSearch: true,
      multiQuality: true,
      multiLine: true,
    ),
    resolver: YyRoomResolver(effectiveClient),
    browse: YyBrowseRepository(effectiveClient.parserHttp),
    search: YySearchRepository(effectiveClient.parserHttp),
  );
}
