/// Twitch HLS 广告过滤代理(平台适配层,依赖 dart:io;Web 不可用)。
///
/// 把 Twitch 的 media playlist 请求收编到本地:播放器打开的是
/// `http://127.0.0.1:<port>/s/<token>/playlist.m3u8`,本代理每次被请求时
/// 拉上游真实 playlist、经解析核心的 [filterTwitchMediaPlaylist] 剔除
/// SSAI 广告段后回吐。段内容不经过代理——Twitch 的段 URL 是绝对地址,
/// 播放器继续直连 CDN 拉段,代理只承担每次几 KB 的 playlist 刷新。
///
/// 为什么必须这样做:mpv/ffmpeg 的 HLS demuxer 不识别 Twitch 的
/// DATERANGE 广告标记,直连上游会把 "Commercial break in progress"
/// 广告板当成直播内容播出;media-kit 又不提供 playlist 级拦截点,唯一
/// 干净的位置就是本地回环代理(等价于 streamlink `--twitch-disable-ads`
/// 的剔除式方案)。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:live_parser/live_parser.dart'
    show StreamLine, filterTwitchMediaPlaylist;

/// 单条本地线路对应的上游会话状态。
class _Session {
  _Session({required this.upstream, required this.headers});

  final Uri upstream;
  final Map<String, String> headers;

  String? lastBody;
  bool adActive = false;
  int failures = 0;
  final DateTime createdAt = DateTime.now();

  /// 同会话刷新串行化:mpv 重开期间可能并发多个 playlist 请求,
  /// 竞态会把旧过滤结果晚写入新请求(广告态闪烁)。
  Future<void> _chain = Future<void>.value();
}

class TwitchAdFilter {
  TwitchAdFilter({
    HttpClient Function()? httpClientFactory,
    bool Function(Uri uri)? shouldFilter,
  }) : _httpClientFactory = httpClientFactory ?? HttpClient.new,
       _shouldFilter = shouldFilter ?? _defaultShouldFilter;

  final HttpClient Function() _httpClientFactory;

  /// 线路是否需要过滤(默认按 Twitch CDN 域名判定)。测试注入点。
  final bool Function(Uri uri) _shouldFilter;

  static bool _defaultShouldFilter(Uri uri) => uri.host.endsWith('.ttvnw.net');

  HttpServer? _server;
  Future<HttpServer>? _starting;
  HttpClient? _client;
  final Map<String, _Session> _sessions = {};
  var _counter = 0;

  /// 注册上限:每次换房/换档/重连都会产生新会话,旧会话的本地地址无人
  /// 再请求,按时间淘汰最老的,防止长会话下映射无界增长。
  static const _maxSessions = 32;

  /// 把 [line] 改写为本地过滤地址;不需要过滤时原样返回。
  Future<StreamLine> wrapLine(StreamLine line) async {
    final uri = Uri.tryParse(line.url);
    if (uri == null || !_shouldFilter(uri)) return line;
    final server = await _ensureServer();
    final token = 's${_counter++}';
    _sessions[token] = _Session(upstream: uri, headers: line.headers);
    _evict();
    final local = Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      path: '/s/$token/playlist.m3u8',
    );
    return StreamLine(
      name: line.name,
      url: local.toString(),
      format: line.format,
      headers: line.headers,
    );
  }

  /// 本地地址 [url] 是否正处于"广告被剔除、上游暂无可播段"状态。
  /// 播放器据此豁免缓冲看门狗(见 [AdStallHoldPolicy]);未知地址一律 false。
  bool isAdStalled(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    final parts = uri.pathSegments;
    if (parts.length != 3 || parts[0] != 's') return false;
    return _sessions[parts[1]]?.adActive ?? false;
  }

  Future<void> dispose() {
    final server = _server;
    _server = null;
    _starting = null;
    _sessions.clear();
    final client = _client;
    _client = null;
    client?.close(force: true); // HttpClient.close 返回 void。
    return server?.close(force: true) ?? Future<void>.value();
  }

  void _evict() {
    while (_sessions.length > _maxSessions) {
      String? oldestKey;
      DateTime? oldestAt;
      _sessions.forEach((key, session) {
        if (oldestAt == null || session.createdAt.isBefore(oldestAt!)) {
          oldestKey = key;
          oldestAt = session.createdAt;
        }
      });
      if (oldestKey == null) break;
      _sessions.remove(oldestKey);
    }
  }

  Future<HttpServer> _ensureServer() {
    final existing = _server;
    if (existing != null) return Future<HttpServer>.value(existing);
    return _starting ??= HttpServer.bind(InternetAddress.loopbackIPv4, 0).then((
      server,
    ) {
      _server = server;
      _starting = null;
      server.listen(_onRequest, onError: (Object _) {}, cancelOnError: false);
      return server;
    });
  }

  Future<void> _onRequest(HttpRequest request) async {
    try {
      final parts = request.uri.pathSegments;
      final session = parts.length == 3 && parts[0] == 's'
          ? _sessions[parts[1]]
          : null;
      if (session == null) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      final body = await _refresh(session);
      if (body == null) {
        request.response.statusCode = HttpStatus.serviceUnavailable;
        request.response.headers.set(HttpHeaders.retryAfterHeader, '2');
        await request.response.close();
        return;
      }
      request.response.headers.set(
        HttpHeaders.contentTypeHeader,
        'application/vnd.apple.mpegurl',
      );
      request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      // 定长 + 非持久连接:playlist 是周期性轮询,每次新建连接比 keep-alive
      // 更贴合,也避免长连接半关闭状态下播放器读到不完整响应。
      final bytes = utf8.encode(body);
      request.response.contentLength = bytes.length;
      request.response.persistentConnection = false;
      request.response.add(bytes);
      await request.response.close();
    } on Object {
      try {
        await request.response.close();
      } on Object catch (_) {
        // 连响应都发不出去,让播放器按网络错误自行处理。
      }
    }
  }

  /// 刷新一次上游(同会话串行)。上游失败时回吐最近一次成功结果,让
  /// 播放器继续用旧窗口;连续失败会清除广告态(见下),不再豁免看门狗。
  Future<String?> _refresh(_Session session) {
    final task = session._chain.then((_) => _fetchAndFilter(session));
    session._chain = task.then<void>((_) {}, onError: (Object _) {});
    return task;
  }

  Future<String?> _fetchAndFilter(_Session session) async {
    HttpClient? client;
    try {
      client = _client ??= _httpClientFactory();
      final request = await client.openUrl('GET', session.upstream);
      session.headers.forEach(request.headers.set);
      final response = await request.close().timeout(const Duration(seconds: 10));
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('上游 ${response.statusCode}');
      }
      final body = await response.transform(utf8.decoder).join();
      final result = filterTwitchMediaPlaylist(body);
      session
        ..lastBody = result.body
        ..adActive = result.adActive
        ..failures = 0;
      return result.body;
    } on Object {
      // 连续两次失败视为上游已失效:广告态是"上一刻仍在播广告"的记忆,
      // 上游死了之后它只会把看门狗豁免成永久挂起,必须失效。
      if (++session.failures >= 2) session.adActive = false;
      return session.lastBody;
    }
  }
}

/// 广告期缓冲看门狗豁免策略(纯 Dart,可单测)。
///
/// 剔除式过滤会让广告期间的 playlist 刷新没有任何可播段,mpv 耗尽缓存后
/// 进入缓冲态——这与真断流在底层完全同貌,但前者是"预期内的合法等待"。
/// 若不豁免,看门狗会在一场 30~180s 的广告 pod 里烧光重连次数并触发
/// 恢复重解析(广告期内拿到的还是同一批广告地址,纯属空转)。故按住
/// 看门狗直到广告结束,并以 [holdBudget] 封顶:超过预算仍无段可播时按
/// 真断流处理(防止上游死亡 + 广告态误判把播放器永久挂在缓冲里)。
class AdStallHoldPolicy {
  const AdStallHoldPolicy({
    this.holdBudget = const Duration(minutes: 3),
    this.recheckInterval = const Duration(seconds: 5),
  });

  /// 单次广告等待的最长按住时长(Twitch 广告 pod 上限约 3 分钟)。
  final Duration holdBudget;

  /// 按住期间复查广告态的间隔。
  final Duration recheckInterval;

  /// 看门狗到期时是否应继续按住而不计失败。
  ///
  /// [holdSince] 为 null 表示本轮等待尚未开始计时(首查即命中广告态);
  /// 非空时按预算判超时。广告态为 false 一律不按住(由调用方清零计时)。
  bool shouldHold({
    required bool adStalled,
    required DateTime now,
    DateTime? holdSince,
  }) {
    if (!adStalled) return false;
    final since = holdSince;
    if (since == null) return true;
    return now.difference(since) < holdBudget;
  }
}
