/// 小红书 live-room API 请求签名(xhshow-js 的 Dart 移植)。
///
/// API host: live-room.xiaohongshu.com(非 edith)。签名头 x-s / x-s-common
/// 的算法移植自 npm 包 `xhshow-js`(SFVideoLive services/streaming-server
/// 同款依赖),凭证来自用户导出的浏览器 cookie(`a1` + `web_session`,
/// 约 7 天过期)。
///
/// 契约(与参考实现 signing.ts 对齐):
/// * [XhsSigner.signedHeaders] 返回 live-room API 请求所需**完整请求头**
///   (UA/Referer/Origin/Cookie + x-s/x-t/x-b3-traceid/x-xray-traceid/x-s-common);
/// * [XhsSigner.fromCredential] 接受凭证页保存的原始值 —— 整串 Cookie 或
///   仅 `a1=...; web_session=...` 两个键均可用(与 UI 校验口径一致);
/// * 直连取流(`www.xiaohongshu.com/livestream/<roomId>` 页面抓取)不需要
///   签名,用 [XhsStreamHeaders.iosUserAgent] 模拟 iOS App 即可。
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// live-room.xiaohongshu.com API 签名器。
class XhsSigner {
  XhsSigner({
    required this.a1,
    required this.webSession,
    required this.cookieHeader,
  });

  /// 从凭证页保存的原始值构造:整串 Cookie 或 `a1=...; web_session=...`。
  /// 缺任一键抛 [ArgumentError](调用方 UI 层已校验,这里是解析核心的兜底)。
  factory XhsSigner.fromCredential(String credentialValue) {
    String? pick(String key) => RegExp('$key=([^;\\s]+)')
        .firstMatch(credentialValue)
        ?.group(1);
    final a1 = pick('a1');
    final webSession = pick('web_session');
    if (a1 == null || a1.isEmpty || webSession == null || webSession.isEmpty) {
      throw ArgumentError(
        'xhs credential must contain non-empty a1 and web_session',
      );
    }
    return XhsSigner(
      a1: a1,
      webSession: webSession,
      cookieHeader: credentialValue.trim(),
    );
  }

  /// 设备 id(签名输入)。
  final String a1;

  /// 登录会话(x-s-common 输入)。
  final String webSession;

  /// 完整 Cookie 串(请求头原样携带)。
  final String cookieHeader;

  /// 签名内部随机源(payload 随机字段、RC4 盐、traceid)。
  ///
  /// 用 secure 随机;源实现用 `Math.random`,两者输出结构一致。
  final Random _random = Random.secure();

  /// 生成 live-room API 请求的完整签名头。
  ///
  /// [uri] 为接口路径(如 `/api/sns/red/live/web/feed/category`),
  /// [params] 为 query 参数(GET;签名对排序后的参数串计算)。
  Map<String, String> signedHeaders(
    String method,
    String uri, {
    Map<String, Object?> params = const {},
  }) {
    return {
      'User-Agent': webUserAgent,
      'Accept': 'application/json, text/plain, */*',
      'Referer': 'https://www.xiaohongshu.com/',
      'Origin': 'https://www.xiaohongshu.com',
      'Cookie': cookieHeader,
      ...signGetRequest(method, uri, params: params),
    };
  }

  /// 签名头(x-s/x-t/traceid/x-s-common),不含 UA/Cookie 等基础头。
  Map<String, String> signGetRequest(
    String method,
    String uri, {
    Map<String, Object?> params = const {},
    int? timestampMs,
  }) {
    final ts = timestampMs ?? DateTime.now().millisecondsSinceEpoch;
    return {
      'x-s': signXS(method, uri, params: params, timestampMs: ts),
      'x-t': '$ts',
      'x-b3-traceid': generateB3TraceId(),
      'x-xray-traceid': generateXrayTraceId(),
      'x-s-common': signXSCommon(timestampMs: ts),
    };
  }

  /// x-s 请求签名(`XYS_` + 自定义 base64 的 JSON 包装)。
  ///
  /// 移植自 xhshow-js `Client.signXS`:extractUri → contentString(GET 参数按
  /// key 排序、值做 pythonQuote)→ MD5 → payload → XOR → 截断 124 字节 →
  /// x3 自定义 base64 → 包进 `mns0301_` 前缀的 JSON → `XYS_` 前缀输出。
  /// payload 内嵌随机字段(seed/fpB 偏移/seq/windowPropsLen),同一输入两次
  /// 调用输出不同,这是源算法的既有行为(服务端可解码)。
  String signXS(
    String method,
    String uri, {
    Map<String, Object?> params = const {},
    int? timestampMs,
  }) {
    final cleanUri = _extractUri(uri);
    final contentString = _buildContentString(method, cleanUri, params);
    final dValue = md5.convert(utf8.encode(contentString)).toString();
    final ts = timestampMs ?? DateTime.now().millisecondsSinceEpoch;
    final sig = _buildSignature(dValue, a1, 'xhs-pc-web', contentString, ts, _random);
    final sigData = <String, String>{
      'x0': '4.2.6',
      'x1': 'xhs-pc-web',
      'x2': 'Windows',
      'x3': _x3Prefix + sig,
      'x4': '',
    };
    final jsonBytes = utf8.encode(jsonEncode(sigData));
    return _xysPrefix + _encodeBase64WithAlphabet(jsonBytes, _customBase64Alphabet);
  }

  /// x-s-common 环境签名(自定义 base64 的 JSON,无前缀)。
  ///
  /// 移植自 xhshow-js `XsCommonSigner.sign`:固定 18 键指纹子集 → B1
  /// (RC4 passphrase 模式,随机盐,盐不进入输出)→ crc32 校验 → JSON。
  /// 内含随机指纹与随机 RC4 盐,输出不可逐字节复现(与源实现一致)。
  String signXSCommon({int? timestampMs}) {
    final now = timestampMs ?? DateTime.now().millisecondsSinceEpoch;
    final b1 = _generateB1(_buildB1FingerprintJson(now, _random), _random);
    final x9 = _crc32JsInt(utf8.encode(b1));
    final sig = <String, Object?>{
      's0': 5,
      's1': '',
      'x0': '1',
      'x1': '4.2.6',
      'x2': 'Windows',
      'x3': 'xhs-pc-web',
      'x4': '4.86.0',
      'x5': a1,
      'x6': '',
      'x7': '',
      'x8': b1,
      'x9': x9,
      'x10': 0,
      'x11': 'normal',
    };
    final jsonBytes = utf8.encode(jsonEncode(sig));
    return _encodeBase64WithAlphabet(jsonBytes, _customBase64Alphabet);
  }

  /// x-b3-traceid(16 个 hex 随机字符)。
  String generateB3TraceId() =>
      List.generate(_b3TraceIdLength, (_) => _hexChars[_random.nextInt(16)]).join();

  /// x-xray-traceid(`(毫秒时间戳 << 23 | seq)` 的 hex + 16 个随机 hex 字符)。
  ///
  /// seq 上限 8388607(2^23 - 1),不侵占时间戳位;时间戳超出 64 位
  /// int 表达范围,与源实现一样走 BigInt。
  String generateXrayTraceId() {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final seq = _random.nextInt(_xrayTraceIdSeqMax + 1);
    final part1 =
        ((BigInt.from(ts) << _xrayTraceIdTimestampShift) | BigInt.from(seq))
            .toRadixString(16)
            .padLeft(16, '0');
    final part2 =
        List.generate(16, (_) => _hexChars[_random.nextInt(16)]).join();
    return part1 + part2;
  }

  /// live-room API 使用的 web UA(与参考实现一致)。
  static const String webUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/151.0.0.0 Safari/537.36';
}

/// 直连取流(www.xiaohongshu.com/livestream 页面)的请求头:模拟 iOS App,
/// 无需签名(参考实现 resolve/xhs/index.ts 与 StreamGet 路线)。
abstract final class XhsStreamHeaders {
  /// `www.xiaohongshu.com/livestream/<roomId>` 页面抓取 UA(iOS App)。
  static const String iosUserAgent =
      'ios/7.830 (ios 17.0; ; iPhone 15 (A2846/A3089/A3090/A3092))';

  /// 直连取流请求头(无签名)。
  static Map<String, String> headers() => {
    'User-Agent': iosUserAgent,
    'Referer': 'https://app.xhs.cn/',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
  };
}

// ----------------------------------------------------------------------------
// 以下为 xhshow-js(https://github.com/renmu123/xhshow-js)dist/index.js 的
// Dart 移植私有实现,常量与流程均以该源码为准;随机字段语义保留。
// ----------------------------------------------------------------------------

/// x-s 输出前缀。
const String _xysPrefix = 'XYS_';

/// x3 段前缀。
const String _x3Prefix = 'mns0301_';

/// x-s-common / x3 的自定义 base64 字母表(encodeCustomBase64)。
const String _customBase64Alphabet =
    'ZmserbBoHQtNP+wOcza/LpngG8yJq42KWYj0DSfdikx3VT16IlUAFM97hECvuRX5';

/// x3 段的自定义 base64 字母表(encodeX3Base64)。
const String _x3Base64Alphabet =
    'MfgqrsbcyzPQRStuvC7mn501HIJBo2DEFTKdeNOwxWXYZap89+/A4UVLhijkl63G';

/// 标准 base64 字母表(用于自定义字母表映射)。
const String _standardBase64Alphabet =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

/// payload 前 124 字节的 XOR 密钥(124 字节,恰好覆盖截断后的完整 payload)。
const String _hexKey =
    '71a302257793271ddd273bcee3e4b98d9d7935e1da33f5765e2ea8afb6dc77a5'
    '1a499d23b67c20660025860cbf13d4540d92497f58686c574e508f46e1956344'
    'f39139bf4faf22a3eef120b79258145b2feb5193b6478669961298e79bedca64'
    '6e1a693a926154a5a7a1bd1cf0dedb742f917a747a1e388b234f2277';

/// payload 版本字节(VERSION_BYTES)。
const List<int> _versionBytes = [119, 104, 96, 41];

/// payload 固定尾部(CHECKSUM_FIXED_TAIL,截断 124 后保留前 13 字节)。
const List<int> _checksumFixedTail = [
  249, 65, 103, 103, 201, 181, 131, 99, 94, 7, 68, 250, 132, 21,
];

/// traceid 用的 hex 字符表(源码 HEX_CHARS)。
const String _hexChars = 'abcdef0123456789';

/// x-b3-traceid 长度。
const int _b3TraceIdLength = 16;

/// x-xray-traceid 的 seq 上限(2^23 - 1)与时间戳移位。
const int _xrayTraceIdSeqMax = 8388607;
const int _xrayTraceIdTimestampShift = 23;

/// CHECKSUM_VERSION / CHECKSUM_XOR_KEY / ENV_FINGERPRINT_XOR_KEY。
const int _checksumVersion = 1;
const int _checksumXorKey = 115;
const int _envFingerprintXorKey = 41;

/// B1 指纹 JSON 的固定内容(源码 FingerprintGenerator.generate 中被
/// generateB1 选中的 18 个键;其余指纹字段不参与 B1)。
const String _b1FpX37 = '0|0|0|0|0|0|0|0|0|1|0|0|0|0|0';
const String _b1FpX38 =
    '0|0|1|0|1|0|0|0|0|0|1|0|1|0|1|0|0|0|0|0|0|0|0|0|0|0|0|0|0|0|0|0'
    '|0|0|0|0|0|0|0';
const String _b1FpCanvasHash = '742cc32c';
const String _b1FpX45 = '__SEC_CAV__1-1-1-1-1|__SEC_WSA__|';
const String _b1FpX49 = '{list:[],type:}';
const String _b1FpX82 = '_0x17a2|_0x1954';

/// B1 的 RC4 passphrase(crypto-js 字符串 key → PasswordBasedCipher)。
const String _b1SecretKey = 'xhswebmplfbt';

/// 从 uri 提取路径:以 `/` 开头则截断 `?` 之前;否则按绝对 URL 取 path。
String _extractUri(String u) {
  u = u.trim();
  if (u.startsWith('/')) {
    final idx = u.indexOf('?');
    return idx != -1 ? u.substring(0, idx) : u;
  }
  try {
    final path = Uri.parse(u).path;
    return path.isEmpty ? '/' : path;
  } on FormatException {
    throw FormatException('cannot extract valid URI path from URL: $u');
  }
}

/// 构建签名内容串(GET:排序参数;POST:uri + JSON 体)。
String _buildContentString(
  String method,
  String uri,
  Map<String, Object?> payload,
) {
  if (method.toUpperCase() == 'POST') {
    // 仅 GET 链路使用;数字序列化与 JS JSON.stringify 在小数形态上有差异。
    return uri + jsonEncode(payload);
  }
  if (payload.isEmpty) {
    return uri;
  }
  final keys = payload.keys.toList()..sort();
  final params = [
    for (final k in keys) '$k=${_pythonQuote(_jsStringValue(payload[k]))}',
  ];
  return '$uri?${params.join('&')}';
}

/// JS `String(value)` 语义的字符串化(含数组 `,` 连接)。
String _jsStringValue(Object? value) {
  if (value == null) {
    return 'null';
  }
  if (value is String) {
    return value;
  }
  if (value is bool) {
    return value ? 'true' : 'false';
  }
  if (value is num) {
    // JS 数字不分整型/浮点:整值 double 不带 `.0`(≥1e21 走指数,与 JS 一致)。
    if (value is double &&
        value == value.truncateToDouble() &&
        value.abs() < 1e21) {
      return value == 0 ? '0' : value.toStringAsFixed(0);
    }
    return value.toString();
  }
  if (value is List) {
    return value.map(_jsStringValue).join(',');
  }
  return value.toString();
}

/// Python 风格 quote(safe=','),等价 encodeURIComponent 后还原 `%2C`。
///
/// Dart `Uri.encodeComponent` 与 `encodeURIComponent` 的保留字符集与
/// 大写 hex 输出完全一致。
String _pythonQuote(String s) => Uri.encodeComponent(s).replaceAll('%2C', ',');

/// x3 段:payload → XOR 密钥 → 截断 124 字节 → 自定义 base64。
String _buildSignature(
  String dValue,
  String a1Value,
  String appIdentifier,
  String stringParam,
  int timestamp,
  Random random,
) {
  final payload = _buildPayloadArray(
    dValue,
    a1Value,
    appIdentifier,
    stringParam,
    timestamp,
    random,
  );
  final xorResult = _xorTransformArray(payload);
  final truncated = xorResult.length > 124 ? xorResult.sublist(0, 124) : xorResult;
  return _encodeBase64WithAlphabet(truncated, _x3Base64Alphabet);
}

/// 构建 125 字节 payload(截断前),布局与 index.js 逐字段对齐:
/// 0..3 版本 | 4..7 随机 seed | 8..15 fpA(ts) | 16..23 fpB(ts-随机偏移) |
/// 24..27 随机 seq | 28..31 随机 windowPropsLen | 32..35 uriLen |
/// 36..43 md5 前 8 字节 ^ seedByte0 | 44 长度 52 | 45..96 a1 | 97 长度 10 |
/// 98..107 appIdentifier | 108..110 常量与校验 | 111..124 固定尾部。
List<int> _buildPayloadArray(
  String hexParameter,
  String a1Value,
  String appIdentifier,
  String stringParam,
  int timestamp,
  Random random,
) {
  final payload = [..._versionBytes];

  final seed = random.nextInt(4294967296); // 0..2^32-1
  final seedBytes = _intToLeBytes(seed, 4);
  payload.addAll(seedBytes);
  final seedByte0 = seedBytes[0];

  payload.addAll(_envFingerprintA(timestamp, _envFingerprintXorKey));

  final timeOffset = 10 + random.nextInt(41); // [10, 50]
  payload.addAll(_envFingerprintB(timestamp - timeOffset));

  final seqVal = 15 + random.nextInt(36); // [15, 50]
  payload.addAll(_intToLeBytes(seqVal, 4));

  final winLen = 900 + random.nextInt(301); // [900, 1200]
  payload.addAll(_intToLeBytes(winLen, 4));

  // JS stringParam.length 为 UTF-16 code unit 数,Dart String.length 相同。
  payload.addAll(_intToLeBytes(stringParam.length, 4));

  final md5Bytes = _hexDecode(hexParameter);
  for (var i = 0; i < 8; i++) {
    payload.add(md5Bytes[i] ^ seedByte0);
  }

  payload.add(52);
  final a1Bytes = utf8.encode(a1Value);
  for (var i = 0; i < 52; i++) {
    payload.add(i < a1Bytes.length ? a1Bytes[i] : 0);
  }

  payload.add(10);
  final srcBytes = utf8.encode(appIdentifier);
  for (var i = 0; i < 10; i++) {
    payload.add(i < srcBytes.length ? srcBytes[i] : 0);
  }

  payload
    ..addAll([1, _checksumVersion, seedByte0 ^ _checksumXorKey])
    ..addAll(_checksumFixedTail);
  return payload;
}

/// fpA:时间戳 8 字节 LE,首字节替换为 `((sum(b1..b4) & 255) + sum(b5..b7)) & 255`,
/// 全体字节再 XOR [xorKey]。
List<int> _envFingerprintA(int ts, int xorKey) {
  final buf = _intToLeBytes(ts, 8);
  var sum1 = 0;
  for (var i = 1; i < 5; i++) {
    sum1 += buf[i];
  }
  var sum2 = 0;
  for (var i = 5; i < 8; i++) {
    sum2 += buf[i];
  }
  buf[0] = ((sum1 & 255) + sum2) & 255;
  return [for (final b in buf) b ^ xorKey];
}

/// fpB:时间戳 8 字节 LE。
List<int> _envFingerprintB(int ts) => _intToLeBytes(ts, 8);

/// 前 [keyLength] 字节与 HEX_KEY 异或,其余保持不变。
List<int> _xorTransformArray(List<int> sourceIntegers) {
  final keyBytes = _hexDecode(_hexKey);
  return [
    for (var i = 0; i < sourceIntegers.length; i++)
      i < keyBytes.length
          ? (sourceIntegers[i] ^ keyBytes[i]) & 255
          : sourceIntegers[i] & 255,
  ];
}

/// 小端字节序拆分 [length] 个字节。
List<int> _intToLeBytes(int val, int length) {
  final arr = List<int>.filled(length, 0);
  var v = val;
  for (var i = 0; i < length; i++) {
    arr[i] = v & 255;
    v >>= 8;
  }
  return arr;
}

/// hex 字符串解码为字节。
List<int> _hexDecode(String hexStr) {
  final out = List<int>.filled(hexStr.length ~/ 2, 0);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hexStr.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

/// 以自定义字母表做标准 padding 的 base64 编码(非字母表字符如 `=` 原样保留)。
String _encodeBase64WithAlphabet(List<int> data, String alphabet) {
  final base64Str = base64.encode(data);
  final buf = StringBuffer();
  for (var i = 0; i < base64Str.length; i++) {
    final ch = base64Str[i];
    final idx = _standardBase64Alphabet.indexOf(ch);
    buf.write(idx != -1 ? alphabet[idx] : ch);
  }
  return buf.toString();
}

/// B1 指纹 JSON(仅 generateB1 选中的 18 键,键序与源码一致)。
String _buildB1FingerprintJson(int timestampMs, Random random) =>
    jsonEncode(<String, Object?>{
      'x33': '0',
      'x34': '0',
      'x35': '0',
      'x36': '${random.nextInt(20) + 1}',
      'x37': _b1FpX37,
      'x38': _b1FpX38,
      'x39': 0,
      'x42': '3.4.4',
      'x43': _b1FpCanvasHash,
      'x44': '$timestampMs',
      'x45': _b1FpX45,
      'x46': 'false',
      'x48': '',
      'x49': _b1FpX49,
      'x50': '',
      'x51': '',
      'x52': '',
      'x82': _b1FpX82,
    });

/// 生成 B1:RC4(passphrase 模式)加密指纹 JSON → latin1 字符串 →
/// customQuote → `%` 分段重组字节 → 自定义 base64。
String _generateB1(String jsonStr, Random random) {
  final ciphertext = _rc4EncryptWithPassphrase(jsonStr, _b1SecretKey, random);
  // latin1 语义:密文字节 → 字符一一对应(每字节 ≤ 255)。
  final ciphertextStr = String.fromCharCodes(ciphertext);
  final encodedUrl = _customQuote(ciphertextStr);
  final parts = encodedUrl.split('%');
  final b = <int>[];
  // 源码从 i=1 开始:首个 `%` 之前的字面段被丢弃(与源实现保持一致)。
  for (var i = 1; i < parts.length; i++) {
    final part = parts[i];
    if (part.length < 2) {
      continue;
    }
    final val = int.tryParse(part.substring(0, 2), radix: 16);
    if (val != null) {
      b.add(val);
    }
    for (var j = 2; j < part.length; j++) {
      b.add(part.codeUnitAt(j));
    }
  }
  return _encodeBase64WithAlphabet(b, _customBase64Alphabet);
}

/// urllib.parse.quote(s, safe="!*'()~_-") 语义:字母数字与 `.` 及 safe 字符
/// 保留,其余按字节(此处字符均 ≤ 255)输出大写 `%XX`。
String _customQuote(String s) {
  const safeChars = "!*'()~_-";
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final b = s.codeUnitAt(i);
    final char = s[i];
    final isUnreserved =
        (b >= 97 && b <= 122) ||
        (b >= 65 && b <= 90) ||
        (b >= 48 && b <= 57) ||
        char == '.';
    if (isUnreserved || safeChars.contains(char)) {
      buf.write(char);
    } else {
      buf.write('%${b.toRadixString(16).toUpperCase().padLeft(2, '0')}');
    }
  }
  return buf.toString();
}

/// crypto-js `RC4.encrypt(plaintext, passphrase)`(字符串 key 走
/// PasswordBasedCipher):随机 8 字节盐,EvpKDF(MD5、1 次迭代)派生
/// 32 字节 key(ivSize=0,无 IV),输出裸密文(盐与 `Salted__` 头被丢弃,
/// 与源实现只取 `encrypted.ciphertext` 一致)。
List<int> _rc4EncryptWithPassphrase(
  String plaintext,
  String passphrase,
  Random random,
) {
  final salt = List<int>.generate(8, (_) => random.nextInt(256));
  final key = _evpKdfMd5(utf8.encode(passphrase), salt, 32);
  return _rc4(key, utf8.encode(plaintext));
}

/// EVP_BytesToKey(MD5,1 次迭代):block0 = MD5(pw || salt),
/// blockN = MD5(blockN-1 || pw || salt),级联截取 [keyLength] 字节。
List<int> _evpKdfMd5(List<int> password, List<int> salt, int keyLength) {
  var block = md5.convert([...password, ...salt]).bytes;
  final derived = <int>[...block];
  while (derived.length < keyLength) {
    block = md5.convert([...block, ...password, ...salt]).bytes;
    derived.addAll(block);
  }
  return derived.sublist(0, keyLength);
}

/// 标准 RC4(KSA + PRGA),逐字节与 crypto-js 的 WordArray 实现等价。
List<int> _rc4(List<int> key, List<int> data) {
  final s = List<int>.generate(256, (i) => i);
  var j = 0;
  for (var i = 0; i < 256; i++) {
    j = (j + s[i] + key[i % key.length]) & 255;
    final t = s[i];
    s[i] = s[j];
    s[j] = t;
  }
  final out = List<int>.filled(data.length, 0);
  var i = 0;
  j = 0;
  for (var k = 0; k < data.length; k++) {
    i = (i + 1) & 255;
    j = (j + s[i]) & 255;
    final t = s[i];
    s[i] = s[j];
    s[j] = t;
    out[k] = data[k] ^ s[(s[i] + s[j]) & 255];
  }
  return out;
}

/// 源码 `crc32JsInt`:标准 crc32 变体,最终再 XOR 多项式并取有符号 int32。
int _crc32JsInt(List<int> data) {
  var crc = 4294967295;
  for (final byte in data) {
    crc ^= byte;
    for (var j = 0; j < 8; j++) {
      final mask = (crc & 1) == 1 ? 3988292384 : 0;
      crc = (crc >> 1) ^ mask;
    }
  }
  final c = crc ^ 4294967295; // 源码 `(crc ^ 0xFFFFFFFF) >>> 0`,crc 恒在 uint32 范围
  final u = 4294967295 ^ c ^ 3988292384; // 同上
  return u >= 2147483648 ? u - 4294967296 : u; // 源码 `u | 0` 的有符号化
}
