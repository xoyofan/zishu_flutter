/// 虎牙房间级资源 `wupui/getResourceInfo` 字段号**实测探针**(一次性取证工具)。
///
/// 复用 `huya_wup.dart` 已验证的 WUP/TUP 封包基建,只把内层
/// `GetResourceInfoReq` 的候选字段号逐个试,并用通用 Tars dumper 打印
/// 真实响应结构,用于**实测**而非推断字段号。
///
/// 运行:`dart run tool/_probe_huya_resource_info.dart [roomId ...] [--dump]`
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:live_parser/src/platforms/huya/huya_wup.dart';
import 'package:live_parser/src/platforms/huya/tars_codec.dart';

const String _ua =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

// ---------------- 通用 Tars dumper ----------------

class _R {
  _R(this.data);
  final Uint8List data;
  int pos = 0;
  bool get eof => pos >= data.length;
  int u8() => data[pos++];
  int i(int size) {
    final v = ByteData.sublistView(data, pos, pos + size);
    pos += size;
    if (size == 1) return v.getInt8(0);
    if (size == 2) return v.getInt16(0, Endian.big);
    if (size == 4) return v.getInt32(0, Endian.big);
    return v.getInt64(0, Endian.big);
  }

  List<int> head() {
    final b = u8();
    int tag = (b & 0xf0) >> 4;
    final type = b & 0x0f;
    if (tag == 15) tag = u8();
    return [tag, type];
  }

  int length() {
    final h = head();
    return switch (h[1]) { 12 => 0, 0 => i(1), 1 => i(2), _ => i(4) };
  }
}

bool _quiet = false;

/// >0 时 map/list 超过该深度只报长度不展开(大响应体检用)。
int _maxDepth = 0;

void _skip(_R r, int type, int n, int depth) {
  for (var i = 0; i < n; i++) {
    _quiet = true;
    final t = type == 8 ? r.head()[1] : r.head()[1];
    _dump(r, t, '  ', depth + 1);
    if (type == 8) {
      _quiet = true;
      _dump(r, r.head()[1], '  ', depth + 1);
    }
    _quiet = false;
  }
}

String _hex(List<int> b) =>
    b.take(24).map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void _dump(_R r, int type, String indent, int depth) {
  void p(String s) {
    if (!_quiet) print(s);
  }

  if (depth > 12) {
    p('$indent ...(too deep)');
    return;
  }
  if (_maxDepth > 0 && depth >= _maxDepth && (type == 8 || type == 9)) {
    final n = r.length();
    p('$indent ${type == 8 ? 'map' : 'list'}($n) [skipped]');
    _skip(r, type, n, depth);
    return;
  }
  switch (type) {
    case 0:
      p('$indent int8  ${r.i(1)}');
    case 1:
      p('$indent int16 ${r.i(2)}');
    case 2:
      p('$indent int32 ${r.i(4)}');
    case 3:
      p('$indent int64 ${r.i(8)}');
    case 4:
      r.pos += 4;
      p('$indent float');
    case 5:
      r.pos += 8;
      p('$indent double');
    case 6:
      final n = r.i(1);
      p('$indent str   "${utf8.decode(r.data.sublist(r.pos, r.pos + n), allowMalformed: true)}"');
      r.pos += n;
    case 7:
      final n = r.i(4);
      p('$indent str   "${utf8.decode(r.data.sublist(r.pos, r.pos + n), allowMalformed: true)}"');
      r.pos += n;
    case 8:
      final n = r.length();
      p('$indent map($n) {');
      for (var i = 0; i < n; i++) {
        _dump(r, r.head()[1], '$indent  k', depth + 1);
        _dump(r, r.head()[1], '$indent  v', depth + 1);
      }
      p('$indent }');
    case 9:
      final n = r.length();
      p('$indent list($n) [');
      for (var i = 0; i < n; i++) {
        _dump(r, r.head()[1], '$indent  ', depth + 1);
      }
      p('$indent ]');
    case 10:
      p('$indent struct {');
      while (!r.eof) {
        final h = r.head();
        if (h[1] == 11) break;
        p('$indent  @${h[0]}');
        _dump(r, h[1], '$indent  ', depth + 1);
      }
      p('$indent }');
    case 11:
      p('$indent structEnd');
    case 12:
      p('$indent zero');
    case 13:
      r.head();
      final n = r.length();
      p('$indent bytes($n) 0x${_hex(r.data.sublist(r.pos, (r.pos + n).clamp(0, r.data.length)))}');
      r.pos += n;
    default:
      p('$indent ??? type=$type');
  }
}

void dumpBytes(Uint8List data, {String label = '', int maxLines = 300, int maxDepth = 0}) {
  _maxDepth = maxDepth;
  print('--- dump $label (${data.length}B) ---');
  if (data.isEmpty) return;
  final r = _R(data);
  var lines = 0;
  while (!r.eof && lines < maxLines) {
    lines++;
    final h = r.head();
    if (h[1] == 11) {
      r.u8();
      continue;
    }
    try {
      _dump(r, h[1], '  ', 0);
    } on Object catch (e) {
      print('  !! stopped at pos=${r.pos}: $e');
      break;
    }
  }
  if (!r.eof) print('  ...(truncated)');
}

// ---------------- 请求/响应 ----------------

/// 取 wup 响应 sBuffer 里 `tRsp` 的 struct 编码(与 huya_wup 同款口径)。
Uint8List readRsp(Uint8List bytes) {
  final packet = TarsReader(Uint8List.sublistView(bytes, 4));
  final sBuffer = packet.readBytes(7);
  if (sBuffer.isEmpty) return Uint8List(0);
  final attrs = TarsReader(sBuffer).readBytesMap(0);
  print('   sBuffer keys=${attrs.keys.toList()} '
      'sizes=${attrs.map((k, v) => MapEntry(k, v.length))}');
  return attrs['tRsp'] ?? Uint8List(0);
}

Uint8List buildResourceInfoRequest(
  int presenterUid,
  List<MapEntry<int, Object>> fields, {
  String func = 'getResourceInfo',
  int requestId = 1,
}) {
  final req = TarsWriter()
    ..writeStruct((w) {
      w.writeStruct((u) => u.writeString('webh5&0.0.0&official', 3), 0);
      for (final f in fields) {
        final v = f.value;
        if (v is String) {
          w.writeString(v, f.key);
        } else {
          w.writeInt(v as int, f.key);
        }
      }
    }, 0);
  final sBuffer = TarsWriter()..writeBytesMap({'tReq': req.takeBytes()}, 0);
  return buildTupPacket(
    servant: 'wupui',
    func: func,
    requestId: requestId,
    sBuffer: sBuffer.takeBytes(),
  );
}

String? serverError(Uint8List body) {
  final text = utf8.decode(body, allowMalformed: true);
  final i = text.indexOf('read ');
  if (i < 0) return null;
  final j = text.indexOf(';', i);
  return text.substring(i, j < 0 ? i + 200 : j);
}

// ---------------- 定向解码:vResource 列表 ----------------

/// 读 `vector<byte>`(服务端可能用 SIMPLE_LIST 或 LIST-of-byte 两种编码)。
Uint8List readByteVectorUnused(TarsReader r, int tag) => Uint8List(0);

/// 展开 `ResourceWrapper{@0 sName, @1 iType, @2 vData(bytes), @3 ...}`
/// 的 @2 负载并按 Tars dump。
void dumpEnvelopePayload(Uint8List elem) {
  final r = _R(elem);
  r.head(); // structBegin
  final f0 = r.head();
  if (f0[1] == 6) {
    final n = r.i(1);
    r.pos += n;
  }
  final f1 = r.head(); // iType
  if (f1[1] == 1) {
    r.i(2);
  } else if (f1[1] == 2) {
    r.i(4);
  } else if (f1[1] == 0) {
    r.i(1);
  }
  final f2 = r.head();
  if (f2[1] == 13) {
    r.head();
    final n = r.length();
    final payload = Uint8List.fromList(elem.sublist(r.pos, r.pos + n));
    dumpBytes(payload, label: 'envelope vData payload', maxLines: 120);
  } else if (f2[1] == 10) {
    print('   envelope vData is inline struct');
  }
}

/// 逐项解析 UniformResource:{@0 iBizType, @1 vData, @2 vItem}。
void inspectResources(Uint8List tRsp, {int dumpBizType = -1, bool dumpMode = false}) {
  final r = _R(tRsp);
  final h = r.head();
  if (h[1] != 10) {
    print('   tRsp top type=${h[1]} (expect structBegin)');
    return;
  }
  final lh = r.head();
  if (lh[0] != 0 || lh[1] != 9) {
    print('   Rsp @${lh[0]} type=${lh[1]} (expect list)');
    return;
  }
  final n = r.length();
  print('   vResource@0 count=$n');
  for (var i = 0; i < n; i++) {
    final eh = r.head();
    if (eh[1] != 10) {
      print('   [$i] not a struct (type=${eh[1]})');
      break;
    }
    var bizType = -1;
    Uint8List? vData;
    var itemCount = -1;
    while (!r.eof) {
      final fh = r.head();
      if (fh[1] == 11) break;
      switch (fh[1]) {
        case 9:
          final cnt = r.length();
          if (fh[0] == 1) {
            final bytes = <int>[];
            final kinds = <int>[];
            final elemRaw = <Uint8List>[];
            for (var k = 0; k < cnt; k++) {
              final before = r.pos;
              _quiet = true;
              _dump(r, r.head()[1], '', 0);
              _quiet = false;
              final raw = tRsp.sublist(before, r.pos);
              kinds.add(raw.isEmpty ? -1 : raw[0] & 0x0f);
              bytes.addAll(raw);
              elemRaw.add(Uint8List.fromList(raw));
            }
            vData = Uint8List.fromList(bytes);
            print('   [$i] vData(list) len=$cnt elemKinds='
                '${kinds.toSet().toList()}');
            if (dumpMode && (dumpBizType < 0 || bizType == dumpBizType)) {
              for (var k = 0; k < elemRaw.length; k++) {
                dumpBytes(
                  elemRaw[k],
                  label: '[$i] vData[$k]',
                  maxLines: 60,
                );
                dumpEnvelopePayload(elemRaw[k]);
              }
            }
          } else {
            itemCount = cnt;
            _skip(r, fh[1], cnt, 0);
          }
        case 13:
          r.head();
          final cnt = r.length();
          final start = r.pos;
          final out = Uint8List.fromList(tRsp.sublist(start, start + cnt));
          r.pos += cnt;
          if (fh[0] == 1) vData = out;
          if (dumpMode && dumpBizType >= 0 && bizType == dumpBizType) {
            print('   [$i] field@${fh[0]} payload(${out.length}B):');
            dumpBytes(out, label: '   [$i] @${fh[0]} payload');
          }
        default:
          _quiet = true;
          final before = r.pos;
          _dump(r, fh[1], '', 0);
          final raw = tRsp.sublist(before, r.pos);
          _quiet = false;
          if (fh[0] == 0 && raw.length == 1) bizType = raw[0] & 0xff;
          print('   [$i] field@${fh[0]} type=${fh[1]} raw=0x${_hex(raw)}');
      }
    }
    print('   [$i] iBizType=$bizType vDataLen=${vData?.length} '
        'itemCount=$itemCount');
    if (bizType == dumpBizType && vData != null) {
      print('   (bizType $dumpBizType vData 已在上方逐元素 dump)');
    }
  }
}

Future<void> main(List<String> args) async {
  final rooms = args.where((a) => !a.startsWith('--')).toList();
  final dumpMode = args.contains('--dump');
  final shallowDump = args.contains('--shallow');
  final targetArg = args.firstWhere(
    (a) => a.startsWith('--biz='),
    orElse: () => '--biz=-1',
  );
  final targetBiz = int.parse(targetArg.split('=').last);
  final client = http.Client();

  for (final room in rooms.isEmpty ? ['333003'] : rooms) {
    final res = await client.get(
      Uri.parse(
        'https://mp.huya.com/cache.php?m=Live&do=profileRoom'
        '&roomid=$room&showSecret=1',
      ),
      headers: const {'User-Agent': _ua, 'Referer': 'https://www.huya.com/'},
    );
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map;
    final data = body['data'];
    if (data is! Map) {
      print('room $room: no profile data');
      continue;
    }
    final profile = (data['profileInfo'] as Map?) ?? const {};
    final live = (data['liveData'] as Map?) ?? const {};
    final uid = int.tryParse('${profile['uid'] ?? ''}') ??
        int.tryParse('${live['uid'] ?? ''}') ??
        0;
    print('== room $room presenterUid=$uid nick=${profile['nick']} ==');
    if (uid <= 0) continue;

    Future<void> probe(
      String label,
      List<MapEntry<int, Object>> fields, {
      String func = 'getResourceInfo',
    }) async {
      final out = await client
          .post(
            Uri.parse(kHuyaWupUrl),
            headers: kHuyaWupHeaders,
            body: buildResourceInfoRequest(uid, fields, func: func),
          )
          .timeout(const Duration(seconds: 20));
      final b = Uint8List.fromList(out.bodyBytes);
      Uint8List rsp = Uint8List(0);
      try {
        rsp = readRsp(b);
      } on Object catch (e) {
        print('   rsp read failed: $e');
      }
      print('  [$label] http=${out.statusCode} bytes=${b.length} '
          'tRsp=${rsp.length} err=${serverError(b) ?? "(none)"}');
      if (dumpMode && rsp.isNotEmpty) {
        dumpBytes(rsp, label: label, maxLines: 400, maxDepth: shallowDump ? 2 : 0);
        if (func == 'getResourceInfo') {
          inspectResources(rsp, dumpBizType: targetBiz, dumpMode: dumpMode);
        }      }
    }

    await probe('getSuperFansInfo(baseline)', [
      MapEntry(1, uid),
      MapEntry(2, uid),
      MapEntry(3, uid),
    ], func: 'getSuperFansInfo');

    await probe('scene@1 only', [MapEntry(1, 'web')]);
    await probe('scene@1=web + pid@3', [MapEntry(1, 'web'), MapEntry(3, uid)]);
    await probe('scene@1=web + str@2="" + pid@6', [
      MapEntry(1, 'web'),
      MapEntry(2, ''),
      MapEntry(6, uid),
    ]);
    await probe('scene@1=pc', [MapEntry(1, 'pc')]);
    await probe('scene@1=h5', [MapEntry(1, 'h5')]);
    await probe('scene@1=web-h5', [MapEntry(1, 'web-h5')]);
    await probe('scene@1=WEB', [MapEntry(1, 'WEB')]);
    await probe('scene@1= + str@2=web + pid@3', [
      MapEntry(1, ''),
      MapEntry(2, 'web'),
      MapEntry(3, uid),
    ]);
  }
  client.close();
}
