/// IPTV M3U 播放列表解析 + SSRF 防护 + 分组/地区中文化。
///
/// 解析 `#EXTINF` 的 tvg-id/tvg-name/tvg-logo/group-title 与下一行 URL;
/// 兼容 `#EXTGRP` 分组行、单引号/无引号属性;同 URL 去重。
library;

/// 频道条目(playlist 解析产物)。
class IptvChannel {
  const IptvChannel({
    required this.id,
    required this.name,
    required this.url,
    required this.logo,
    required this.group,
    required this.tvgId,
    this.quality,
    this.country,
    this.geoBlocked = false,
    this.not247 = false,
  });

  /// 稳定频道 id:tvg-id 优先,其次净化后的频道名。
  final String id;
  final String name;
  final String url;
  final String logo;
  final String group;
  final String tvgId;

  /// 清晰度:名称 (1080p) 或 tvg-id @SD/@HD/@FHD/@UHD 推导。
  final String? quality;

  /// 国家/地区中文名(tvg-id TLD 推导)。
  final String? country;
  final bool geoBlocked;
  final bool not247;
}

/// SSRF 违规:远程播放列表使用了内网/保留地址或非法协议。
class IptvSsrfException implements Exception {
  const IptvSsrfException(this.message);

  final String message;

  @override
  String toString() => 'IptvSsrfException: $message';
}

/// 内网/保留地址段(IPv4 点分 + 常见 IPv6 形态)。
final List<RegExp> _privateHostPatterns = [
  RegExp(r'^localhost$', caseSensitive: false),
  RegExp(r'\.localhost$', caseSensitive: false),
  RegExp(r'\.local$', caseSensitive: false),
  RegExp(r'\.internal$', caseSensitive: false),
  RegExp(r'^0\.0\.0\.0$'),
  RegExp(r'^127\.\d{1,3}\.\d{1,3}\.\d{1,3}$'),
  RegExp(r'^10\.\d{1,3}\.\d{1,3}\.\d{1,3}$'),
  RegExp(r'^169\.254\.\d{1,3}\.\d{1,3}$'),
  RegExp(r'^172\.(1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3}$'),
  RegExp(r'^192\.168\.\d{1,3}\.\d{1,3}$'),
  RegExp(r'^100\.(6[4-9]|[7-9]\d|1[01]\d|12[0-7])\.\d{1,3}\.\d{1,3}$'),
  RegExp(r'^192\.0\.0\.\d{1,3}$'),
  RegExp(r'^198\.1[89]\.\d{1,3}\.\d{1,3}$'),
  RegExp(r'^(2(2[4-9]|3\d))\.\d{1,3}\.\d{1,3}\.\d{1,3}$'),
  RegExp(r'^240\.'),
  RegExp(r'^\[?::1\]?$'),
  RegExp(r'^\[?fc00:', caseSensitive: false),
  RegExp(r'^\[?fe80:', caseSensitive: false),
];

/// SSRF 防护:仅 http/https + 拒绝内网/保留地址(IP 字面量与内网域名形态)。
Uri assertSafePlaylistUrl(String rawUrl) {
  final text = rawUrl.trim();
  final Uri parsed;
  try {
    parsed = Uri.parse(text);
  } on FormatException {
    throw IptvSsrfException('无效的播放列表 URL: $rawUrl');
  }
  if ((parsed.scheme != 'http' && parsed.scheme != 'https') || !text.toLowerCase().startsWith('http')) {
    throw IptvSsrfException('不允许的协议: ${parsed.scheme}');
  }
  final host = parsed.host.toLowerCase();
  final isIpv4Literal = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host);
  if (host.isEmpty ||
      isIpv4Literal ||
      _privateHostPatterns.any((re) => re.hasMatch(host))) {
    throw IptvSsrfException('拒绝内网/保留地址: $host');
  }
  if (host.startsWith('[') && !RegExp(r'^\[2[0-9a-f]', caseSensitive: false).hasMatch(host)) {
    throw IptvSsrfException('拒绝非公网 IPv6 地址: $host');
  }
  return parsed;
}

/// 频道名 → 稳定 id(小写、非法字符折叠为 -)。
String channelSlug(String name) {
  var slug = name
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fff]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (slug.length > 64) slug = slug.substring(0, 64);
  return slug.isEmpty ? 'channel' : slug;
}

/// EXTINF 属性解析:兼容双引号/单引号/无引号。
String _extinfAttr(String line, String key) {
  final m = RegExp(
    '$key="([^"]*)"|$key=\'([^\']*)\'|$key=([^\\s,]+)',
    caseSensitive: false,
  ).firstMatch(line);
  return (m?.group(1) ?? m?.group(2) ?? m?.group(3) ?? '').trim();
}

/// 解析 M3U 文本 → 频道列表。
List<IptvChannel> parseM3U(String content) {
  final channels = <IptvChannel>[];
  final seen = <String>{};
  final lines = content.split(RegExp(r'\r?\n'));
  String? attrs;
  var name = '';
  var extGroup = '';

  for (final rawLine in lines) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    if (line.toUpperCase().startsWith('#EXTINF')) {
      final commaIdx = line.indexOf(',');
      attrs = commaIdx >= 0 ? line.substring(0, commaIdx) : line;
      name = commaIdx >= 0 ? line.substring(commaIdx + 1).trim() : '';
      extGroup = '';
      continue;
    }
    if (line.toUpperCase().startsWith('#EXTGRP')) {
      final idx = line.indexOf(':');
      if (idx >= 0) extGroup = line.substring(idx + 1).trim();
      continue;
    }
    if (line.startsWith('#')) continue;

    final url = line;
    if (!url.toLowerCase().startsWith('http') || attrs == null) {
      attrs = null;
      continue;
    }
    if (!seen.add(url)) {
      attrs = null;
      continue;
    }
    final tvgId = _extinfAttr(attrs, 'tvg-id');
    final tvgName = _extinfAttr(attrs, 'tvg-name');
    final channelName = name.isNotEmpty ? name : (tvgName.isNotEmpty ? tvgName : '未命名频道');
    final group = _extinfAttr(attrs, 'group-title').isNotEmpty
        ? _extinfAttr(attrs, 'group-title')
        : (extGroup.isNotEmpty ? extGroup : '未分组');
    channels.add(
      IptvChannel(
        id: tvgId.isNotEmpty ? tvgId : channelSlug(channelName),
        name: channelName,
        url: url,
        logo: _extinfAttr(attrs, 'tvg-logo'),
        group: group,
        tvgId: tvgId,
        quality: qualityOf(channelName, tvgId),
        country: countryZhOf(tvgId),
        geoBlocked: RegExp(r'\[geo-blocked\]', caseSensitive: false).hasMatch(channelName),
        not247: RegExp(r'not\s*24/7', caseSensitive: false).hasMatch(channelName),
      ),
    );
    attrs = null;
    name = '';
    extGroup = '';
  }
  return channels;
}

/// 频道流地址的展示格式:m3u8 → hls;flv → flv;其余 → ts 直链。
String channelFormat(String url) {
  final u = url.toLowerCase();
  if (u.contains('.m3u8')) return 'hls';
  if (u.contains('.flv')) return 'flv';
  return 'ts';
}

const Map<String, String> _feedQuality = {
  'sd': '标清',
  'hd': '高清',
  'fhd': '全高清',
  'uhd': '4K',
  '4k': '4K',
};

/// 清晰度:名称 (1080p)/(720p) 优先,其次 tvg-id 尾部 @SD/@HD/@FHD/@UHD。
String? qualityOf(String name, String tvgId) {
  final p = RegExp(r'\((\d{3,4})[pP]\)').firstMatch(name);
  if (p != null) return '${p.group(1)}p';
  final feed = RegExp(r'@([A-Za-z0-9]+)$').firstMatch(tvgId)?.group(1)?.toLowerCase();
  if (feed == null) return null;
  return _feedQuality[feed];
}

const Map<String, String> _groupZh = {
  'general': '综合',
  'news': '新闻',
  'entertainment': '娱乐',
  'religious': '宗教',
  'movies': '电影',
  'music': '音乐',
  'series': '剧集',
  'sports': '体育',
  'kids': '少儿',
  'documentary': '纪录片',
  'education': '教育',
  'comedy': '喜剧',
  'culture': '文化',
  'legislative': '政务',
  'animation': '动画',
  'lifestyle': '生活',
  'classic': '经典',
  'shop': '购物',
  'business': '商业',
  'outdoor': '户外',
  'travel': '旅游',
  'family': '家庭',
  'cooking': '美食',
  'public': '公共',
  'auto': '汽车',
  'science': '科学',
  'weather': '天气',
  'relax': '休闲',
  'interactive': '互动',
};

/// 分组名 → 中文展示名(大小写不敏感;空 → 未分组;未收录原样返回)。
String iptvGroupZh(String group) {
  final raw = group.trim();
  if (raw.isEmpty) return '未分组';
  return _groupZh[raw.toLowerCase()] ?? raw;
}

const Map<String, String> _tldZh = {
  'cn': '中国', 'hk': '香港', 'tw': '台湾', 'mo': '澳门', 'jp': '日本', 'kr': '韩国',
  'sg': '新加坡', 'my': '马来西亚', 'th': '泰国', 'vn': '越南', 'ph': '菲律宾',
  'id': '印尼', 'in': '印度', 'pk': '巴基斯坦', 'bd': '孟加拉', 'lk': '斯里兰卡',
  'np': '尼泊尔', 'kz': '哈萨克斯坦', 'tr': '土耳其', 'ae': '阿联酋', 'sa': '沙特',
  'il': '以色列', 'ir': '伊朗', 'iq': '伊拉克', 'qa': '卡塔尔', 'us': '美国',
  'ca': '加拿大', 'mx': '墨西哥', 'br': '巴西', 'ar': '阿根廷', 'cl': '智利',
  'co': '哥伦比亚', 'pe': '秘鲁', 've': '委内瑞拉', 'uk': '英国', 'gb': '英国',
  'fr': '法国', 'de': '德国', 'it': '意大利', 'es': '西班牙', 'pt': '葡萄牙',
  'nl': '荷兰', 'be': '比利时', 'ch': '瑞士', 'at': '奥地利', 'se': '瑞典',
  'no': '挪威', 'dk': '丹麦', 'fi': '芬兰', 'pl': '波兰', 'cz': '捷克',
  'ro': '罗马尼亚', 'hu': '匈牙利', 'gr': '希腊', 'ru': '俄罗斯', 'ua': '乌克兰',
  'au': '澳大利亚', 'nz': '新西兰', 'za': '南非', 'eg': '埃及', 'ng': '尼日利亚',
  'ma': '摩洛哥', 'dz': '阿尔及利亚',
};

/// tvg-id → 国家/地区中文名(形如 `ChannelId.cc@feed`;无 TLD 或未收录返回 null)。
String? countryZhOf(String tvgId) {
  final m = RegExp(r'\.([a-z]{2})(?:@|$)', caseSensitive: false).firstMatch(tvgId.trim());
  if (m == null) return null;
  return _tldZh[m.group(1)!.toLowerCase()];
}
