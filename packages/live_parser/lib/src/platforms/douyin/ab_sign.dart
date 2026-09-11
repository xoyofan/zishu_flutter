/// 抖音 a_bogus 签名。
///
/// 移植自 SFVideoLive `streaming-server/src/resolve/douyin/ab-sign.ts`
/// (该实现为 streamget `ab_sign.py` 的 TS 移植):SM3(国标)+ RC4 + 两套变体
/// Base64 编码表 + 确定性前缀。签名输入为 URLSearchParams 序列化后的 query
/// 原文与 User-Agent。
library;

import 'dart:convert';
import 'dart:typed_data';

const String _kWindowEnvStr =
    '1920|1080|1920|1040|0|30|0|0|1872|92|1920|1040|1857|92|1|24|Win32';

const Map<String, String> _kEncodingTables = {
  's0': 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=',
  's3': 'ckdp1h4ZKsUB80/Mfvw36XIgR25+WQAlEi7NLboqYTOPuzmFjJnryx9HVGDaStCe',
  's4': 'Dkdpgh2ZmsQB80/MfvV36XI1R45-WUAlEixNLwoqYTOPuzKFjJnry79HbGcaStCe',
};

int _u32(int value) => value & 0xFFFFFFFF;

int _leftRotate(int x, int n) {
  n %= 32;
  if (n == 0) return _u32(x);
  final v = _u32(x);
  return _u32((v << n) | (v >>> (32 - n)));
}

int _getTj(int j) => j < 16 ? 2043430169 : 2055708042;

int _ffJ(int j, int x, int y, int z) =>
    j < 16 ? _u32(x ^ y ^ z) : _u32((x & y) | (x & z) | (y & z));

int _ggJ(int j, int x, int y, int z) =>
    j < 16 ? _u32(x ^ y ^ z) : _u32((x & y) | ((_u32(~x)) & z));

/// SM3 摘要(与 TS 移植版逐位对齐)。
class _Sm3 {
  List<int> _reg = <int>[];
  List<int> _chunk = <int>[];
  int _size = 0;

  _Sm3() {
    _reset();
  }

  void _reset() {
    _reg = [
      1937774191,
      1226093241,
      388252375,
      3666478592,
      2842636476,
      372324522,
      3817729613,
      2969243214,
    ];
    _chunk = <int>[];
    _size = 0;
  }

  void _write(Object data) {
    final bytes = data is String ? utf8.encode(data) : List<int>.from(data as List<int>);
    _size += bytes.length;
    var offset = 0;
    while (offset < bytes.length) {
      final space = 64 - _chunk.length;
      final remaining = bytes.length - offset;
      final take = space < remaining ? space : remaining;
      _chunk.addAll(bytes.sublist(offset, offset + take));
      offset += take;
      while (_chunk.length >= 64) {
        _compress(_chunk.sublist(0, 64));
        _chunk = _chunk.sublist(64);
      }
    }
  }

  Uint8List sum([Object? data]) {
    if (data != null) {
      _reset();
      _write(data);
    }
    _fill();
    for (var f = 0; f < _chunk.length; f += 64) {
      _compress(_chunk.sublist(f, f + 64));
    }
    final result = Uint8List(32);
    for (var i = 0; i < 8; i++) {
      final value = _u32(_reg[i]);
      result[i * 4] = (value >>> 24) & 0xff;
      result[i * 4 + 1] = (value >>> 16) & 0xff;
      result[i * 4 + 2] = (value >>> 8) & 0xff;
      result[i * 4 + 3] = value & 0xff;
    }
    _reset();
    return result;
  }

  void _fill() {
    final bitLength = 8 * _size;
    var paddingPos = _chunk.length;
    _chunk.add(0x80);
    paddingPos = (paddingPos + 1) % 64;
    if (64 - paddingPos < 8) paddingPos -= 64;
    while (paddingPos < 56) {
      _chunk.add(0);
      paddingPos += 1;
    }
    final highBits = bitLength ~/ 4294967296;
    for (var i = 3; i >= 0; i--) {
      _chunk.add((highBits >>> (8 * i)) & 0xff);
    }
    for (var i = 3; i >= 0; i--) {
      _chunk.add((bitLength >>> (8 * i)) & 0xff);
    }
  }

  void _compress(List<int> data) {
    final w = List<int>.filled(132, 0);
    for (var t = 0; t < 16; t++) {
      w[t] = _u32(
        (data[4 * t] << 24) |
            (data[4 * t + 1] << 16) |
            (data[4 * t + 2] << 8) |
            data[4 * t + 3],
      );
    }
    for (var j = 16; j < 68; j++) {
      final a = _u32(w[j - 16] ^ w[j - 9] ^ _leftRotate(w[j - 3], 15));
      final b = _u32(a ^ _leftRotate(a, 15) ^ _leftRotate(a, 23));
      w[j] = _u32(b ^ _leftRotate(w[j - 13], 7) ^ w[j - 6]);
    }
    for (var j = 0; j < 64; j++) {
      w[j + 68] = _u32(w[j] ^ w[j + 4]);
    }

    var a = _reg[0];
    var b = _reg[1];
    var c = _reg[2];
    var d = _reg[3];
    var e = _reg[4];
    var f = _reg[5];
    var g = _reg[6];
    var h = _reg[7];

    for (var j = 0; j < 64; j++) {
      final ss1 = _leftRotate(
        _u32(_u32(_leftRotate(a, 12) + e) + _leftRotate(_getTj(j), j)),
        7,
      );
      final ss2 = _u32(ss1 ^ _leftRotate(a, 12));
      final tt1 = _u32(_u32(_u32(_ffJ(j, a, b, c) + d) + ss2) + w[j + 68]);
      final tt2 = _u32(_u32(_u32(_ggJ(j, e, f, g) + h) + ss1) + w[j]);
      d = c;
      c = _leftRotate(b, 9);
      b = a;
      a = tt1;
      h = g;
      g = _leftRotate(f, 19);
      f = e;
      e = _u32(tt2 ^ _leftRotate(tt2, 9) ^ _leftRotate(tt2, 17));
    }

    _reg[0] = _u32(_reg[0] ^ a);
    _reg[1] = _u32(_reg[1] ^ b);
    _reg[2] = _u32(_reg[2] ^ c);
    _reg[3] = _u32(_reg[3] ^ d);
    _reg[4] = _u32(_reg[4] ^ e);
    _reg[5] = _u32(_reg[5] ^ f);
    _reg[6] = _u32(_reg[6] ^ g);
    _reg[7] = _u32(_reg[7] ^ h);
  }
}

String _rc4Encrypt(String plaintext, String key) {
  final s = List<int>.generate(256, (i) => i);
  var j = 0;
  for (var i = 0; i < 256; i++) {
    j = (j + s[i] + key.codeUnitAt(i % key.length)) % 256;
    final tmp = s[i];
    s[i] = s[j];
    s[j] = tmp;
  }
  var i = 0;
  j = 0;
  final out = StringBuffer();
  for (final code in plaintext.codeUnits) {
    i = (i + 1) % 256;
    j = (j + s[i]) % 256;
    final tmp = s[i];
    s[i] = s[j];
    s[j] = tmp;
    out.writeCharCode(s[(s[i] + s[j]) % 256] ^ code);
  }
  return out.toString();
}

int _getLongInt(int roundNum, String longStr) {
  final round = roundNum * 3;
  final char1 = round < longStr.length ? longStr.codeUnitAt(round) : 0;
  final char2 = round + 1 < longStr.length ? longStr.codeUnitAt(round + 1) : 0;
  final char3 = round + 2 < longStr.length ? longStr.codeUnitAt(round + 2) : 0;
  return (char1 << 16) | (char2 << 8) | char3;
}

String _resultEncrypt(String longStr, String tableKey) {
  final encodingTable = _kEncodingTables[tableKey]!;
  const masks = [16515072, 258048, 4032, 63];
  const shifts = [18, 12, 6, 0];
  final out = StringBuffer();
  var roundNum = 0;
  var longInt = _getLongInt(roundNum, longStr);
  final totalChars = ((longStr.length / 3) * 4).ceil();
  for (var i = 0; i < totalChars; i++) {
    if (i ~/ 4 != roundNum) {
      roundNum += 1;
      longInt = _getLongInt(roundNum, longStr);
    }
    final index = i % 4;
    final charIndex = (longInt & masks[index]) >> shifts[index];
    out.write(encodingTable[charIndex]);
  }
  return out.toString();
}

List<int> _generRandom(int randomNum, List<int> option) {
  final byte1 = randomNum & 255;
  final byte2 = (randomNum >> 8) & 255;
  return [
    (byte1 & 170) | (option[0] & 85),
    (byte1 & 85) | (option[0] & 170),
    (byte2 & 170) | (option[1] & 85),
    (byte2 & 85) | (option[1] & 170),
  ];
}

String _generateRandomStr() {
  const randomValues = [0.123456789, 0.987654321, 0.555555555];
  final bytes = <int>[];
  bytes.addAll(_generRandom((randomValues[0] * 10000).truncate(), const [3, 45]));
  bytes.addAll(_generRandom((randomValues[1] * 10000).truncate(), const [1, 0]));
  bytes.addAll(_generRandom((randomValues[2] * 10000).truncate(), const [1, 5]));
  return String.fromCharCodes(bytes);
}

List<int> _splitToBytes(int num) {
  final v = _u32(num);
  return [(v >>> 24) & 255, (v >>> 16) & 255, (v >>> 8) & 255, v & 255];
}

String _generateRc4BbStr(
  String urlSearchParams,
  String userAgent,
  String windowEnvStr, {
  int? startTimeOverride,
}) {
  const suffix = 'cus';
  const args = [0, 1, 14];
  const aid = 6383;
  const pageId = 110624;

  final sm3 = _Sm3();
  final startTime =
      startTimeOverride ?? DateTime.now().millisecondsSinceEpoch;
  final urlSearchParamsList = sm3.sum(sm3.sum('$urlSearchParams$suffix'));
  final cus = sm3.sum(sm3.sum(suffix));
  final uaKey = String.fromCharCodes(const [0, 1, 14]);
  final ua = sm3.sum(_resultEncrypt(_rc4Encrypt(userAgent, uaKey), 's3'));
  final endTime = startTime + 100;

  final b = <int, int>{
    8: 3,
    10: endTime,
    16: startTime,
    18: 44,
  };

  final startBytes = _splitToBytes(b[16]!);
  b[20] = startBytes[0];
  b[21] = startBytes[1];
  b[22] = startBytes[2];
  b[23] = startBytes[3];
  b[24] = (b[16]! ~/ 4294967296) & 255;
  b[25] = (b[16]! ~/ 1099511627776) & 255;

  final arg0Bytes = _splitToBytes(args[0]);
  b[26] = arg0Bytes[0];
  b[27] = arg0Bytes[1];
  b[28] = arg0Bytes[2];
  b[29] = arg0Bytes[3];
  b[30] = (args[1] ~/ 256) & 255;
  b[31] = args[1] % 256;
  final arg1Bytes = _splitToBytes(args[1]);
  b[32] = arg1Bytes[0];
  b[33] = arg1Bytes[1];
  final arg2Bytes = _splitToBytes(args[2]);
  b[34] = arg2Bytes[0];
  b[35] = arg2Bytes[1];
  b[36] = arg2Bytes[2];
  b[37] = arg2Bytes[3];

  b[38] = urlSearchParamsList[21];
  b[39] = urlSearchParamsList[22];
  b[40] = cus[21];
  b[41] = cus[22];
  b[42] = ua[23];
  b[43] = ua[24];

  final endBytes = _splitToBytes(b[10]!);
  b[44] = endBytes[0];
  b[45] = endBytes[1];
  b[46] = endBytes[2];
  b[47] = endBytes[3];
  b[48] = b[8]!;
  b[49] = (b[10]! ~/ 4294967296) & 255;
  b[50] = (b[10]! ~/ 1099511627776) & 255;

  b[51] = pageId;
  final pageIdBytes = _splitToBytes(pageId);
  b[52] = pageIdBytes[0];
  b[53] = pageIdBytes[1];
  b[54] = pageIdBytes[2];
  b[55] = pageIdBytes[3];
  b[56] = aid;
  b[57] = aid & 255;
  b[58] = (aid >> 8) & 255;
  b[59] = (aid >> 16) & 255;
  b[60] = (aid >> 24) & 255;

  final windowEnvList = windowEnvStr.codeUnits;
  b[64] = windowEnvList.length;
  b[65] = b[64]! & 255;
  b[66] = b[64]! >> 8;
  b[69] = 0;
  b[70] = 0;
  b[71] = 0;
  b[72] =
      b[18]! ^
      b[20]! ^
      b[26]! ^
      b[30]! ^
      b[38]! ^
      b[40]! ^
      b[42]! ^
      b[21]! ^
      b[27]! ^
      b[31]! ^
      b[35]! ^
      b[39]! ^
      b[41]! ^
      b[43]! ^
      b[22]! ^
      b[28]! ^
      b[32]! ^
      b[36]! ^
      b[23]! ^
      b[29]! ^
      b[33]! ^
      b[37]! ^
      b[44]! ^
      b[45]! ^
      b[46]! ^
      b[47]! ^
      b[48]! ^
      b[49]! ^
      b[50]! ^
      b[24]! ^
      b[25]! ^
      b[52]! ^
      b[53]! ^
      b[54]! ^
      b[55]! ^
      b[57]! ^
      b[58]! ^
      b[59]! ^
      b[60]! ^
      b[65]! ^
      b[66]! ^
      b[70]! ^
      b[71]!;

  final bb = <int>[
    b[18]!,
    b[20]!,
    b[52]!,
    b[26]!,
    b[30]!,
    b[34]!,
    b[58]!,
    b[38]!,
    b[40]!,
    b[53]!,
    b[42]!,
    b[21]!,
    b[27]!,
    b[54]!,
    b[55]!,
    b[31]!,
    b[35]!,
    b[57]!,
    b[39]!,
    b[41]!,
    b[43]!,
    b[22]!,
    b[28]!,
    b[32]!,
    b[60]!,
    b[36]!,
    b[23]!,
    b[29]!,
    b[33]!,
    b[37]!,
    b[44]!,
    b[45]!,
    b[59]!,
    b[46]!,
    b[47]!,
    b[48]!,
    b[49]!,
    b[50]!,
    b[24]!,
    b[25]!,
    b[65]!,
    b[66]!,
    b[70]!,
    b[71]!,
  ];
  bb.addAll(windowEnvList);
  bb.add(b[72]!);
  return _rc4Encrypt(String.fromCharCodes(bb), String.fromCharCode(121));
}

/// 生成 `a_bogus` 值(不带 `=` 之外的额外转义;调用方自行 URL 编码)。
///
/// [timestamp] 仅测试用:固定签名时间以复现确定性输出。
String douyinAbSign(
  String urlSearchParams,
  String userAgent, {
  int? timestamp,
}) {
  final core =
      '${_generateRandomStr()}${_generateRc4BbStr(urlSearchParams, userAgent, _kWindowEnvStr, startTimeOverride: timestamp)}';
  return '${_resultEncrypt(core, 's4')}=';
}
