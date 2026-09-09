/// 虎牙播放地址签名:anti_code 换新(fm 解出前缀 + md5(seqId|ctype|t) + wsTime)。
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../http/parser_http.dart';

String _md5Hex(String text) => md5.convert(utf8.encode(text)).toString();

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
  final wsTime = ((t13 + 110624) ~/ 1000).toRadixString(16).toLowerCase();

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
