/// 虎牙播放地址签名:anti_code 换新(fm 解出前缀 + md5(seqId|ctype|t) + wsTime)。
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../http/parser_http.dart';

String _md5Hex(String text) => md5.convert(utf8.encode(text)).toString();

/// 取两个 16 进制时间戳中较晚的一个。[server] 无法解析(缺失/非 16 进制)时
/// 直接返回 [fallback](调用方保证其可解析)。
String _laterHexTime(String server, String fallback) {
  final parsedServer = int.tryParse(server, radix: 16);
  if (parsedServer == null) return fallback;
  final parsedFallback = int.tryParse(fallback, radix: 16) ?? 0;
  return parsedServer >= parsedFallback ? server : fallback;
}

/// 签名核心(纯函数,可做固定向量测试):
/// `wsSecret = md5(pf_uid_streamName_md5(seqId|ctype|t)_wsTime)`。
String computeHuyaWsSecret({
  required String fmPrefix,
  required String ctype,
  required String streamName,
  required int uid,
  required int seqId,
  required int paramsT,
  required String wsTime,
}) {
  final hash = _md5Hex('$seqId|$ctype|$paramsT');
  final secret = '${fmPrefix}_${uid}_${streamName}_${hash}_$wsTime';
  return _md5Hex(secret);
}

/// 从上游 anti_code 提取 fm 的 base64 解码首段(如 `1137`)。
String huyaFmPrefix(String fmRaw) {
  final decoded = base64.decode(Uri.decodeComponent(fmRaw));
  final text = utf8.decode(decoded);
  return text.split('_').first;
}

/// 由旧 anti_code 与流名生成新签名 query(不含 ratio,调用方按清晰度追加)。
String buildHuyaAntiCode(String oldAntiCode, String streamName) {
  const paramsT = 100;
  const sdkVersion = 2403051612;

  final query = Uri.splitQueryString(oldAntiCode);
  final fm = query['fm'] ?? '';
  final ctype = query['ctype'] ?? '';
  final fs = query['fs'] ?? '';
  if (fm.isEmpty || ctype.isEmpty || fs.isEmpty) {
    throw const ParserHttpException('无效的 anti_code');
  }

  final t13 = DateTime.now().millisecondsSinceEpoch;
  final sdkSid = t13;
  final initUuid = ((t13 % 10000000000) * 1000 + (t13 % 1000)) % 4294967295;
  final uid = 1400000000000 + (t13 % 9999999);
  final seqId = uid + sdkSid;

  // wsTime 决定**地址租约**:CDN 以「wsTime 是否已过」判定有效性(实测过期
  // 一律 403、未来值放行,故租约 ≈ wsTime - now)。上游 anti_code 自带一个
  // wsTime(实测 ≈ now+284s),自造值 `(now+110624ms)` 只有 ≈ now+110s —— 
  // 把地址寿命砍掉了约 60%,是「看一两分钟就断」的直接成因。取两者中更晚者:
  // 沿用服务端值拉长租约,但若上游给的是已过期的旧值则退回自造值,避免直接用
  // 一个开场即 403 的地址。参考 pure_live `huya_site.dart` 的 `mapAnti['wsTime']`。
  final wsTime = _laterHexTime(
    (query['wsTime'] ?? '').trim(),
    ((t13 + 110624) ~/ 1000).toRadixString(16).toLowerCase(),
  );

  final wsSecret = computeHuyaWsSecret(
    fmPrefix: huyaFmPrefix(fm),
    ctype: ctype,
    streamName: streamName,
    uid: uid,
    seqId: seqId,
    paramsT: paramsT,
    wsTime: wsTime,
  );

  return 'wsSecret=$wsSecret&wsTime=$wsTime&seqid=$seqId&ctype=$ctype&ver=1'
      '&fs=$fs&uuid=$initUuid&u=$uid&t=$paramsT&sv=$sdkVersion'
      '&sdk_sid=$sdkSid&codec=264';
}
