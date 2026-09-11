/// 快手直播输入归一与图片地址规范化。
library;

import '../../http/parser_http.dart';

/// 快手站点标识(与 UI PlatformBrandCatalog / nav 对齐)。
const String kKuaishouSiteId = 'kuaishou';

/// 快手解析源标识。
const String kKuaishouSource = 'live_parser/kuaishou';

final RegExp _kuaishouHost = RegExp(
  r'(^|\.)(kuaishou\.com|chenzhongtech\.com|gifshow\.com)$',
  caseSensitive: false,
);

/// 房间页路径段(非房间号),归一 URL 时跳过。
const Set<String> _pathBlocklist = {'u', 'profile', 'live', 'explore'};

/// 快手掌上常见图片扩展名;poster 缺扩展名时补 `.jpg`。
const List<String> kKuaishouImageExtensions = [
  'png',
  'jpg',
  'jpeg',
  'webp',
  'bmp',
  'gif',
  'avif',
];

/// 将房间号或快手房间地址归一为作者 id。
String normalizeKuaishouRoomId(String value) {
  final raw = value.trim();
  if (raw.isEmpty) return '';
  if (!raw.contains('://') && !raw.contains('/')) return raw;

  var candidate = raw;
  if (!candidate.contains('://') && !candidate.startsWith('//')) {
    candidate = 'https://$candidate';
  }
  final uri = Uri.tryParse(candidate);
  if (uri != null && uri.hasScheme && _kuaishouHost.hasMatch(uri.host)) {
    for (final segment in uri.pathSegments.reversed) {
      if (segment.isEmpty || _pathBlocklist.contains(segment.toLowerCase())) {
        continue;
      }
      return segment;
    }
  }

  final segments = raw
      .split('/')
      .where((segment) => segment.isNotEmpty)
      .toList(growable: false);
  if (segments.isNotEmpty) return segments.last.split('?').first;
  throw ParserHttpException('无法解析快手房间号: $value');
}

/// 从房间号生成规范化房间页地址。
String kuaishouSourceUrl(String roomId) => 'https://live.kuaishou.com/u/$roomId';

/// `//`、`http://` 图片地址统一为 HTTPS。
String httpsKuaishouUrl(Object? raw) {
  final value = raw?.toString().trim() ?? '';
  if (value.isEmpty) return '';
  if (value.startsWith('//')) return 'https:$value';
  if (value.startsWith('http://')) return 'https://${value.substring(7)}';
  return value;
}

/// poster 是否为图片扩展名(否则上游需补 `.jpg`)。
bool isKuaishouImageUrl(String url) {
  if (url.isEmpty) return false;
  final path = url.split('?').first;
  final dot = path.lastIndexOf('.');
  if (dot < 0 || dot == path.length - 1) return false;
  return kKuaishouImageExtensions.contains(
    path.substring(dot + 1).toLowerCase(),
  );
}

/// 封面地址:协议归一,缺扩展名补 `.jpg`。
String kuaishouPosterUrl(Object? raw) {
  final url = httpsKuaishouUrl(raw);
  if (url.isEmpty || isKuaishouImageUrl(url)) return url;
  return '$url.jpg';
}
