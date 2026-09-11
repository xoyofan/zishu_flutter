/// 抖音输入归一、公共请求头与随机 token。
library;

import 'dart:math';

import '../../http/parser_http.dart';

/// 抖音站点标识(与 UI PlatformBrandCatalog / nav 对齐)。
const String kDouyinSiteId = 'douyin';

/// 抖音解析源标识。
const String kDouyinSource = 'live_parser/douyin';

/// PC Web 端固定 UA(与签名实现绑定的浏览器版本,不要随意升级)。
const String kDouyinUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36';

/// msToken 字符集与默认长度(与 web 端一致)。
const String _kMsTokenChars =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';

/// 生成随机 msToken(默认 107 位)。
String randomDouyinMsToken([int length = 107]) {
  final random = Random.secure();
  return String.fromCharCodes(
    Iterable.generate(
      length,
      (_) => _kMsTokenChars.codeUnitAt(random.nextInt(_kMsTokenChars.length)),
    ),
  );
}

/// PC 端通用请求头。
Map<String, String> douyinPcHeaders({
  String referer = 'https://live.douyin.com/',
  String? cookie,
}) => {
  'User-Agent': kDouyinUserAgent,
  'Accept-Language': 'zh-CN,zh;q=0.9',
  'Referer': referer,
  if (cookie != null && cookie.trim().isNotEmpty) 'Cookie': cookie.trim(),
};

/// 将房间号或抖音直播地址归一为 web_rid。
String normalizeDouyinRoomId(String value) {
  final text = value.trim();
  if (text.isEmpty) return '';
  if (RegExp(r'^\d+$').hasMatch(text)) return text;
  if (RegExp(r'^[A-Za-z0-9_.+-]+$').hasMatch(text)) return text;
  if (!text.contains('douyin.com')) {
    throw ParserHttpException('无效的抖音地址: $value');
  }
  var url = text;
  if (!url.startsWith('http')) url = 'https://$url';
  final uri = Uri.tryParse(url);
  if (uri == null) throw ParserHttpException('无效的抖音地址: $value');
  final segments = uri.pathSegments.where((segment) => segment.isNotEmpty).toList();
  if (segments.isEmpty) return '';
  return segments.last;
}

/// 房间页地址。
String douyinSourceUrl(String webRid) => 'https://live.douyin.com/$webRid';

/// `//`、`http://` 图片地址统一为 HTTPS。
String httpsDouyinUrl(Object? raw) {
  final value = raw?.toString().trim() ?? '';
  if (value.isEmpty) return '';
  if (value.startsWith('//')) return 'https:$value';
  if (value.startsWith('http://')) return 'https://${value.substring(7)}';
  return value;
}

/// 按 URLSearchParams 语义序列化(空格 `+`;键值都做 query 编码)。
String serializeDouyinQuery(List<MapEntry<String, String>> params) {
  return params
      .map(
        (entry) =>
            '${Uri.encodeQueryComponent(entry.key)}='
            '${Uri.encodeQueryComponent(entry.value)}',
      )
      .join('&');
}
