/// 抖音弹幕:WSS + PushFrame/protobuf。
///
/// 签名沿用 X-Bogus 变体(SIGN_KEYS 拼接串 md5 -> get_sign),帧解析移植自
/// SFVideoLive `live-shared/src/protocol/douyin`。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../contracts/contracts.dart';
import '../../http/danmaku_transport.dart';
import '../../http/parser_http.dart';
import '../../models/models.dart';
import '../douyu/json_utils.dart';
import 'normalize.dart';
import 'protobuf_lite.dart';
import 'room_api.dart';
import 'xbogus.dart';

/// 弹幕网关。
const String kDouyinWsHost =
    'wss://webcast100-ws-web-lq.douyin.com/webcast/im/push/v2/';

/// 心跳间隔。
const Duration kDouyinHeartbeat = Duration(seconds: 10);

/// 参与 WS 签名的字段(顺序敏感)。
const List<String> kDouyinSignKeys = [
  'live_id',
  'aid',
  'version_code',
  'webcast_sdk_version',
  'room_id',
  'sub_room_id',
  'sub_channel_id',
  'did_rule',
  'user_unique_id',
  'device_platform',
  'device_type',
  'ac',
  'identity',
];

class DouyinDanmakuConnector implements DanmakuConnector {
  DouyinDanmakuConnector(
    this._client, {
    DanmakuTransport? transport,
    this.heartbeatInterval = kDouyinHeartbeat,
  }) : transport = transport ?? const IoDanmakuTransport();

  final DouyinClient _client;
  final DanmakuTransport transport;
  final Duration heartbeatInterval;

  @override
  SiteCapabilities get capabilities => const SiteCapabilities(danmaku: true);

  @override
  Future<DanmakuSession> connect(DanmakuSessionRequest request) async {
    final webRid = normalizeDouyinRoomId(request.roomId);
    final room = await fetchDouyinWebStreamData(_client, webRid);
    if (jsonInt(room['status']) == 4) {
      throw const ParserHttpException('房间未开播或缺少弹幕连接参数');
    }
    final internalRoomId = await resolveDouyinInternalRoomId(
      _client,
      webRid,
      room,
    );
    if (internalRoomId.isEmpty) {
      throw const ParserHttpException('房间未开播或缺少弹幕连接参数');
    }
    final cookie = await _client.sessionCookie();
    final socket = await transport.connect(
      Uri.parse(buildDouyinWsUrl(internalRoomId)),
      headers: {
        'User-Agent': kDouyinUserAgent,
        'Origin': 'https://live.douyin.com',
        'Referer': 'https://live.douyin.com/',
        if (cookie.trim().isNotEmpty) 'Cookie': cookie,
      },
    );
    return DouyinDanmakuSession(
      webRid,
      socket,
      heartbeatInterval: heartbeatInterval,
    );
  }
}

/// 构造弹幕 WS 地址(query 固定参数 + X-Bogus 变体签名)。
String buildDouyinWsUrl(
  String internalRoomId, {
  String? userUniqueId,
  int? timestamp,
}) {
  final uniqueId =
      userUniqueId ??
      '${BigInt.parse('7319483754668557238') + BigInt.from(Random.secure().nextInt(1000000))}';
  final now = timestamp ?? DateTime.now().millisecondsSinceEpoch;
  final params = <MapEntry<String, String>>[
    const MapEntry('app_name', 'douyin_web'),
    const MapEntry('version_code', '180800'),
    const MapEntry('webcast_sdk_version', '1.0.14-beta.0'),
    const MapEntry('update_version_code', '1.0.14-beta.0'),
    const MapEntry('compress', 'gzip'),
    const MapEntry('device_platform', 'web'),
    const MapEntry('cookie_enabled', 'true'),
    const MapEntry('screen_width', '1920'),
    const MapEntry('screen_height', '1080'),
    const MapEntry('browser_language', 'zh-CN'),
    const MapEntry('browser_platform', 'Win32'),
    const MapEntry('browser_name', 'Mozilla'),
    const MapEntry(
      'browser_version',
      '5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36',
    ),
    const MapEntry('browser_online', 'true'),
    const MapEntry('tz_name', 'Asia/Shanghai'),
    const MapEntry(
      'cursor',
      'd-1_u-1_fh-7392091211001140287_t-1721106114633_r-1',
    ),
    MapEntry(
      'internal_ext',
      'internal_src:dim|wss_push_room_id:$internalRoomId|'
          'wss_push_did:$uniqueId|first_req_ms:${now - 12}|'
          'fetch_time:$now|seq:1|wss_info:0-$now-0-0|'
          'wrds_v:7392094459690748497',
    ),
    const MapEntry('host', 'https://live.douyin.com'),
    const MapEntry('aid', '6383'),
    const MapEntry('live_id', '1'),
    const MapEntry('did_rule', '3'),
    const MapEntry('endpoint', 'live_pc'),
    const MapEntry('support_wrds', '1'),
    MapEntry('user_unique_id', uniqueId),
    const MapEntry('im_path', '/webcast/im/fetch/'),
    const MapEntry('identity', 'audience'),
    const MapEntry('need_persist_msg_count', '15'),
    MapEntry('room_id', internalRoomId),
    const MapEntry('heartbeatDuration', '0'),
  ];
  final query = serializeDouyinQuery(params);

  // 与 JS 一致:decodeURIComponent(不解码 +)后再按 SIGN_KEYS 拼接。
  final map = <String, String>{};
  for (final part in query.split('&')) {
    final index = part.indexOf('=');
    if (index < 0) continue;
    map[Uri.decodeComponent(part.substring(0, index))] = Uri.decodeComponent(
      part.substring(index + 1),
    );
  }
  final stub = kDouyinSignKeys.map((key) => '$key=${map[key] ?? ''}').join(',');
  final signature = generateXBogus(
    md5.convert(utf8.encode(stub)).toString(),
    1,
  );
  return '$kDouyinWsHost?$query&signature=$signature';
}

class DouyinDanmakuSession implements DanmakuSession {
  DouyinDanmakuSession(
    this.roomId,
    this._socket, {
    required Duration heartbeatInterval,
  }) {
    _statesController.add(DanmakuSessionState.connecting);
    _subscription = _socket.data.listen(
      _onData,
      onDone: () => _onDisconnected(),
      onError: (Object _) => _onDisconnected(),
    );
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) {
      if (!_closed) _socket.send(encodeDouyinPushFrame(payloadType: 'hb'));
    });
    // 进房立即发一次心跳(pure_live joinRoom 同款),否则服务端可能不推流。
    _socket.send(encodeDouyinPushFrame(payloadType: 'hb'));
    _statesController.add(DanmakuSessionState.connected);
  }

  final String roomId;
  final DanmakuSocket _socket;

  late final StreamSubscription<Object?> _subscription;
  late final Timer _heartbeatTimer;

  final _messagesController = StreamController<DanmakuMessage>.broadcast();
  final _statesController = StreamController<DanmakuSessionState>.broadcast();

  bool _closed = false;

  @override
  Stream<DanmakuMessage> get messages => _messagesController.stream;

  @override
  Stream<DanmakuSessionState> get states => _statesController.stream;

  void _onData(Object? data) {
    if (_closed || data is! List<int>) return;
    final frame = parseDouyinPushFrame(Uint8List.fromList(data));
    final payload = frame.payload;
    if (frame.payloadType == 'hb' || payload == null) return;

    Uint8List body;
    final isGzip =
        frame.encoding.toLowerCase() == 'gzip' ||
        (payload.length >= 2 && payload[0] == 0x1f && payload[1] == 0x8b);
    try {
      body = isGzip ? Uint8List.fromList(gzip.decode(payload)) : payload;
    } on Object {
      return;
    }

    final parsed = parseDouyinResponsePayload(body);
    if (parsed.needAck && parsed.internalExt.isNotEmpty) {
      _socket.send(
        encodeDouyinPushFrame(
          logId: frame.logId,
          payloadType: 'ack',
          payload: Uint8List.fromList(utf8.encode(parsed.internalExt)),
        ),
      );
    }
    for (final chat in parsed.chats) {
      _messagesController.add(
        DanmakuMessage(
          type: DanmakuMessageType.chat,
          roomId: roomId,
          userName: chat.user,
          userId: chat.userId,
          text: chat.text,
          badgeName: chat.badgeName,
          badgeLevel: chat.badgeLevel,
          badgeUrl: chat.badgeUrl,
          badges: chat.badgeLevel > 0
              ? [
                  DanmakuBadge(
                    name: chat.badgeName,
                    level: chat.badgeLevel,
                    url: chat.badgeUrl,
                  ),
                ]
              : const [],
          userLevel: chat.userLevel,
          userLevelIconUrl: chat.userLevelIconUrl,
          sentAt: chat.sentAtMs > 0
              ? DateTime.fromMillisecondsSinceEpoch(chat.sentAtMs)
              : null,
          rawType: 'chat',
          segments: chat.segments,
        ),
      );
    }
  }

  void _onDisconnected() {
    if (_closed) return;
    _statesController.add(DanmakuSessionState.disconnected);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _heartbeatTimer.cancel();
    await _subscription.cancel();
    await _socket.close();
    _statesController.add(DanmakuSessionState.disconnected);
    await _messagesController.close();
    await _statesController.close();
  }
}
