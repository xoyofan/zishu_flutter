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
        if (message != null) _messagesController.add(message);
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
    var fontColor = 0;
    reader.readStruct(6, (format) {
      fontColor = format.readInt(0);
    });

    return DanmakuMessage(
      type: DanmakuMessageType.chat,
      roomId: roomId,
      color: fontColor > 0 ? (fontColor & 0xffffff) : 0,
      userName: nickName,
      userId: '',
      text: content,
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
