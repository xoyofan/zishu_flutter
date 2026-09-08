/// 站点注册表：siteId → RemoteSiteSource 单例。
///
/// streaming-server 的平台 id 即站点 id：
/// douyu/huya/bilibili/douyin/kuaishou/yy/twitch/soop/youtube/xhs/iptv。
/// iptv 是否可用取决于 server /api/config/playback 的能力矩阵，
/// 这里不做能力判断，由调用方按需取用。
library;

import '../remote/remote_site_source.dart';
import '../remote/stream_api_client.dart';

class SiteRegistry {
  SiteRegistry._();

  static StreamApiClient? _client;
  static final Map<String, RemoteSiteSource> _sources = {};

  /// 已知站点 id（streaming-server 平台 id）。
  static const List<String> knownSiteIds = [
    'douyu',
    'huya',
    'bilibili',
    'douyin',
    'kuaishou',
    'yy',
    'twitch',
    'soop',
    'youtube',
    'xhs',
    'iptv',
  ];

  /// 注入 API 客户端（app 启动时调用一次；重复调用覆盖）。
  static void init(StreamApiClient client) => _client = client;

  /// 按 siteId 取单例 source；未 init 时抛 StateError。
  static RemoteSiteSource sourceOf(String siteId) {
    return _sources.putIfAbsent(siteId, () {
      final client = _client;
      if (client == null) {
        throw StateError('SiteRegistry 未初始化：先调用 SiteRegistry.init(StreamApiClient)');
      }
      return RemoteSiteSource(siteId, client);
    });
  }

  /// 清空缓存（仅供测试）。
  static void reset() {
    _sources.clear();
    _client = null;
  }
}
