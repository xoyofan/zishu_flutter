/// SOOP 弹幕:自有文本协议 WebSocket。
///
/// 帧以 `ESC TAB`(`\x1b\x09`)开头:4 位 opcode + 6 位 size + 字段(`\x0c`
/// 分隔);连接后先发 connect 包,200ms 后发 join 包,之后每 20s 发一次
/// 心跳。接收侧只放行 0005 聊天帧(opcode 白名单,对齐 web 768f8cd)。
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

/// WS 握手头:上游按平台 Origin/UA 校验(SFVideo soop-danmaku-relay.ts:6-8)。
const Map<String, String> kSoopChatHandshakeHeaders = {
  'Origin': 'https://play.sooplive.co.kr',
  'Referer': 'https://play.sooplive.co.kr/',
  'User-Agent':
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36',
};

/// 聊天 opcode：0005 是普通文字，0109(SVC_OGQ_EMOTICON) 是独立表情帧。
const String kSoopChatOpcode = '0005';
const String kSoopOgqEmoticonOpcode = '0109';

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

    // ws 优先、wss 兜底:真机实测(2026-09-03, web resolve/soop/index.ts)
    // ws://…:9000 可正常握手,wss://…:9000 在多数网络出口直接超时。
    //
    // 上游会按出口节点下发聊天集群域名,且旧域名 `chat.sooplive.co.kr` 已
    // NXDOMAIN 下线(2026-09-19 实测:先拿到旧域全超时,重取 API 后拿到
    // `chat-XXXX.sooplive.com:9000` 动态域 101 握手成功)。因此两轮候选全
    // 失败后重取一次 player_live_api,用新集群域名再试一轮。
    Object? lastError;
    for (var round = 0; round < 2; round++) {
      var attemptDetail = detail;
      if (round == 1) {
        final fresh = parseSoopRoomDetail(
          await fetchSoopPlayerApi(_http, roomId),
          roomId,
        );
        if (!fresh.hasChat) break;
        attemptDetail = fresh;
      }
      for (final scheme in const ['ws', 'wss']) {
        final uri = Uri.parse(
          '$scheme://${attemptDetail.chatDomain}:${attemptDetail.chatPort}'
          '/Websocket/$roomId',
        );
        try {
          final socket = await transport.connect(
            uri,
            protocols: const ['chat'],
            headers: kSoopChatHandshakeHeaders,
          );
          return SoopDanmakuSession(
            roomId,
            attemptDetail.chatNo,
            socket,
            heartbeatInterval: heartbeatInterval,
          );
        } catch (error) {
          lastError = error;
        }
      }
    }
    throw ParserHttpException('SOOP 弹幕连接失败(ws/wss 两轮候选均不可达): $lastError');
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
    _send(
      '${_escape}000100000600$_separator$_separator${_separator}16$_separator',
    );
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
    // packet = ESC+TAB + 4 位 opcode + 6 位 size + 字段(0x0c 分隔);一条
    // WS 消息可能拼接多个包。opcode 白名单门控:非 0005 的系统帧一律丢弃
    // (0001/0002 握手 ACK、0004 观众列表、0127 粉丝勋章),否则会被当成
    // 无意义弹幕刷屏(web 768f8cd 同款语义)。
    final text = utf8.decode(data, allowMalformed: true);
    for (final packet in text.split(_escape)) {
      if (packet.length < 4) continue;
      final opcode = packet.substring(0, 4);
      if (opcode != kSoopChatOpcode && opcode != kSoopOgqEmoticonOpcode) {
        continue;
      }
      final parts = packet.split(_separator);
      if (opcode == kSoopOgqEmoticonOpcode) {
        _emitOgqEmoticon(parts);
        continue;
      }
      // 普通聊天帧:字段足够、第二字段不是控制码、且不含「|」分隔的批量行。
      if (parts.length <= 6) continue;
      final comment = parts[1].trim();
      final user = parts[6].trim();
      if (comment.isEmpty ||
          user.isEmpty ||
          comment == '-1' ||
          comment == '1' ||
          comment.contains('|')) {
        continue;
      }
      final badges = _soopBadges(
        parts.length > 7 ? parts[7] : '',
        parts.length > 8 ? parts[8] : '',
        roomId,
      );
      _messagesController.add(
        DanmakuMessage(
          type: DanmakuMessageType.chat,
          roomId: roomId,
          userName: user,
          userId: '',
          text: comment,
          color: _soopChatColor(parts.length > 9 ? parts[9] : ''),
          badgeName: badges.isEmpty ? '' : badges.first.name,
          badgeLevel: badges.isEmpty ? 0 : badges.first.level,
          badgeKind: badges.isEmpty ? '' : badges.first.kind,
          badgeUrl: badges.isEmpty ? '' : badges.first.url,
          badges: badges,
          rawType: 'chat',
        ),
      );
    }
  }

  void _emitOgqEmoticon(List<String> parts) {
    if (parts.length <= 13) return;
    final message = parts[1].trim();
    final groupId = parts[2].trim();
    final subId = parts[3].trim();
    final version = parts[4].trim();
    final userId = parts[5].trim();
    final user = parts[6].trim();
    final flag = parts[7].trim();
    final extension = parts[11].trim().isEmpty
        ? 'png'
        : parts[11].trim();
    final months = parts[12].trim();
    final animated = parts.length > 17 && parts[17].trim() == '1';
    if (message.isEmpty || groupId.isEmpty || subId.isEmpty || user.isEmpty) {
      return;
    }
    final imageUrl = soopOgqEmoticonUrl(
      groupId: groupId,
      subId: subId,
      version: version,
      extension: animated ? 'webp' : extension,
    );
    if (imageUrl.isEmpty) return;
    final segments = <DanmakuSegment>[];
    if (message.isNotEmpty) segments.add(DanmakuSegment.text(message));
    segments.add(DanmakuSegment.emoji(text: '[OGQ表情]', url: imageUrl));
    final badges = _soopBadges(flag, months, roomId);
    _messagesController.add(
      DanmakuMessage(
        type: DanmakuMessageType.chat,
        roomId: roomId,
        userName: user,
        userId: userId,
        text: message.isEmpty ? '[OGQ表情]' : message,
        segments: segments,
        color: _soopChatColor(parts.length > 8 ? parts[8] : ''),
        badgeName: badges.isEmpty ? '' : badges.first.name,
        badgeLevel: badges.isEmpty ? 0 : badges.first.level,
        badgeKind: badges.isEmpty ? '' : badges.first.kind,
        badgeUrl: badges.isEmpty ? '' : badges.first.url,
        badges: badges,
        rawType: 'soop:ogq_emoticon',
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

/// SOOP 0005 的 flag1 位域:粉丝团、管理员、铁粉、订阅。
const int _soopFlagFanclub = 32;
const int _soopFlagManager = 256;
const int _soopFlagTopfan = 32768;
const int _soopFlagSubscriber = 268435456;

List<DanmakuBadge> _soopBadges(
  String flagRaw,
  String monthsRaw,
  String roomId,
) {
  final flag = int.tryParse(flagRaw.split('|').first.trim()) ?? 0;
  final months = int.tryParse(monthsRaw.trim()) ?? 0;
  final result = <DanmakuBadge>[];
  if ((flag & _soopFlagSubscriber) != 0 || months > 0) {
    final lv = months > 0 ? months : 1;
    result.add(
      DanmakuBadge(
        name: '$lv',
        level: lv,
        color: 0xEF565F,
        kind: 'subscriber',
        url: soopSubscriberBadgeUrl(roomId, lv),
      ),
    );
  }
  if ((flag & _soopFlagManager) != 0) {
    result.add(
      const DanmakuBadge(name: 'M', level: 1, color: 0x53B1AE, kind: 'manager'),
    );
  }
  if ((flag & _soopFlagTopfan) != 0) {
    result.add(
      const DanmakuBadge(name: 'T', level: 1, color: 0xD65B8F, kind: 'topfan'),
    );
  }
  if ((flag & _soopFlagFanclub) != 0) {
    result.add(
      const DanmakuBadge(name: 'F', level: 1, color: 0x75AA5C, kind: 'fanclub'),
    );
  }
  return result;
}

String soopSubscriberBadgeUrl(String roomId, int months) {
  if (roomId.isEmpty) return '';
  final suffix = months >= 24
      ? '_24'
      : months >= 12
      ? '_12'
      : months >= 6
      ? '_6'
      : '';
  return 'https://static.file.sooplive.com/spcon/pc_$roomId$suffix.png';
}

String soopOgqEmoticonUrl({
  required String groupId,
  required String subId,
  required String version,
  required String extension,
}) {
  if (groupId.isEmpty || subId.isEmpty) return '';
  final cleanExtension = extension.isEmpty ? 'png' : extension.toLowerCase();
  return 'https://ogq-sticker-global-cdn-z01.afreecatv.com/'
      'sticker/$groupId/${subId}_160.$cleanExtension?v=$version';
}

/// SOOP 文字色字段(parts[9],十进制 RGB 整数):空/非法按 UI 默认色(0);
/// -1 等 32 位补码值按低 24 位截断(web colorFromPackedInt 同构,-1 → 白色)。
int _soopChatColor(String raw) {
  final value = int.tryParse(raw.trim());
  if (value == null) return 0;
  return value & 0xFFFFFF;
}
