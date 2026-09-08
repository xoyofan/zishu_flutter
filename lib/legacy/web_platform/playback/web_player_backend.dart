/// Web 播放后端抽象（纯 Dart，无 JS 互操作）。
///
/// HLS 用 hls.js、FLV/MPEGTS 用 mpegts.js —— 各自的具体实现见
/// `js_media_loader.dart`（含 dart:js_interop，仅 Web 可用）。
/// VM 单测用 FakeBackend 实现 [WebPlayerBackend] 即可驱动适配器逻辑。
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show protected;
import 'package:flutter/widgets.dart' show BoxFit, Widget;

/// 视频尺寸事件载荷。
class VideoSize {
  final int width;
  final int height;
  const VideoSize(this.width, this.height);

  @override
  bool operator ==(Object other) =>
      other is VideoSize && other.width == width && other.height == height;
  @override
  int get hashCode => Object.hash(width, height);
  @override
  String toString() => 'VideoSize($width x $height)';
}

/// 播放器状态（语义对齐 pure_live PlayerState）。
enum PlayerState {
  idle,
  initializing,
  initialized,
  preparing,
  buffering,
  ready,
  playing,
  paused,
  completed,
  stopped,
  error,
  disposed,
}

/// 播放异常（语义对齐 pure_live PlayerException，UI 只读 [message]）。
class PlaybackException implements Exception {
  final String message;
  final String? code;
  final Object? error;
  final StackTrace? stackTrace;

  PlaybackException({
    required this.message,
    this.code,
    this.error,
    this.stackTrace,
  });

  @override
  String toString() => '[playback] $message';
}

/// Web 播放后端：一次 [open] 播一个流，事件经流回调给适配器。
///
/// 事件均为 broadcast 流；适配器侧用 session token 过滤旧后端的
/// 迟到事件（切源/切房 generation fence）。
abstract class WebPlayerBackend {
  /// 缓冲开始(true)/结束(false)。
  Stream<bool> get onBuffering;

  /// 开始/停止播放（video 元素 playing/pause 事件）。
  Stream<bool> get onPlaying;

  /// 流结束（ended）。
  Stream<bool> get onCompleted;

  /// 不可恢复错误消息（hls fatal / mpegts ERROR / video error / 不支持等）。
  Stream<String> get onError;

  /// 视频尺寸变化（loadedmetadata/resize）。
  Stream<VideoSize> get onSize;

  /// 打开流。[format] 为 'hls' | 'flv' | 'mpegts'；[mediaElement] 为
  /// 适配器创建的不透明视频元素引用（Web 上是 HTMLVideoElement）。
  Future<void> open(String url, {required String format, Object? mediaElement});

  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> setVolume(double volume);

  /// 销毁内核实例（hls.destroy / mpegts unload+detach+destroy）并清空 video。
  Future<void> dispose();
}

/// 渲染承载面：适配器 init 时创建一次，视频元素全生命周期复用。
abstract class WebVideoSurface {
  /// Flutter 侧渲染组件（Web 上是 HtmlElementView）。
  Widget buildWidget(BoxFit fit);

  /// 传给 [WebPlayerBackend.open] 的不透明媒体元素引用。
  Object? get mediaElement;

  Future<void> dispose();
}

/// 事件汇合基类：broadcast 控制器 + 当前值 + emit 助手。
abstract class WebPlayerBackendBase implements WebPlayerBackend {
  final _bufferingCtrl = StreamController<bool>.broadcast();
  final _playingCtrl = StreamController<bool>.broadcast();
  final _completedCtrl = StreamController<bool>.broadcast();
  final _errorCtrl = StreamController<String>.broadcast();
  final _sizeCtrl = StreamController<VideoSize>.broadcast();

  bool _closed = false;
  bool _isPlaying = false;

  @override
  Stream<bool> get onBuffering => _bufferingCtrl.stream;
  @override
  Stream<bool> get onPlaying => _playingCtrl.stream;
  @override
  Stream<bool> get onCompleted => _completedCtrl.stream;
  @override
  Stream<String> get onError => _errorCtrl.stream;
  @override
  Stream<VideoSize> get onSize => _sizeCtrl.stream;

  bool get isPlaying => _isPlaying;
  bool get isClosed => _closed;

  @protected
  void emitBuffering(bool value) {
    if (!_closed) _bufferingCtrl.add(value);
  }

  @protected
  void emitPlaying(bool value) {
    _isPlaying = value;
    if (!_closed) _playingCtrl.add(value);
  }

  @protected
  void emitCompleted(bool value) {
    if (!_closed) _completedCtrl.add(value);
  }

  @protected
  void emitError(String message) {
    if (!_closed) _errorCtrl.add(message);
  }

  @protected
  void emitSize(VideoSize size) {
    if (!_closed) _sizeCtrl.add(size);
  }

  /// 关闭全部事件流（子类 dispose 末尾调用；重复调用安全）。
  @protected
  Future<void> closeEventHub() async {
    if (_closed) return;
    _closed = true;
    await Future.wait([
      _bufferingCtrl.close(),
      _playingCtrl.close(),
      _completedCtrl.close(),
      _errorCtrl.close(),
      _sizeCtrl.close(),
    ]);
  }
}
