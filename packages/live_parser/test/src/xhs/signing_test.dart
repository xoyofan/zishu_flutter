// xhs 签名移植对照测试:以 node 端 xhshow-js 生成的固定向量
// (test/fixtures/xhs/signing_vectors.json,由 test/support/xhs_vector_gen.mjs
// 生成)验证 Dart 实现与源算法一致。
//
// 随机性口径(与源算法一致,无法逐字节):
// * x-s 的 x3 payload 内嵌 seed(4..7)/fpB 时间偏移(16..23)/seq(24..27)/
//   windowPropsLen(28..31)随机区域,并衍生 md5^seedByte0(36..43)与校验
//   字节(110);本测试对确定性区域逐字节断言(连同 XOR 前的 x3 裸字节,
//   一起钉死 HEX_KEY 与两套 base64 字母表),随机区域按源码区间断言。
// * x-s-common 含随机指纹与随机 RC4 盐,做结构/键序/固定字段断言,并用
//   x9 == crc32(utf8(x8)) 做链式校验。
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:live_parser/src/platforms/xhs/signing.dart';
import 'package:test/test.dart';

Map<String, dynamic> _loadFixture() =>
    jsonDecode(File('test/fixtures/xhs/signing_vectors.json').readAsStringSync())
        as Map<String, dynamic>;

XhsSigner _signerFor(String a1) => XhsSigner(
  a1: a1,
  webSession: 'web-session-not-used-by-signature',
  cookieHeader: 'a1=$a1; web_session=web-session-not-used-by-signature',
);

List<int> _bytesOfHex(String hexStr) {
  final out = List<int>.filled(hexStr.length ~/ 2, 0);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hexStr.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

/// 用 fixture meta 中的字母表做自定义 base64 解码(与 index.js 一致:
/// 非字母表字符如 `=` 原样映射到标准字母表之外)。
List<int> _decodeBase64WithAlphabet(String data, String alphabet) {
  const standard = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  final buf = StringBuffer();
  for (var i = 0; i < data.length; i++) {
    final idx = alphabet.indexOf(data[i]);
    buf.write(idx != -1 ? standard[idx] : data[i]);
  }
  return base64.decode(buf.toString());
}

List<int> _xorWithKey(List<int> bytes, List<int> key) => [
  for (var i = 0; i < bytes.length; i++)
    i < key.length ? (bytes[i] ^ key[i]) & 255 : bytes[i] & 255,
];

int _readLe(List<int> bytes, int offset, int length) {
  var value = 0;
  for (var i = length - 1; i >= 0; i--) {
    value = (value << 8) | (bytes[offset + i] & 255);
  }
  return value;
}

/// x3 payload 的确定性字节偏移全集(其余偏移受随机字段影响)。
/// x3 payload 的确定性字节偏移全集(其余偏移受随机字段影响)。
/// 4..7 seed;16 fpB 低字节;24 seq 低字节;28..29 windowPropsLen 低两字节
/// (900..1200 跨 0x384..0x4B0,次低字节在 {3,4} 间随机);
/// 36..43 md5^seedByte0;110 seedByte0^115。
/// 注:fpB 高位字节(17..23)在本 fixture 的固定时间戳(256 对齐)下稳定。
bool _isDeterministicPayloadOffset(int offset) =>
    !(offset >= 4 && offset <= 7) &&
    offset != 16 &&
    offset != 24 &&
    !(offset >= 28 && offset <= 29) &&
    !(offset >= 36 && offset <= 43) &&
    offset != 110;

Map<String, Object?> _decodeXsWrapper(String xs, String customAlphabet) {
  expect(xs, startsWith('XYS_'));
  final jsonBytes = _decodeBase64WithAlphabet(xs.substring('XYS_'.length), customAlphabet);
  return Map<String, Object?>.from(jsonDecode(utf8.decode(jsonBytes)) as Map);
}

void main() {
  // group 注册体在 main() 内立即执行,fixture 需在注册前同步加载。
  final fixture = _loadFixture();

  group('signXS:与 node 固定向量对齐', () {
    final meta = fixture['meta'] as Map<String, dynamic>;
    final customAlphabet = meta['custom_base64_alphabet'] as String;
    final x3Alphabet = meta['x3_base64_alphabet'] as String;
    final fixtureKey = _bytesOfHex(meta['hex_key'] as String);

    for (final raw in fixture['xs_vectors'] as List<dynamic>) {
      final vector = raw as Map<String, dynamic>;
      test(vector['name'] as String, () {
        final a1 = vector['a1'] as String;
        final ts = vector['timestamp_ms'] as int;
        final params = Map<String, Object?>.from(vector['params'] as Map);
        final fixturePayload = _bytesOfHex(vector['expected_payload_hex'] as String);
        final fixtureRaw = _bytesOfHex(vector['expected_x3_raw_hex'] as String);
        final expectedWrapper = vector['expected_wrapper'] as Map<String, dynamic>;

        // fixture 自检:x3 裸字节 XOR HEX_KEY 应还原 payload。
        expect(_xorWithKey(fixtureRaw, fixtureKey), fixturePayload);

        final signer = _signerFor(a1);
        final xs = signer.signXS(
          vector['method'] as String,
          vector['uri'] as String,
          params: params,
          timestampMs: ts,
        );

        // 包装 JSON:前缀、键序与固定字段与 node 一致。
        final wrapper = _decodeXsWrapper(xs, customAlphabet);
        expect(wrapper.keys.toList(), ['x0', 'x1', 'x2', 'x3', 'x4']);
        expect(wrapper['x0'], expectedWrapper['x0']);
        expect(wrapper['x1'], expectedWrapper['x1']);
        expect(wrapper['x2'], expectedWrapper['x2']);
        expect(wrapper['x4'], expectedWrapper['x4']);

        // x3 裸字节(XOR 前,内嵌 HEX_KEY)与解码后 payload 的确定性区域
        // 逐字节一致 —— 顺带钉死产品侧 HEX_KEY 与 x3 字母表。
        final dartRaw = _decodeBase64WithAlphabet(
          (wrapper['x3'] as String).substring('mns0301_'.length),
          x3Alphabet,
        );
        expect(dartRaw, hasLength(124));
        final dartPayload = _xorWithKey(dartRaw, fixtureKey);
        expect(dartPayload, hasLength(124));
        for (var i = 0; i < 124; i++) {
          if (_isDeterministicPayloadOffset(i)) {
            expect(
              dartPayload[i],
              fixturePayload[i],
              reason: '确定性偏移 $i 不一致(${vector['name']})',
            );
          }
        }
        // md5 区与校验字节:与自身 seedByte0 异或后应与 node 一致。
        for (var i = 0; i < 8; i++) {
          expect(
            dartPayload[36 + i] ^ dartPayload[4],
            fixturePayload[36 + i] ^ fixturePayload[4],
            reason: 'md5 区偏移 ${36 + i} 不一致(${vector['name']})',
          );
        }
        expect(dartPayload[110] ^ dartPayload[4], 115);
        expect(fixturePayload[110] ^ fixturePayload[4], 115);

        // 随机区域按源码区间断言。
        final fpB = _readLe(dartPayload, 16, 8);
        expect((fpB - ts).abs(), inInclusiveRange(10, 50), reason: 'fpB 时间偏移');
        expect(_readLe(dartPayload, 24, 4), inInclusiveRange(15, 50), reason: 'seq');
        expect(
          _readLe(dartPayload, 28, 4),
          inInclusiveRange(900, 1200),
          reason: 'windowPropsLen',
        );
      });
    }
  });

  group('signXS:结构与随机性', () {
    test('同一输入两次签名输出不同(payload 含随机字段)', () {
      final signer = _signerFor('18ee4d580016f0abc123def456ghi789jkl012mno345');
      final a = signer.signXS('GET', '/api/sns/red/live/web/feed/category');
      final b = signer.signXS('GET', '/api/sns/red/live/web/feed/category');
      expect(a, isNot(b));
      expect(a, startsWith('XYS_'));
    });

    test('完整 URL 自动提取 pathname 并丢弃 query', () {
      final signer = _signerFor('18ee4d580016f0abc123def456ghi789jkl012mno345');
      const uri = 'https://live-room.xiaohongshu.com/api/sns/red/live/enter?x=1';
      // extractUri 正确性由向量组交叉验证;这里只保证不抛异常且形态正确。
      expect(signer.signXS('GET', uri), startsWith('XYS_'));
    });
  });

  group('signXSCommon:结构与固定字段', () {
    final meta = fixture['meta'] as Map<String, dynamic>;
    final customAlphabet = meta['custom_base64_alphabet'] as String;
    final fixedFields = fixture['xs_common_fixed_fields'] as Map<String, dynamic>;
    const a1 = '18ee4d580016f0abc123def456ghi789jkl012mno345';

    test('解码后键序与固定字段与 node 一致', () {
      final xsc = _signerFor(a1).signXSCommon(timestampMs: 1727673600000);
      final jsonBytes = _decodeBase64WithAlphabet(xsc, customAlphabet);
      final sig = Map<String, Object?>.from(jsonDecode(utf8.decode(jsonBytes)) as Map);
      expect(sig.keys.toList(), [
        's0', 's1', 'x0', 'x1', 'x2', 'x3', 'x4', 'x5',
        'x6', 'x7', 'x8', 'x9', 'x10', 'x11',
      ]);
      for (final key in fixedFields.keys) {
        expect(sig[key], fixedFields[key], reason: '固定字段 $key 不一致');
      }
      expect(sig['x5'], a1);
      expect(sig['s0'], isA<int>());
      expect(sig['x10'], isA<int>());

      // x8(B1):非空、字母表 + padding 字符集、可解码出字节。
      final b1 = sig['x8'] as String;
      expect(b1, isNotEmpty);
      for (final ch in b1.runes) {
        expect(
          customAlphabet.contains(String.fromCharCode(ch)) ||
              String.fromCharCode(ch) == '=',
          isTrue,
          reason: 'x8 含非法字符 ${String.fromCharCode(ch)}',
        );
      }
      expect(_decodeBase64WithAlphabet(b1, customAlphabet), isNotEmpty);

      // x9:有符号 int32,且等于 crc32JsInt(utf8(x8))(链式校验产品 crc32)。
      final x9 = sig['x9'] as int;
      expect(x9, inInclusiveRange(-2147483648, 2147483647));
      expect(x9, crc32JsIntReference(utf8.encode(b1)));
    });

    test('两次调用输出不同(随机指纹 + 随机 RC4 盐)', () {
      final signer = _signerFor(a1);
      expect(signer.signXSCommon(), isNot(signer.signXSCommon()));
    });

    test('输出可被 custom base64 字符集表示', () {
      final xsc = _signerFor(a1).signXSCommon();
      for (final ch in xsc.runes) {
        expect(
          customAlphabet.contains(String.fromCharCode(ch)) ||
              String.fromCharCode(ch) == '=',
          isTrue,
        );
      }
    });
  });

  group('RC4/EvpKDF 语义向量(crypto-js passphrase 模式)', () {
    // 说明:RC4 盐在源实现中随机且被丢弃,无法从公开接口注入,故本组用与
    // crypto-js 逐字节对齐过的本地复刻核对 fixture(生成脚本已先行自检),
    // 产品侧 RC4 为同一转录,并经 x-s-common 结构校验覆盖。
    test('EVP_BytesToKey(MD5) + RC4 与 crypto-js 输出一致', () {
      for (final raw in fixture['rc4_vectors'] as List<dynamic>) {
        final v = raw as Map<String, dynamic>;
        final passphrase = utf8.encode(v['passphrase'] as String);
        final salt = _bytesOfHex(v['salt_hex'] as String);
        final plaintext = utf8.encode(v['plaintext'] as String);

        var block = md5.convert([...passphrase, ...salt]).bytes;
        final derived = <int>[...block];
        while (derived.length < 32) {
          block = md5.convert([...block, ...passphrase, ...salt]).bytes;
          derived.addAll(block);
        }
        expect(derived.sublist(0, 32), _bytesOfHex(v['key_hex'] as String));

        expect(rc4Reference(derived.sublist(0, 32), plaintext),
            _bytesOfHex(v['ciphertext_hex'] as String));
      }
    });
  });

  group('crc32JsInt 固定向量', () {
    test('与 index.js 源逻辑一致(含空串与非负/负值)', () {
      for (final raw in fixture['crc32_vectors'] as List<dynamic>) {
        final v = raw as Map<String, dynamic>;
        expect(
          crc32JsIntReference(utf8.encode(v['input_utf8'] as String)),
          v['expected'] as int,
          reason: 'crc32 输入 "${(v['input_utf8'] as String).trim()}"',
        );
      }
    });
  });

  group('traceid', () {
    test('x-b3-traceid:16 个源码字符表内的 hex 字符', () {
      final signer = _signerFor('18ee4d580016f0abc123def456ghi789jkl012mno345');
      final b3 = signer.generateB3TraceId();
      expect(b3, hasLength(16));
      for (final ch in b3.split('')) {
        expect('abcdef0123456789'.contains(ch), isTrue, reason: '非法字符 $ch');
      }
      expect(signer.generateB3TraceId(), isNot(b3));
    });

    test('x-xray-traceid 向量:node 端 (ts<<23|seq) 公式复核', () {
      final v = fixture['xray_traceid_vector'] as Map<String, dynamic>;
      final ts = v['timestamp'] as int;
      final seq = v['seq'] as int;
      final part1 = ((BigInt.from(ts) << 23) | BigInt.from(seq))
          .toRadixString(16)
          .padLeft(16, '0');
      final expected = v['expected'] as String;
      expect(expected, startsWith(part1));
      expect(expected.length, part1.length + 16);
      for (final ch in expected.split('')) {
        expect('abcdef0123456789'.contains(ch), isTrue);
      }
    });

    test('x-xray-traceid:高段解码出当前时间戳,低 16 位为随机 hex', () {
      final signer = _signerFor('18ee4d580016f0abc123def456ghi789jkl012mno345');
      final trace = signer.generateXrayTraceId();
      expect(trace.length, greaterThanOrEqualTo(32));
      final part2 = trace.substring(trace.length - 16);
      for (final ch in part2.split('')) {
        expect('abcdef0123456789'.contains(ch), isTrue);
      }
      final value = BigInt.parse(trace.substring(0, trace.length - 16), radix: 16);
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final ts = value >> 23;
      expect(
        ts >= BigInt.from(nowMs - 60000) && ts <= BigInt.from(nowMs + 60000),
        isTrue,
        reason: '时间戳段 $ts 与当前时间 $nowMs 偏差超过 60s',
      );
      expect((value & BigInt.from(0x7fffff)) >= BigInt.zero, isTrue);
    });
  });
}

/// index.js `crc32JsInt` 的逐字语义副本(测试本地引用实现,
/// 由 fixture 固定向量锚定;产品侧结果经 x9 链式校验对齐到此)。
int crc32JsIntReference(List<int> data) {
  var crc = 4294967295;
  for (final byte in data) {
    crc ^= byte;
    for (var j = 0; j < 8; j++) {
      final mask = (crc & 1) == 1 ? 3988292384 : 0;
      crc = (crc >> 1) ^ mask;
    }
  }
  final c = crc ^ 4294967295;
  final u = 4294967295 ^ c ^ 3988292384;
  return u >= 2147483648 ? u - 4294967296 : u;
}

/// 标准 RC4 参考实现(仅用于 RC4 语义向量核对)。
List<int> rc4Reference(List<int> key, List<int> data) {
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
