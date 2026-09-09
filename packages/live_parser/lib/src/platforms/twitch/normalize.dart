/// Twitch 输入归一:房间标识统一为小写 login(`fps_shaka`)。
library;

/// 站点 id。
const String kTwitchSiteId = 'twitch';

final RegExp _twitchHost = RegExp(r'^(www\.)?twitch\.tv/', caseSensitive: false);

/// 从完整 URL、裸 login 或 `@login` 中提取 login;无法识别时返回空串。
///
/// 仅支持直播间;VOD(`/videos/...`)与短链不在首版范围内。
String normalizeTwitchLogin(String input) {
  var text = input.trim();
  if (text.isEmpty) return '';
  if (text.startsWith('@')) text = text.substring(1);
  if (!text.contains('://') && _twitchHost.hasMatch(text)) {
    text = 'https://$text';
  }

  final uri = Uri.tryParse(text);
  if (uri != null && uri.hasScheme) {
    final host = uri.host.toLowerCase();
    if (host == 'twitch.tv' || host.endsWith('.twitch.tv')) {
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segments.isEmpty) return '';
      if (segments.first == 'videos') return '';
      return segments.first.toLowerCase();
    }
    // 其它域名的 URL 不是 Twitch 直播间。
    return '';
  }
  if (text.contains('/') || text.contains(' ')) return '';
  return text.toLowerCase();
}

/// Twitch CDN 图片模板:把 `{width}x{height}` 填成实际尺寸。
String fillTwitchImageTemplate(String url, {int width = 640, int height = 360}) {
  if (url.isEmpty) return '';
  return url
      .replaceFirst('{width}', '$width')
      .replaceFirst('{height}', '$height')
      .replaceAll('{width}x{height}', '${width}x$height');
}
