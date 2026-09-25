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
/// - SideHeader 的 svip tone 行(`ROOM_STAT_COLUMNS.huya` 第 3 列,
///   `field: "diamondFans"` / label「超粉」)是**超粉人数**,不是身份档位:
///   servant `wupui` 的 `getSuperFansInfo`(`iSuperFansNum +
///   iYearSuperFansNum`,tag1/tag2)为主,为 0/不可信时回退
///   `getSuperFansRankPanel`(`iNum` tag5 + `iPlusNum` tag10);两请求并发
///   发出,口径与 web `fetchHuyaSuperFanCount` 完全一致(含
///   `isPlausibleHuyaSuperFanCount` 置信度校验)。承载字段为
///   [RoomSummary.diamondFans](沿用 web `FollowStatus.diamondFans` 键名)。
/// - 两请求的 RequestPacket 结构与 `liveui/getVipBarList` 完全相同
///   (仅 servant/func/sBuffer 内的 struct 字段编号不同),字节级 golden 见
///   `test/src/platforms/huya/huya_wup_test.dart`(与 web `@tars/stream`
///   同参数输出逐字节一致)。
/// - 聊天行的 VIP/SVIP 是虎牙消费等级(11200 ConsumeLevelBadgeInfo
///   iLevel,弹幕侧已提取为 DanmakuMessage.userLevel)渲染的 emblem 图,
///   消费等级 → 7 档 identity 映射(≤4→1、≤7→2、≤10→3、≤13→4、≤16→11、
///   ≤19→12、其余 13;web fanBadges/huya.ts resolveHuyaVipEmblemIdentity),
///   徽章图片化由后续 UI 波次消费该映射,不在本文件展开。
library;

import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'huya_fans_badge_resource.dart';
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

/// wupui/getSuperFansInfo 请求体(含 4 字节包长)。
///
/// GetSuperFansInfoReq(单个 struct):tag0 tUserId{tag3 sHuyaUserId=
/// `webh5&0.0.0&official`}、tag1 lPid=presenterUid、tag2 lTid=channelId、
/// tag3 lSid=channelId(注意字段编号与 VipListReq 不同)。
Uint8List buildSuperFansInfoRequest({
  required int presenterUid,
  required int channelId,
  int requestId = 1,
}) {
  final req = TarsWriter()
    ..writeStruct((writer) {
      writer.writeStruct((userId) => userId.writeString(_kUserToken, 3), 0);
      writer.writeInt(presenterUid, 1);
      writer.writeInt(channelId, 2);
      writer.writeInt(channelId, 3);
    }, 0);
  final sBuffer = TarsWriter()..writeBytesMap({'tReq': req.takeBytes()}, 0);
  return buildTupPacket(
    servant: 'wupui',
    func: 'getSuperFansInfo',
    requestId: requestId,
    sBuffer: sBuffer.takeBytes(),
  );
}

/// wupui/getSuperFansRankPanel 请求体(含 4 字节包长)。
///
/// GetSuperFansRankPanelReq(单个 struct):tag0 tUserId、tag1 lPid=
/// presenterUid、tag2 iPage=0、tag3 iCount=1(web 真源只填 lPid,
/// 不发 channelId)。
Uint8List buildSuperFansRankPanelRequest({
  required int presenterUid,
  int page = 0,
  int count = 1,
  int requestId = 1,
}) {
  final req = TarsWriter()
    ..writeStruct((writer) {
      writer.writeStruct((userId) => userId.writeString(_kUserToken, 3), 0);
      writer.writeInt(presenterUid, 1);
      writer.writeInt(page, 2);
      writer.writeInt(count, 3);
    }, 0);
  final sBuffer = TarsWriter()..writeBytesMap({'tReq': req.takeBytes()}, 0);
  return buildTupPacket(
    servant: 'wupui',
    func: 'getSuperFansRankPanel',
    requestId: requestId,
    sBuffer: sBuffer.takeBytes(),
  );
}

/// wupui/getResourceInfo 请求体(含 4 字节包长)。
///
/// `GetResourceInfoReq` 字段号**逐条核对自官网 Tars 生成代码**
/// (`assets/modules/taf/structs/ResourceManagerServant.js`,见
/// [HuyaFansBadgeResource] 文件头):tag0 tUserId{tag3 sHuyaUserId}、
/// tag1 sScene、tag2 sVersion、tag3 lPid。
///
/// **只发 tag0 + tag1**:`lPid` 字段号虽已从官网代码取到(tag3),但
/// 2026-09-26 实测表明 `CommonFansBadgeSplit` 的底图模板与房间无关
/// (房间 333003 / 9999 响应字节完全一致,加/不加 lPid 也一致),
/// 故不发无用的 lPid;`sVersion` 官网也不填。
Uint8List buildResourceInfoRequest({int requestId = 1}) {
  final req = TarsWriter()
    ..writeStruct((writer) {
      writer.writeStruct((userId) => userId.writeString(_kUserToken, 3), 0);
      writer.writeString('web', 1);
    }, 0);
  final sBuffer = TarsWriter()..writeBytesMap({'tReq': req.takeBytes()}, 0);
  return buildTupPacket(
    servant: 'wupui',
    func: 'getResourceInfo',
    requestId: requestId,
    sBuffer: sBuffer.takeBytes(),
  );
}

/// getSuperFansInfo 响应的超粉计数(整数;展示层自行格式化)。
class HuyaSuperFansInfo {
  const HuyaSuperFansInfo({
    required this.superFansNum,
    required this.yearSuperFansNum,
  });

  /// 超粉数(GetSuperFansInfoRsp.iSuperFansNum,tag1)。
  final int superFansNum;

  /// 年超粉数(GetSuperFansInfoRsp.iYearSuperFansNum,tag2)。
  final int yearSuperFansNum;

  /// web 口径:`iSuperFansNum + iYearSuperFansNum`。
  int get total => superFansNum + yearSuperFansNum;
}

/// getSuperFansRankPanel 响应的超粉计数。
class HuyaSuperFansPanel {
  const HuyaSuperFansPanel({required this.num, required this.plusNum});

  /// 当前页超粉数(GetSuperFansRankPanelRsp.iNum,tag5)。
  final int num;

  /// 附加超粉数(GetSuperFansRankPanelRsp.iPlusNum,tag10)。
  final int plusNum;

  /// web 口径:`iNum + iPlusNum`。
  int get total => num + plusNum;
}

/// web `isPlausibleHuyaSuperFanCount`:>0、不等于 presenterUid(uid 原样
/// 回显视为脏值)、且 ≤ 5_000_000;不满足即视为不可信,不得展示。
bool isPlausibleHuyaSuperFanCount(int total, int presenterUid) {
  if (total <= 0) return false;
  if (total == presenterUid) return false;
  if (total > 5000000) return false;
  return true;
}

/// 取出 wup 响应里 `tRsp` 的 struct 编码(包长头 → sBuffer → tRsp);
/// 结构不符时抛 [TarsDecodeException]。
Uint8List _readResponseStruct(Uint8List bytes) {
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
  return rsp;
}

/// 解析 getSuperFansInfo 响应;结构不符时抛 [TarsDecodeException]。
///
/// 字段缺失按 0 读(tag 不存在 → 0),与 web `readInt32(tag, false, 0)` 同口径;
/// 0 由调用方按「数据诚实性」留空,不回填。
HuyaSuperFansInfo parseSuperFansInfoResponse(Uint8List bytes) {
  var seen = false;
  int? superFansNum;
  int? yearSuperFansNum;
  TarsReader(_readResponseStruct(bytes)).readStruct(0, (reader) {
    seen = true;
    superFansNum = reader.readInt(1);
    yearSuperFansNum = reader.readInt(2);
  });
  if (!seen || superFansNum == null || yearSuperFansNum == null) {
    throw const TarsDecodeException('wup response without tRsp struct');
  }
  return HuyaSuperFansInfo(
    superFansNum: superFansNum!,
    yearSuperFansNum: yearSuperFansNum!,
  );
}

/// 解析 getSuperFansRankPanel 响应;结构不符时抛 [TarsDecodeException]。
HuyaSuperFansPanel parseSuperFansRankPanelResponse(Uint8List bytes) {
  var seen = false;
  int? num;
  int? plusNum;
  TarsReader(_readResponseStruct(bytes)).readStruct(0, (reader) {
    seen = true;
    num = reader.readInt(5);
    plusNum = reader.readInt(10);
  });
  if (!seen || num == null || plusNum == null) {
    throw const TarsDecodeException('wup response without tRsp struct');
  }
  return HuyaSuperFansPanel(num: num!, plusNum: plusNum!);
}

/// 解析 getVipBarList 响应;结构不符时抛 [TarsDecodeException]。
HuyaVipBarCount parseVipBarListResponse(Uint8List bytes) {
  final rsp = _readResponseStruct(bytes);
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
    final bytes = await _exchange(
      buildVipBarListRequest(
        presenterUid: presenterUid,
        channelId: channelId <= 0 ? presenterUid : channelId,
        requestId: _nextRequestId(),
      ),
    );
    if (bytes == null) return null;
    try {
      return parseVipBarListResponse(bytes).totalNum;
    } on TarsDecodeException {
      return null;
    }
  }

  /// wupui/getSuperFansInfo → 超粉原始计数;失败返回 null(不伪造 0)。
  Future<HuyaSuperFansInfo?> fetchSuperFansInfo({
    required int presenterUid,
    required int channelId,
  }) async {
    if (presenterUid <= 0) return null;
    final bytes = await _exchange(
      buildSuperFansInfoRequest(
        presenterUid: presenterUid,
        channelId: channelId <= 0 ? presenterUid : channelId,
        requestId: _nextRequestId(),
      ),
    );
    if (bytes == null) return null;
    try {
      return parseSuperFansInfoResponse(bytes);
    } on TarsDecodeException {
      return null;
    }
  }

  /// wupui/getSuperFansRankPanel → 超粉榜单计数;失败返回 null。
  Future<HuyaSuperFansPanel?> fetchSuperFansRankPanel({
    required int presenterUid,
    int page = 0,
    int count = 1,
  }) async {
    if (presenterUid <= 0) return null;
    final bytes = await _exchange(
      buildSuperFansRankPanelRequest(
        presenterUid: presenterUid,
        page: page,
        count: count,
        requestId: _nextRequestId(),
      ),
    );
    if (bytes == null) return null;
    try {
      return parseSuperFansRankPanelResponse(bytes);
    } on TarsDecodeException {
      return null;
    }
  }

  /// 超粉人数(`RoomSummary.diamondFans` 口径):web
  /// `fetchHuyaSuperFanCount` 的等价实现 ——
  /// `getSuperFansInfo`(iSuperFansNum + iYearSuperFansNum)与
  /// `getSuperFansRankPanel`(iNum + iPlusNum)**并发**发出(对齐真源
  /// `Promise.all`,仅在播时调用,不给关注刷新链路重复发请求),
  /// 取第一个通过 [isPlausibleHuyaSuperFanCount] 的结果;
  /// 都不可信(或请求失败)返回 null —— 调用方留空,不回填 0。
  Future<int?> fetchSuperFanCount({
    required int presenterUid,
    required int channelId,
  }) async {
    if (presenterUid <= 0) return null;
    try {
      final (info, panel) = await (
        fetchSuperFansInfo(presenterUid: presenterUid, channelId: channelId),
        fetchSuperFansRankPanel(presenterUid: presenterUid),
      ).wait;
      final fromInfo = info?.total ?? 0;
      if (isPlausibleHuyaSuperFanCount(fromInfo, presenterUid)) {
        return fromInfo;
      }
      final fromPanel = panel?.total ?? 0;
      if (isPlausibleHuyaSuperFanCount(fromPanel, presenterUid)) {
        return fromPanel;
      }
      return null;
    } on Exception {
      return null;
    }
  }

  /// wupui/getResourceInfo → 房间级粉丝牌底图模板;失败返回 null
  /// (不伪造,调用方沿用自绘胶囊降级)。
  ///
  /// 房间级资源实为全局资源包(实测),故不需 presenterUid;单次会话在
  /// `connect()` 时 fire-and-forget 拉一次即可。
  Future<HuyaFansBadgeResource?> fetchFansBadgeResource() async {
    final bytes = await _exchange(
      buildResourceInfoRequest(requestId: _nextRequestId()),
    );
    if (bytes == null) return null;
    final Uint8List tRsp;
    try {
      tRsp = _readResponseStruct(bytes);
    } on TarsDecodeException {
      return null;
    }
    return parseHuyaResourceInfoResponse(tRsp);
  }

  /// POST 一次 wup 请求并返回原始报文;非 200/超时/网络异常统一 null。
  Future<Uint8List?> _exchange(Uint8List request) async {
    try {
      final response = await _client
          .post(Uri.parse(kHuyaWupUrl), headers: kHuyaWupHeaders, body: request)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      return response.bodyBytes;
    } on Exception {
      return null;
    }
  }

  /// 请求 id(服务端原样回显、不校验);同一次刷新内的并发请求取不同值。
  int _nextRequestId() =>
      (DateTime.now().microsecondsSinceEpoch + _requestSeq++) % 1000000;

  static int _requestSeq = 0;
}
