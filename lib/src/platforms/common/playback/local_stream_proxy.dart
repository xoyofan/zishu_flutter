/// 本地流代理:对齐斗鱼官方 PC 客户端 DySDKController(127.0.0.1:5001)
/// 的取流架构 —— mpv 只见一条本地 FLV 流,远端 token 过期/换节点由代理层
/// 对播放器完全透明地消化。
///
/// - 首连接([StreamProxySession] 创建)由 mpv 首次请求本地 URL 时懒启动,
///   字节经 [FlvStreamSplicer.feedPrimary] 原样透传并追踪时间轴;
/// - [StreamProxySession.switchUpstream] 断开旧远端、用新 URL 重连,新流
///   前导被剥离、tag 时间戳平移到旧轴([FlvStreamSplicer] 负责),mpv 侧
///   感知不到切换(仅短暂消耗缓冲);
/// - 上游失败(连接拒绝/读错误/提前结束):**直接断开 mpv 侧连接**,让
///   mpv 报网络错误进入既有恢复链(致命传输诊断短路已在播放器侧就位)。
///
/// 安全:仅 bind 127.0.0.1 随机端口;不设 Content-Length(chunked)。
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'flv_stream_splicer.dart';
import 'playback_log.dart';

/// upstream 建连(含响应头返回)超时:超过即视为该源失败。
const Duration _connectTimeout = Duration(seconds: 10);

class LocalStreamProxy {
  HttpServer? _server;
  int _nextSessionId = 0;
  final Map<int, StreamProxySession> _sessions = {};

  int get port => _server?.port ?? 0;
  bool get isRunning => _server != null;

  Future<void> start() async {
    if (_server != null) return;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    // 请求处理必须在 onData 内以 async 闭包持有:同步回调返回后 dart:io
    // 会把 response 绑进内部 drain 流,跨事件的异步 add 会挂死
    // ("StreamSink is bound to a stream",最小探针实测)。
    server.listen(
      (request) {
        unawaited(_routeRequest(request));
      },
      onError: (Object error) {
        PlaybackLog.write('proxy_server_error', {'error': '$error'});
      },
      cancelOnError: true,
    );
    PlaybackLog.write('proxy_started', {'port': server.port});
  }

  StreamProxySession openSession(String upstreamUrl) {
    final id = _nextSessionId++;
    final session = StreamProxySession._(id, this, upstreamUrl);
    _sessions[id] = session;
    PlaybackLog.write('proxy_session_open', {
      'session': id,
      'upstream': Uri.tryParse(upstreamUrl)?.host,
    });
    return session;
  }

  Future<void> _routeRequest(HttpRequest request) async {
    final segment = request.uri.pathSegments.firstOrNull;
    final id = int.tryParse(segment?.split('.').first ?? '');
    final session = id == null ? null : _sessions[id];
    if (session == null) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    await session._attachClient(request);
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    for (final session in List.of(_sessions.values)) {
      await session.dispose();
    }
    if (server != null) {
      await server.close(force: true);
    }
    PlaybackLog.write('proxy_stopped');
  }
}

/// 单个播放会话:一个本地 URL ↔ 一个远端 upstream(可热切换)。
class StreamProxySession {
  StreamProxySession._(this.id, this._proxy, String upstreamUrl)
      : _upstreamUrl = upstreamUrl;

  final int id;
  final LocalStreamProxy _proxy;
  final FlvStreamSplicer _splicer = FlvStreamSplicer();
  HttpClient? _httpClient;
  HttpClientRequest? _upstreamRequest;
  StreamSubscription<List<int>>? _upstreamSub;

  /// 对 mpv 的写通道:全部字节写进 controller,由 pipe 持有 response 写出。
  /// 直接跨事件持有 HttpResponse 调 add() 在 dart:io 里不可靠
  /// ("StreamSink is bound to a stream" / 挂死,最小探针实测),管道模式下
  /// 写操作都收在 addStream 生命周期内。
  StreamController<List<int>>? _outgoing;

  String _upstreamUrl;
  int _generation = 0;
  bool _disposed = false;

  /// mpv 要打开的本地地址(懒连接:upstream 在 mpv 首次请求时才拉)。
  String get localUrl => 'http://127.0.0.1:${_proxy.port}/$id.flv';

  /// 当前 upstream 的 host(供日志归因,mpv 侧只见 127.0.0.1)。
  String get upstreamHost => Uri.tryParse(_upstreamUrl)?.host ?? '';

  /// upstream 热切换(token 预刷新 / 换节点):断旧连、接新连,mpv 无感。
  ///
  /// 返回 `false` 表示会话已终结(会话级 [dispose] 已执行,mpv 断开)或
  /// mpv 尚未接上 —— 调用方应回退整组重开。
  Future<bool> switchUpstream(String url) async {
    if (_disposed) return false;
    _upstreamUrl = url;
    final generation = ++_generation;
    await _abortUpstream();
    _splicer.beginUpstreamSwitch();
    final outgoing = _outgoing;
    if (outgoing == null || outgoing.isClosed) return false;
    PlaybackLog.write('proxy_upstream_switch', {
      'session': id,
      'upstream': upstreamHost,
    });
    await _connectUpstream(generation, secondary: true);
    return !_disposed;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    await _abortUpstream();
    _closeOutgoing();
    _httpClient?.close(force: true);
    _httpClient = null;
    _proxy._sessions.remove(id);
    PlaybackLog.write('proxy_session_close', {'session': id});
  }

  Future<void> _attachClient(HttpRequest request) async {
    if (_disposed || _outgoing != null) {
      // 同一会话的第二个连接不允许(mpv 重开走新 session):直接关闭。
      await request.response.close();
      return;
    }
    final response = request.response;
    response.bufferOutput = false;
    response.headers.contentType = ContentType('video', 'x-flv');
    // 先行提交响应头:upstream 建连/首字节可能耗时数百 ms,mpv 侧的
    // http 等待不应由它兜底(否则慢上游会被误判为打开失败)。
    try {
      await response.flush();
    } catch (_) {
      // mpv 侧已断开:由后续清理路径兜底。
    }
    final outgoing = StreamController<List<int>>();
    _outgoing = outgoing;
    // pipe 完成有两种来路:我们 close outgoing(upstream 失败/会话释放)或
    // mpv 断开连接 —— 都意味着会话终结,统一走清理。
    unawaited(
      outgoing.stream
          .pipe(response)
          .then((_) {})
          .catchError((Object _) {})
          .whenComplete(() {
        if (!_disposed) unawaited(dispose());
      }),
    );
    PlaybackLog.write('proxy_client_attached', {
      'session': id,
      'upstream': upstreamHost,
    });
    await _connectUpstream(_generation, secondary: false);
  }

  Future<void> _connectUpstream(int generation, {required bool secondary}) async {
    if (_disposed || generation != _generation) return;
    try {
      final httpClient = _httpClient ??= HttpClient();
      final upstreamRequest = await httpClient
          .getUrl(Uri.parse(_upstreamUrl))
          .timeout(_connectTimeout);
      _upstreamRequest = upstreamRequest;
      final response = await upstreamRequest.close().timeout(_connectTimeout);
      if (response.statusCode != HttpStatus.ok) {
        response.drain<void>().catchError((Object _) {});
        _onUpstreamFailure(generation, 'http_${response.statusCode}');
        return;
      }
      _upstreamSub = response.listen(
        (chunk) {
          if (_disposed || generation != _generation) return;
          final out = secondary
              ? _splicer.feedSecondary(Uint8List.fromList(chunk))
              : _splicer.feedPrimary(Uint8List.fromList(chunk));
          if (out.isNotEmpty) _outgoing?.add(out);
        },
        onDone: () => _onUpstreamFailure(generation, 'upstream_done'),
        onError: (Object error) =>
            _onUpstreamFailure(generation, 'upstream_error: $error'),
        cancelOnError: true,
      );
    } catch (error) {
      _onUpstreamFailure(generation, 'connect_failed: $error');
    }
  }

  void _onUpstreamFailure(int generation, String reason) {
    if (_disposed || generation != _generation) return;
    PlaybackLog.write('proxy_upstream_fail', {
      'session': id,
      'upstream': upstreamHost,
      'reason': _shortReason(reason),
    });
    // 阶段 1 语义:上游救不回来就结束本地流,让 mpv 报网络错误进入既有
    // 恢复链(致命传输诊断短路 → re-resolve)。
    unawaited(dispose());
  }

  Future<void> _abortUpstream() async {
    final sub = _upstreamSub;
    _upstreamSub = null;
    await sub?.cancel();
    final request = _upstreamRequest;
    _upstreamRequest = null;
    request?.abort();
  }

  void _closeOutgoing() {
    final outgoing = _outgoing;
    _outgoing = null;
    if (outgoing != null && !outgoing.isClosed) {
      outgoing.close();
      // pipe 收到 done 后会 close response(mpv 侧读到流结束)。
    }
  }

  static String _shortReason(String reason) =>
      reason.length > 80 ? reason.substring(0, 80) : reason;
}
