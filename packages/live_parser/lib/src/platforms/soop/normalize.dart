/// SOOP(原 AfreecaTV)输入归一与图片地址规范化。
library;

import '../../http/parser_http.dart';

/// SOOP 站点标识(与 UI PlatformBrandCatalog / nav 对齐)。
const String kSoopSiteId = 'soop';

/// SOOP 解析源标识。
const String kSoopSource = 'live_parser/soop';

final RegExp _roomIdPattern = RegExp(r'^[A-Za-z0-9_]+$');
final RegExp _soopHost = RegExp(
  r'(^|\.)(sooplive\.co\.kr|afreecatv\.com)$',
  caseSensitive: false,
);

/// 播放页路径段(非房间号),归一 URL 时跳过。
const Set<String> _pathBlocklist = {'station', 'player', 'embed', 'live'};

/// 将房间号或 SOOP 房间地址归一为 BJID。
///
/// 支持 `play.sooplive.co.kr/{id}`、`www.sooplive.co.kr/station/{id}`、
/// `bj.afreecatv.com/{id}` 等形态;非站点地址按末段兜底。
String normalizeSoopRoomId(String value) {
  final raw = value.trim();
  if (raw.isEmpty) return '';
  if (!raw.contains('://') && !raw.contains('/')) {
    if (_roomIdPattern.hasMatch(raw)) return raw;
    throw ParserHttpException('无法解析 SOOP 房间号: $value');
  }

  var candidate = raw;
  if (!candidate.contains('://') && !candidate.startsWith('//')) {
    candidate = 'https://$candidate';
  }
  final uri = Uri.tryParse(candidate);
  if (uri != null && uri.hasScheme && _soopHost.hasMatch(uri.host)) {
    for (final segment in uri.pathSegments.reversed) {
      if (segment.isEmpty || _pathBlocklist.contains(segment.toLowerCase())) {
        continue;
      }
      if (_roomIdPattern.hasMatch(segment)) return segment;
    }
  }

  if (_roomIdPattern.hasMatch(raw)) return raw;
  throw ParserHttpException('无法解析 SOOP 房间号: $value');
}

/// 从房间号生成规范化播放页地址。
String soopSourceUrl(String roomId) => 'https://play.sooplive.co.kr/$roomId';

/// `//`、`http://` 图片地址统一为 HTTPS。
String httpsSoopUrl(Object? raw) {
  final value = raw?.toString().trim() ?? '';
  if (value.isEmpty) return '';
  if (value.startsWith('//')) return 'https:$value';
  if (value.startsWith('http://')) return 'https://${value.substring(7)}';
  return value;
}

/// 房间详情头像(station LOGO 桌面形态,缺失时上游 404,由 UI 兜底)。
///
/// 形态 `LOGO/{前两位}/{id}/{id}.jpg` **不带 `/m/` 段**:2026-09 探针实测
/// 30/30 真实房间 `LOGO/{bucket}/{id}/m/{id}.jpg` 全量 404(桌面 jpg 已迁出
/// `/m/` 段;`/m/` 仅剩移动端 webp 形态,见 [soopMobileAvatarUrl]),
/// 而不带 `/m/` 的 jpg 30/30 全部 200 —— 旧形态会让播放页头像整站兜底成
/// 首字母占位。
String soopAvatarUrl(String roomId) {
  if (roomId.length < 2) return '';
  final bucket = roomId.substring(0, 2);
  return 'https://stimg.sooplive.co.kr/LOGO/$bucket/$roomId/$roomId.jpg';
}

/// 搜索/列表头像(m 站规格)。
String soopMobileAvatarUrl(String roomId) {
  if (roomId.length < 2) return '';
  final bucket = roomId.substring(0, 2);
  return 'https://stimg.sooplive.co.kr/LOGO/$bucket/$roomId/m/$roomId.webp';
}
