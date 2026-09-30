/// B 站 WBI 签名与匿名 buvid3(best-effort:取不到时回落无签名/无 cookie)。
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../http/parser_http.dart';
import '../douyu/json_utils.dart';

/// 标准 WBI mixinKey 混淆表(64 项,公开算法)。
const List<int> kWbiMixinKeyEncTab = [
  46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35, 27, 43, 5, 49,
  33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13, 37, 48, 7, 16, 24, 55, 40, 61,
  26, 17, 0, 1, 60, 51, 30, 4, 22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11, 36,
  20, 34, 44, 52,
];

String getWbiMixinKey(String imgKey, String subKey) {
  final s = imgKey + subKey;
  final buffer = StringBuffer();
  for (final i in kWbiMixinKeyEncTab) {
    if (i < s.length) buffer.write(s[i]);
  }
  final key = buffer.toString();
  return key.length <= 32 ? key : key.substring(0, 32);
}

/// WBI 签名:过滤含 `!` 的值 → 追加 wts → key 升序拼接 → md5(joined + mixinKey)。
/// 返回带 wts + w_rid 的新参数表。
Map<String, String> signWbi(
  Map<String, String> params,
  String mixinKey, {
  required int wts,
}) {
  final body = <String, String>{};
  params.forEach((key, value) {
    if (value.contains('!')) return;
    body[key] = value;
  });
  body['wts'] = '$wts';
  final keys = body.keys.toList()..sort();
  final joined = keys.map((k) => '$k=${body[k]}').join('&');
  body['w_rid'] = md5.convert(utf8.encode(joined + mixinKey)).toString();
  return body;
}

/// mixinKey + buvid3 缓存(TTL 内复用)。
class BilibiliCredentials {
  BilibiliCredentials({DateTime Function()? now}) : _now = now ?? (() => DateTime.now());

  final DateTime Function() _now;

  static const _keysTtl = Duration(hours: 12);
  static const _buvidTtl = Duration(hours: 24);

  String? _mixinKey;
  DateTime? _mixinKeyAt;
  String? _buvid3;
  DateTime? _buvidAt;

  /// 登录 Cookie 整串(凭证页粘贴,核心是 SESSDATA)。空串 = 匿名。
  /// 由 [BilibiliClient] 构造时注入;请求头在 bilibiliFetchJson 里与匿名
  /// buvid3 合并(不能塞 ParserHttp 默认头:每次请求的 `Cookie: buvid3=…`
  /// 会整键覆盖默认头,登录态就丢了)。
  String loginCookie = '';

  String? peekMixinKey() => _valid(_mixinKey, _mixinKeyAt, _keysTtl);
  String? peekBuvid3() => _valid(_buvid3, _buvidAt, _buvidTtl);

  String? _valid(String? value, DateTime? at, Duration ttl) {
    if (value == null || at == null) return null;
    if (_now().difference(at) < ttl) return value;
    return null;
  }

  void cacheMixinKey(String key) {
    _mixinKey = key;
    _mixinKeyAt = _now();
  }

  void cacheBuvid3(String value) {
    _buvid3 = value;
    _buvidAt = _now();
  }

  /// nav 接口取 img/sub key 混出 mixinKey;失败返回 null。
  Future<String?> fetchMixinKey(ParserHttp http) async {
    final cached = peekMixinKey();
    if (cached != null) return cached;
    try {
      final response = await http.get(
        Uri.parse('https://api.bilibili.com/x/web-interface/nav'),
        headers: const {'Referer': 'https://www.bilibili.com/'},
      );
      final payload = jsonMapOf(jsonDecode(utf8.decode(response.bodyBytes)));
      final wbi = jsonMapOf(jsonMapOf(payload['data'])['wbi_img']);
      final imgUrl = jsonText(wbi['img_url']);
      final subUrl = jsonText(wbi['sub_url']);
      if (imgUrl.isEmpty || subUrl.isEmpty) return null;
      final imgKey = _fileNameKey(imgUrl);
      final subKey = _fileNameKey(subUrl);
      if (imgKey.isEmpty || subKey.isEmpty) return null;
      final mixinKey = getWbiMixinKey(imgKey, subKey);
      cacheMixinKey(mixinKey);
      return mixinKey;
    } on ParserHttpException {
      return null;
    }
  }

  /// finger/spi 匿名 buvid3(无需登录);失败返回空串。
  Future<String> fetchBuvid3(ParserHttp http) async {
    final cached = peekBuvid3();
    if (cached != null) return cached;
    try {
      final response = await http.get(
        Uri.parse('https://api.bilibili.com/x/frontend/finger/spi'),
        headers: const {'Referer': 'https://www.bilibili.com/'},
      );
      final payload = jsonMapOf(jsonDecode(utf8.decode(response.bodyBytes)));
      final b3 = jsonText(payload['data'] == null ? null : jsonMapOf(payload['data'])['b_3']).trim();
      if (b3.isNotEmpty) {
        cacheBuvid3(b3);
        return b3;
      }
    } on ParserHttpException {
      // 回落无 cookie。
    }
    return '';
  }
}

String _fileNameKey(String url) {
  final file = url.split('/').last;
  return file.split('.').first;
}
