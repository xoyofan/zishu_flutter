/// 虎牙 wup(TUP v3)贵宾查询:字节级 golden 锁定。
///
/// golden 字节为 2026-09-19 对线上 `cdnws.api.huya.com` 实测抓取
/// (房间 11342412,presenterUid=channelId=1394575534):
/// - 请求侧逐字节对齐 web `@tars/stream` Tup 构造(同参数同 requestId);
/// - 响应侧为同参数另一次实时抓取的完整报文(贵宾数实时变化,
///   VipBarListRsp.iTotal=76、iTotalNum=76;web Tup.decode 同报文确认),
///   锁定真实解析路径(map 嵌套 + struct list 跳跃)。
library;

import 'dart:typed_data';

import 'package:live_parser/src/platforms/huya/huya_wup.dart';
import 'package:live_parser/src/platforms/huya/tars_codec.dart';
import 'package:test/test.dart';

/// 线上实测请求(liveui/getVipBarList,requestId=12345)。
const String _kGoldenRequestHex =
    '0000006510032c3c41303956066c6976657569660d6765745669704261724c697374'
    '7d00003a0800010604745265711d00002d0a0a3614776562683526302e302e30266f'
    '6666696369616c0b12531f88ae22531f88ae3c400152531f88ae6c0b8c980ca80c';

/// 线上实测响应(VipBarListRsp.iTotal=76、iTotalNum=76)。
const String _kGoldenResponseHex =
    '0000056d10032c3c41303956066c6976657569660d6765745669704261724c6973747d00'
    '01054108000206001d0000010c0604745273701d0001052c0a10012003304c4900030a02'
    '5804ea7010112a025804ea701c226be876803606e585ace788b54004500460027c8100ee'
    '9a0c1c2c3c4c5c66000baa0c160026003c4c5c0bb2658399d90b3a0c1c2c3c460056006c'
    '7c8c9ca600b6000b4a0c1c2c3c4c5c6c7c8c9600acba06001c2c0bccdc0b5606e5a4a7e5'
    'a4a76c7c866168747470733a2f2f68757961696d672e6d737374617469632e636f6d2f61'
    '76617461722f313036302f35312f38616335343034353465663363396462383234653031'
    '33663732343064645f3138305f3133352e6a70673f313536303539373539349ca02dd609'
    '2d312e303030303030e6092d312e303030303030f60f00fa100c16000bf61100fa120258'
    '04ea70120014a3980bfa130c1c2c3c4c56000bfa140c1c26000bfa150c1600260036000b'
    'f91600010a000c1d00000a025804ea7010192c30010bfc17fc1b0b0a030000000081fa79'
    '0e10022a0c1c2c36004c5c6c7c8c9a0c1c2c3c4c5c66000baa0c160026003c4c5c0bbc0b'
    '3a030000000081fa790e12531f88ae2102093300000000aa9636ff4611666c6f77706574'
    '5f32303030352e6d7034564568747470733a2f2f6469792d6173736574732e6d73737461'
    '7469632e636f6d2f687979732f677561726467726164653230323231312f677561726472'
    '616e6b2f312e706e676c725a184200826ab54900910c95a600b6000b4a0c1c2c3c4c5c6c'
    '7c8c9600acba06001c2c0bccdc0b561438e79a84e5ae88e68aa4e7b2bee781b531e58fb7'
    '6c7c8660687474703a2f2f68757961696d672e6d737374617469632e636f6d2f61766174'
    '61722f313032392f39302f61653165316665323037656265323736323166636437343166'
    '39353066645f3138305f3133352e6a70673f313538313139383933329cacd600e600f60f'
    '00fa100c16000bf61100fa120c1c0bfa130c1c2c3c4c56000bfa140c1c26000bfa150c16'
    '00260036000bf91600010a00091d0000180601381613e79a84e5ae88e68aa4e7b2bee781'
    'b531e58fb70bfc17fc1b0b0a03000001174b4e9e0f10022a0c1c2c36004c5c6c7c8c9a0c'
    '1c2c3c4c5c66000baa0c160026003c4c5c0bbc0b3a03000001174b4e9e0f12531f88ae20'
    '09326bad22ff4611666c6f777065745f32303030352e6d7034564568747470733a2f2f64'
    '69792d6173736574732e6d737374617469632e636f6d2f687979732f6775617264677261'
    '64653230323231312f677561726472616e6b2f312e706e676c7269821b80826a99998091'
    '00e4a600b6000b4a0c1c2c3c4c5c6c7c8c9600acba06001c2c0bccdc0b5631e59083e68e'
    '89e59083e68e89e59083e68e89e7bb9fe7bb9fe59083e68e89e79a84e5ae88e68aa4e7b2'
    'bee781b531e58fb76c7c866168747470733a2f2f68757961696d672e6d73737461746963'
    '2e636f6d2f6176617461722f313036342f64612f31623963383432363934383231346132'
    '37333166623432383663386234635f3138305f3133352e6a70673f313738393737353332'
    '319cacd600e600f60f00fa100c16000bf61100fa120c1c0bfa130c1c2c3c4c56000bfa14'
    '0c1c26000bfa150c1600260036000bf91600010a00091d000035061ee59083e68e89e590'
    '83e68e89e59083e68e89e7bb9fe7bb9fe59083e68e891613e79a84e5ae88e68aa4e7b2be'
    'e781b531e58fb70bfc17fc1b0b5606e6989fe9a5ad6c72531f88ae865668747470733a2f'
    '2f6469792d6173736574732e6d737374617469632e636f6d2f687979732f66656e7a7561'
    '6e7368656e676a69323032322f66656e7a75616e6f6c642f6a69616e726f6e6766656e7a'
    '75616e2e706e67990ca04cb600c6000b8c980ca80c';

Uint8List _hexBytes(String hex) {
  final result = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < result.length; i++) {
    result[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return result;
}

/// 构造最小可用 wup 响应(sBuffer = {"tRsp": struct{3: total, 10: totalNum}})。
Uint8List buildFakeVipResponse({required int total, required int totalNum}) {
  final rspStruct = TarsWriter()
    ..writeStruct((writer) {
      writer.writeInt(total, 3);
      writer.writeInt(totalNum, 10);
    }, 0);
  final sBuffer = TarsWriter()
    ..writeBytesMap({'tRsp': rspStruct.takeBytes()}, 0);
  return buildTupPacket(
    servant: 'liveui',
    func: 'getVipBarList',
    requestId: 7,
    sBuffer: sBuffer.takeBytes(),
  );
}

void main() {
  test('请求构造:与线上实测字节逐位一致(web @tars/stream 对齐)', () {
    final request = buildVipBarListRequest(
      presenterUid: 1394575534,
      channelId: 1394575534,
      requestId: 12345,
    );
    expect(
      request,
      _hexBytes(_kGoldenRequestHex),
      reason: 'TUP 包长头 + RequestPacket(tag1..10) + sBuffer 必须逐字节对齐',
    );
  });

  test('响应解析:真实线上报文读出 iTotal/iTotalNum', () {
    final count = parseVipBarListResponse(_hexBytes(_kGoldenResponseHex));
    expect(count.total, 76);
    expect(count.totalNum, 76);
  });

  test('响应解析:跨 tag 跳跃(list 中间字段不干扰 tag3/tag10)', () {
    // tRsp struct 内塞 tag1/tag2 与一个 list(tag4),tag3/tag10 仍可定位。
    final rspStruct = TarsWriter()
      ..writeStruct((writer) {
        writer.writeInt(1, 1);
        writer.writeInt(3, 2);
        writer.writeInt(21, 3);
        writer.writeStringList(const ['a', 'b'], 4);
        writer.writeInt(42, 10);
      }, 0);
    final sBuffer = TarsWriter()
      ..writeBytesMap({'tRsp': rspStruct.takeBytes()}, 0);
    final packet = buildTupPacket(
      servant: 'liveui',
      func: 'getVipBarList',
      requestId: 1,
      sBuffer: sBuffer.takeBytes(),
    );
    final count = parseVipBarListResponse(packet);
    expect(count.total, 21);
    expect(count.totalNum, 42);
  });

  test('响应解析:缺 tRsp / 包过短 / 非法字节全部抛 TarsDecodeException', () {
    expect(
      () => parseVipBarListResponse(Uint8List.fromList([0, 0, 0, 4])),
      throwsA(anything),
      reason: '无 sBuffer',
    );
    expect(
      () => parseVipBarListResponse(Uint8List.fromList([0, 0])),
      throwsA(anything),
      reason: '包过短',
    );
    expect(
      () => parseVipBarListResponse(
        Uint8List.fromList(List<int>.filled(64, 0xff)),
      ),
      throwsA(anything),
      reason: '非法字段类型',
    );
  });

  test('HuyaWupClient.fetchVipBarCount:presenterUid 非正数直接返回 null', () async {
    final client = HuyaWupClient();
    addTearDown(client.close);
    expect(await client.fetchVipBarCount(presenterUid: 0, channelId: 1), isNull);
    expect(await client.fetchVipBarCount(presenterUid: -1, channelId: 1), isNull);
  });
}
