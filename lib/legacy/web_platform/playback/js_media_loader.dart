/// Web 播放内核装载与 dart:js_interop 桥接 —— 仅 Flutter Web 可用。
///
/// 内核注入：`web/index.html` 以 <script> 引入
///   - hls.js（1.x，对齐 SFVideoLive web ^1.6.2）→ window.Hls
///   - mpegts.js（1.x，对齐 SFVideoLive web ^1.8.2，flv.js 的维护分支）→ window.mpegts
/// CDN：jsDelivr（https://cdn.jsdelivr.net/npm/hls.js@1/dist/hls.min.js、
/// .../mpegts.js@1/dist/mpegts.min.js），脚本加载失败/缺失时由此处兜底重注入。
///
/// 互操作面 = SFVideoLive web 实际调用的 API（usePlayer.ts）：
///   hls.js   : isSupported / new Hls({enableWorker, lowLatencyMode,
///              liveSyncDurationCount, backBufferLength}) / on(Events.ERROR,
///              Events.MANIFEST_PARSED) / loadSource / attachMedia / destroy
///   mpegts.js: isSupported / createPlayer({type:'flv'|'mpegts', url, isLive,
///              hasAudio, hasVideo, cors[, referrerPolicy]}, {enableStashBuffer,
///              lazyLoad}) / attachMediaElement / on(Events.ERROR,
///              Events.MEDIA_INFO) / load / pause / unload / detachMediaElement /
///              destroy
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart' show BoxFit, HtmlElementView, Widget;
import 'package:web/web.dart' as web;

import 'web_player_backend.dart';

// ---------------------------------------------------------------------------
// 内核脚本装载
// ---------------------------------------------------------------------------

/// 与 web/index.html 中的注入保持一致（兜底重注入用）。
const String kHlsJsScriptUrl =
    'https://cdn.jsdelivr.net/npm/hls.js@1/dist/hls.min.js';
const String kMpegtsJsScriptUrl =
    'https://cdn.jsdelivr.net/npm/mpegts.js@1/dist/mpegts.min.js';

final Map<String, Future<JSAny?>> _scriptGlobals = {};

JSAny? _global(String name) => globalContext.getProperty<JSAny?>(name.toJS);

/// 确保全局对象存在：已挂载直接返回；否则注入 <script> 并轮询等待。
Future<JSAny?> _ensureScriptGlobal(
  String globalName,
  String src, {
  Duration timeout = const Duration(seconds: 12),
}) {
  return _scriptGlobals.putIfAbsent(globalName, () async {
    final existing = _global(globalName);
    if (existing != null) return existing;
    await _injectScript(src);
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final v = _global(globalName);
      if (v != null) return v;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    throw StateError('等待 $globalName 超时（脚本加载失败?）: $src');
  });
}

Future<void> _injectScript(String src) {
  final completer = Completer<void>();
  final script = web.HTMLScriptElement();
  script.src = src;
  script.onload = ((web.Event _) {
    if (!completer.isCompleted) completer.complete();
  }).toJS;
  script.onerror = ((web.Event _) {
    if (!completer.isCompleted) {
      completer.completeError(StateError('脚本加载失败: $src'));
    }
  }).toJS;
  web.document.head?.append(script);
  return completer.future;
}

// ---------------------------------------------------------------------------
// 最小互操作面（仅声明 SFVideoLive web 实际调用的成员）
// ---------------------------------------------------------------------------

/// window.Hls —— hls.js 类（静态成员 + 构造）与其播放器实例共用一个互操作面。
@JS('Hls')
extension type HlsJsApi._(JSObject _) implements JSObject {
  /// new Hls(config)
  external factory HlsJsApi(JSObject config);

  external static bool isSupported();
  @JS('Events')
  external static JSObject get events;

  // 播放器实例方法（new Hls(cfg) 返回的对象）
  external void on(JSAny? event, JSFunction callback);
  external void loadSource(String url);
  external void attachMedia(JSObject mediaElement);
  external void destroy();
}

/// window.mpegts —— mpegts.js 模块。
@JS('mpegts')
extension type MpegtsApi._(JSObject _) implements JSObject {
  external bool isSupported();
  external MpegtsPlayer createPlayer(JSObject mediaDataSource, JSObject config);
  @JS('Events')
  external JSObject get events;
}

/// mpegts.js 的播放器实例。
extension type MpegtsPlayer._(JSObject _) implements JSObject {
  external void attachMediaElement(JSObject mediaElement);
  external void on(JSAny? event, JSFunction callback);
  external void load();
  external void pause();
  external void unload();
  external void detachMediaElement();
  external void destroy();
}

JSAny? _events(JSObject events, String name) =>
    events.getProperty<JSAny?>(name.toJS);

bool _jsBool(JSAny? value, {bool orElse = false}) =>
    value != null && value.isA<JSBoolean>()
    ? (value as JSBoolean).toDart
    : orElse;

String _jsString(JSAny? value) {
  if (value.isUndefinedOrNull) return '';
  final dart = value.dartify();
  return dart == null ? '' : dart.toString();
}

JSObject _jsObject(Map<String, JSAny?> entries) {
  final o = JSObject();
  entries.forEach((k, v) => o.setProperty(k.toJS, v));
  return o;
}

// ---------------------------------------------------------------------------
// Web 渲染承载面：单个 <video> 元素 + HtmlElementView
// ---------------------------------------------------------------------------

int _surfaceCounter = 0;

class WebVideoSurfaceImpl implements WebVideoSurface {
  final web.HTMLVideoElement element;
  final String _viewId;

  WebVideoSurfaceImpl._(this.element, this._viewId);

  /// 创建 video 元素并注册 platform view 工厂。
  factory WebVideoSurfaceImpl() {
    final el = web.HTMLVideoElement();
    el.controls = false;
    el.playsInline = true;
    // E7 冒烟脚本（tool/smoke_play.mjs）以此 id 定位 <video> 做断言。
    el.id = 'smoke-video';
    el.setAttribute('playsinline', '');
    el.setAttribute('webkit-playsinline', '');
    el.setAttribute('disablepictureinpicture', '');
    final id = 'zishu-video-${_surfaceCounter++}';
    ui_web.platformViewRegistry.registerViewFactory(id, (int viewId) => el);
    return WebVideoSurfaceImpl._(el, id);
  }

  @override
  Widget buildWidget(BoxFit fit) => HtmlElementView(viewType: _viewId);

  @override
  Object? get mediaElement => element;

  @override
  Future<void> dispose() async {}
}

// ---------------------------------------------------------------------------
// 具体后端
// ---------------------------------------------------------------------------

/// video 元素事件桥接（hls / mpegts 两个后端共用）。
mixin _VideoElementEvents on WebPlayerBackendBase {
  web.HTMLVideoElement? _el;
  final List<(String, JSFunction)> _boundListeners = [];
  bool _wantPlay = false;

  web.HTMLVideoElement? get videoElement => _el;

  void bindVideoElement(Object? mediaElement) {
    final el = mediaElement as web.HTMLVideoElement?;
    _el = el;
    if (el == null) return;
    _on(el, 'playing', (_) {
      emitBuffering(false);
      emitPlaying(true);
    });
    _on(el, 'waiting', (_) => emitBuffering(true));
    _on(el, 'pause', (_) => emitPlaying(false));
    _on(el, 'error', (_) => emitError('video element error'));
    _on(el, 'ended', (_) {
      emitPlaying(false);
      emitCompleted(true);
    });
    _onSizeSync();
    _on(el, 'loadedmetadata', (_) => _onSizeSync());
    _on(el, 'resize', (_) => _onSizeSync());
    _on(el, 'canplay', (_) {
      if (_wantPlay) unawaited(tryPlayVideo());
    });
  }

  void _onSizeSync() {
    final el = _el;
    if (el == null) return;
    if (el.videoWidth > 0 && el.videoHeight > 0) {
      emitSize(VideoSize(el.videoWidth, el.videoHeight));
    }
  }

  void _on(
    web.HTMLVideoElement el,
    String type,
    void Function(web.Event) handler,
  ) {
    final fn = handler.toJS;
    el.addEventListener(type, fn);
    _boundListeners.add((type, fn));
  }

  Future<void> tryPlayVideo() async {
    final el = _el;
    if (el == null || isClosed) return;
    try {
      await el.play().toDart;
    } catch (_) {
      // NotAllowedError：浏览器策略拒绝（需用户手势后重试）
      emitError('浏览器拒绝了播放（需用户手势触发后重试）');
    }
  }

  void pauseVideo() {
    _wantPlay = false;
    try {
      _el?.pause();
    } catch (_) {
      /* ignore */
    }
  }

  /// 清空 video 的 src（对齐 clearNativeSource）。
  void clearVideoSource() {
    final el = _el;
    if (el == null) return;
    try {
      el.pause();
      el.removeAttribute('src');
      el.load();
    } catch (_) {
      /* ignore */
    }
  }

  void unbindVideoElement() {
    final el = _el;
    for (final (type, fn) in _boundListeners) {
      try {
        el?.removeEventListener(type, fn);
      } catch (_) {
        /* ignore */
      }
    }
    _boundListeners.clear();
    _el = null;
  }
}

/// hls.js 后端（HLS / m3u8）。
class HlsJsBackend extends WebPlayerBackendBase with _VideoElementEvents {
  HlsJsApi? _hls;

  @override
  Future<void> open(
    String url, {
    required String format,
    Object? mediaElement,
  }) async {
    final apiAny = await _ensureScriptGlobal('Hls', kHlsJsScriptUrl);
    if (apiAny == null) {
      throw StateError('hls.js 未加载（window.Hls 缺失）');
    }
    if (!HlsJsApi.isSupported()) {
      throw UnsupportedError('当前浏览器不支持 hls.js');
    }
    bindVideoElement(mediaElement);
    final player = HlsJsApi(
      _jsObject({
        'enableWorker': true.toJS,
        // 直播追边：低延迟模式 + 贴边 3 个分片（对齐 SFVideoLive 默认配置）
        'lowLatencyMode': true.toJS,
        'liveSyncDurationCount': 3.toJS,
        // 回收已播分片，防止长时观看内存增长（对齐 SFVideoLive backBufferLength）
        'backBufferLength': 60.toJS,
      }),
    );
    _hls = player;
    final events = HlsJsApi.events;
    final errorEvent = _events(events, 'ERROR');
    final manifestEvent = _events(events, 'MANIFEST_PARSED');
    player.on(
      errorEvent,
      ((JSAny? ignoredEvent, JSAny? data) {
        final obj = data as JSObject?;
        final fatal = _jsBool(obj?.getProperty<JSAny?>('fatal'.toJS));
        final details = _jsString(obj?.getProperty<JSAny?>('details'.toJS));
        if (fatal) {
          emitError('hls.js fatal: ${details.isEmpty ? 'unknown' : details}');
        }
      }).toJS,
    );
    player.on(
      manifestEvent,
      ((JSAny? ignoredEvent, JSAny? ignoredData) {
        // 注意：toJS 回调必须返回 void（dart2js 拒绝带 Future 的签名）
        if (_wantPlay) unawaited(tryPlayVideo());
      }).toJS,
    );
    player.loadSource(url);
    player.attachMedia((videoElement as web.HTMLVideoElement) as JSObject);
  }

  @override
  Future<void> play() async {
    _wantPlay = true;
    await tryPlayVideo();
  }

  @override
  Future<void> pause() async => pauseVideo();

  @override
  Future<void> stop() async => pauseVideo();

  @override
  Future<void> setVolume(double volume) async {
    final el = videoElement;
    if (el != null) el.volume = volume.clamp(0.0, 1.0);
  }

  @override
  Future<void> dispose() async {
    try {
      _hls?.destroy();
    } catch (_) {
      /* ignore */
    }
    _hls = null;
    pauseVideo();
    clearVideoSource();
    unbindVideoElement();
    await closeEventHub();
  }
}

/// mpegts.js 后端（FLV 直播 type='flv'，IPTV TS 直链 type='mpegts'）。
class MpegtsJsBackend extends WebPlayerBackendBase with _VideoElementEvents {
  MpegtsPlayer? _player;

  @override
  Future<void> open(
    String url, {
    required String format,
    Object? mediaElement,
  }) async {
    final mpegtsAny = await _ensureScriptGlobal('mpegts', kMpegtsJsScriptUrl);
    final api = mpegtsAny as MpegtsApi;
    if (!api.isSupported()) {
      throw UnsupportedError('当前浏览器不支持 mpegts.js');
    }
    bindVideoElement(mediaElement);
    final type = format == 'mpegts' ? 'mpegts' : 'flv';
    final dataSource = _jsObject({
      'type': type.toJS,
      'url': url.toJS,
      'isLive': true.toJS,
      'hasAudio': true.toJS,
      'hasVideo': true.toJS,
      'cors': true.toJS,
      // 仅 flv 直链带 referrerPolicy（对齐 playFlv）
      if (type == 'flv') 'referrerPolicy': 'origin-when-cross-origin'.toJS,
    });
    final config = _jsObject({
      'enableStashBuffer': false.toJS,
      'lazyLoad': false.toJS,
    });
    final player = api.createPlayer(dataSource, config);
    _player = player;
    player.attachMediaElement(
      (videoElement as web.HTMLVideoElement) as JSObject,
    );
    final events = api.events;
    player.on(
      _events(events, 'ERROR'),
      ((JSAny? ignoredType, JSAny? detail) {
        emitError('mpegts.js error: ${_jsString(detail)}');
      }).toJS,
    );
    player.on(
      _events(events, 'MEDIA_INFO'),
      ((JSAny? ignoredType, JSAny? ignoredInfo) {
        if (_wantPlay) unawaited(tryPlayVideo());
      }).toJS,
    );
    player.load();
  }

  @override
  Future<void> play() async {
    _wantPlay = true;
    await tryPlayVideo();
  }

  @override
  Future<void> pause() async => pauseVideo();

  @override
  Future<void> stop() async => pauseVideo();

  @override
  Future<void> setVolume(double volume) async {
    final el = videoElement;
    if (el != null) el.volume = volume.clamp(0.0, 1.0);
  }

  @override
  Future<void> dispose() async {
    // 对齐 teardownPlayer：pause → unload → detachMediaElement → destroy
    try {
      final p = _player;
      if (p != null) {
        p.pause();
        p.unload();
        p.detachMediaElement();
        p.destroy();
      }
    } catch (_) {
      /* ignore */
    }
    _player = null;
    clearVideoSource();
    unbindVideoElement();
    await closeEventHub();
  }
}

// ---------------------------------------------------------------------------
// 默认工厂（backend_factory.dart 条件导出的 Web 实现）
// ---------------------------------------------------------------------------

/// format: 'hls' → hls.js；'flv' | 'mpegts' → mpegts.js；其余不支持。
WebPlayerBackend defaultWebPlayerBackendFactory(String format) {
  if (format == 'hls') return HlsJsBackend();
  return MpegtsJsBackend();
}

WebVideoSurface defaultWebVideoSurface() => WebVideoSurfaceImpl();
