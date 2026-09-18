/// B 站弹幕:WebSocket + 二进制包协议(zlib protover=2,零第三方依赖)。
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
import 'packet.dart';
import 'room_api.dart';
import 'wbi.dart';

const Duration kBilibiliDanmakuHeartbeat = Duration(seconds: 30);

const String kBilibiliDanmakuFallbackUrl = 'wss://broadcastlv.chat.bilibili.com/sub';

class BilibiliDanmakuConnector implements DanmakuConnector {
  BilibiliDanmakuConnector({
    required ParserHttp parserHttp,
    DanmakuTransport? transport,
    BilibiliCredentials? credentials,
    this.heartbeatInterval = kBilibiliDanmakuHeartbeat,
    this.fallbackUrl = kBilibiliDanmakuFallbackUrl,
  }) : _http = parserHttp,
       _credentials = credentials ?? BilibiliCredentials(),
       _transport = transport ?? const IoDanmakuTransport();

  final ParserHttp _http;
  final BilibiliCredentials _credentials;
  final DanmakuTransport _transport;
  final Duration heartbeatInterval;
  final String fallbackUrl;

  @override
  SiteCapabilities get capabilities => const SiteCapabilities(danmaku: true);

  @override
  Future<DanmakuSession> connect(DanmakuSessionRequest request) async {
    final room = request.roomId.trim();
    if (!RegExp(r'^\d+$').hasMatch(room)) {
      throw ParserHttpException('无效 B 站房间号: ${request.roomId}');
    }

    final prepared = await _prepare(room);
    final socket = await _transport.connect(Uri.parse(prepared.wsUrl));
    return BilibiliDanmakuSession(
      room,
      prepared.authBody,
      socket,
      heartbeatInterval: heartbeatInterval,
    );
  }

  /// 取弹幕服务器与鉴权参数:getDanmuInfo 失败降级 getConf;再失败回退公共端点。
  Future<({String wsUrl, String authBody})> _prepare(String room) async {
    final buvid3 = await _credentials.fetchBuvid3(_http);
    var hostList = const <Map<String, dynamic>>[];
    var token = '';

    Future<void> loadInfo() async {
      final data = jsonMapOf(
        await bilibiliFetchJson(
          _http,
          _credentials,
          Uri.parse('https://api.live.bilibili.com/xlive/web-room/v1/index/getDanmuInfo'),
          params: {'id': room, 'type': '0'},
          roomId: room,
        ),
      );
      token = jsonText(data['token']);
      hostList = jsonListOf(data['host_list']).whereType<Map<String, dynamic>>().toList();
    }

    Future<void> loadConf() async {
      final data = jsonMapOf(
        await bilibiliFetchJson(
          _http,
          _credentials,
          Uri.parse('https://api.live.bilibili.com/room/v1/Danmu/getConf'),
          params: {'room_id': room},
          roomId: room,
        ),
      );
      token = jsonText(data['token']);
      final servers = jsonListOf(data['host_server_list']).whereType<Map<String, dynamic>>().toList();
      if (servers.isNotEmpty) {
        hostList = servers;
      } else {
        final host = jsonText(data['host']);
        if (host.isNotEmpty) {
          hostList = [
            {'host': host, 'port': jsonInt(data['port']), 'wss_port': 443},
          ];
        }
      }
    }

    try {
      await loadInfo();
    } on BilibiliApiException {
      // getDanmuInfo 被风控时降级 getConf。
    }
    if (token.isEmpty || hostList.isEmpty) {
      await loadConf();
    }

    final host = hostList.isEmpty
        ? null
        : hostList.firstWhere(
            (item) => jsonText(item['host']).isNotEmpty,
            orElse: () => hostList.first,
          );
    if (token.isEmpty) {
      throw const ParserHttpException('房间未开播或缺少弹幕连接参数');
    }

    final wsUrl = host == null
        ? fallbackUrl
        : _wsUrlOf(jsonText(host['host']), jsonInt(host['wss_port'] ?? host['port']));

    // 带 buvid 时 uid 固定 0,避免服务端 uid 校验不一致。
    final auth = jsonEncode({
      'uid': 0,
      'roomid': int.parse(room),
      'protover': 2,
      if (buvid3.isNotEmpty) 'buvid': buvid3,
      'platform': 'web',
      'type': 2,
      'key': token,
    });
    return (wsUrl: wsUrl, authBody: auth);
  }

  String _wsUrlOf(String host, int wssPort) {
    final cleanHost = host.replaceFirst(RegExp(r'^https?://'), '');
    final port = wssPort == 0 ? 443 : wssPort;
    return port == 443 ? 'wss://$cleanHost/sub' : 'wss://$cleanHost:$port/sub';
  }
}

class BilibiliDanmakuSession implements DanmakuSession {
  BilibiliDanmakuSession(
    this.roomId,
    String authBody,
    this._socket, {
    required Duration heartbeatInterval,
  }) : _authPacket = encodeBiliPacket(BiliPacketOp.auth, utf8.encode(authBody)) {
    _messages = _messagesController.stream;
    _states = _statesController.stream;
    _statesController.add(DanmakuSessionState.connecting);
    _subscription = _socket.data.listen(
      _onData,
      onDone: () => _emitDisconnected(),
      onError: (Object _) => _emitDisconnected(),
    );
    _socket.send(_authPacket);
    // 认证后需立刻发首次心跳(pure_live/SFVideoLive 同款)。
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) {
      if (!_closed) _sendHeartbeat();
    });
  }

  final String roomId;
  final DanmakuSocket _socket;
  final Uint8List _authPacket;

  late final Stream<DanmakuMessage> _messages;
  late final Stream<DanmakuSessionState> _states;
  late final StreamSubscription<Object?> _subscription;
  late final Timer _heartbeatTimer;

  final _messagesController = StreamController<DanmakuMessage>.broadcast();
  final _statesController = StreamController<DanmakuSessionState>.broadcast();

  bool _closed = false;
  bool _authOk = false;

  /// chat 重推去重:cap 对齐 web bilibiliDanmakuDedup(1200)。
  final ChatDedup _chatDedup = ChatDedup(cap: 1200);

  @override
  Stream<DanmakuMessage> get messages => _messages;

  @override
  Stream<DanmakuSessionState> get states => _states;

  void _sendHeartbeat() => _socket.send(encodeBiliPacket(BiliPacketOp.heartbeat, const []));

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
      _decodeStream(bytes, depth: 0);
    } on BiliPacketFormatException {
      // 单帧解析失败不影响后续帧。
    }
  }

  void _decodeStream(Uint8List data, {required int depth}) {
    if (depth > 3) return;
    for (final packet in decodeBiliPackets(data)) {
      _decodePacket(packet, depth: depth);
    }
  }

  void _decodePacket(BiliPacket packet, {required int depth}) {
    switch (packet.operation) {
      case BiliPacketOp.heartbeatAck:
        if (packet.body.length >= 4) {
          final popularity = ByteData.sublistView(packet.body).getInt32(0, Endian.big);
          _messagesController.add(
            DanmakuMessage(
              type: DanmakuMessageType.other,
              roomId: roomId,
              userName: '',
              userId: '',
              text: '$popularity',
              rawType: 'bilibili:popularity',
            ),
          );
        }
      case BiliPacketOp.message:
        if (packet.protocolVersion == 2) {
          _decodeStream(decompressBiliBody(packet.body, 2), depth: depth + 1);
        } else if (packet.protocolVersion == 0) {
          _handleText(decodeUtf8(packet.body));
        }
      case BiliPacketOp.authAck:
        final text = decodeUtf8(packet.body).trim();
        var code = 0;
        if (text.isNotEmpty) {
          final decoded = jsonMapOf(jsonDecode(text));
          code = jsonInt(decoded['code']);
        }
        if (code == 0 && !_authOk) {
          _authOk = true;
          _statesController.add(DanmakuSessionState.connected);
          _sendHeartbeat();
        } else if (code != 0) {
          _emitDisconnected();
        }
    }
  }

  void _handleText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final obj = jsonMapOf(jsonDecode(trimmed));
    final cmd = jsonText(obj['cmd']);
    if (!cmd.contains('DANMU_MSG')) return;
    final info = obj['info'];
    if (info is! List || info.length < 3) return;

    final meta = info[0] is List ? info[0] as List<Object?> : const <Object?>[];
    final user = info[2] is List ? info[2] as List<Object?> : const <Object?>[];
    final text0 = info.length > 1 ? info[1]?.toString() ?? '' : '';
    final userName = user.length > 1 ? user[1]?.toString() ?? '' : '';
    final userId = user.isNotEmpty ? user[0]?.toString() ?? '' : '';
    final color = meta.length > 3 ? _intOf(meta[3]) : 0;

    // 徽章提取(对齐 web fanBadges/userLevels/bilibili.ts):
    // 粉丝牌优先新协议 info[0][15].user.medal{name,level},回落老结构
    // info[3][0]=level、info[3][1]=name(web 口径,level>0 才有效);
    // 用户等级 UL = info[4][0](纯色 pill,无静态图)。
    var badgeName = '';
    var badgeLevel = 0;
    final metaUser = meta.length > 15 ? jsonMapOf(meta[15]) : null;
    final newMedal = jsonMapOf(jsonMapOf(metaUser)['user'])['medal'];
    if (newMedal is Map) {
      final medal = jsonMapOf(newMedal);
      badgeName = jsonText(medal['name']);
      badgeLevel = jsonInt(medal['level']);
    }
    if (badgeName.isEmpty && badgeLevel <= 0 && info.length > 3 && info[3] is List) {
      final medal = info[3] as List<Object?>;
      final level = medal.isNotEmpty ? _intOf(medal[0]) : 0;
      final name = medal.length > 1 ? medal[1]?.toString() ?? '' : '';
      if (level > 0 && name.isNotEmpty) {
        badgeLevel = level;
        badgeName = name;
      }
    }
    var userLevel = 0;
    if (info.length > 4 && info[4] is List) {
      final ul = info[4] as List<Object?>;
      userLevel = ul.isNotEmpty ? _intOf(ul[0]) : 0;
    }

    // 协议重推去重(对齐 web bilibiliDanmakuDedup,cap 1200):契约暂无
    // id 字段,先用「用户+正文」兜底 key(web id 无效时的 fallback 同款)。
    if (!_chatDedup.allow('$userName\u0000$text0')) return;

    _messagesController.add(
      DanmakuMessage(
        type: DanmakuMessageType.chat,
        roomId: roomId,
        color: color & 0xffffff,
        userName: userName,
        userId: userId,
        text: text0,
        badgeName: badgeName,
        badgeLevel: badgeLevel,
        userLevel: userLevel,
        rawType: cmd,
      ),
    );
  }

  static int _intOf(Object? value) =>
      value is num ? value.toInt() : int.tryParse('${value ?? ''}') ?? 0;

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
