/// 虎牙贵宾查询:Tars wup(TUP v3)二进制协议。
///
/// 真源对齐 SFVideoLive `services/streaming-server/src/follow/huya-wup.ts`
/// (web 侧经 `@tars/stream` 的 Tup 封装);请求/响应字节结构均为
/// 2026-09-19 对线上 cdnws.api.huya.com 实测确认(golden 见
/// `test/src/platforms/huya/huya_wup_test.dart`)。
///
/// 协议要点:
/// - POST `https://cdnws.api.huya.com/?baseinfo=default`,body =
///   4 字节大端包长(含自身)+ RequestPacket:
///   tag1 tupVersion=3、tag2 cPacketType=0、tag3 iMessageType=0、
///   tag4 iRequestId、tag5 servantName=`liveui`、tag6 funcName=`getVipBarList`、
///   tag7 sBuffer、tag8 iTimeout=0、tag9 context={}、tag10 status={}
///   (两个空 map;`@tars/stream` 对空 map 编码为 MAP 头 + tag0 zeroTag)。
/// - sBuffer 是 `map<string, vector<byte>>`:`{"tReq": <VipListReq 编码>}`。
///   `@tars/stream` 的 UniAttribute 实测把「内层 map<类型名, BinBuffer>」
///   退化成单个 BinBuffer 直写 tag1(SimpleList),本实现按实测字节对齐,
///   服务端不校验类型名。
/// - VipListReq(单个 struct):tag0 tUserId{tag3 sHuyaUserId=
///   `webh5&0.0.0&official`}、tag1 lTid=channelId、tag2 lSid=channelId、
///   tag3 iStart=0、tag4 iCount=1、tag5 lPid=presenterUid、tag6 iUidNum=0。
/// - 响应同构:sBuffer `{"tRsp": <VipBarListRsp 编码>}`;VipBarListRsp 是
///   单个 struct:tag3 iTotal(当前条目数)、tag10 iTotalNum(贵宾总数)。
///   SideHeader「贵宾」行取 iTotalNum(web follow/status.ts 的 huya 快照
///   用 formatCount(rsp.iTotalNum || rsp.iTotal))。
///
/// SVIP 口径说明(web 真源里没有「SVIP 文本」判定,不得伪造):
/// - SideHeader 的 svip tone 行是「超粉人数」(wupui/getSuperFansInfo +
///   getSuperFansRankPanel),不是身份档位;本轮未实现,RoomSummary 无
///   对应字段。
/// - 聊天行的 VIP/SVIP 是虎牙消费等级(11200 ConsumeLevelBadgeInfo
///   iLevel,弹幕侧已提取为 DanmakuMessage.userLevel)渲染的 emblem 图,
///   消费等级 → 7 档 identity 映射(≤4→1、≤7→2、≤10→3、≤13→4、≤16→11、
///   ≤19→12、其余 13;web fanBadges/huya.ts resolveHuyaVipEmblemIdentity),
///   徽章图片化由后续 UI 波次消费该映射,不在本文件展开。
library;

import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'tars_codec.dart';
import 'tars_exception.dart';

/// 虎牙 wup 网关(web huya-wup.ts WUP_URL)。
const String kHuyaWupUrl = 'https://cdnws.api.huya.com/?baseinfo=default';

/// web huya-wup.ts WUP_HEADERS(Content-Type 必须是二进制流)。
const Map<String, String> kHuyaWupHeaders = {
  'Content-Type': 'application/octet-stream',
  'User-Agent':
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  'Origin': 'https://www.huya.com',
  'Referer': 'https://www.huya.com/',
};

const String _kUserToken = 'webh5&0.0.0&official';

/// liveui/getVipBarList 请求体(含 4 字节包长)。
///
/// [requestId] 任意;服务端原样回显([parseVipBarListResponse] 不校验)。
Uint8List buildVipBarListRequest({
  required int presenterUid,
  required int channelId,
  int requestId = 1,
}) {
  final req = TarsWriter()
    ..writeStruct((writer) {
      writer.writeStruct((userId) => userId.writeString(_kUserToken, 3), 0);
      writer.writeInt(channelId, 1);
      writer.writeInt(channelId, 2);
      writer.writeInt(0, 3);
      writer.writeInt(1, 4);
      writer.writeInt(presenterUid, 5);
      writer.writeInt(0, 6);
    }, 0);
  final sBuffer = TarsWriter()..writeBytesMap({'tReq': req.takeBytes()}, 0);
  return buildTupPacket(
    servant: 'liveui',
    func: 'getVipBarList',
    requestId: requestId,
    sBuffer: sBuffer.takeBytes(),
  );
}

/// 编码完整 TUP 包:4 字节大端包长(含自身)+ RequestPacket tag1..tag10。
Uint8List buildTupPacket({
  required String servant,
  required String func,
  required int requestId,
  required Uint8List sBuffer,
}) {
  final writer = TarsWriter()
    ..writeInt(3, 1)
    ..writeInt(0, 2)
    ..writeInt(0, 3)
    ..writeInt(requestId, 4)
    ..writeString(servant, 5)
    ..writeString(func, 6)
    ..writeBytes(sBuffer, 7)
    ..writeInt(0, 8)
    ..writeStringMap(const {}, 9)
    ..writeStringMap(const {}, 10);
  final payload = writer.takeBytes();
  final total = payload.length + 4;
  return Uint8List.fromList([
    (total >> 24) & 0xff,
    (total >> 16) & 0xff,
    (total >> 8) & 0xff,
    total & 0xff,
    ...payload,
  ]);
}

/// getVipBarList 响应的贵宾计数(整数;展示层自行格式化)。
class HuyaVipBarCount {
  const HuyaVipBarCount({required this.total, required this.totalNum});

  /// 当前条目数(VipBarListRsp.iTotal,web 用作 iTotalNum 的兜底)。
  final int total;

  /// 贵宾总数(VipBarListRsp.iTotalNum,SideHeader「贵宾」行口径)。
  final int totalNum;
}

/// 解析 getVipBarList 响应;结构不符时抛 [TarsDecodeException]。
HuyaVipBarCount parseVipBarListResponse(Uint8List bytes) {
  if (bytes.length < 8) {
    throw const TarsDecodeException('wup packet too short');
  }
  final packet = TarsReader(Uint8List.sublistView(bytes, 4));
  final sBuffer = packet.readBytes(7);
  if (sBuffer.isEmpty) {
    throw const TarsDecodeException('wup packet without sBuffer');
  }
  final attributes = TarsReader(sBuffer).readBytesMap(0);
  final rsp = attributes['tRsp'];
  if (rsp == null || rsp.isEmpty) {
    throw const TarsDecodeException('wup response without tRsp');
  }
  int? total;
  int? totalNum;
  TarsReader(rsp).readStruct(0, (reader) {
    total = reader.readInt(3);
    totalNum = reader.readInt(10);
  });
  if (total == null || totalNum == null) {
    throw const TarsDecodeException('wup response without tRsp struct');
  }
  return HuyaVipBarCount(total: total!, totalNum: totalNum!);
}

/// wup HTTP 客户端:与 [ParserHttp] 平行,独立注入 [http.Client] 便于单测。
class HuyaWupClient {
  HuyaWupClient({http.Client? httpClient})
    : _client = httpClient ?? http.Client(),
      _ownsClient = httpClient == null;

  final http.Client _client;
  final bool _ownsClient;

  void close() {
    if (_ownsClient) _client.close();
  }

  /// liveui/getVipBarList → 贵宾总数;任何失败(HTTP 非 200/超时/解析异常)
  /// 返回 null,调用方留空不伪造(与 web huya-wup.ts 的 catch→"" 同语义)。
  Future<int?> fetchVipBarCount({
    required int presenterUid,
    required int channelId,
  }) async {
    if (presenterUid <= 0) return null;
    final request = buildVipBarListRequest(
      presenterUid: presenterUid,
      channelId: channelId <= 0 ? presenterUid : channelId,
      requestId: DateTime.now().microsecondsSinceEpoch % 1000000,
    );
    try {
      final response = await _client
          .post(Uri.parse(kHuyaWupUrl), headers: kHuyaWupHeaders, body: request)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      return parseVipBarListResponse(response.bodyBytes).totalNum;
    } on Exception {
      return null;
    }
  }
}
