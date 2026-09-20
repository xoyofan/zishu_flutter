/// 快手弹幕:移动端增量 feed 轮询。
///
/// 桌面 WebSocket 引导有签名门槛,m 站 `wap/live/feed` 匿名即可返回公开评论、
/// 游标与拉取节奏;一次请求完成后再排下一次,避免定时器叠加。协议与 pure_live
/// 对齐。
library;

import 'dart:async';
import 'dart:convert';

import '../../contracts/contracts.dart';
import '../../http/parser_http.dart';
import '../../models/models.dart';
import '../douyu/json_utils.dart';
import 'normalize.dart';
import 'room_api.dart';

/// feed 双端点:主站不可用时切备用域。
const List<String> kKuaishouFeedHosts = [
  'livev.m.chenzhongtech.com',
  'm.gifshow.com',
];

/// 最大连续重连次数。
const int kKuaishouFeedMaxReconnect = 8;

/// 房间号 -> liveStreamId(测试可注入,避免真实请求)。
typedef KuaishouLiveStreamIdFetcher = Future<String> Function(String roomId);

/// (liveStreamId, cursor) -> feed 原始 JSON(测试可注入)。
typedef KuaishouFeedFetcher = Future<Object?> Function(
  String liveStreamId,
  String cursor,
);

/// 一次 feed 轮询结果。
class KuaishouFeedBatch {
  const KuaishouFeedBatch({
    required this.cursor,
    required this.pullDelay,
    required this.messages,
  });

  final String cursor;
  final Duration pullDelay;
  final List<DanmakuMessage> messages;
}

class KuaishouDanmakuConnector implements DanmakuConnector {
  KuaishouDanmakuConnector(
    this._http, {
    this.streamIdFetcher,
    this.feedFetcher,
    this.minimumPollDelay = const Duration(seconds: 1),
  });

  final ParserHttp _http;
  final KuaishouLiveStreamIdFetcher? streamIdFetcher;
  final KuaishouFeedFetcher? feedFetcher;
  final Duration minimumPollDelay;

  @override
  SiteCapabilities get capabilities => const SiteCapabilities(danmaku: true);

  @override
  Future<DanmakuSession> connect(DanmakuSessionRequest request) async {
    final roomId = normalizeKuaishouRoomId(request.roomId);
    final liveStreamId = await (streamIdFetcher ?? _fetchLiveStreamId)(roomId);
    if (liveStreamId.isEmpty) {
      throw const ParserHttpException('快手直播间信息缺失(可能已下播)');
    }
    final session = KuaishouDanmakuSession(
      roomId,
      liveStreamId,
      feedFetcher ?? _fetchFeed,
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

  Future<String> _fetchLiveStreamId(String roomId) async {
    final detail = await fetchKuaishouRoomDetail(_http, roomId);
    return detail.liveStreamId;
  }

  Future<Object?> _fetchFeed(String liveStreamId, String cursor) async {
    Object? lastError;
    StackTrace? lastStackTrace;
    for (final host in kKuaishouFeedHosts) {
      try {
        final response = await _http.get(
          Uri.https(host, '/wap/live/feed', {
            'liveStreamId': liveStreamId,
            if (cursor.isNotEmpty) 'cursor': cursor,
          }),
          headers: const {
            'User-Agent':
                'Mozilla/5.0 (Linux; Android 16; Mobile) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/139.0 Mobile Safari/537.36',
            'Accept': 'application/json, text/plain, */*',
            'Referer': 'https://livev.m.chenzhongtech.com/',
          },
        );
        return jsonDecode(utf8.decode(response.bodyBytes));
      } catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;
      }
    }
    Error.throwWithStackTrace(lastError!, lastStackTrace!);
  }
}

class KuaishouDanmakuSession implements DanmakuSession {
  KuaishouDanmakuSession(
    this.roomId,
    this.liveStreamId,
    this._fetcher, {
    this.minimumPollDelay = const Duration(seconds: 1),
  });

  final String roomId;
  final String liveStreamId;
  final KuaishouFeedFetcher _fetcher;
  final Duration minimumPollDelay;

  late final StreamController<DanmakuMessage> _messagesController =
      StreamController<DanmakuMessage>.broadcast(onListen: _flushPending);

  final _statesController = StreamController<DanmakuSessionState>.broadcast();

  /// 首个订阅者之前产生的消息(首轮轮询先于 listen)先入缓冲,订阅时补发。
  final List<DanmakuMessage> _pending = [];
  static const int _maxPending = 200;

  /// 已投递消息指纹(时间+用户+内容),跨轮询去重;上限防长跑涨内存。
  final Set<String> _seen = <String>{};
  static const int _maxSeen = 500;

  int _generation = 0;
  String _cursor = '';
  int _reconnectAttempts = 0;
  Timer? _timer;
  bool _closed = false;
  bool _connected = false;

  @override
  Stream<DanmakuMessage> get messages => _messagesController.stream;

  @override
  Stream<DanmakuSessionState> get states => _statesController.stream;

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

  /// 首次拉取(带 3 次快速重试);失败抛出,由 connector 交给上层进入断开态。
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
        await _pollOnce(generation, propagateFailure: true);
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
  }) async {
    if (_closed || generation != _generation) return;
    try {
      final raw = await _fetcher(liveStreamId, _cursor);
      if (_closed || generation != _generation) return;
      final batch = parseKuaishouFeed(raw, roomId: roomId);
      if (batch.cursor.isNotEmpty) _cursor = batch.cursor;
      _reconnectAttempts = 0;

      if (!_connected) {
        _connected = true;
        _statesController.add(DanmakuSessionState.connected);
      }
      for (final message in batch.messages) {
        if (_seen.length >= _maxSeen) _seen.remove(_seen.first);
        final key =
            '${message.sentAt?.millisecondsSinceEpoch ?? 0}\u0000'
            '${message.userId}\u0000${message.text}';
        if (!_seen.add(key)) continue;
        _emitMessage(message);
      }
      _schedule(generation, batch.pullDelay);
    } catch (error, stackTrace) {
      if (_closed || generation != _generation) return;
      if (propagateFailure) rethrow;
      _handleFailure(generation, error, stackTrace);
    }
  }

  void _handleFailure(int generation, Object error, StackTrace stackTrace) {
    _reconnectAttempts++;
    if (_connected) {
      _connected = false;
      _statesController.add(DanmakuSessionState.disconnected);
    }
    if (_reconnectAttempts > kKuaishouFeedMaxReconnect) return;
    final seconds = 1 << (_reconnectAttempts - 1).clamp(0, 3);
    _schedule(generation, Duration(seconds: seconds));
  }

  void _schedule(int generation, Duration requestedDelay) {
    if (_closed || generation != _generation) return;
    _timer?.cancel();
    final delay = requestedDelay < minimumPollDelay
        ? minimumPollDelay
        : requestedDelay;
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

/// 解析 feed 响应:result!=1 视为失败;仅取 comment 类型。
///
/// 表情说明(2026-09-20 调研):m 站 `wap/live/feed` 的 comment 只携带纯文本
/// `content`,表情以 `[贊]`/`[笑哭]` 名称记号内联在文本里,协议不携带表情
/// ID/URL;快手表情包「名称 → 图片」映射在其客户端资源内,无公开 URL 规则,
/// 抓包前不做 image segment 伪造(数据诚实),UI 按纯文本渲染记号原文。
KuaishouFeedBatch parseKuaishouFeed(Object? raw, {String roomId = ''}) {
  dynamic payload = raw;
  for (var depth = 0; depth < 3 && payload is String; depth++) {
    payload = jsonDecode(payload);
  }
  if (payload is Map && payload['data'] is Map) payload = payload['data'];
  if (payload is! Map) {
    throw const FormatException('Kuaishou feed has an invalid shape');
  }

  final result = jsonInt(payload['result']);
  if (result != 1) {
    throw StateError('Kuaishou feed rejected the request (result: $result)');
  }
  final cursor = jsonText(payload['cursor']);
  final rawPull = jsonInt(payload['pullCycleSeconds']);
  final pullSeconds = (rawPull == 0 ? 3 : rawPull).clamp(1, 10);

  final messages = <DanmakuMessage>[];
  for (final rawFeed in jsonListOf(payload['liveStreamFeeds'])) {
    final feed = jsonMapOf(rawFeed);
    if (jsonText(feed['type']).toLowerCase() != 'comment') continue;
    final content = jsonText(feed['content']).trim();
    if (content.isEmpty) continue;
    final author = jsonMapOf(feed['author']);
    final userName = jsonText(author['userName']).trim();
    final timestamp = jsonInt(feed['time']);
    messages.add(
      DanmakuMessage(
        type: DanmakuMessageType.chat,
        roomId: roomId,
        userName: userName.isEmpty ? '快手用户' : userName,
        userId: jsonText(author['userId']),
        text: content,
        sentAt: timestamp > 0
            ? DateTime.fromMillisecondsSinceEpoch(timestamp)
            : null,
        rawType: 'comment',
      ),
    );
  }

  return KuaishouFeedBatch(
    cursor: cursor,
    pullDelay: Duration(seconds: pullSeconds),
    messages: List<DanmakuMessage>.unmodifiable(messages),
  );
}
