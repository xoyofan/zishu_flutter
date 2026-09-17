/// YouTube 输入归一与公共请求头。
library;

import '../../utils/header_sanitizer.dart';

/// YouTube 站点标识(与 UI PlatformBrandCatalog / nav 对齐)。
const String kYoutubeSiteId = 'youtube';

/// YouTube 解析源标识。
const String kYoutubeSource = 'live_parser/youtube';

/// 页面请求 UA。
const String kYoutubeUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

final RegExp _videoIdPattern = RegExp(r'^[A-Za-z0-9_-]{11}$');

/// 是否为合法 11 位 videoId。
bool isValidYoutubeVideoId(String value) => _videoIdPattern.hasMatch(value);

/// 从 URL / 裸 videoId 提取 11 位 id;无法识别返回 null。
String? extractYoutubeVideoId(String value) {
  final raw = value.trim();
  if (raw.isEmpty) return null;
  if (_videoIdPattern.hasMatch(raw)) return raw;
  final patterns = <RegExp>[
    RegExp(r'youtu\.be/([A-Za-z0-9_-]{11})'),
    RegExp(r'[?&]v=([A-Za-z0-9_-]{11})'),
    RegExp(r'youtube\.com/live/([A-Za-z0-9_-]{11})'),
    RegExp(r'youtube\.com/embed/([A-Za-z0-9_-]{11})'),
    RegExp(r'([A-Za-z0-9_-]{11})(?:\?|/|$)'),
  ];
  for (final pattern in patterns) {
    final match = pattern.firstMatch(raw);
    final id = match?.group(1);
    if (id != null && _videoIdPattern.hasMatch(id)) return id;
  }
  return null;
}

/// watch 页地址。
String youtubeSourceUrl(String videoId) =>
    'https://www.youtube.com/watch?v=$videoId';

/// 页面请求头。
Map<String, String> youtubePageHeaders({
  String referer = 'https://www.youtube.com/',
  String? cookie,
}) => {
  'User-Agent': kYoutubeUserAgent,
  'Accept':
      'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
  'Accept-Language': 'en-US,en;q=0.9',
  'Referer': referer,
  if (cookie != null && cookie.trim().isNotEmpty) 'Cookie': cookie.trim(),
};

/// YouTube 媒体流(HLS master/变体/分片)请求头。
///
/// googlevideo 分发以 UA/Referer 做反爬校验,与拉取媒体清单(fetchYoutubePlaylist)
/// 及链路预校验(validateYoutubeChain)同源;下发给播放器时必须带同一组头。
final Map<String, String> youtubePlaybackHeaders = sanitizeHeaders(const {
  'user-agent': kYoutubeUserAgent,
  'referer': 'https://www.youtube.com/',
});
