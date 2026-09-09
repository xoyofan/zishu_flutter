/// B 站输入归一。
library;

import '../../http/parser_http.dart';

final RegExp _digitsOnly = RegExp(r'^\d+$');
final RegExp _roomIdInUrl = RegExp(r'live\.bilibili\.com/(?:blanc/)?(\d+)');

/// 房间号/URL 归一:纯数字补全域名;缺协议补 https;非 B 站地址直接拒绝。
String normalizeBilibiliUrl(String value) {
  final text = value.trim();
  if (_digitsOnly.hasMatch(text)) {
    return 'https://live.bilibili.com/$text';
  }
  if (!text.contains('bilibili.com')) {
    throw ParserHttpException('无效的 B 站直播地址: $value');
  }
  if (!text.startsWith('http')) {
    return 'https://$text';
  }
  return text;
}

/// 从标准地址提取数字房间号;个性域名(别名)无法直接提取,返回末段。
String bilibiliRoomIdFromUrl(String url) {
  final normalized = normalizeBilibiliUrl(url);
  final match = _roomIdInUrl.firstMatch(normalized);
  if (match != null) return match.group(1)!;
  final withoutTrailing = normalized.replaceFirst(RegExp(r'/$'), '');
  final segments = withoutTrailing.split('/').where((s) => s.isNotEmpty).toList();
  return segments.isEmpty ? '' : segments.last;
}
