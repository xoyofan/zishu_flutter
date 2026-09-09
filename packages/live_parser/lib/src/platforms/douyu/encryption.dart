/// 白名单密钥:getEncryption 拉取 + TTL 缓存 + md5 auth 计算。
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../http/parser_http.dart';
import 'json_utils.dart';

/// 未登录态固定 did(SFVideoLive 同款)。
const String kDouyuDefaultDid = '10000000000000000000000000001501';

class WhiteKey {
  const WhiteKey({
    required this.key,
    required this.randStr,
    required this.encTime,
    required this.encData,
    required this.isSpecial,
  });

  final String key;
  final String randStr;
  final int encTime;
  final String encData;
  final bool isSpecial;

  factory WhiteKey.fromJson(Map<String, dynamic> json) => WhiteKey(
    key: jsonText(json['key']),
    randStr: jsonText(json['rand_str']),
    encTime: jsonInt(json['enc_time']),
    encData: jsonText(json['enc_data']),
    isSpecial: jsonBool(json['is_special']),
  );
}

String md5Hex(String text) => md5.convert(utf8.encode(text)).toString();

/// 斗鱼播放接口签名:`secret` 迭代 md5(rand_str + key) enc_time 次,
/// 再叠加 salt(非 special 白名单为 rid+ts)。
String computeDouyuAuth({
  required String rid,
  required WhiteKey white,
  required int ts,
}) {
  var secret = white.randStr;
  final salt = white.isSpecial ? '' : '$rid$ts';
  for (var i = 0; i < white.encTime; i++) {
    secret = md5Hex(secret + white.key);
  }
  return md5Hex(secret + white.key + salt);
}

/// getEncryption 结果缓存:有效期内直接复用,过期后重新拉取。
class WhiteKeyCache {
  WhiteKeyCache({
    this.ttl = const Duration(seconds: 60),
    DateTime Function()? now,
  }) : _now = now ?? (() => DateTime.now());

  final Duration ttl;
  final DateTime Function() _now;

  WhiteKey? _cached;
  int _expiresAtEpochSec = 0;

  WhiteKey? peek() {
    final nowSec = _now().millisecondsSinceEpoch ~/ 1000;
    if (_cached != null && nowSec < _expiresAtEpochSec) return _cached;
    return null;
  }

  Future<WhiteKey> fetch(ParserHttp http, {String did = kDouyuDefaultDid}) async {
    final cached = peek();
    if (cached != null) return cached;

    final url = Uri.parse(
      'https://www.douyu.com/wgapi/livenc/liveweb/websec/getEncryption?did=$did',
    );
    final response = await http.get(url);
    final payload = jsonMapOf(jsonDecode(utf8.decode(response.bodyBytes)));
    if (jsonInt(payload['error']) != 0 || payload['data'] is! Map<String, dynamic>) {
      throw const ParserHttpException('获取白名单密钥失败');
    }
    final white = WhiteKey.fromJson(payload['data'] as Map<String, dynamic>);
    _cached = white;
    _expiresAtEpochSec = _now().millisecondsSinceEpoch ~/ 1000 + ttl.inSeconds;
    return white;
  }

  /// 仅供测试重置。
  void debugReset() {
    _cached = null;
    _expiresAtEpochSec = 0;
  }
}
