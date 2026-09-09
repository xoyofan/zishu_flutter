/// 斗鱼输入归一:房间号或 URL 统一为标准房间页地址。
library;

import '../../http/parser_http.dart';

final RegExp _digitsOnly = RegExp(r'^\d+$');
final RegExp _douyuRidInUrl = RegExp(r'douyu\.com/(\d+)');
final RegExp _ridParam = RegExp(r'rid=(\d+)');

/// 房间号/URL 归一:纯数字补全域名;缺协议补 https;非斗鱼地址直接拒绝。
String normalizeDouyuUrl(String value) {
  final text = value.trim();
  if (_digitsOnly.hasMatch(text)) {
    return 'https://www.douyu.com/$text';
  }
  if (!text.contains('douyu.com')) {
    throw ParserHttpException('无效的斗鱼地址: $value');
  }
  if (!text.startsWith('http')) {
    return 'https://$text';
  }
  return text;
}

/// 从标准地址中提取数字房间号;失败返回空串(由调用方走房间别名解析)。
String douyuRidFromUrl(String url) {
  final ridInUrl = _douyuRidInUrl.firstMatch(url)?.group(1);
  if (ridInUrl != null) return ridInUrl;
  return _ridParam.firstMatch(url)?.group(1) ?? '';
}
