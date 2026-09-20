/// YouTube 弹幕:watch 页取 conversationBar continuation,InnerTube
/// `live_chat/get_live_chat` 轮询增量。
library;

import 'dart:async';
import 'dart:convert';

import '../../contracts/contracts.dart';
import '../../http/parser_http.dart';
import '../../models/models.dart';
import '../douyu/json_utils.dart';
import 'emoji_shortcodes.dart';
import 'normalize.dart';
import 'room_api.dart';

const String _kChatClientVersion = '2.20260904.01.00';

/// 连续失败上限(超过视为直播结束/聊天关闭,停止轮询)。
const int kYoutubeMaxReconnect = 5;

/// continuation -> 原始响应(测试可注入)。
typedef YoutubeChatFetcher = Future<Object?> Function(String continuation);

/// 拉取直播聊天 continuation(无 conversationBar 即未开播/聊天关闭)。
Future<String> fetchYoutubeChatToken(ParserHttp http, String videoId) async {
  try {
    final response = await http.get(
      Uri.parse('https://www.youtube.com/watch?v=$videoId&hl=en'),
      headers: youtubePageHeaders(),
    );
    final data = extractJsonObjectAfter(
      utf8.decode(response.bodyBytes),
      'ytInitialData',
    );
    if (data == null) return '';
    final renderer = _nestedMap(data, const [
      'contents',
      'twoColumnWatchNextResults',
      'conversationBar',
      'liveChatRenderer',
    ]);
    final continuations = jsonListOf(renderer['continuations']);
    if (continuations.isEmpty) return '';
    return jsonText(
      jsonMapOf(jsonMapOf(continuations.first)['reloadContinuationData'])['continuation'],
    );
  } on Object {
    return '';
  }
}

class YoutubeDanmakuConnector implements DanmakuConnector {
  YoutubeDanmakuConnector(
    this._http, {
    this.fetcher,
    this.minimumPollDelay = const Duration(seconds: 2),
  });

  final ParserHttp _http;
  final YoutubeChatFetcher? fetcher;
  final Duration minimumPollDelay;

  @override
  SiteCapabilities get capabilities => const SiteCapabilities(danmaku: true);

  @override
  Future<DanmakuSession> connect(DanmakuSessionRequest request) async {
    final videoId = extractYoutubeVideoId(request.roomId);
    if (videoId == null) {
      throw const ParserHttpException('无效的 YouTube 房间号');
    }
    final token = await fetchYoutubeChatToken(_http, videoId);
    if (token.isEmpty) {
      throw const ParserHttpException('未开播或聊天已关闭');
    }
    final session = YoutubeDanmakuSession(
      videoId,
      token,
      fetcher ?? _fetchChat,
      minimumPollDelay: minimumPollDelay,
    );
    try {
      await session.start();
    } on Object {
      await session.close();
      rethrow;
    }
    return session;
  }

  Future<Object?> _fetchChat(String continuation) async {
    final response = await _http.postJson(
      Uri.parse(
        'https://www.youtube.com/youtubei/v1/live_chat/get_live_chat'
        '?prettyPrint=false',
      ),
      body: {
        'context': {
          'client': {
            'clientName': 'WEB',
            'clientVersion': _kChatClientVersion,
            'hl': 'zh-CN',
          },
        },
        'continuation': continuation,
      },
      headers: const {'User-Agent': kYoutubeUserAgent},
    );
    return _http.jsonMap(response);
  }
}

class YoutubeDanmakuSession implements DanmakuSession {
  YoutubeDanmakuSession(
    this.videoId,
    String initialToken,
    this._fetcher, {
    this.minimumPollDelay = const Duration(seconds: 2),
  }) : _token = initialToken;

  final String videoId;
  final YoutubeChatFetcher _fetcher;
  final Duration minimumPollDelay;

  String _token;
  late final StreamController<DanmakuMessage> _messagesController =
      StreamController<DanmakuMessage>.broadcast(onListen: _flushPending);
  final _statesController = StreamController<DanmakuSessionState>.broadcast();

  /// 首轮轮询可能先于订阅,先入缓冲。
  final List<DanmakuMessage> _pending = [];
  static const int _maxPending = 200;

  final Set<String> _seen = <String>{};
  static const int _maxSeen = 800;

  int _generation = 0;
  int _errorStreak = 0;
  Timer? _timer;
  bool _closed = false;
  bool _connected = false;

  @override
  Stream<DanmakuMessage> get messages => _messagesController.stream;

  @override
  Stream<DanmakuSessionState> get states => _statesController.stream;

  Future<void> start() async {
    _statesController.add(DanmakuSessionState.connecting);
    final generation = ++_generation;
    Object? lastError;
    StackTrace? lastStackTrace;
    for (var attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(
          Duration(milliseconds: attempt == 1 ? 600 : 1400),
        );
      }
      if (_closed || generation != _generation) return;
      try {
        await _pollOnce(generation, propagateFailure: true, firstBatch: true);
        return;
      } catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;
      }
    }
    _connected = false;
    _statesController.add(DanmakuSessionState.disconnected);
    Error.throwWithStackTrace(lastError!, lastStackTrace!);
  }

  Future<void> _pollOnce(
    int generation, {
    bool propagateFailure = false,
    bool firstBatch = false,
  }) async {
    if (_closed || generation != _generation) return;
    try {
      final raw = await _fetcher(_token);
      if (_closed || generation != _generation) return;
      final json = raw is Map ? Map<String, dynamic>.from(raw) : null;
      if (json == null || json['error'] != null) {
        throw StateError('YouTube 聊天请求失败');
      }
      final liveChat = _nestedMap(json, const [
        'continuationContents',
        'liveChatContinuation',
      ]);

      final batch = <DanmakuMessage>[];
      for (final action in jsonListOf(liveChat['actions'])) {
        final item = jsonMapOf(jsonMapOf(action)['addChatItemAction'])['item'];
        final itemMap = jsonMapOf(item);
        final textRenderer = jsonMapOf(
          itemMap['liveChatTextMessageRenderer'],
        );
        final paidRenderer = jsonMapOf(
          itemMap['liveChatPaidMessageRenderer'],
        );
        final renderer = textRenderer.isNotEmpty ? textRenderer : paidRenderer;
        if (renderer.isEmpty) continue;
        final paid = textRenderer.isEmpty;

        final text = _runsToText(jsonMapOf(renderer['message'])['runs']);
        if (text.isEmpty && !paid) continue;
        final id = jsonText(renderer['id']);
        if (id.isNotEmpty && !_seen.add(id)) continue;
        if (_seen.length > _maxSeen) _seen.clear();

        final userName =
            jsonText(jsonMapOf(renderer['authorName'])['simpleText']).trim();
        final amount = jsonText(
          jsonMapOf(renderer['purchaseAmountText'])['simpleText'],
        ).trim();
        final usec = int.tryParse(jsonText(renderer['timestampUsec']));
        batch.add(
          DanmakuMessage(
            type: DanmakuMessageType.chat,
            roomId: videoId,
            userName: userName.isEmpty ? 'YouTube 用户' : userName,
            userId: '',
            text: paid && amount.isNotEmpty ? '$amount $text'.trim() : text,
            color: paid ? 0xffb300 : 0,
            sentAt: usec == null
                ? null
                : DateTime.fromMicrosecondsSinceEpoch(usec),
            rawType: 'chat',
          ),
        );
      }

      final emitted = firstBatch && batch.length > 20
          ? batch.sublist(batch.length - 20)
          : batch;
      for (final message in emitted) {
        _emitMessage(message);
      }

      if (!_connected) {
        _connected = true;
        _statesController.add(DanmakuSessionState.connected);
      }
      _errorStreak = 0;

      final next = _nextContinuation(liveChat);
      if (next == null) {
        _token = '';
        _connected = false;
        _statesController.add(DanmakuSessionState.disconnected);
        return;
      }
      _token = next.token;
      _schedule(generation, next.delay);
    } catch (_) {
      if (_closed || generation != _generation) return;
      if (propagateFailure) rethrow;
      _handleFailure(generation);
    }
  }

  ({String token, Duration delay})? _nextContinuation(
    Map<String, dynamic> liveChat,
  ) {
    final continuations = jsonListOf(liveChat['continuations']);
    if (continuations.isEmpty) return null;
    final first = jsonMapOf(continuations.first);
    final data =
        jsonMapOf(first['invalidationContinuationData']).isNotEmpty
        ? jsonMapOf(first['invalidationContinuationData'])
        : jsonMapOf(first['timedContinuationData']);
    final token = jsonText(data['continuation']);
    if (token.isEmpty) return null;
    final timeoutMs = jsonInt(data['timeoutMs']);
    final clamped = timeoutMs.clamp(2000, 15000);
    final delay = Duration(milliseconds: clamped);
    return (
      token: token,
      delay: delay < minimumPollDelay ? minimumPollDelay : delay,
    );
  }

  void _emitMessage(DanmakuMessage message) {
    if (_messagesController.hasListener) {
      _messagesController.add(message);
    } else if (_pending.length < _maxPending) {
      _pending.add(message);
    }
  }

  void _flushPending() {
    if (_pending.isEmpty) return;
    for (final message in _pending) {
      _messagesController.add(message);
    }
    _pending.clear();
  }

  void _handleFailure(int generation) {
    _errorStreak += 1;
    if (_connected) {
      _connected = false;
      _statesController.add(DanmakuSessionState.disconnected);
    }
    if (_errorStreak >= kYoutubeMaxReconnect) return;
    final seconds = 1 << (_errorStreak - 1).clamp(0, 4);
    _schedule(generation, Duration(seconds: seconds));
  }

  void _schedule(int generation, Duration delay) {
    if (_closed || generation != _generation) return;
    _timer?.cancel();
    _timer = Timer(delay, () {
      _timer = null;
      if (!_closed && generation == _generation) {
        unawaited(_pollOnce(generation));
      }
    });
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _generation++;
    _timer?.cancel();
    _timer = null;
    _pending.clear();
    _statesController.add(DanmakuSessionState.disconnected);
    await _messagesController.close();
    await _statesController.close();
  }
}

/// runs → 纯文本。emoji run(协议表情)不显示原始短代码占位:
/// - `emojiId` 已是 Unicode(标准 emoji 多数形态)→ 直接采用;
/// - 否则取首个 shortcut 过 `replaceYoutubeEmojiShortcodes` 短代码映射表
///   (含 CLDR 短名补充;未知名保留原文,数据诚实不伪造);
/// - 文本段(用户逐字输入)不过映射表,避免把「1:100:2」这类字面量误改。
String _runsToText(Object? runs) {
  final buffer = StringBuffer();
  for (final raw in jsonListOf(runs)) {
    final run = jsonMapOf(raw);
    final text = jsonText(run['text']);
    if (text.isNotEmpty) {
      buffer.write(text);
      continue;
    }
    final emoji = jsonMapOf(run['emoji']);
    final emojiId = jsonText(emoji['emojiId']);
    if (emojiId.isNotEmpty && !emojiId.startsWith(':')) {
      buffer.write(emojiId);
      continue;
    }
    final shortcuts = jsonListOf(emoji['shortcuts']);
    if (shortcuts.isNotEmpty) {
      buffer.write(replaceYoutubeEmojiShortcodes(jsonText(shortcuts.first)));
    }
  }
  return buffer.toString();
}

Map<String, dynamic> _nestedMap(Map<String, dynamic> root, List<String> path) {
  var current = root;
  for (final key in path) {
    current = jsonMapOf(current[key]);
    if (current.isEmpty) return const {};
  }
  return current;
}
