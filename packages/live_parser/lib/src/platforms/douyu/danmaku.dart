/// 斗鱼弹幕:WebSocket + STT 协议(pure_live/SFVideoLive 对齐)。
///
/// 帧格式:`[int32 len][int32 len][int16 689|690][int8 0][int8 0][body][\0]`,
/// len 为 little-endian,值 = 8 + body + 1;服务端 type 为 690。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../../http/danmaku_transport.dart';
import '../../contracts/contracts.dart';
import '../../models/models.dart';

/// 客户端 -> 服务端帧类型码。
const int _clientFrameType = 689;

/// 弹幕代理端口池:单端口可能拒连,重连时轮换。
const List<String> kDouyuDanmakuPorts = ['8501', '8502', '8503', '8504', '8505', '8506'];

/// 客户端应用层心跳间隔。
const Duration kDouyuDanmakuHeartbeat = Duration(seconds: 45);

/// STT 文本 -> 值(对象 / 数组 / 标量),转义还原 `@S` -> `/`、`@A` -> `@`。
/// 顺序与 pure_live 一致:先按 `//` 拆数组,再按 `@=` 键值对解析。
Object? parseDouyuStt(String input) {
  final str = input.endsWith('\x00') ? input.substring(0, input.length - 1) : input;
  if (str.contains('//')) {
    return [
      for (final part in str.split('//'))
        if (part.isNotEmpty) parseDouyuStt(part),
    ];
  }
  if (str.contains('@=')) {
    final result = <String, Object?>{};
    for (final field in str.split('/')) {
      if (field.isEmpty) continue;
      final separator = field.indexOf('@=');
      if (separator <= 0) continue;
      final key = field.substring(0, separator);
      final value = _unescapeStt(field.substring(separator + 2));
      result[key] = parseDouyuStt(value);
    }
    return result;
  }
  return _unescapeStt(str);
}

String _unescapeStt(String str) => str.replaceAll('@S', '/').replaceAll('@A', '@');

/// 应用层消息编码为完整 WebSocket 帧(含尾部 \0)。
Uint8List encodeDouyuFrame(String body) {
  final payload = utf8.encode('$body\x00');
  final buffer = Uint8List(payload.length + 12);
  final view = ByteData.sublistView(buffer);
  final length = payload.length + 8;
  view.setInt32(0, length, Endian.little);
  view.setInt32(4, length, Endian.little);
  view.setInt16(8, _clientFrameType, Endian.little);
  view.setInt16(10, 0, Endian.little);
  buffer.setAll(12, payload);
  return buffer;
}

/// 一个 WebSocket 帧常合并多个 packet:按各 packet 自身长度迭代。
List<String> decodeDouyuPackets(List<int> bytes) {
  final packets = <String>[];
  final data = Uint8List.fromList(bytes);
  var offset = 0;
  while (offset + 12 <= data.length) {
    final fullLength = ByteData.sublistView(data, offset, offset + 4).getUint32(0, Endian.little);
    final bodyLength = fullLength - 9;
    final frameLength = fullLength + 4;
    if (fullLength < 9 || bodyLength < 0 || offset + frameLength > data.length) break;
    packets.add(
      utf8.decode(data.sublist(offset + 12, offset + 12 + bodyLength), allowMalformed: true),
    );
    offset += frameLength;
  }
  return packets;
}

/// 弹幕颜色映射(col 字段),0 为默认色。
int douyuChatColor(int col) => switch (col) {
  1 => 0xff0000,
  2 => 0x1e87f0,
  3 => 0x7ac84b,
  4 => 0xff7f00,
  5 => 0x9b39f4,
  6 => 0xff69b4,
  _ => 0,
};

String _firstBadgeUrl(Map<String, Object?> stt) {
  for (final key in const ['bimg', 'bimgurl', 'badgeimg', 'badge_img']) {
    final value = _sttText(stt[key]).trim();
    if (value.isEmpty) continue;
    return value.startsWith('//') ? 'https:$value' : value;
  }
  return '';
}

String _sttText(Object? raw) {
  if (raw is List) return raw.map(_sttText).join('/');
  return raw?.toString() ?? '';
}

int _packedRgbColor(Object? raw) {
  final value = int.tryParse(raw?.toString().trim() ?? '') ?? 0;
  return value > 0 ? value & 0xffffff : 0;
}

/// STT 整数取值(缺字段/非数字 → 0)。
int _sttInt(Object? raw) => int.tryParse(raw?.toString().trim() ?? '') ?? 0;

class DouyuDanmakuConnector implements DanmakuConnector {
  DouyuDanmakuConnector({DanmakuTransport? transport, this.heartbeatInterval = kDouyuDanmakuHeartbeat})
    : transport = transport ?? const IoDanmakuTransport();

  final DanmakuTransport transport;
  final Duration heartbeatInterval;

  int _portIndex = 0;

  @override
  SiteCapabilities get capabilities => const SiteCapabilities(danmaku: true);

  @override
  Future<DanmakuSession> connect(DanmakuSessionRequest request) async {
    final port = kDouyuDanmakuPorts[_portIndex % kDouyuDanmakuPorts.length];
    _portIndex += 1;
    final socket = await transport.connect(
      Uri.parse('wss://danmuproxy.douyu.com:$port/'),
    );
    return DouyuDanmakuSession(
      request.roomId,
      socket,
      heartbeatInterval: heartbeatInterval,
    );
  }
}

class DouyuDanmakuSession implements DanmakuSession {
  DouyuDanmakuSession(
    this.roomId,
    this._socket, {
    required Duration heartbeatInterval,
  }) {
    _states = _statesController.stream;
    _messages = _messagesController.stream;
    _statesController.add(DanmakuSessionState.connecting);
    _subscription = _socket.data.listen(
      _onData,
      onDone: () => _dispose(DanmakuSessionState.disconnected),
      onError: (Object _) => _dispose(DanmakuSessionState.disconnected),
    );
    _socket.send(encodeDouyuFrame('type@=loginreq/roomid@=$roomId/'));
    _socket.send(encodeDouyuFrame('type@=joingroup/rid@=$roomId/gid@=-9999/'));
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) {
      if (!_closed) _socket.send(encodeDouyuFrame('type@=mrkl/'));
    });
  }

  final String roomId;
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

  void _onData(Object? data) {
    final packets = data is String
        ? [data]
        : decodeDouyuPackets(data! as List<int>);
    for (final packet in packets) {
      final parsed = parseDouyuStt(packet);
      if (parsed is! Map<String, Object?>) continue;
      final type = parsed['type']?.toString() ?? '';
      switch (type) {
        case 'pingreq':
          _socket.send(encodeDouyuFrame('type@=pingresp/'));
        case 'loginres':
          _statesController.add(DanmakuSessionState.connected);
        case 'chatmsg' || 'chatmessage':
          final message = _chatFromStt(parsed);
          if (message != null) _messagesController.add(message);
      }
    }
  }

  DanmakuMessage? _chatFromStt(Map<String, Object?> stt) {
    /// 合并超级留言后,新包以 `dms` 标记可见弹幕;老包仍用 `if=1`。
    if (stt['dms'] == null && stt['if']?.toString() != '1') return null;
    final packetRoomId = stt['rid']?.toString() ?? '';
    if (packetRoomId.isNotEmpty && packetRoomId != roomId) return null;

    final rawTimestamp = int.tryParse(stt['cst']?.toString() ?? '');
    final sentAt = rawTimestamp == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            rawTimestamp > 100000000000 ? rawTimestamp : rawTimestamp * 1000,
          );
    final badgeName =
        (stt['bnn'] ?? stt['bn'] ?? '').toString().trim();
    // 粉丝牌等级:`bl` 与 `fl` 在真实抓包里同值(房间 252140 样本 25/25、26/26),
    // `fl` 只在 `bl` 缺失或为 0 时兜底,不改已有语义。
    final blLevel = _sttInt(stt['bl'] ?? stt['bnnl']);
    final badgeLevel = blLevel > 0 ? blLevel : _sttInt(stt['fl']);
    final badgeUrl = _firstBadgeUrl(stt);
    final badgeColor = _packedRgbColor(stt['bc']);
    // 粉丝牌资源字段:`brid` = 粉丝牌所属房间号，`hc` = 徽章校验码(32 位 hex)。
    // **只入库、不做显隐闸门**：「跨房粉丝团牌不显示」尚无官网证据，属产品
    // 口径待定；启用前保持零行为变化。
    final badgeRoomId = int.tryParse(stt['brid']?.toString().trim() ?? '') ?? 0;
    final badgeCheckCode = stt['hc']?.toString().trim() ?? '';
    final badge = badgeName.isNotEmpty && badgeLevel > 0
        ? DanmakuBadge(
            name: badgeName,
            level: badgeLevel,
            color: badgeColor,
            url: badgeUrl,
            badgeRoomId: badgeRoomId,
            badgeCheckCode: badgeCheckCode,
          )
        : null;
    // 官网聊天行的 4 类徽章:LV / 粉丝牌 / 至尊大钻石 / 贵族(+超粉、钻粉两个
    // 身份标记)。字段名取自官网 `live-next-player-aside` 的用户归一函数:
    //   ne→nobleLevel、sl+sid→supremeLevel/supremeSid、sahf→superFan、
    //   diaf/cdiaf→diamondFan、diafid→diamondIconId。
    // 顺序 = 官网聊天行从左到右(粉丝牌 → 至尊 → 贵族 → 超粉 → 钻粉),
    // 展示层按 kind 分档渲染(见 side_panel/chat_badges.dart 斗鱼分支)。
    final nobleLevel = _sttInt(stt['ne']);
    final supremeLevel = _sttInt(stt['sl']);
    final supremeSid = _sttInt(stt['sid']);
    final superFan = _sttInt(stt['sahf']) > 0;
    // `cdiaf` 是 `diaf` 的同义冗余字段(样本里同时下发同值),任一为 1 即可。
    final diamondFan = _sttInt(stt['diaf']) > 0 || _sttInt(stt['cdiaf']) > 0;
    final diamondIconId = _sttInt(stt['diafid']);
    return DanmakuMessage(
      type: DanmakuMessageType.chat,
      roomId: roomId,
      color: douyuChatColor(int.tryParse(stt['col']?.toString() ?? '') ?? 0),
      userName: stt['nn']?.toString() ?? '',
      userId: stt['uid']?.toString() ?? '',
      text: stt['txt']?.toString() ?? '',
      badgeName: badgeName,
      badgeLevel: badgeLevel,
      badgeUrl: badgeUrl,
      badges: [
        ?badge,
        if (supremeLevel > 0)
          DanmakuBadge(name: '至尊大钻石', level: supremeLevel, kind: 'supreme'),
        if (nobleLevel > 0)
          DanmakuBadge(name: '贵族', level: nobleLevel, kind: 'noble'),
        // 超粉/钻粉是**身份标记**而非等级，level 恒 0（UI 只看 kind 分档）。
        if (superFan)
          const DanmakuBadge(name: '超粉', level: 0, kind: 'superfan'),
        if (diamondFan)
          const DanmakuBadge(name: '钻粉', level: 0, kind: 'diamondfan'),
      ],
      userLevel: int.tryParse(
            (stt['level'] ?? stt['lv'] ?? '').toString(),
          ) ??
          0,
      nobleLevel: nobleLevel,
      supremeLevel: supremeLevel,
      supremeSid: supremeSid,
      superFan: superFan,
      diamondFan: diamondFan,
      diamondIconId: diamondIconId,
      sentAt: sentAt,
      rawType: stt['type']?.toString() ?? '',
    );
  }

  void _dispose(DanmakuSessionState state) {
    if (_closed) return;
    _statesController.add(state);
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
