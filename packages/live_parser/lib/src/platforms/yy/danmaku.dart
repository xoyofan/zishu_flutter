/// YY 弹幕:纯 Dart 复刻官方 Web trident 协议(参考 SFVideoLive
/// `services/streaming-server/src/danmaku/yy-stream.ts`,2026-09-04 逆向)。
///
/// 流程:
/// 1. 连 `wss://h5-sinchl.yy.com/websocket?appid=yymwebh5&version=3.2.10&uuid=<uuid>`;
/// 2. 发常量登录帧 778244(SDK 硬编码,跨会话逐字节相同);
/// 3. 收 778500(Xo/No 信封)取出 uid/passport/cookie/ticket;
/// 4. 构造注册帧 775684 回发,收 775940 表示注册成功;
/// 5. 按官方模板重放订阅帧(字节替换 模板uid/模板sid),之后每 5s 心跳 794116;
/// 6. 弹幕在 512011/内层 80216 帧,含 marker `58520400`,其后为 u16 长度前缀
///    UTF-8 串流:频道名、文本、昵称;贵族勋章走无 marker 的资料帧按昵称缓存。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../../contracts/contracts.dart';
import '../../http/danmaku_transport.dart';
import '../../models/models.dart';
import 'subscribe_templates.dart';

/// 帧头第 3 字段恒为 200。
const int kYyFrameHeader = 200;

const int kYyUriLogin = 778244;
const int kYyUriLoginRes = 778500;
const int kYyUriRegister = 775684;
const int kYyUriRegisterRes = 775940;
const int kYyUriHeartbeat = 794116;
const int kYyUriChat = 512011;

/// 弹幕帧内层服务 id。
const int kYyChatInnerId = 80216;

/// 弹幕帧标记 `0x00045258`(LE 字节 `58 52 04 00`)。
const List<int> kYyChatMarker = <int>[0x58, 0x52, 0x04, 0x00];

/// 模板中录制的 游客uid / 房间sid(小端 4 字节),发送前按字节替换。
const List<int> kYyTemplateUid = <int>[0xa1, 0x6d, 0x79, 0x7d]; // 2105109921
const List<int> kYyTemplateSid = <int>[0xd0, 0x6a, 0x45, 0x03]; // 54880976

/// 常量登录帧 778244(78 字节,来自官方客户端抓包)。
const String kYyLoginFrameHex =
    '4e00000004e00b00c80000006e4d00003a0000000000000000001100'
    '42382d39372d35412d31372d41442d3444110042382d39372d35412d31372d41442d3444'
    '00000000080079796d7765626835';

Uint8List? _cachedLoginFrame;

/// 78 字节常量登录帧(惰性解码,进程内复用)。
Uint8List get kYyLoginFrame =>
    _cachedLoginFrame ??= _hexToBytes(kYyLoginFrameHex);

/// YY 协议层错误(登录拒绝、帧结构异常等)。
class YyProtocolException implements Exception {
  const YyProtocolException(this.message);

  final String message;

  @override
  String toString() => 'YyProtocolException: $message';
}

Uint8List _hexToBytes(String hex) {
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

/// 帧:`[u32 len][u32 uri][u16 200][body]`,全部小端。
Uint8List buildYyFrame(int uri, List<int> body) {
  final out = Uint8List(10 + body.length);
  final data = ByteData.sublistView(out);
  data.setUint32(0, out.length, Endian.little);
  data.setUint32(4, uri, Endian.little);
  data.setUint16(8, kYyFrameHeader, Endian.little);
  out.setRange(10, out.length, body);
  return out;
}

Uint8List _u16leBytes(int v) {
  final data = ByteData(2)..setUint16(0, v, Endian.little);
  return data.buffer.asUint8List();
}

Uint8List _u32leBytes(int v) {
  final data = ByteData(4)..setUint32(0, v, Endian.little);
  return data.buffer.asUint8List();
}

Uint8List _u64leBytes(int v) {
  final data = ByteData(8)..setUint64(0, v, Endian.little);
  return data.buffer.asUint8List();
}

/// TL 写入器(对应官方 SDK 的 marshal,全部小端)。
class YyTlWriter {
  final _buffer = BytesBuilder();

  YyTlWriter u8(int v) {
    _buffer.addByte(v & 0xff);
    return this;
  }

  YyTlWriter u16(int v) {
    _buffer.add(_u16leBytes(v));
    return this;
  }

  YyTlWriter u32(int v) {
    _buffer.add(_u32leBytes(v & 0xffffffff));
    return this;
  }

  YyTlWriter u64(int v) {
    _buffer.add(_u64leBytes(v));
    return this;
  }

  /// `pushString`:u16 长度 + latin1 字节(YY 登录/注册帧仅 ASCII 字段)。
  YyTlWriter str(String s) {
    final bytes = <int>[for (final code in s.codeUnits) code & 0xff];
    u16(bytes.length);
    _buffer.add(bytes);
    return this;
  }

  /// `pushUint8Array`:u16 长度 + 字节。
  YyTlWriter bytesN(List<int> bytes) {
    u16(bytes.length);
    _buffer.add(bytes);
    return this;
  }

  /// `pushUint8Array32`:u32 长度 + 字节。
  YyTlWriter bytes32(List<int> bytes) {
    u32(bytes.length);
    _buffer.add(bytes);
    return this;
  }

  Uint8List done() => _buffer.toBytes();
}

/// TL 读取器。
class YyTlReader {
  YyTlReader(this._bytes, [this.offset = 0]);

  final Uint8List _bytes;
  int offset;

  int u8() => _bytes[offset++];

  int u16() {
    final v = ByteData.sublistView(_bytes).getUint16(offset, Endian.little);
    offset += 2;
    return v;
  }

  int u32() {
    final v = ByteData.sublistView(_bytes).getUint32(offset, Endian.little);
    offset += 4;
    return v;
  }

  int u64() {
    final v = ByteData.sublistView(_bytes).getUint64(offset, Endian.little);
    offset += 8;
    return v;
  }

  Uint8List bytes(int len) {
    final v = _bytes.sublist(offset, offset + len);
    offset += len;
    return v;
  }

  /// u16 长度前缀字符串(latin1)。
  String str() => String.fromCharCodes(bytes(u16()));

  bool get isEmpty => offset >= _bytes.length;
}

/// 778500 登录响应中的会话票据。
class YyLoginTicket {
  const YyLoginTicket({
    required this.resCode,
    required this.uid,
    required this.passport,
    required this.password,
    required this.cookie,
    required this.ticket,
  });

  final int resCode;

  /// 游客会话 uid(注册帧与订阅模板替换用)。
  final int uid;

  /// 会话 id,形如 `2094916962_prereg`。
  final String passport;

  /// 40 位 token。
  final String password;

  /// 服务端签发票据,注册帧原样回传。
  final Uint8List cookie;
  final Uint8List ticket;
}

/// 解析 778500 登录响应:Xo 信封 + No 票据。
YyLoginTicket parseYyLoginRes(List<int> frame) {
  if (frame.length < 14) {
    throw const YyProtocolException('登录响应帧过短');
  }
  final r = YyTlReader(Uint8List.fromList(frame), 10); // 去帧头
  r.str(); // Xo.context
  final xoResCode = r.u32();
  r.u32(); // Xo.ruri(游客登录为 20078)
  final payload = r.bytes(r.u32());
  if (xoResCode != 200 && xoResCode != 0) {
    throw YyProtocolException('登录被拒绝: resCode=$xoResCode');
  }
  final n = YyTlReader(payload);
  n.str(); // No.context
  final resCode = n.u32();
  final uid = n.u32();
  n.u32(); // yyid
  final passport = n.str();
  final password = n.str();
  final cookie = n.bytes(n.u16());
  final ticket = n.bytes(n.u16());
  return YyLoginTicket(
    resCode: resCode,
    uid: uid,
    passport: passport,
    password: password,
    cookie: cookie,
    ticket: ticket,
  );
}

/// 构造 775684 注册帧。
Uint8List buildYyRegister(YyLoginTicket ticket, String uuid) {
  const mac = 'B8-97-5A-17-AD-4D'; // SDK 硬编码常量
  final loginAuthInfo = (YyTlWriter()
        ..str(ticket.passport)
        ..str(ticket.password)
        ..u32(2) // cliType
        ..u32(0) // cliVer
        ..u32(0) // cliLcid
        ..str('yytianlaitv') // from = appName(官方常量)
        ..str(mac)
        ..str('yymwebn_yymwebh5')
        ..u32(0)
        ..u32(0)
        ..u32(0)
        ..u32(0)
        ..str(uuid))
      .done();
  final body = (YyTlWriter()
        ..bytes32(loginAuthInfo)
        ..u32(259) // appid(UDB)
        ..u64(ticket.uid)
        ..u8(0) // bRelogin
        ..bytesN(ticket.ticket)
        ..bytesN(ticket.cookie)
        ..str('259:0') // context "appid:userType"
        ..str('')
        ..str('')
        ..str('')
        ..u8(0)
        ..u32(0)
        ..u32(0)
        ..u32(0xffffffff)
        ..str('')
        ..u32(1)
        ..str('BCIFVer')
        ..str('V2'))
      .done();
  return buildYyFrame(kYyUriRegister, body);
}

/// 心跳帧 794116(跨会话相同)。
Uint8List get kYyHeartbeat =>
    buildYyFrame(kYyUriHeartbeat, (YyTlWriter()..u32(0)).done());

/// 字节级替换模板中的 模板uid/模板sid -> 本会话值,长度不变。
Uint8List patchYyTemplate(String hex, int uid, int sid) {
  final src = _hexToBytes(hex);
  final freshUid = _u32leBytes(uid);
  final freshSid = _u32leBytes(sid);
  final out = Uint8List(src.length);
  var i = 0;
  while (i < src.length) {
    if (i + 4 <= src.length && _matchAt(src, i, kYyTemplateUid)) {
      out.setRange(i, i + 4, freshUid);
      i += 4;
    } else if (i + 4 <= src.length && _matchAt(src, i, kYyTemplateSid)) {
      out.setRange(i, i + 4, freshSid);
      i += 4;
    } else {
      out[i] = src[i];
      i += 1;
    }
  }
  return out;
}

bool _matchAt(Uint8List src, int offset, List<int> pattern) {
  for (var j = 0; j < pattern.length; j++) {
    if (src[offset + j] != pattern[j]) return false;
  }
  return true;
}

/// 一条解析出的 YY 聊天。
class YyChatItem {
  const YyChatItem({required this.user, required this.text});

  final String user;
  final String text;
}

/// 扫帧内 u16 长度前缀的可读字符串(UTF-8),返回串与偏移。
List<({int at, String text})> scanYyStrings(
  List<int> buf, {
  int maxLength = 300,
  bool rejectNumeric = true,
}) {
  final out = <({int at, String text})>[];
  final bytes = buf is Uint8List ? buf : Uint8List.fromList(buf);
  final data = ByteData.sublistView(bytes);
  var o = 0;
  while (o + 2 <= bytes.length) {
    final len = data.getUint16(o, Endian.little);
    if (len >= 2 &&
        len <= maxLength &&
        o + 2 + len <= bytes.length &&
        _isReadableYyString(bytes, o + 2, len, rejectNumeric)) {
      out.add((
        at: o,
        text: utf8.decode(bytes.sublist(o + 2, o + 2 + len), allowMalformed: true),
      ));
      o += 2 + len;
      continue;
    }
    o += 1;
  }
  return out;
}

bool _isReadableYyString(Uint8List bytes, int start, int len, bool rejectNumeric) {
  final text = utf8.decode(bytes.sublist(start, start + len), allowMalformed: true);
  final readable = RegExp(
    r'^[\x20-\x7e一-龥龥＀-￯　-〿ограм∀-➿♪•·，！？。、【】]+$',
  ).hasMatch(text);
  if (!readable) return false;
  if (rejectNumeric && RegExp(r'^[0-9.:\-/]+$').hasMatch(text)) return false;
  return true;
}

/// 解析弹幕帧(512011/80216 + marker);非弹幕帧返回 null。
YyChatItem? parseYyChatFrame(List<int> buf) {
  if (buf.length < 40) return null;
  final data = ByteData.sublistView(
    buf is Uint8List ? buf : Uint8List.fromList(buf),
  );
  if (data.getUint32(4, Endian.little) != kYyUriChat) return null;
  if (data.getUint32(12, Endian.little) != kYyChatInnerId) return null;
  if (!_containsMarker(buf, 20)) return null;

  final strings =
      scanYyStrings(buf, maxLength: 120).map((t) => t.text).toList();
  if (strings.length < 2) return null;
  final channel = strings[0];
  final text = strings[1];
  if (text == channel) return null;
  var user = 'YY用户';
  for (final s in strings.skip(2).take(3)) {
    if (s.length >= 2 &&
        s.length <= 20 &&
        !RegExp(r'^[0-9]+$').hasMatch(s) &&
        s != 'yy' &&
        s != text &&
        s != channel) {
      user = s;
      break;
    }
  }
  return YyChatItem(user: user, text: text);
}

bool _containsMarker(List<int> buf, int from) {
  for (var i = from; i + kYyChatMarker.length <= buf.length; i++) {
    var hit = true;
    for (var j = 0; j < kYyChatMarker.length; j++) {
      if (buf[i + j] != kYyChatMarker[j]) {
        hit = false;
        break;
      }
    }
    if (hit) return true;
  }
  return false;
}

/// 贵族勋章缓存:无 marker 的 80216 资料帧按昵称积累 chat 可命中的图标 URL。
///
/// 资料帧两类(2026-09-06 协议实测):
/// 1. 键值批量帧:`"nick"→昵称`、`"medal"→pcMedal JSON(含 16px 勋章图标)` 等;
/// 2. 贡献榜帧(位置式):`pcMedal JSON` 之后首个非 URL 串是昵称。
class YyMedalCache {
  YyMedalCache({this.maxEntries = 3000});

  final int maxEntries;
  final Map<String, String> _medals = <String, String>{};

  static const _reservedKeys = <String>{
    'nick',
    'uid',
    'medal',
    'logo',
    'nobleType',
    'nobleClub',
    'clubSwitch',
    'msg',
    'unicast',
  };

  /// 资料帧识别:有 marker 是单条弹幕;无 marker 按形态分流进缓存。
  void rememberUserInfoFrame(List<int> buf) {
    if (buf.length < 16) return;
    final data = ByteData.sublistView(
      buf is Uint8List ? buf : Uint8List.fromList(buf),
    );
    if (data.getUint32(12, Endian.little) != kYyChatInnerId) return;
    if (_containsMarker(buf, 20)) return;
    final tokens = scanYyStrings(buf).map((t) => t.text).toList();
    if (tokens.contains('nick')) {
      _rememberBatch(tokens);
    } else if (tokens.any((t) => t.startsWith('{"pcMedal"'))) {
      _rememberRank(tokens);
    }
  }

  String medalFor(String nick) => _medals[nick.trim()] ?? '';

  void _rememberBatch(List<String> tokens) {
    for (var i = 0; i < tokens.length; i++) {
      if (tokens[i] != 'nick') continue;
      final nick = tokens[i + 1];
      if (nick.isEmpty || _reservedKeys.contains(nick)) continue;
      for (var j = i + 2; j < _min(i + 9, tokens.length); j++) {
        if (tokens[j] == 'medal' &&
            j + 1 < tokens.length &&
            tokens[j + 1].startsWith('{"pcMedal"')) {
          _remember(nick, tokens[j + 1]);
          break;
        }
      }
    }
  }

  void _rememberRank(List<String> tokens) {
    for (var i = 0; i < tokens.length; i++) {
      if (!tokens[i].startsWith('{"pcMedal"')) continue;
      for (var j = i + 1; j < _min(i + 5, tokens.length); j++) {
        final t = tokens[j];
        if (t.startsWith('http') || _reservedKeys.contains(t)) continue;
        _remember(t, tokens[i]);
        break;
      }
    }
  }

  void _remember(String nick, String medalJson) {
    final key = nick.trim();
    if (key.isEmpty || _medals.containsKey(key)) return;
    final url = _extractMedalUrl(medalJson);
    if (url.isEmpty) return;
    if (_medals.length >= maxEntries) _medals.clear();
    _medals[key] = url;
  }

  String _extractMedalUrl(String json) {
    final match = RegExp(r'"url"\s*:\s*"([^"]+)"').firstMatch(json);
    return match?.group(1)?.trim() ?? '';
  }
}

int _min(int a, int b) => a < b ? a : b;

/// YY 弹幕连接器:trident 协议,游客可收弹幕。
class YyDanmakuConnector implements DanmakuConnector {
  YyDanmakuConnector({
    DanmakuTransport? transport,
    this.sidResolver,
    this.heartbeatInterval = const Duration(seconds: 5),
    this.subscribeStagger = const Duration(milliseconds: 200),
    this.chatDedupeWindow = const Duration(seconds: 3),
    YyMedalCache? medalCache,
  })  : transport = transport ?? const IoDanmakuTransport(),
        medalCache = medalCache ?? YyMedalCache();

  final DanmakuTransport transport;
  final Duration heartbeatInterval;

  /// 订阅模板逐条发送的间隔(官方客户端 200ms;测试可置零)。
  final Duration subscribeStagger;

  /// 同文本弹幕的双内层帧去重窗口。
  final Duration chatDedupeWindow;

  final Future<int> Function(String roomId)? sidResolver;
  final YyMedalCache medalCache;

  @override
  SiteCapabilities get capabilities => const SiteCapabilities(danmaku: true);

  @override
  Future<DanmakuSession> connect(DanmakuSessionRequest request) async {
    final uuid = _randomUuid();
    final socket = await transport.connect(
      Uri.parse(
        'wss://h5-sinchl.yy.com/websocket'
        '?appid=yymwebh5&version=3.2.10&uuid=$uuid',
      ),
      headers: const {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
            'AppleWebKit/537.36 (KHTML, like Gecko) '
            'Chrome/131.0.0.0 Safari/537.36',
        'Origin': 'https://www.yy.com',
      },
    );

    // sid:官方 H5 走房间详情(topSid),简单房间 roomId 即 sid;失败回退 roomId。
    var sid = int.tryParse(request.roomId) ?? 0;
    final resolver = sidResolver;
    if (resolver != null) {
      try {
        sid = await resolver(request.roomId);
      } catch (_) {
        // 详情失败时保留 roomId 回退值。
      }
    }

    return YyDanmakuSession(
      socket,
      roomId: request.roomId,
      sid: sid,
      uuid: uuid,
      heartbeatInterval: heartbeatInterval,
      subscribeStagger: subscribeStagger,
      chatDedupeWindow: chatDedupeWindow,
      medalCache: medalCache,
    );
  }
}

String _randomUuid() {
  final now = DateTime.now().microsecondsSinceEpoch;
  final rand = now ^ (now * 2654435761 & 0xffffffff);
  final hex = rand.toRadixString(16).padLeft(8, '0');
  return '$hex-$hex-4${hex.substring(1)}-8${hex.substring(1)}-$hex$hex';
}

/// 一场已建立的 YY 弹幕会话。
class YyDanmakuSession implements DanmakuSession {
  YyDanmakuSession(
    this._socket, {
    required this.roomId,
    required this.sid,
    required this.uuid,
    required this.heartbeatInterval,
    required this.subscribeStagger,
    required this.chatDedupeWindow,
    required this.medalCache,
  }) {
    _states = _statesController.stream;
    _messages = _messagesController.stream;
    _statesController.add(DanmakuSessionState.connecting);
    _subscription = _socket.data.listen(
      _onData,
      onDone: () => _dispose(DanmakuSessionState.disconnected),
      onError: (Object _) => _dispose(DanmakuSessionState.disconnected),
    );
    _socket.send(kYyLoginFrame);
  }

  final String roomId;
  final int sid;
  final String uuid;
  final Duration heartbeatInterval;
  final Duration subscribeStagger;
  final Duration chatDedupeWindow;
  final YyMedalCache medalCache;

  final DanmakuSocket _socket;
  late final Stream<DanmakuMessage> _messages;
  late final Stream<DanmakuSessionState> _states;
  late final StreamSubscription<Object?> _subscription;
  Timer? _heartbeatTimer;
  final List<Timer> _subscribeTimers = <Timer>[];

  final _messagesController = StreamController<DanmakuMessage>.broadcast();
  final _statesController = StreamController<DanmakuSessionState>.broadcast();

  YyLoginTicket? _ticket;
  bool _registered = false;
  bool _closed = false;
  String _lastText = '';
  DateTime _lastTextAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _seq = 0;

  /// 注册帧已收到 775940 回执(订阅与心跳已启动)。
  bool get isRegistered => _registered;

  @override
  Stream<DanmakuMessage> get messages => _messages;

  @override
  Stream<DanmakuSessionState> get states => _states;

  void _onData(Object? data) {
    if (data is! List<int> || _closed) return;
    final bytes = data is Uint8List ? data : Uint8List.fromList(data);
    if (bytes.length < 8) return;
    final uri = ByteData.sublistView(bytes).getUint32(4, Endian.little);

    switch (uri) {
      case kYyUriLoginRes:
        if (_registered) return;
        try {
          _ticket = parseYyLoginRes(bytes);
        } on YyProtocolException {
          _dispose(DanmakuSessionState.disconnected);
          return;
        }
        _socket.send(buildYyRegister(_ticket!, uuid));
        _registered = true;
      case kYyUriRegisterRes:
        if (!_registered) return;
        _sendSubscribes();
        _heartbeatTimer = Timer.periodic(
          heartbeatInterval,
          (_) {
            if (!_closed) _socket.send(kYyHeartbeat);
          },
        );
        _statesController.add(DanmakuSessionState.connected);
      case kYyUriChat:
        medalCache.rememberUserInfoFrame(bytes);
        final item = parseYyChatFrame(bytes);
        if (item == null) return;
        final now = DateTime.now();
        if (item.text == _lastText &&
            now.difference(_lastTextAt) < chatDedupeWindow) {
          return;
        }
        _lastText = item.text;
        _lastTextAt = now;
        _seq += 1;
        final medalUrl = medalCache.medalFor(item.user);
        _messagesController.add(
          DanmakuMessage(
            type: DanmakuMessageType.chat,
            roomId: roomId,
            userName: item.user,
            userId: '',
            text: item.text,
            color: 0xFFFFFF,
            badgeUrl: medalUrl,
            badgeName: medalUrl.isEmpty ? '' : '贵族',
            badgeLevel: medalUrl.isEmpty ? 0 : 1,
            id: 'yy-$_seq',
            sentAt: now,
            rawType: uri.toString(),
          ),
        );
    }
  }

  void _sendSubscribes() {
    final ticket = _ticket;
    if (ticket == null) return;
    for (var i = 0; i < kYySubscribeTemplates.length; i++) {
      final delay = subscribeStagger * i;
      final frame = patchYyTemplate(
        kYySubscribeTemplates[i],
        ticket.uid,
        sid,
      );
      if (delay == Duration.zero) {
        if (!_closed) _socket.send(frame);
      } else {
        _subscribeTimers.add(
          Timer(delay, () {
            if (!_closed) _socket.send(frame);
          }),
        );
      }
    }
  }

  void _dispose(DanmakuSessionState state) {
    if (_closed) return;
    _closed = true;
    _heartbeatTimer?.cancel();
    for (final timer in _subscribeTimers) {
      timer.cancel();
    }
    _statesController.add(state);
    _statesController.close();
    _messagesController.close();
  }

  @override
  Future<void> close() async {
    if (!_closed) _dispose(DanmakuSessionState.disconnected);
    await _subscription.cancel();
    await _socket.close();
  }
}
