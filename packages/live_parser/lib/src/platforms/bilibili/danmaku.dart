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
    var badgeColorStart = 0;
    var badgeColorEnd = 0;
    var badgeColorBorder = 0;
    var badgeTextColor = 0;
    var badgeColorLevel = 0;
    var badgeIconUrl = '';
    var userLevelIconUrl = '';
    var guardLevel = 0;
    final metaUser = meta.length > 15 ? jsonMapOf(meta[15]) : null;
    final newUser = jsonMapOf(jsonMapOf(metaUser)['user']);
    final newMedal = newUser['medal'];
    final wealth = jsonMapOf(newUser['wealth']);
    // 消息 id:info[0][15].extra JSON 的 id_str(web bilibiliMeta.ts:274-290),
    // 用于协议重推去重;缺失回落「用户+正文」key。
    var danmakuId = '';
    if (metaUser != null) {
      final extraText = jsonText(metaUser['extra']);
      if (extraText.isNotEmpty) {
        try {
          final extra = jsonMapOf(jsonDecode(extraText));
          danmakuId = jsonText(extra['id_str']).trim();
        } on FormatException {
          // extra 非 JSON:忽略 id。
        }
      }
    }
    if (newMedal is Map) {
      final medal = jsonMapOf(newMedal);
      badgeName = jsonText(medal['name']);
      badgeLevel = jsonInt(medal['level']);
      // 新协议带 v2_medal_color_*(hex 字符串);UI 端做 bilibiliComposed 渐变
      // (对齐 web ChatFanBadge/buildBilibiliBadgeStyle:to left, start→end);
      // 文字/等级数字色 = v2_medal_color_text/level(web bilibili.ts:121-141)。
      badgeColorStart = _hexColorOf(jsonText(medal['v2_medal_color_start']).isNotEmpty
          ? jsonText(medal['v2_medal_color_start'])
          : jsonText(medal['color_start']));
      badgeColorEnd = _hexColorOf(jsonText(medal['v2_medal_color_end']).isNotEmpty
          ? jsonText(medal['v2_medal_color_end'])
          : jsonText(medal['color_end']));
      badgeColorBorder = _hexColorOf(jsonText(medal['v2_medal_color_border']).isNotEmpty
          ? jsonText(medal['v2_medal_color_border'])
          : jsonText(medal['color_border']));
      badgeTextColor = _hexColorOf(jsonText(medal['v2_medal_color_text']));
      badgeColorLevel = _hexColorOf(jsonText(medal['v2_medal_color_level']));
      badgeIconUrl = jsonText(medal['guard_icon'] ?? medal['honor_icon']).trim();
      guardLevel = _intOf(medal['guard_level']);
    }
    if (wealth['level'] != null && _intOf(wealth['level']) > 0) {
      userLevelIconUrl = _bilibiliWealthIconUrl(wealth);
    }
    if (badgeName.isEmpty && badgeLevel <= 0 && info.length > 3 && info[3] is List) {
      final medal = info[3] as List<Object?>;
      final level = medal.isNotEmpty ? _intOf(medal[0]) : 0;
      final name = medal.length > 1 ? medal[1]?.toString() ?? '' : '';
      // 老结构色值为十进制 int:web 口径 [8]=start/[9]=end/[5]=border。
      if (level > 0 && name.isNotEmpty) {
        badgeLevel = level;
        badgeName = name;
        badgeColorStart = medal.length > 8 ? _intOf(medal[8]) & 0xffffff : 0;
        badgeColorEnd = medal.length > 9 ? _intOf(medal[9]) & 0xffffff : 0;
        badgeColorBorder = medal.length > 5 ? _intOf(medal[5]) & 0xffffff : 0;
        if (guardLevel == 0 && medal.length > 10) {
          guardLevel = _intOf(medal[10]);
        }
      }
    }
    var userLevel = 0;
    if (info.length > 4 && info[4] is List) {
      final ul = info[4] as List<Object?>;
      userLevel = ul.isNotEmpty ? _intOf(ul[0]) : 0;
    }
    if (userLevel == 0 && userLevelIconUrl.isNotEmpty) {
      userLevel = _intOf(wealth['level']);
    }
    if (guardLevel == 0) {
      final rootMedal = jsonMapOf(obj['medal_info']);
      guardLevel = _intOf(rootMedal['guard_level']);
    }
    final fanBadge = badgeName.isNotEmpty && badgeLevel > 0
        ? DanmakuBadge(
            name: badgeName,
            level: badgeLevel,
            iconUrl: badgeIconUrl,
          )
        : null;
    final guard = _bilibiliGuardBadge(guardLevel);

    final segments = _emoteSegments(meta, text0);

    // 协议重推去重(对齐 web bilibiliDanmakuDedup,cap 1200):
    // 优先 id_str,缺失回落「用户+正文」key(web fallback 同款)。
    final dedupKey = danmakuId.isNotEmpty ? danmakuId : '$userName\u0000$text0';
    if (!_chatDedup.allow(dedupKey)) return;

    _messagesController.add(
      DanmakuMessage(
        type: DanmakuMessageType.chat,
        roomId: roomId,
        color: color & 0xffffff,
        userName: userName,
        userId: userId,
        text: text0,
        segments: segments,
        badgeName: badgeName,
        badgeLevel: badgeLevel,
        userLevel: userLevel,
        badgeColorStart: badgeColorStart,
        badgeColorEnd: badgeColorEnd,
        badgeColorBorder: badgeColorBorder,
        badgeTextColor: badgeTextColor,
        badgeColorLevel: badgeColorLevel,
        badges: fanBadge == null ? const [] : [fanBadge],
        guard: guard,
        userLevelIconUrl: userLevelIconUrl,
        id: danmakuId,
        rawType: cmd,
      ),
    );
  }

  static List<DanmakuSegment> _emoteSegments(
    List<Object?> meta,
    String text,
  ) {
    if (text.isEmpty) return const [];
    final candidates = <Object?>[];
    void collect(Object? raw) {
      if (raw is List) {
        candidates.addAll(raw);
      } else if (raw is Map) {
        final nested = raw['emote'];
        if (nested is List) candidates.addAll(nested);
      }
    }

    if (meta.length > 13) collect(meta[13]);
    if (meta.length > 15) collect(meta[15]);

    final urls = <String, String>{};
    for (final candidate in candidates) {
      if (candidate is! Map) continue;
      final url = jsonText(candidate['url']).trim().isNotEmpty
          ? jsonText(candidate['url']).trim()
          : jsonText(candidate['emote_url']).trim();
      final rawName = jsonText(candidate['emoji']).trim().isNotEmpty
          ? jsonText(candidate['emoji']).trim()
          : jsonText(candidate['emoticon']).trim().isNotEmpty
          ? jsonText(candidate['emoticon']).trim()
          : jsonText(candidate['text']).trim();
      final name = rawName.replaceAll(RegExp(r'^\[+|\]+$'), '').trim();
      if (url.isNotEmpty && name.isNotEmpty) urls[name] = url;
    }
    if (urls.isEmpty) return const [];

    final segments = <DanmakuSegment>[];
    final pattern = RegExp(r'\[([^\[\]]+)\]');
    var cursor = 0;
    var hit = false;
    for (final match in pattern.allMatches(text)) {
      if (match.start > cursor) {
        segments.add(DanmakuSegment.text(text.substring(cursor, match.start)));
      }
      final url = urls[match.group(1)];
      if (url != null) {
        hit = true;
        segments.add(
          DanmakuSegment.emoji(
            text: match.group(0)!,
            url: url,
            name: match.group(1)!,
          ),
        );
      } else {
        segments.add(DanmakuSegment.text(match.group(0)!));
      }
      cursor = match.end;
    }
    if (!hit) return const [];
    if (cursor < text.length) {
      segments.add(DanmakuSegment.text(text.substring(cursor)));
    }
    return segments;
  }

  static int _intOf(Object? value) =>
      value is num ? value.toInt() : int.tryParse('${value ?? ''}') ?? 0;

  /// "#RRGGBB" / "RRGGBB" → 0xRRGGBB;解析失败返回 0(= 协议未提供)。
  static int _hexColorOf(String hex) {
    final text = hex.trim().replaceFirst('#', '');
    final value = int.tryParse(text, radix: 16);
    if (value == null) return 0;
    return text.length == 8 ? value & 0xffffff : value;
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

String _bilibiliWealthIconUrl(Map<String, dynamic> wealth) {
  final key = jsonText(wealth['dm_icon_key'] ?? wealth['iconUrl']).trim();
  if (key.isEmpty) return '';
  if (key.startsWith('http://') || key.startsWith('https://')) return key;
  return 'https://i0.hdslb.com/bfs/live-reward/activity/wealth/$key';
}

DanmakuBadge? _bilibiliGuardBadge(int level) => switch (level) {
  1 => const DanmakuBadge(
    name: '总督',
    level: 1,
    color: 0xffe74c3c,
    kind: 'guard',
  ),
  2 => const DanmakuBadge(
    name: '提督',
    level: 2,
    color: 0xff3498db,
    kind: 'guard',
  ),
  3 => const DanmakuBadge(
    name: '舰长',
    level: 3,
    color: 0xfff39c12,
    kind: 'guard',
  ),
  _ => null,
};
