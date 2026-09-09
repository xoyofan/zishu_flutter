/// IPTV 频道仓库:多源 provider 加载、合并与缓存(远程源失败回退上次数据)。
///
/// provider 配置由宿主注入(纯 Dart 包不读文件系统):
///   - `url`:远程 M3U 地址(http/https,经 SSRF 防护)
///   - `m3uContent`:直接内联的 M3U 文本(本地播放列表)
library;

import 'dart:async';

import '../../http/parser_http.dart';
import 'playlist.dart';

/// IPTV 站点标识。
const String kIptvSiteId = 'iptv';

/// 播放列表数据源。
class IptvSource {
  const IptvSource({
    required this.id,
    required this.name,
    this.url,
    this.m3uContent,
    this.enabled = true,
  }) : assert(url != null || m3uContent != null, 'IPTV 源需要 url 或 m3uContent');

  final String id;
  final String name;

  /// 远程 M3U 地址。
  final String? url;

  /// 内联 M3U 文本。
  final String? m3uContent;
  final bool enabled;
}

/// 带来源标签的频道。
class IptvTaggedChannel extends IptvChannel {
  const IptvTaggedChannel({
    required this.providerId,
    required super.id,
    required super.name,
    required super.url,
    required super.logo,
    required super.group,
    required super.tvgId,
    super.quality,
    super.country,
    super.geoBlocked,
    super.not247,
  });

  final String providerId;
}

/// 频道仓库:实例持有源配置与缓存。
class IptvChannelRepository {
  IptvChannelRepository({
    required List<IptvSource> channelSources,
    ParserHttp? parserHttp,
    this.cacheTtl = const Duration(minutes: 10),
  }) : _sources = channelSources,
       _http = parserHttp ?? ParserHttp();

  final List<IptvSource> _sources;
  final ParserHttp _http;
  final Duration cacheTtl;

  IptvChannelSnapshot? _cache;
  final Map<String, List<IptvTaggedChannel>> _lastGood = {};

  /// 清空缓存(宿主刷新源后调用)。
  void resetCache() => _cache = null;

  /// 加载全部启用源的频道(合并、TTL 缓存;失败源回退 lastGood)。
  Future<IptvChannelSnapshot> loadAll() async {
    final cached = _cache;
    if (cached != null && DateTime.now().difference(cached.at) < cacheTtl) {
      return cached;
    }
    final results = await Future.wait([
      for (final source in _sources.where((s) => s.enabled)) _loadSource(source),
    ]);
    final snapshot = IptvChannelSnapshot(
      at: DateTime.now(),
      channels: [for (final r in results) ...r.channels],
      stats: [for (final r in results) r.stat],
    );
    _cache = snapshot;
    return snapshot;
  }

  Future<({List<IptvTaggedChannel> channels, IptvSourceStat stat})> _loadSource(
    IptvSource source,
  ) async {
    final stat = IptvSourceStat(
      id: source.id,
      name: source.name,
      kind: source.url != null ? 'url' : 'file',
      source: source.url ?? 'inline',
      channelCount: 0,
    );
    try {
      final content = source.url != null
          ? await _fetchPlaylist(source.url!)
          : (source.m3uContent ?? '');
      final channels = parseM3U(content);
      stat.channelCount = channels.length;
      final tagged = [
        for (final c in channels)
          IptvTaggedChannel(
            providerId: source.id,
            id: '${source.id}:${c.tvgId.isNotEmpty ? c.tvgId : channelSlug(c.name)}',
            name: c.name,
            url: c.url,
            logo: c.logo,
            group: iptvGroupZh(c.group),
            tvgId: c.tvgId,
            quality: c.quality,
            country: c.country,
            geoBlocked: c.geoBlocked,
            not247: c.not247,
          ),
      ];
      _lastGood[source.id] = tagged;
      return (channels: tagged, stat: stat);
    } on IptvSsrfException {
      // SSRF 违规属配置错误,硬失败(安全语义不降级)。
      rethrow;
    } catch (_) {
      final stale = _lastGood[source.id];
      if (stale != null && stale.isNotEmpty) {
        stat.error = '暂时使用上次缓存 ${stale.length} 条';
        stat.channelCount = stale.length;
        return (channels: stale, stat: stat);
      }
      return (channels: const <IptvTaggedChannel>[], stat: stat);
    }
  }

  Future<String> _fetchPlaylist(String url) async {
    assertSafePlaylistUrl(url);
    final response = await _http.get(
      Uri.parse(url),
      headers: const {'Accept': '*/*'},
    );
    return response.body;
  }
}

/// 一次加载的频道快照与各源状态。
class IptvChannelSnapshot {
  const IptvChannelSnapshot({
    required this.at,
    required this.channels,
    required this.stats,
  });

  final DateTime at;
  final List<IptvTaggedChannel> channels;
  final List<IptvSourceStat> stats;
}

/// 单个数据源的状态。
class IptvSourceStat {
  IptvSourceStat({
    required this.id,
    required this.name,
    required this.kind,
    required this.source,
    required this.channelCount,
    this.error,
  });

  final String id;
  final String name;
  final String kind;
  final String source;
  int channelCount;
  String? error;
}
