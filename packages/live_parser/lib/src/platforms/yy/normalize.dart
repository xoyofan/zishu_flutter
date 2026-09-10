/// YY 输入归一与图片/网页地址规范化。
library;

import '../../http/parser_http.dart';

/// YY 站点标识。
const String kYySiteId = 'yy';

final RegExp _digitsOnly = RegExp(r'^\d+$');
final RegExp _yyHost = RegExp(r'(^|\.)yy\.com$', caseSensitive: false);

/// 将房间号或 YY 房间地址归一为数字 sid。
///
/// YY 房间地址可能带协议、查询参数和末尾斜杠。对于站点地址，优先
/// 解析 path，避免把 query 中无关数字误认成房间号；其它输入则沿用
/// 旧适配器的末段数字兜底行为。
String normalizeYyRoomId(String value) {
  final raw = value.trim();
  if (raw.isEmpty) return '';
  if (_digitsOnly.hasMatch(raw)) return raw;

  var candidate = raw;
  if (!candidate.contains('://') &&
      (candidate.toLowerCase().startsWith('yy.com') ||
          candidate.toLowerCase().startsWith('www.yy.com'))) {
    candidate = 'https://$candidate';
  }

  final uri = Uri.tryParse(candidate);
  if (uri != null && uri.hasScheme) {
    if (!_yyHost.hasMatch(uri.host)) {
      throw ParserHttpException('无效的 YY 地址: $value');
    }
    for (final segment in uri.pathSegments.reversed) {
      if (_digitsOnly.hasMatch(segment)) return segment;
    }
    final pathDigits = RegExp(r'(\d+)').allMatches(uri.path).toList();
    if (pathDigits.isNotEmpty) return pathDigits.last.group(1)!;
    throw ParserHttpException('无法解析 YY 房间号: $value');
  }

  final yyHost = RegExp(r'(?:^|\.)yy\.com(?:/|$)', caseSensitive: false);
  if (yyHost.hasMatch(raw)) {
    final digits = RegExp(r'(\d+)').allMatches(raw).toList();
    if (digits.isNotEmpty) return digits.last.group(1)!;
  }

  final digits = RegExp(r'(\d+)').allMatches(raw).toList();
  if (digits.isNotEmpty) return digits.last.group(1)!;
  throw ParserHttpException('无法解析 YY 房间号: $value');
}

/// 常用别名：与参考 TypeScript 适配器保持同名语义。
String normalizeYy(String value) => normalizeYyRoomId(value);

/// 常用别名：从房间输入生成规范化的 YY 房间页地址。
String normalizeYyUrl(String value) {
  final roomId = normalizeYyRoomId(value);
  if (roomId.isEmpty) throw ParserHttpException('无效的 YY 房间输入: $value');
  return 'https://www.yy.com/$roomId';
}

/// `//`、`http://` 图片地址统一为 HTTPS。
String httpsYyUrl(Object? raw) {
  final value = raw?.toString().trim() ?? '';
  if (value.isEmpty) return '';
  if (value.startsWith('//')) return 'https:$value';
  if (value.startsWith('http://')) return 'https://${value.substring(7)}';
  return value;
}

/// 常用别名：参考适配器中的 `validImgUrl`。
String validYyImgUrl(Object? raw) => httpsYyUrl(raw);
