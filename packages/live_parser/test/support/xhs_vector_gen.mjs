// 一次性向量生成脚本:xhshow-js(node) -> Dart 移植的对照向量。
//
// 用法(SFVideoLive 需已安装 xhshow-js 与 crypto-js):
//   node test/support/xhs_vector_gen.mjs
// 可用环境变量 SFVIDEO_LIVE_ROOT 覆盖 SFVideoLive 根目录(默认 F:/project/SFVideoLive)。
//
// 输出: test/fixtures/xhs/signing_vectors.json
//
// 说明:
// * x-s 的 x3 payload 内嵌 4 个随机区域(随机 seed、fpB 时间偏移、seq、
//   windowPropsLen),并衍生出 md5^seedByte0(36..43)与校验字节(110),
//   因此固定输入下 x-s 不具备逐字节确定性。本脚本记录固定输入下 node 的
//   完整 x-s、解码后 payload(payload_hex)与 XOR 前 x3 裸字节(x3_raw_hex,
//   内嵌 HEX_KEY),Dart 侧对确定性区域逐字节断言、随机区域按源码区间断言。
// * x-s-common 含随机指纹(x36/x44)与随机盐 RC4,只记录固定字段与样例。
// * HEX_KEY 与两个 base64 字母表直接从 index.js 源码正则提取,避免转录错误。

import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { join } from 'node:path';

const SF_ROOT = process.env.SFVIDEO_LIVE_ROOT ?? 'F:/project/SFVideoLive';
const toFileUrl = (p) => `file:///${SF_ROOT}/${p}`;
const assert = (cond, msg) => {
  if (!cond) throw new Error(`向量生成自检失败: ${msg}`);
};

const xhshow = await import(toFileUrl('node_modules/xhshow-js/dist/index.js'));
const { Client, generateXrayTraceId, decodeCustomBase64 } = xhshow;
const RC4 = (await import(toFileUrl('node_modules/crypto-js/rc4.js'))).default;
const CryptoJS = (await import(toFileUrl('node_modules/crypto-js/core.js'))).default;

// ---- 从 index.js 源码提取常量(真源,零转录) ----
const indexSource = readFileSync(
  new URL(toFileUrl('node_modules/xhshow-js/dist/index.js')),
  'utf8',
);
const extractConst = (name) => {
  const m = indexSource.match(new RegExp(`var ${name} = "([^"]+)"`));
  assert(m, `index.js 中未找到 ${name}`);
  return m[1];
};
const HEX_KEY = extractConst('HEX_KEY');
const CUSTOM_ALPHABET = extractConst('CUSTOM_BASE64_ALPHABET');
const X3_ALPHABET = extractConst('X3_BASE64_ALPHABET');
assert(/^[0-9a-f]{248}$/.test(HEX_KEY), 'HEX_KEY 应为 248 位 hex(124 字节)');
assert(CUSTOM_ALPHABET.length === 64 && X3_ALPHABET.length === 64, '字母表长度应为 64');

// ---- 与 index.js 逐字对应的 crc32JsInt 副本(该函数未被导出) ----
function crc32JsInt(data) {
  let crc = 4294967295;
  for (let i = 0; i < data.length; i++) {
    crc ^= data[i];
    for (let j = 0; j < 8; j++) {
      crc = crc >>> 1 ^ 3988292384 & -(crc & 1);
    }
  }
  const c = (crc ^ 4294967295) >>> 0;
  const poly = 3988292384;
  const u = (4294967295 ^ c ^ poly) >>> 0;
  return u | 0;
}

// ---- 本地 EvpKDF+RC4 复刻(用于 rc4_vectors 自检,算法已另行探针验证) ----
function evpkdfMd5(pwStr, saltBuf, keyLen) {
  const pw = Buffer.from(pwStr, 'utf8');
  let block = createHash('md5').update(Buffer.concat([pw, saltBuf])).digest();
  const parts = [block];
  while (Buffer.concat(parts).length < keyLen) {
    block = createHash('md5').update(Buffer.concat([block, pw, saltBuf])).digest();
    parts.push(block);
  }
  return Buffer.concat(parts).subarray(0, keyLen);
}
function rc4(key, data) {
  const S = [...Array(256).keys()];
  let j = 0;
  for (let i = 0; i < 256; i++) {
    j = (j + S[i] + key[i % key.length]) % 256;
    [S[i], S[j]] = [S[j], S[i]];
  }
  const out = Buffer.alloc(data.length);
  let i = 0;
  j = 0;
  for (let k = 0; k < data.length; k++) {
    i = (i + 1) % 256;
    j = (j + S[i]) % 256;
    [S[i], S[j]] = [S[j], S[i]];
    out[k] = data[k] ^ S[(S[i] + S[j]) % 256];
  }
  return out;
}

// ---- 工具 ----
const hex = (bytes) => Buffer.from(bytes).toString('hex');

function decodeX3Raw(x3) {
  // decodeX3Base64 的结果(未做 XOR 逆变换),内嵌 HEX_KEY 信息
  let sig = x3.startsWith('mns0301_') ? x3.slice('mns0301_'.length) : x3;
  return [...xhshow.decodeX3Base64(sig)];
}

// ---- 固定输入 ----
const A1 = '18ee4d580016f0abc123def456ghi789jkl012mno34550001234';
assert(A1.length === 52, `a1 长度应为 52,实际 ${A1.length}`);
const WEB_SESSION = '18d06c1c5c8gq0p1vbxhiqbwyy044b1fY1Xy8m1y2vQ5Q';
const TS = 1727673600000;
const client = new Client();

// ---- x-s 向量(固定输入,完整记录 node 输出) ----
const xsInputs = [
  {
    name: 'get_no_params',
    method: 'GET',
    uri: '/api/sns/red/live/web/feed/category',
    params: {},
  },
  {
    name: 'get_multi_params_pythonquote',
    method: 'GET',
    uri: '/api/sns/red/live/search/rooms',
    // 键序故意乱序;含逗号(需 pythonQuote 还原)、中文与空格
    params: { z_b: '3', keyword: '中文 直播', tags: '游戏,才艺', room_id: '123456', a_a: '1' },
  },
  {
    name: 'get_full_url',
    method: 'GET',
    uri: 'https://live-room.xiaohongshu.com/api/sns/red/live/enter_room?ignore=1',
    params: { room_id: '999' },
  },
  {
    name: 'get_array_param',
    method: 'GET',
    uri: '/api/sns/red/live/feed',
    params: { ids: ['7', '8', '9'], type: '1' },
  },
];

const xs_vectors = xsInputs.map((input) => {
  const x_s = client.signXS(input.method, input.uri, A1, 'xhs-pc-web', input.params, TS);
  assert(x_s.startsWith('XYS_'), 'x-s 应以 XYS_ 开头');
  const wrapper = JSON.parse(
    Buffer.from(decodeCustomBase64(x_s.slice('XYS_'.length))).toString('utf8'),
  );
  const payload = [...client.decodeX3(wrapper.x3)];
  assert(payload.length === 124, `x3 解码后应为 124 字节,实际 ${payload.length}`);
  return {
    name: input.name,
    method: input.method,
    uri: input.uri,
    params: input.params,
    a1: A1,
    app_id: 'xhs-pc-web',
    timestamp_ms: TS,
    expected_x_s: x_s,
    expected_wrapper: { x0: wrapper.x0, x1: wrapper.x1, x2: wrapper.x2, x4: wrapper.x4 },
    expected_payload_hex: hex(payload),
    expected_x3_raw_hex: hex(decodeX3Raw(wrapper.x3)),
  };
});

// 自检:x3 裸字节 XOR HEX_KEY 后应等于 payload
{
  const keyBytes = Buffer.from(HEX_KEY, 'hex');
  for (const v of xs_vectors) {
    const raw = Buffer.from(v.expected_x3_raw_hex, 'hex');
    const payload = Buffer.from(v.expected_payload_hex, 'hex');
    for (let i = 0; i < 124; i++) {
      const k = i < keyBytes.length ? keyBytes[i] : 0;
      assert((raw[i] ^ k) === payload[i], `x3_raw_hex 与 payload_hex 在偏移 ${i} 不自洽`);
    }
  }
}

// ---- x-s-common:固定字段 + 样例 ----
const xscSample = client.signXSCommon({ a1: A1, web_session: WEB_SESSION });
const xscSig = JSON.parse(
  Buffer.from(decodeCustomBase64(xscSample)).toString('utf8'),
);
const xs_common_fixed_fields = {
  s0: xscSig.s0,
  s1: xscSig.s1,
  x0: xscSig.x0,
  x1: xscSig.x1,
  x2: xscSig.x2,
  x3: xscSig.x3,
  x4: xscSig.x4,
  x6: xscSig.x6,
  x7: xscSig.x7,
  x10: xscSig.x10,
  x11: xscSig.x11,
};
assert(xscSig.x5 === A1, 'x5 应为 a1');

// ---- RC4 语义向量(crypto-js passphrase 模式:随机 8 字节 salt,EvpKDF 派生 32 字节 key) ----
const rc4_vectors = [
  '',
  '{"x33":"0","x82":"_0x17a2|_0x1954"}',
  '中文 mixed ascii 123',
  'a'.repeat(300),
].map((plaintext) => {
  const passphrase = 'xhswebmplfbt';
  const out = RC4.encrypt(plaintext, passphrase);
  const saltHex = out.salt.toString(CryptoJS.enc.Hex);
  const keyHex = out.key.toString(CryptoJS.enc.Hex);
  const ctHex = out.ciphertext.toString(CryptoJS.enc.Hex);
  const key = evpkdfMd5(passphrase, Buffer.from(saltHex, 'hex'), 32);
  assert(key.toString('hex') === keyHex, 'EvpKDF 复刻自检失败');
  assert(
    rc4(key, Buffer.from(plaintext, 'utf8')).toString('hex') === ctHex,
    'RC4 复刻自检失败',
  );
  return {
    plaintext,
    passphrase,
    salt_hex: saltHex,
    key_hex: keyHex,
    ciphertext_hex: ctHex,
  };
});

// ---- crc32JsInt 向量 ----
const crc32_inputs = ['', 'hello', 'XYS_fZbGzKramg0qufeVO0R', 'x'.repeat(1000)];
const crc32_vectors = crc32_inputs.map((input) => ({
  input_utf8: input,
  expected: crc32JsInt(Buffer.from(input, 'utf8')),
}));

// ---- traceid ----
const xray_ts = 1727673600000;
const xray_seq = 8388607;
const xray_expected = generateXrayTraceId(xray_ts, xray_seq);
assert(
  xray_expected.startsWith(
    ((BigInt(xray_ts) << 23n) | BigInt(xray_seq)).toString(16).padStart(16, '0'),
  ),
  'xray 向量前段应等于 (ts<<23|seq) 的 hex',
);
const b3_sample = client.getB3TraceId();
assert(/^[a-f0-9]{16}$/.test(b3_sample), 'b3 应为 16 位 hex');

// ---- 写出 ----
const fixture = {
  meta: {
    generator: 'test/support/xhs_vector_gen.mjs',
    source: `${SF_ROOT}/node_modules/xhshow-js/dist/index.js`,
    note:
      'x-s 的 x3 payload 内嵌随机区域:seed(4..7)、fpB 时间偏移(16..23,偏移量 10..50)、' +
      'seq(24..27,15..50)、windowPropsLen(28..31,900..1200),并衍生 md5^seedByte0(36..43)' +
      '与校验字节(110),故 x-s 不具备逐字节确定性;确定性区域逐字节可比。',
    hex_key: HEX_KEY,
    custom_base64_alphabet: CUSTOM_ALPHABET,
    x3_base64_alphabet: X3_ALPHABET,
  },
  xs_vectors,
  xs_common_fixed_fields,
  xs_common_sample: { a1: A1, web_session: WEB_SESSION, output: xscSample },
  rc4_vectors,
  crc32_vectors,
  b3_traceid_sample: b3_sample,
  xray_traceid_vector: { timestamp: xray_ts, seq: xray_seq, expected: xray_expected },
};

const outPath = join(import.meta.dirname, '..', 'fixtures', 'xhs', 'signing_vectors.json');
mkdirSync(join(import.meta.dirname, '..', 'fixtures', 'xhs'), { recursive: true });
writeFileSync(outPath, `${JSON.stringify(fixture, null, 2)}\n`, 'utf8');
console.log(`已生成 ${outPath}`);
console.log(`x-s 向量 ${xs_vectors.length} 组;rc4 向量 ${rc4_vectors.length} 组;crc32 向量 ${crc32_vectors.length} 组`);
