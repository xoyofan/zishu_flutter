/// 虎牙弹幕:WebSocket + Tars 协议(pure_live 对齐)。
///
/// 帧:`WebSocketCommand{cmdType, data}`;加入分组 cmdType=16,心跳 5,
/// 服务端推送 7(data 为 HYPushMessage{pushType, uri, msg, protocolType}),
/// uri=1400 为弹幕(MessageNotice),8006 为在线人数。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../../http/danmaku_transport.dart';
import '../../http/parser_http.dart';
import '../../contracts/contracts.dart';
import '../../models/models.dart';
import '../../utils/chat_dedup.dart';
import '../douyu/json_utils.dart';
import 'huya_fans_badge_resource.dart';
import 'huya_wup.dart';
import 'room_api.dart';
import 'tars_codec.dart';
import 'tars_exception.dart';

/// 服务端 -> 客户端命令码。
const int _cmdS2CHeartbeatAck = 6;
const int _cmdS2CMsgPush = 7;
const int _cmdS2CRegisterGroupRsp = 17;

/// 客户端 -> 服务端命令码。
const int _cmdC2SHeartbeat = 5;
const int _cmdC2SRegisterGroup = 16;

/// 弹幕消息 uri。
const int _uriChatMessage = 1400;
const int _uriOnlineCount = 8006;

/// 装饰 appId(web 真源 HUYA_DECO_APP,apps/web/src/utils/danmaku/huyaJce.ts
/// 306-309 行):10400 粉丝牌、11200 消费等级牌。
const int _decoAppIdFans = 10400;
const int _decoAppIdConsumeLevel = 11200;

/// MessageNotice 中装饰列表可能出现的 tag(web 真源 420 行:8/9/12/15 均按
/// `LIST<DecorationInfo>` 累积读取)。
const List<int> _decorationTags = [8, 9, 12, 15];

/// 虎牙 sMessageId 形如「数字-数字」时视为弱 id(web huyaDanmakuDedupKey 的
/// 排除规则同款),不去重判重。
final RegExp _kHuyaWeakId = RegExp(r'^\d+-\d+$');

const Duration kHuyaDanmakuHeartbeat = Duration(seconds: 60);

const String kHuyaDanmakuUrl = 'wss://cdnws.api.huya.com:443';

class HuyaDanmakuConnector implements DanmakuConnector {
  HuyaDanmakuConnector({
    required ParserHttp parserHttp,
    DanmakuTransport? transport,
    // 房间级粉丝牌资源通道(wupui/getResourceInfo);null = 不拉(测试/降级)。
    this.wup,
    this.heartbeatInterval = kHuyaDanmakuHeartbeat,
    this.url = kHuyaDanmakuUrl,
  })  : _http = parserHttp,
        _transport = transport ?? const IoDanmakuTransport();

  final ParserHttp _http;
  final DanmakuTransport _transport;

  /// 房间级粉丝牌资源通道;null 时不拉房间资源(UI 沿用自绘胶囊)。
  final HuyaWupClient? wup;
  final Duration heartbeatInterval;
  final String url;

  @override
  SiteCapabilities get capabilities => const SiteCapabilities(danmaku: true);

  @override
  Future<DanmakuSession> connect(DanmakuSessionRequest request) async {
    final topSid = await fetchHuyaDanmakuTopSid(_http, request.roomId);
    // 房间级粉丝牌底图模板:fire-and-forget,早于 socket 建连发起(实测为
    // 全局资源包,只需一次),**失败/超时一律降级**,不影响弹幕连接。
    final resource = wup?.fetchFansBadgeResource().then(
      (value) => value,
      onError: (Object _) => null,
    );
    final socket = await _transport.connect(Uri.parse(url));
    return HuyaDanmakuSession(
      request.roomId,
      topSid,
      socket,
      heartbeatInterval: heartbeatInterval,
      fansBadgeResource: resource,
    );
  }
}

/// 从 profileRoom 取弹幕分组 id(lChannelId,回退 liveChannel/channel)。
Future<int> fetchHuyaDanmakuTopSid(ParserHttp http, String roomId) async {
  final room = roomId.trim();
  if (!RegExp(r'^\d+$').hasMatch(room)) {
    throw ParserHttpException('无效虎牙房间号: $roomId');
  }
  final data = await fetchHuyaProfileRoomData(http, room);
  if (data == null) {
    throw const ParserHttpException('虎牙房间信息获取失败');
  }
  final streamInfoList = jsonMapOfList(jsonMapOf(data['stream'])['baseSteamInfoList']);
  var topSid = 0;
  if (streamInfoList.isNotEmpty) {
    topSid = _intOf(streamInfoList.first['lChannelId']);
  }
  if (topSid == 0) {
    final liveData = jsonMapOf(data['liveData']);
    topSid = _intOf(liveData['liveChannel'] ?? liveData['channel']);
  }
  if (topSid == 0) {
    throw const ParserHttpException('房间未开播或缺少弹幕连接参数');
  }
  return topSid;
}

class HuyaDanmakuSession implements DanmakuSession {
  HuyaDanmakuSession(
    this.roomId,
    this.topSid,
    this._socket, {
    required Duration heartbeatInterval,
    Future<HuyaFansBadgeResource?>? fansBadgeResource,
  }) {
    _messages = _messagesController.stream;
    _states = _statesController.stream;
    // 资源到达后回填缓存;在资源就绪前到的弹幕按无底图降级(不阻塞正文)。
    _fansBadgeResource = null;
    fansBadgeResource?.then((resource) => _fansBadgeResource = resource);
    _statesController.add(DanmakuSessionState.connecting);
    _subscription = _socket.data.listen(
      _onData,
      onDone: () => _emitDisconnected(),
      onError: (Object _) => _emitDisconnected(),
    );
    _sendJoinGroup();
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) {
      if (!_closed) _socket.send(_encodeCommand(_cmdC2SHeartbeat, Uint8List(0)));
    });
  }

  final String roomId;
  final int topSid;
  final DanmakuSocket _socket;

  late final Stream<DanmakuMessage> _messages;
  late final Stream<DanmakuSessionState> _states;
  late final StreamSubscription<Object?> _subscription;
  late final Timer _heartbeatTimer;

  /// chat 重推去重:cap 对齐 web huyaDanmakuDedup(800)。
  final ChatDedup _chatDedup = ChatDedup(cap: 800);

  final _messagesController = StreamController<DanmakuMessage>.broadcast();
  final _statesController = StreamController<DanmakuSessionState>.broadcast();

  /// 房间级粉丝牌资源(已到达的缓存;null = 未取到,UI 降级自绘胶囊)。
  HuyaFansBadgeResource? _fansBadgeResource;

  bool _closed = false;

  @override
  Stream<DanmakuMessage> get messages => _messages;

  @override
  Stream<DanmakuSessionState> get states => _states;

  void _sendJoinGroup() {
    final body = TarsWriter()
      ..writeStringList(['live:$topSid', 'chat:$topSid'], 0)
      ..writeString('', 1);
    _socket.send(_encodeCommand(_cmdC2SRegisterGroup, body.takeBytes()));
  }

  Uint8List _encodeCommand(int cmdType, Uint8List data) {
    final writer = TarsWriter()
      ..writeInt(cmdType, 0)
      ..writeBytes(data, 1);
    return writer.takeBytes();
  }

  void _onData(Object? data) {
    final Uint8List bytes;
    if (data is List<int>) {
      bytes = Uint8List.fromList(data);
    } else if (data is String) {
      bytes = utf8.encode(data);
    } else {
      return;
    }
    try {
      final frame = decodeTarsCommandFrame(bytes);
      switch (frame.cmdType) {
        case _cmdS2CRegisterGroupRsp:
          // 分组注册确认作为会话就绪信号
          _statesController.add(DanmakuSessionState.connected);
        case _cmdS2CHeartbeatAck:
          break;
        case _cmdS2CMsgPush:
          _handlePush(frame.data);
      }
    } on TarsDecodeException {
      // 单帧解析失败不影响后续帧。
    }
  }

  void _handlePush(Uint8List data) {
    final reader = TarsReader(data);
    final uri = reader.readInt(1);
    final msg = reader.readBytes(2);
    switch (uri) {
      case _uriChatMessage:
        final message = _chatFromNotice(msg);
        // WS 常对同一条推送多次(对齐 web huyaDanmakuDedup,cap 800):
        // 优先 sMessageId 判重;虎牙 sMessageId 常为「数字-数字」格式(web
        // huyaDanmakuDedupKey 的 ^\d+-\d+$ 排除规则视为无效),此时与空 id
        // 一致走「用户+正文」兜底 key。
        if (message != null) {
          final key = message.id.isNotEmpty && !_kHuyaWeakId.hasMatch(message.id)
              ? message.id
              : '${message.userName}\u0000${message.text}';
          if (!_chatDedup.allow(key)) return;
          _messagesController.add(message);
        }
      case _uriOnlineCount:
        final online = TarsReader(msg).readInt(0);
        _messagesController.add(
          DanmakuMessage(
            type: DanmakuMessageType.other,
            roomId: roomId,
            userName: '',
            userId: '',
            text: '$online',
            rawType: 'huya:8006',
          ),
        );
    }
  }

  DanmakuMessage? _chatFromNotice(Uint8List msg) {
    final reader = TarsReader(msg);
    var nickName = '';
    reader.readStruct(0, (userInfo) {
      nickName = userInfo.readString(2);
    });
    final content = reader.readString(3);
    // 表情:MessageNotice 当前协议(web 真源 huyaJce.ts parseMessageNotice
    // 391-435 行)只有 userInfo@0/content@3/color@5/decorations@8/9/12/15/
    // sMessageId@20,没有独立表情段;正文内嵌的 `[表情名]` 括号文本 web 端
    // 也不做图片化(DanmakuRichText 的 emoji 映射表仅 douyin 加载)。故虎牙
    // 保持纯文本,DanmakuMessage.segments 恒空,不拆段。
    var fontColor = 0;
    reader.readStruct(6, (format) {
      fontColor = format.readInt(0);
    });

    // 徽章/等级(对齐 web 真源 parseMessageNotice,apps/web/src/utils/danmaku/
    // huyaJce.ts:392-435):装饰列表 DecorationInfo{appId@0, data@2} 可能出现在
    // tag 8/9/12/15,全部累积、同 appId 后写覆盖先写(applyDecorations,374-390 行)。
    // - appId=10400 粉丝牌 BadgeInfo{sBadgeName@3, iBadgeLevel@4}(350-361 行);
    //   level<=0 视为无牌,不覆盖此前有效值(normalizeHuyaBadge,
    //   apps/web/src/utils/badges/fanBadges/huya.ts:107-125)。
    // - appId=11200 消费等级 ConsumeLevelBadgeInfo{iLevel@1}(362-373 行);
    //   level<=0 视为无等级(normalizeHuyaUserLevel,
    //   apps/web/src/utils/badges/userLevels/huya.ts:9-28)。契约 userLevel
    //   即消费等级,UI 端与粉丝牌并列渲染、无回退关系(SideChatTab.vue:38-46,
    //   lib/src/features/play/widgets/play_side_panel.dart:1044-1060)。
    var badgeName = '';
    var badgeLevel = 0;
    var badgeVFlag = 0;
    var badgeVLogo = '';
    var userLevel = 0;
    var userLevelStyle = 0;
    var userLevelPolished = 0;
    // BadgeInfo tag 17/19/22/25/26(字段号逐条核对自官网 Tars 生成代码
    // `assets/modules/taf/structs/FansServant.js` 的 `SimpleBadgeInfo`,
    // 与 `MessageNotice` 弹幕装饰用的是同一结构):
    // - 17 iBadgeType:非 0 = 「信仰」牌(`E_BADGE_TYPE_FAITH`),也是
    //   `<identity>` 占位符的回落值;
    // - 18 tFaithInfo / 19 tSuperFansInfo:19 内 **iSFFlag@1**(超粉标识);
    // - 22 iCustomBadgeFlag:1 = 房间定制粉丝牌(走 CustomFansBadgeResource);
    // - 25 tExternal: **iFansIdentity@1**、**iBadgeSize@2**;
    // - 26 iExtinguished:1 = 熄灭态(官网 floorUrl 的 `<dark>`)。
    var badgeType = 0;
    var badgeSuperFans = 0;
    var badgeCustom = 0;
    var badgeIdentity = 0;
    var badgeSize = 0;
    var badgeExtinguished = 0;
    try {
      for (final tag in _decorationTags) {
        final decorations = reader.readStructList(
          tag,
          (r) => (appId: r.readInt(0), data: r.readBytes(2)),
        );
        for (final deco in decorations) {
          // 空 data 跳过,与 web `if (!deco?.data?.byteLength) continue` 一致。
          if (deco.data.isEmpty) continue;
          switch (deco.appId) {
            case _decoAppIdFans:
              final badge = TarsReader(deco.data);
              // Tars 字段按 tag 升序排布,必须按序读(与官网
              // `SimpleBadgeInfo.readFrom` 同序);tag 18/19/25 是 struct,
              // 必须读到才能继续定位后面的 tag。
              final name = badge.readString(3);
              final level = badge.readInt(4);
              final vFlag = badge.readInt(12);
              final vLogo = badge.readString(13);
              badgeType = badge.readInt(17);
              // tFaithInfo(18):协议不消费,读掉以保持偏移。
              badge.readStruct(18, (_) {});
              var superFans = 0;
              badge.readStruct(19, (sf) {
                // SuperFansInfo{0 lSFExpiredTS, 1 iSFFlag, 2 lSFAnnualTS,
                // 3 iSFVariety, 4 lOpenTS, 5 lMemoryDay}(官网生成代码)。
                superFans = sf.readInt(1);
              });
              final custom = badge.readInt(22);
              var identity = 0;
              var size = 0;
              badge.readStruct(25, (external) {
                // CustomBadgeDynamicExternal{0 sFloorExter, 1 iFansIdentity,
                // 2 iBadgeSize}。
                identity = external.readInt(1);
                size = external.readInt(2);
              });
              final extinguished = badge.readInt(26);
              if (level > 0) {
                badgeLevel = level;
                badgeName = name;
                badgeVFlag = vFlag;
                badgeVLogo = vLogo;
                badgeSuperFans = superFans;
                badgeCustom = custom;
                badgeIdentity = identity;
                badgeSize = size;
                badgeExtinguished = extinguished;
              }
            case _decoAppIdConsumeLevel:
              final levelReader = TarsReader(deco.data);
              final level = levelReader.readInt(1);
              final style = levelReader.readInt(2);
              final polished = levelReader.readInt(3);
              if (level > 0) {
                userLevel = level;
                userLevelStyle = style;
                userLevelPolished = polished;
              }
          }
        }
      }
    } on TarsDecodeException {
      // 装饰数据残缺只丢徽章不丢正文(web 整帧 catch 会丢整条,这里更保守)。
    }

    // 消息 id:MessageNotice.sMessageId(tag 20,web huyaJce.ts 同 tag)。
    // 读取须在装饰(tag 8-15)之后 —— Tars 字段按 tag 升序排布。
    var sMessageId = '';
    try {
      sMessageId = reader.readString(20);
    } on TarsDecodeException {
      // 无 id 不影响正文。
    }

    // 官方底图:房间级资源(CommonFansBadgeSplit.tCommonBadge.sFloorUrl)
    // 拼出,放在 `DanmakuBadge.url`(UI 粉丝牌胶囊的官方底图位);拿不到
    // 资源时留空串,UI 沿用自绘渐变胶囊。`<identity>` 取官网
    // `sfid || type`:优先 `tExternal.iFansIdentity`,否则 `iBadgeType`。
    //
    // **定制牌**(iCustomBadgeFlag==1)官网走 NewFloor 空底框
    // (`<size>_<ua>_<status>_<sfmark>_<level>`)并叠独立等级数字图
    // (`AppLevel <ua>_<level>.png`),与通用 DefaultFloor(等级已烘焙)
    // 完全不同(2026-09-27 房间 518518 官网 shadow DOM 取证)。status:
    // 官网按 per-badge `iSFEffectLevel` 判特效档,定制包未下发控制时
    // 实测超粉恒 2 / 非超粉恒 1 —— 按 sfMark 近似。
    final resource = _fansBadgeResource;
    final isCustom = badgeCustom == 1;
    final safeSize = badgeSize <= 0 ? kHuyaFansBadgeDefaultSize : badgeSize;
    final sfMark = badgeSuperFans > 0 ? 1 : 0;
    final customFloorUrl = !isCustom || resource == null
        ? ''
        : huyaCustomBadgeFloorUrl(
            template: resource.customFloorTemplate,
            level: badgeLevel,
            size: safeSize,
            sfMark: sfMark,
            status: sfMark > 0 ? 2 : 1,
          );
    final customLevelUrl = !isCustom || resource == null
        ? ''
        : huyaCustomBadgeLevelUrl(
            template: resource.customLevelUrlTemplate,
            level: badgeLevel,
          );
    final floorUrl = resource == null
        ? ''
        : isCustom && customFloorUrl.isNotEmpty
            ? customFloorUrl
            : huyaFansBadgeFloorUrl(
                template: resource.floorUrlTemplate,
                level: badgeLevel,
                identity: badgeIdentity > 0 ? badgeIdentity : badgeType,
                size: safeSize,
                dark: badgeExtinguished,
              );

    final badge = badgeName.isNotEmpty && badgeLevel > 0
        ? DanmakuBadge(
            name: badgeName,
            level: badgeLevel,
            vFlag: badgeVFlag,
            vLogo: badgeVLogo,
            // 虎牙 `DanmakuBadge.url` = 官方粉丝牌**底图**(非图标);
            // 与其它平台的 `url` 语义不同,只由虎牙分支消费。
            url: floorUrl,
            // 定制牌的独立等级数字图(NewFloor 底框不含数字),UI 叠加。
            levelUrl: customLevelUrl,
            identity: badgeIdentity,
            badgeSize: safeSize,
            floorUrlTemplate: resource?.floorUrlTemplate ?? '',
            extinguished: badgeExtinguished,
            custom: isCustom,
          )
        : null;
    return DanmakuMessage(
      type: DanmakuMessageType.chat,
      roomId: roomId,
      color: fontColor > 0 ? (fontColor & 0xffffff) : 0,
      userName: nickName,
      userId: '',
      text: content,
      badgeName: badgeName,
      badgeLevel: badgeLevel,
      badges: badge == null ? const [] : [badge],
      userLevel: userLevel,
      userLevelBadgeStyle: userLevelStyle,
      userLevelIsPolished: userLevelPolished,
      // 贵族(虎牙 iNobleLevel)只在 **OnTVBarrageNotice**(uri 1450 的
      // OnTV 系消息)里,`MessageNotice` 的装饰结构不含该字段 → 恒 0,
      // 宁可留空也不编数据。
      nobleLevel: 0,
      // 超粉:`BadgeInfo.tSuperFansInfo.iSFFlag@1` > 0。
      superFan: badgeSuperFans > 0,
      id: sMessageId,
      rawType: 'huya:1400',
    );
  }

  void _emitDisconnected() {
    if (_closed) return;
    _statesController.add(DanmakuSessionState.disconnected);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _heartbeatTimer.cancel();
    await _subscription.cancel();
    _statesController.add(DanmakuSessionState.disconnected);
    await _socket.close();
    await _messagesController.close();
    await _statesController.close();
  }
}

int _intOf(Object? value) => value is num ? value.toInt() : int.tryParse('${value ?? ''}') ?? 0;
