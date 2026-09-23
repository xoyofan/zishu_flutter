/// Twitch 弹幕:公开 IRC 网关(匿名 justinfan,无需登录与 Client-ID)。
///
/// - 端点 `wss://irc-ws.chat.twitch.tv`(443);进房 `JOIN #<login>`。
/// - `CAP REQ :twitch.tv/tags` 换取 color/display-name/emotes 等 IRCv3 标签。
/// - 保活:收到 `PING :tmi.twitch.tv` 回 `PONG :tmi.twitch.tv`;服务端要求
///   重连时下发 `RECONNECT`,按断开处理(由 UI 侧手动重连)。
/// - 只消费 `PRIVMSG` 聊天行;一条 WS 消息可能拼接多行 IRC(CRLF 分隔)。
/// - emotes 标签里的字节区间是**码点(scalar)下标**而非 UTF-16 下标,中文/
///   emoji 文本必须按 runes 切分,否则段错位。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../../contracts/contracts.dart';
import '../../http/danmaku_transport.dart';
import '../../http/parser_http.dart';
import '../../models/models.dart';
import 'normalize.dart';

/// Twitch 弹幕网关地址(公开 IRC,匿名可读)。
const String kTwitchIrcUrl = 'wss://irc-ws.chat.twitch.tv';

/// 表情图 CDN 模板([emotes] 标签只给 id,名字可从原文区间取)。
const String kTwitchEmoteUrlTemplate =
    'https://static-cdn.jtvnw.net/emoticons/v2/{id}/default/dark/1.0';

class TwitchDanmakuConnector implements DanmakuConnector {
  TwitchDanmakuConnector({DanmakuTransport? transport})
    : transport = transport ?? const IoDanmakuTransport();

  final DanmakuTransport transport;

  @override
  SiteCapabilities get capabilities => const SiteCapabilities(danmaku: true);

  @override
  Future<DanmakuSession> connect(DanmakuSessionRequest request) async {
    final login = normalizeTwitchLogin(request.roomId);
    if (login.isEmpty) {
      throw ParserHttpException('无法识别的 Twitch 频道');
    }
    // sendAsText:IRC 行必须以 TEXT 帧发送 —— Twitch tmi 网关收到 BINARY
    // 帧直接断连(2026-09-20 探针实证:同链路 TEXT 帧收完整注册流程,
    // BINARY 帧 101 后 ~250ms 被掐零消息,表现即「连接成功但零弹幕」)。
    final socket = await transport.connect(
      Uri.parse(kTwitchIrcUrl),
      sendAsText: true,
    );
    return TwitchDanmakuSession(login, socket);
  }
}

class TwitchDanmakuSession implements DanmakuSession {
  TwitchDanmakuSession(this.channel, this._socket) {
    _statesController.add(DanmakuSessionState.connecting);
    _subscription = _socket.data.listen(
      _onData,
      onDone: () => _onDisconnected(DanmakuSessionState.disconnected),
      onError: (Object _) => _onDisconnected(DanmakuSessionState.disconnected),
    );
    // 匿名登录:justinfan<N> 是 Twitch 约定的只读访客账号;PASS 按社区
    // 惯例带 SCHMOOPIIE 占位(服务端不校验)。
    //
    // **JOIN 必须等收到 001 Welcome 再发**:Twitch 在注册完成前会静默丢弃
    // JOIN(实测连上即发,大热度频道 15s 零消息)。
    _send('CAP REQ :twitch.tv/tags');
    _send('PASS SCHMOOPIIE');
    _send('NICK justinfan${10000 + _random.nextInt(89000)}');
  }

  final String channel;
  final DanmakuSocket _socket;

  final _random = Random();
  bool _joinSent = false;
  late final StreamSubscription<Object?> _subscription;

  final _messagesController = StreamController<DanmakuMessage>.broadcast();
  final _statesController = StreamController<DanmakuSessionState>.broadcast();

  bool _closed = false;

  @override
  Stream<DanmakuMessage> get messages => _messagesController.stream;

  @override
  Stream<DanmakuSessionState> get states => _statesController.stream;

  void _send(String line) => _socket.send(utf8.encode('$line\r\n'));

  void _onData(Object? data) {
    if (_closed) return;
    final String text;
    if (data is String) {
      text = data;
    } else if (data is List<int>) {
      text = utf8.decode(data, allowMalformed: true);
    } else {
      return;
    }
    for (final rawLine in text.split('\r\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('PING')) {
        _send('PONG :tmi.twitch.tv');
        continue;
      }
      // 001 Welcome = 注册完成:此刻发 JOIN 才会被受理,随后视为已连接。
      if (!_joinSent && line.contains(' 001 ')) {
        _joinSent = true;
        _send('JOIN #$channel');
        _statesController.add(DanmakuSessionState.connected);
      }
      final message = _parseIrcLine(line);
      if (message != null) _messagesController.add(message);
    }
  }

  /// 解析一行 IRC;只产出 PRIVMSG 聊天(RECONNECT 在外层按断开处理)。
  DanmakuMessage? _parseIrcLine(String line) {
    var rest = line;
    var tags = const <String, String>{};
    if (rest.startsWith('@')) {
      final space = rest.indexOf(' ');
      if (space < 0) return null;
      tags = _parseTags(rest.substring(1, space));
      rest = rest.substring(space + 1);
    }
    // 服务器/用户前缀(`:tmi.twitch.tv` 或 `nick!user@host`)。
    var prefix = '';
    if (rest.startsWith(':')) {
      final space = rest.indexOf(' ');
      if (space < 0) return null;
      prefix = rest.substring(1, space);
      rest = rest.substring(space + 1);
    }
    if (rest.startsWith('RECONNECT')) {
      // 服务端要求重连:按断开上报,连接由 UI 侧「重新连接弹幕」发起。
      _onDisconnected(DanmakuSessionState.disconnected);
      return null;
    }
    if (!rest.startsWith('PRIVMSG ')) return null;

    // prefix 的 nick 即登录名(小写)。
    final nick = prefix.split('!').first.trim();

    final trailing = rest.substring('PRIVMSG '.length);
    final colon = trailing.indexOf(':');
    final text = colon < 0 ? '' : trailing.substring(colon + 1);
    if (text.isEmpty) return null;

    final displayName = _unescapeTag(tags['display-name'] ?? '');
    final color = _parseColorTag(tags['color'] ?? '');
    final twitchBadges = _parseTwitchBadges(tags['badges'] ?? '');
    return DanmakuMessage(
      type: DanmakuMessageType.chat,
      roomId: channel,
      userName: displayName.isNotEmpty ? displayName : nick,
      userId: nick,
      text: text,
      color: color,
      badges: twitchBadges,
      id: _unescapeTag(tags['id'] ?? ''),
      sentAt: _parseTimestamp(tags['tmi-sent-ts'] ?? ''),
      rawType: 'chat',
      segments: _buildSegments(text, tags['emotes'] ?? ''),
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
    await _subscription.cancel();
    await _socket.close();
    _statesController.add(DanmakuSessionState.disconnected);
    await _messagesController.close();
    await _statesController.close();
  }
}

const _twitchBadgeCdn = <String, String>{
  'broadcaster': '5527c58c-fc70-11e9-841e-784f43822e80',
  'moderator': '32679f86-9526-4b63-b32a-6b9a6a95f55c',
  'subscriber': '5d9f2208-5dd8-11e7-8513-2ff4adfae661',
  'vip': 'b817aba4-fad8-49e2-b88a-7cc744dfa6ec',
  'partner': 'd12a2e27-1c86-4d50-b1a1-655c0462a4ac',
  'staff': '93874e8c-5c6f-46c6-a89c-39f05da653ea',
  'founder': '51ef22f8-5472-411a-909a-4201d55d7425',
  'premium': 'bbbe0db0-a598-423e-86d0-f9fb98ca1933',
  'artist': '87603a06-dc64-468a-8486-02c53b14b978',
};

const _twitchBadgePriority = <String>[
  'broadcaster',
  'staff',
  'partner',
  'founder',
  'vip',
  'moderator',
  'subscriber',
  'premium',
  'artist',
];

List<DanmakuBadge> _parseTwitchBadges(String raw) {
  if (raw.trim().isEmpty) return const [];
  final entries = <({String key, int version})>[];
  for (final item in raw.split(',')) {
    final slash = item.indexOf('/');
    final key = (slash < 0 ? item : item.substring(0, slash)).trim();
    if (!_twitchBadgeCdn.containsKey(key)) continue;
    final version = slash < 0
        ? 1
        : int.tryParse(item.substring(slash + 1).trim()) ?? 1;
    entries.add((key: key, version: version));
  }
  entries.sort(
    (a, b) => _twitchBadgePriority.indexOf(a.key)
        .compareTo(_twitchBadgePriority.indexOf(b.key)),
  );
  if (entries.isEmpty) return const [];
  final first = entries.first;
  return [
    DanmakuBadge(
      name: first.key,
      level: first.version,
      kind: 'twitch',
      url: 'https://static-cdn.jtvnw.net/badges/v1/'
          '${_twitchBadgeCdn[first.key]}/2',
    ),
  ];
}

/// IRCv3 标签串 `k=v;k2=v2` → map;值按 IRC 转义还原。
Map<String, String> _parseTags(String source) {
  final result = <String, String>{};
  for (final pair in source.split(';')) {
    if (pair.isEmpty) continue;
    final eq = pair.indexOf('=');
    if (eq < 0) {
      result[pair] = '';
      continue;
    }
    result[pair.substring(0, eq)] = _unescapeTag(pair.substring(eq + 1));
  }
  return result;
}

/// IRCv3 值转义:`\:`→`;`、`\s`→空格、`\\`→`\`、`\r`/`\n`→换行。
String _unescapeTag(String value) {
  if (!value.contains(r'\')) return value;
  final buffer = StringBuffer();
  for (var i = 0; i < value.length; i++) {
    final char = value[i];
    if (char != r'\' || i + 1 >= value.length) {
      buffer.write(char);
      continue;
    }
    switch (value[i + 1]) {
      case ':':
        buffer.write(';');
      case 's':
        buffer.write(' ');
      case 'r':
        buffer.write('\r');
      case 'n':
        buffer.write('\n');
      default:
        buffer.write(value[i + 1]);
    }
    i++;
  }
  return buffer.toString();
}

/// `#RRGGBB` → 0xRRGGBB;空/非法按 0(UI 默认色)。
int _parseColorTag(String value) {
  final text = value.trim();
  if (text.length != 7 || !text.startsWith('#')) return 0;
  return int.tryParse(text.substring(1), radix: 16) ?? 0;
}

DateTime? _parseTimestamp(String value) {
  final ms = int.tryParse(value.trim());
  return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
}

/// emotes 标签 → 富文本段。格式 `id:start-end,start-end/id:...`,
/// 区间为码点下标(闭区间),按原文 runes 切分;表情段 text 取原文该区间
/// 的表情名并包成 `[名]` 形态(web TwitchEmoteSegment 同构)。
List<DanmakuSegment> _buildSegments(String text, String emotesTag) {
  if (emotesTag.trim().isEmpty) return const [];
  final runes = text.runes.toList();
  if (runes.isEmpty) return const [];

  final ranges = <(int, int, String)>[];
  for (final group in emotesTag.split('/')) {
    final colon = group.indexOf(':');
    if (colon <= 0) continue;
    final id = group.substring(0, colon).trim();
    if (id.isEmpty) continue;
    for (final part in group.substring(colon + 1).split(',')) {
      final dash = part.indexOf('-');
      if (dash <= 0) continue;
      final start = int.tryParse(part.substring(0, dash).trim());
      final end = int.tryParse(part.substring(dash + 1).trim());
      if (start == null || end == null || start >= end) continue;
      if (end >= runes.length) continue;
      ranges.add((start, end, id));
    }
  }
  if (ranges.isEmpty) return const [];
  ranges.sort((a, b) => a.$1.compareTo(b.$1));

  final segments = <DanmakuSegment>[];
  var cursor = 0;
  for (final (start, end, id) in ranges) {
    if (start < cursor) continue; // 重叠区间丢弃后者,保证顺序不乱
    if (start > cursor) {
      final piece = String.fromCharCodes(runes.sublist(cursor, start));
      if (piece.isNotEmpty) segments.add(DanmakuSegment.text(piece));
    }
    final name = String.fromCharCodes(runes.sublist(start, end + 1));
    segments.add(
      DanmakuSegment.emoji(
        text: '[$name]',
        name: name,
        url: kTwitchEmoteUrlTemplate.replaceAll('{id}', id),
      ),
    );
    cursor = end + 1;
  }
  if (cursor < runes.length) {
    final piece = String.fromCharCodes(runes.sublist(cursor));
    if (piece.isNotEmpty) segments.add(DanmakuSegment.text(piece));
  }
  return segments;
}
