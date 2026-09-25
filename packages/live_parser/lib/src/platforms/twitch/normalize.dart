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

/// Twitch `broadcastLanguage` → 中文展示名。
///
/// 仅覆盖实测出现的语言码;未收录的码原样返回(数据诚实性:不猜译)。
/// 映射表在 Twitch 侧,不进共享层——其它平台语言码语义不同,各自维护。
/// 注意:语言 chip 仅展示不可点(Twitch `streams(broadcastLanguage:)`
/// 过滤不支持),映射只影响展示文案。
String twitchLanguageName(String code) => _twitchLanguageNames[code] ?? code;

const Map<String, String> _twitchLanguageNames = {
  'RU': '俄语',
  'FR': '法语',
  'EN': '英语',
  'DE': '德语',
  'JP': '日语',
  'KR': '韩语',
  'ZH': '中文',
};
