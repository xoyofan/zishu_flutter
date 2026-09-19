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
    this.heartbeatInterval = kHuyaDanmakuHeartbeat,
    this.url = kHuyaDanmakuUrl,
  }) : _http = parserHttp,
       _transport = transport ?? const IoDanmakuTransport();

  final ParserHttp _http;
  final DanmakuTransport _transport;
  final Duration heartbeatInterval;
  final String url;

  @override
  SiteCapabilities get capabilities => const SiteCapabilities(danmaku: true);

  @override
  Future<DanmakuSession> connect(DanmakuSessionRequest request) async {
    final topSid = await fetchHuyaDanmakuTopSid(_http, request.roomId);
    final socket = await _transport.connect(Uri.parse(url));
    return HuyaDanmakuSession(
      request.roomId,
      topSid,
      socket,
      heartbeatInterval: heartbeatInterval,
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
  }) {
    _messages = _messagesController.stream;
    _states = _statesController.stream;
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
    var userLevel = 0;
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
              // Tars 字段按 tag 升序排布,必须先读 tag 3 再读 tag 4(与
              // web parseOfficialBadgeInfo 的读取顺序一致)。
              final name = badge.readString(3);
              final level = badge.readInt(4);
              if (level > 0) {
                badgeLevel = level;
                badgeName = name;
              }
            case _decoAppIdConsumeLevel:
              final level = TarsReader(deco.data).readInt(1);
              if (level > 0) {
                userLevel = level;
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

    return DanmakuMessage(
      type: DanmakuMessageType.chat,
      roomId: roomId,
      color: fontColor > 0 ? (fontColor & 0xffffff) : 0,
      userName: nickName,
      userId: '',
      text: content,
      badgeName: badgeName,
      badgeLevel: badgeLevel,
      userLevel: userLevel,
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
