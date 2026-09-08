/// Web 播放器适配器 —— 实现 pure_live UnifiedPlayer 语义（简化契约）。
///
/// - `setDataSource(url, playUrls, headers, {site, roomId, audioOnly})`：
///   format 判定（对齐 playUrlKind）→ 选后端（hls.js / mpegts.js）→
///   headers 非空（needsProxy）时 URL 改写为
///   `{streamApiBaseUrl}/api/live-stream?url=…`（见 proxy_urls.dart）。
/// - generation fence：每次切源/切房 `_session` 自增并作为 token 捕获进
///   事件回调；旧后端的迟到事件（含 dispose 期间的“临终”事件、迟到的
///   open 完成）一律丢弃，且迟到的旧后端会被强制 dispose。
/// - 纯 Dart，无 dart:js_interop import：后端/承载面经
///   backend_factory.dart 条件导出注入，VM 单测用 fake 替换。
library;

import 'dart:async';

import 'package:flutter/widgets.dart' show BoxFit, SizedBox, Widget;

import 'backend_factory.dart';
import 'proxy_urls.dart';
import 'web_player_backend.dart';

/// 后端工厂：按 format（'hls' | 'flv' | 'mpegts'）创建播放后端。
typedef WebPlayerBackendFactory = WebPlayerBackend Function(String format);

/// 承载面工厂：init 时调用一次，创建 video 元素 + HtmlElementView。
typedef WebVideoSurfaceFactory = WebVideoSurface Function();

class WebVideoPlayerAdapter {
  /// 运行时解析 streaming-server base URL（代理改写用）。
  /// 返回空串时无法拼代理，带 Referer 的线路将按原地址直连（大概率失败）。
  final String Function()? resolveStreamApiBaseUrl;

  /// 承载面工厂（默认走 backend_factory.dart 的条件导出；测试注入 fake）。
  final WebVideoSurfaceFactory? surfaceFactory;

  final WebPlayerBackendFactory _backendFactory;

  WebVideoSurface? _surface;
  WebPlayerBackend? _backend;
  final List<StreamSubscription<void>> _backendSubs = [];

  bool _initialized = false;
  bool _disposed = false;
  bool _audioOnly = false;
  bool _playing = false;
  PlayerState _stateValue = PlayerState.idle;

  /// generation fence 会话 token。
  int _session = 0;

  final _stateCtrl = StreamController<PlayerState>.broadcast();
  final _playingCtrl = StreamController<bool>.broadcast();
  final _loadingCtrl = StreamController<bool>.broadcast();
  final _errorCtrl = StreamController<PlaybackException>.broadcast();
  final _completeCtrl = StreamController<bool>.broadcast();
  final _widthCtrl = StreamController<int?>.broadcast();
  final _heightCtrl = StreamController<int?>.broadcast();

  WebVideoPlayerAdapter({
    WebPlayerBackendFactory? backendFactory,
    this.surfaceFactory,
    this.resolveStreamApiBaseUrl,
  }) : _backendFactory = backendFactory ?? defaultWebPlayerBackendFactory;

  // ---- 状态 ---------------------------------------------------------------

  bool get isInitialized => _initialized;
  bool get isPlayingNow => _playing;
  PlayerState get state => _stateValue;

  Stream<PlayerState> get onStateChanged => _stateCtrl.stream;
  Stream<bool> get onPlaying => _playingCtrl.stream;
  Stream<bool> get onLoading => _loadingCtrl.stream;
  Stream<PlaybackException> get onError => _errorCtrl.stream;
  Stream<bool> get onComplete => _completeCtrl.stream;
  Stream<int?> get width => _widthCtrl.stream;
  Stream<int?> get height => _heightCtrl.stream;

  // ---- 生命周期 -----------------------------------------------------------

  Future<void> init({bool audioOnly = false}) async {
    if (_initialized || _disposed) return;
    _audioOnly = audioOnly;
    _stateValue = PlayerState.initializing;
    _stateCtrl.add(_stateValue);
    try {
      _surface = (surfaceFactory ?? defaultWebVideoSurface)();
      _initialized = true;
      _transition(PlayerState.initialized);
    } catch (e, s) {
      _fail(
        PlaybackException(
          message: 'init 失败: $e',
          code: 'init',
          error: e,
          stackTrace: s,
        ),
      );
    }
  }

  /// 设置数据源并打开后端。
  ///
  /// [url] 当前播放地址；[playUrls] 备用地址（首个可判定格式的地址生效）；
  /// [headers] 非空时改写为代理地址（needsProxy 语义）。
  /// [site]/[roomId] 进入代理 query（site/room 参数）。
  Future<void> setDataSource(
    String url,
    List<String> playUrls,
    Map<String, String> headers, {
    String? site,
    String? roomId,
    bool audioOnly = false,
  }) async {
    if (_disposed) return;
    _audioOnly = audioOnly;
    final session = ++_session;

    // 复位状态（对齐 pure_live：换源即清尺寸/完成态）
    _playing = false;
    _playingCtrl.add(false);
    _loadingCtrl.add(true);
    _completeCtrl.add(false);
    _widthCtrl.add(null);
    _heightCtrl.add(null);
    _transition(PlayerState.preparing);

    // 拆旧后端：dispose 先行（其“临终”事件由 token 过滤），随后才取消订阅
    await _teardownBackend();

    final candidates = [
      url,
      ...playUrls,
    ].map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    var kind = 'other';
    var chosen = '';
    for (final c in candidates) {
      final k = playbackUrlKind(c);
      if (k != 'other') {
        chosen = c;
        kind = k;
        break;
      }
    }

    if (chosen.isEmpty) {
      _loadingCtrl.add(false);
      _fail(
        PlaybackException(
          message: 'Web 播放层不支持该地址格式: ${candidates.firstOrNull ?? url}',
          code: 'format',
        ),
      );
      return;
    }

    // headers 非空 → 浏览器无法直连，改写为 streaming-server 代理
    var playUrl = chosen;
    if (headers.isNotEmpty) {
      final base = resolveStreamApiBaseUrl?.call() ?? '';
      playUrl = proxyUrl(base, playUrl, site: site ?? '', room: roomId ?? '');
    }

    final backend = _backendFactory(kind);
    _backend = backend;
    _subscribeBackend(backend, session);
    try {
      await backend.open(
        playUrl,
        format: kind,
        mediaElement: _surface?.mediaElement,
      );
    } catch (e, s) {
      if (_session != session) {
        // 迟到的 open 失败：属旧会话，强制回收并丢弃
        await _disposeQuietly(backend);
        return;
      }
      _loadingCtrl.add(false);
      _fail(
        PlaybackException(
          message: '打开流失败（$kind）: $e',
          code: 'open',
          error: e,
          stackTrace: s,
        ),
      );
      return;
    }
    if (_session != session) {
      // 迟到的 open 完成：本次 setDataSource 已被新会话取代，回收旧后端并丢弃
      await _disposeQuietly(backend);
      return;
    }
    _loadingCtrl.add(false);
    _transition(PlayerState.ready);
  }

  Future<void> _disposeQuietly(WebPlayerBackend backend) async {
    try {
      await backend.dispose();
    } catch (_) {
      /* ignore */
    }
  }

  Future<void> play() async {
    if (_disposed) return;
    final backend = _backend;
    if (backend == null) return;
    await backend.play();
  }

  Future<void> pause() async {
    if (_disposed) return;
    await _backend?.pause();
  }

  Future<void> stop() async {
    if (_disposed) return;
    await _backend?.stop();
    if (!_disposed) _transition(PlayerState.stopped);
  }

  /// 不销毁后端，仅静音 + 暂停（pure_live 语义：切房防黑屏）。
  Future<void> softStop() async {
    if (_disposed) return;
    await _backend?.setVolume(0);
    await _backend?.pause();
  }

  Future<void> setVolume(double volume) async {
    if (_disposed) return;
    await _backend?.setVolume(volume);
  }

  Future<void> hardDispose() async {
    if (_disposed) return;
    _disposed = true;
    _session++; // 终止一切迟到回调
    await _teardownBackend();
    await _surface?.dispose();
    _surface = null;
    _initialized = false;
    _transition(PlayerState.disposed);
    await Future.wait([
      _stateCtrl.close(),
      _playingCtrl.close(),
      _loadingCtrl.close(),
      _errorCtrl.close(),
      _completeCtrl.close(),
      _widthCtrl.close(),
      _heightCtrl.close(),
    ]);
  }

  Widget getVideoWidget(BoxFit boxFit) {
    if (_audioOnly) return const SizedBox.shrink();
    final surface = _surface;
    if (surface == null) return const SizedBox.shrink();
    return surface.buildWidget(boxFit);
  }

  // ---- 内部 ---------------------------------------------------------------

  void _transition(PlayerState next) {
    if (_stateValue == next) return;
    _stateValue = next;
    _stateCtrl.add(next);
  }

  void _fail(PlaybackException e) {
    _stateValue = PlayerState.error;
    _stateCtrl.add(PlayerState.error);
    _errorCtrl.add(e);
  }

  /// 拆旧后端：先 dispose（此时旧事件靠 token 过滤），后取消订阅。
  Future<void> _teardownBackend() async {
    final backend = _backend;
    _backend = null;
    if (backend == null) return;
    try {
      await backend.dispose();
    } catch (_) {
      /* ignore */
    }
    for (final sub in _backendSubs) {
      await sub.cancel();
    }
    _backendSubs.clear();
  }

  /// 订阅后端事件；每个回调捕获 session token —— 非当前会话的事件一律丢弃。
  void _subscribeBackend(WebPlayerBackend backend, int session) {
    bool stale() => _session != session || _disposed;
    _backendSubs.addAll([
      backend.onPlaying.listen((v) {
        if (stale()) return;
        _playing = v;
        _playingCtrl.add(v);
        if (v) {
          _transition(PlayerState.playing);
        } else if (_stateValue == PlayerState.playing ||
            _stateValue == PlayerState.buffering) {
          _transition(PlayerState.paused);
        }
      }),
      backend.onBuffering.listen((v) {
        if (stale()) return;
        _loadingCtrl.add(v);
        if (v) {
          _transition(PlayerState.buffering);
        } else if (_playing) {
          _transition(PlayerState.playing);
        }
      }),
      backend.onError.listen((message) {
        if (stale()) return;
        _playing = false;
        _playingCtrl.add(false);
        _loadingCtrl.add(false);
        _fail(PlaybackException(message: message, code: 'backend'));
      }),
      backend.onCompleted.listen((v) {
        if (stale()) return;
        _playing = false;
        _transition(PlayerState.completed);
        _completeCtrl.add(v);
      }),
      backend.onSize.listen((size) {
        if (stale()) return;
        _widthCtrl.add(size.width);
        _heightCtrl.add(size.height);
      }),
    ]);
  }
}
