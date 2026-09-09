/// 虎牙输入归一:房间号或 URL 统一为标准房间页地址。
library;

import '../../http/parser_http.dart';

final RegExp _digitsOnly = RegExp(r'^\d+$');

/// 房间号/URL 归一:纯数字补全域名;缺协议补 https;非虎牙地址直接拒绝。
String normalizeHuyaUrl(String value) {
  final text = value.trim();
  if (_digitsOnly.hasMatch(text)) {
    return 'https://www.huya.com/$text';
  }
  if (!text.contains('huya.com')) {
    throw ParserHttpException('无效的虎牙地址: $value');
  }
  if (!text.startsWith('http')) {
    return 'https://$text';
  }
  return text;
}

/// 从标准地址提取末段房间标识(数字房间号或主播别名);别名需回源换取数字 rid。
String huyaRoomIdFromUrl(String url) {
  final withoutQuery = url.split('?').first;
  final segments = withoutQuery.split('/').where((s) => s.isNotEmpty).toList();
  return segments.isEmpty ? '' : segments.last;
}

/// 末段含字母即为主播别名地址,需请求页面换取数字房间号。
bool isHuyaAliasRoomId(String roomId) => roomId.contains(RegExp('[a-zA-Z]'));
