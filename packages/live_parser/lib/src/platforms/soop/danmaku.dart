/// SOOP 弹幕:自有文本协议 WebSocket。
///
/// 帧以 `ESC TAB`(`\x1b\x09`)开头、字段以 `\x0c` 分隔;连接后先发 connect
/// 包,200ms 后发 join 包,之后每 20s 发一次心跳。协议与 pure_live 对齐。
library;

import 'dart:async';
import 'dart:convert';

import '../../contracts/contracts.dart';
import '../../http/danmaku_transport.dart';
import '../../http/parser_http.dart';
import '../../models/models.dart';
import 'normalize.dart';
import 'room_api.dart';

/// 心跳间隔。
const Duration kSoopDanmakuHeartbeat = Duration(seconds: 20);

/// join 包延迟:connect 包发出后等待 200ms 再进房(pure_live 同款)。
const Duration kSoopDanmakuJoinDelay = Duration(milliseconds: 200);

const String _escape = '\x1b\x09';
const String _separator = '\x0c';

class SoopDanmakuConnector implements DanmakuConnector {
  SoopDanmakuConnector(
    this._http, {
    DanmakuTransport? transport,
    this.heartbeatInterval = kSoopDanmakuHeartbeat,
  }) : transport = transport ?? const IoDanmakuTransport();

  final ParserHttp _http;
  final DanmakuTransport transport;
  final Duration heartbeatInterval;

  @override
  SiteCapabilities get capabilities => const SiteCapabilities(danmaku: true);

  @override
  Future<DanmakuSession> connect(DanmakuSessionRequest request) async {
    final roomId = normalizeSoopRoomId(request.roomId);
    final payload = await fetchSoopPlayerApi(_http, roomId);
    final detail = parseSoopRoomDetail(payload, roomId);
    if (!detail.hasChat) {
      throw const ParserHttpException('SOOP 弹幕参数缺失(可能已下播)');
    }

    final uri = Uri.parse(
      'wss://${detail.chatDomain}:${detail.chatPort}/Websocket/$roomId',
    );
    final socket = await transport.connect(uri, protocols: const ['chat']);
    return SoopDanmakuSession(
      roomId,
      detail.chatNo,
      socket,
      heartbeatInterval: heartbeatInterval,
    );
  }
}

class SoopDanmakuSession implements DanmakuSession {
  SoopDanmakuSession(
    this.roomId,
    this.chatNo,
    this._socket, {
    required Duration heartbeatInterval,
  }) {
    _statesController.add(DanmakuSessionState.connecting);
    _subscription = _socket.data.listen(
      _onData,
      onDone: () => _onDisconnected(DanmakuSessionState.disconnected),
      onError: (Object _) => _onDisconnected(DanmakuSessionState.disconnected),
    );
    // 握手由 transport.connect 完成,这里直接发握手包并视为已连接。
    _send('${_escape}000100000600$_separator$_separator${_separator}16$_separator');
    _joinTimer = Timer(kSoopDanmakuJoinDelay, () {
      if (!_closed) {
        final size = utf8.encode(chatNo).length + 6;
        _send(
          '${_escape}0002${size.toString().padLeft(6, '0')}00$_separator'
          '$chatNo$_separator$_separator$_separator$_separator$_separator',
        );
      }
    });
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) {
      if (!_closed) _send('${_escape}000000000100$_separator');
    });
    _statesController.add(DanmakuSessionState.connected);
  }

  final String roomId;
  final String chatNo;
  final DanmakuSocket _socket;

  late final StreamSubscription<Object?> _subscription;
  late final Timer _joinTimer;
  late final Timer _heartbeatTimer;

  final _messagesController = StreamController<DanmakuMessage>.broadcast();
  final _statesController = StreamController<DanmakuSessionState>.broadcast();

  bool _closed = false;

  @override
  Stream<DanmakuMessage> get messages => _messagesController.stream;

  @override
  Stream<DanmakuSessionState> get states => _statesController.stream;

  void _send(String packet) => _socket.send(utf8.encode(packet));

  void _onData(Object? data) {
    if (_closed || data is! List<int>) return;
    final messages = _splitBySeparator(data)
        .map((part) => utf8.decode(part, allowMalformed: true))
        .toList();
    // 聊天帧:字段足够、第二字段不是控制码、且不含「|」分隔的批量行。
    if (messages.length <= 6) return;
    final text = messages[1];
    if (text.isEmpty ||
        text == '-1' ||
        text == '1' ||
        text.contains('|')) {
      return;
    }
    _messagesController.add(
      DanmakuMessage(
        type: DanmakuMessageType.chat,
        roomId: roomId,
        userName: messages[6],
        userId: '',
        text: text,
        rawType: 'chat',
      ),
    );
  }

  void _onDisconnected(DanmakuSessionState state) {
    if (_closed) return;
    _statesController.add(state);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _joinTimer.cancel();
    _heartbeatTimer.cancel();
    await _subscription.cancel();
    await _socket.close();
    _statesController.add(DanmakuSessionState.disconnected);
    await _messagesController.close();
    await _statesController.close();
  }
}

/// 按单字节分隔符切分,**保留空段**(字段按位置取,与 pure_live splitList 一致)。
List<List<int>> _splitBySeparator(List<int> data) {
  if (data.isEmpty) return const [];
  final parts = <List<int>>[];
  var start = 0;
  for (var i = 0; i < data.length; i++) {
    if (data[i] == 0x0c) {
      parts.add(data.sublist(start, i));
      start = i + 1;
    }
  }
  parts.add(data.sublist(start, data.length));
  return parts;
}
