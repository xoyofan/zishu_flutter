/// IPTV 站点组装:频道列表驱动的直播源(M3U),无弹幕、单直连线路。
library;

import '../../http/danmaku_transport.dart';
import '../../http/parser_http.dart';
import '../../contracts/contracts.dart';
import '../../registry/site_display.dart';
import '../../models/models.dart';
import 'browse.dart';
import 'channel_repository.dart';

export 'channel_repository.dart' show IptvSource, IptvChannelRepository, IptvChannelSnapshot;
export 'playlist.dart' show IptvChannel, parseM3U, channelFormat;
import 'playlist.dart';
import 'search.dart';

/// IPTV 解析源标识。
const String kIptvSource = 'live_parser/iptv';

class IptvRoomResolver implements RoomResolver {
  IptvRoomResolver(this._repository);

  final IptvChannelRepository _repository;

  @override
  Future<RoomPayload> resolveRoom(RoomRequest request) async {
    final id = request.roomIdOrUrl.trim();
    final channel = await _findChannel(id);
    if (channel == null) {
      return RoomPayload(
        site: kIptvSiteId,
        roomId: id,
        sourceUrl: '',
        anchorName: id,
        title: '频道不存在',
        cover: '',
        avatar: '',
        category: '',
        cid: id,
        roomState: RoomState.notFound,
        streams: const [],
        availableQualities: const [],
        source: kIptvSource,
        fetchedAt: DateTime.now(),
        error: '频道不存在或播放列表为空',
      );
    }

    final format = channelFormat(channel.url);
    return RoomPayload(
      site: kIptvSiteId,
      roomId: channel.id,
      sourceUrl: '',
      anchorName: channel.name,
      title: channel.name,
      cover: channel.logo,
      avatar: '',
      category: channel.group,
      cid: channel.group,
      roomState: RoomState.live,
      streams: [
        StreamQuality(
          name: '直播',
          rate: 0,
          lines: [
            StreamLine(name: '直连', url: channel.url, format: format),
          ],
        ),
      ],
      availableQualities: const [QualityOption(name: '直播', rate: 0)],
      source: kIptvSource,
      fetchedAt: DateTime.now(),
    );
  }

  /// 频道查找:精确 id → 去前缀/后缀容错 → 大小写不敏感。
  Future<IptvTaggedChannel?> _findChannel(String id) async {
    if (id.isEmpty) return null;
    final snapshot = await _repository.loadAll();
    final channels = snapshot.channels;
    for (final channel in channels) {
      if (channel.id == id) return channel;
    }
    // 容错 1:不带 provider 前缀的旧 id
    final key = id.contains(':') ? id.substring(id.indexOf(':') + 1) : id;
    for (final channel in channels) {
      if (channel.id == key || channel.id.endsWith(':$key')) return channel;
    }
    // 容错 2:大小写不敏感
    final lower = id.toLowerCase();
    for (final channel in channels) {
      if (channel.id.toLowerCase() == lower) return channel;
    }
    return null;
  }
}

/// 组装 IPTV 注册项;[sources] 由宿主注入(远程 URL 或内联 M3U 文本)。
SiteRegistration buildIptvRegistration({
  required List<IptvSource> sources,
  DanmakuTransport? danmakuTransport,
  ParserHttp? parserHttp,
}) {
  final repository = IptvChannelRepository(
    channelSources: sources,
    parserHttp: parserHttp,
  );
  return SiteRegistration(
    id: kIptvSiteId,
    name: 'IPTV',
    capabilities: const SiteCapabilities(
      browse: true,
      roomSearch: true,
      multiLine: true,
    ),
    display: kIptvDisplay,
    resolver: IptvRoomResolver(repository),
    browse: IptvBrowseRepository(repository),
    search: IptvSearchRepository(repository),
  );
}
