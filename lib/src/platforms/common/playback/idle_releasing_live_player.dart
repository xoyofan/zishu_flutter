import 'dart:async';

import 'package:flutter/widgets.dart' show BoxFit, SizedBox, Widget;
import 'package:live_parser/live_parser.dart' show StreamLine;

import 'live_player.dart';
import 'media_kit_live_player.dart';

/// 稳定播放器代理，通过活动房间租约管理 native 播放器生命周期。
class IdleReleasingLivePlayer implements LivePlayer, LineRecoveryAware {
  IdleReleasingLivePlayer({
    required LivePlayer Function() createPlayer,
    Future<void> Function(LivePlayer)? releasePlayer,
    this.idleDelay = const Duration(seconds: 20),
  }) : _create = createPlayer,
       _release =
           releasePlayer ??
           ((p) async {
             if (p is MediaKitLivePlayer) {
               await p.releaseNative();
             } else {
               p.dispose();
             }
           });
  final LivePlayer Function() _create;
  final Future<void> Function(LivePlayer) _release;
  final Duration idleDelay;
  LivePlayer? _inner;
  Timer? _timer;
  Future<void>? _disposing;
  Future<void>? _rootRelease;
  int _sequence = 0;
  int? _active;
  bool _closed = false;
  final _snapshots = StreamController<PlayerSnapshot>.broadcast();
  StreamSubscription<PlayerSnapshot>? _subscription;
  final _viewChanges = StreamController<int>.broadcast();
  LineRecoveryHandler? _recovery;
  int _viewGeneration = 0;

  Stream<int> get viewChanges => _viewChanges.stream;
  LineRecoveryHandler? get debugRecoveryHandler => _recovery;
  LivePlayer? get currentPlayer => _inner;
  int enterRoom() {
    if (_closed) throw StateError('Player entry is disposed');
    final token = ++_sequence;
    _active = token;
    _timer?.cancel();
    _timer = null;
    return token;
  }

  Future<void> leaveRoom(int token) async {
    if (_active != token || _closed) return;
    _active = null;
    final stopGeneration = token;
    await _inner?.stop();
    if (_closed || _active != null || stopGeneration != _sequence) return;
    _timer?.cancel();
    _timer = Timer(idleDelay, () {
      if (!_closed && _active == null) unawaited(_disposeIdle());
    });
  }

  Future<void> disposeAsync() => _rootRelease ??= _disposeRoot();

  Future<void> _disposeRoot() async {
    if (!_closed) {
      _closed = true;
      _active = null;
      _sequence++;
      _timer?.cancel();
      _timer = null;
      await _disposeIdle(force: true);
      await _disposing;
      await _viewChanges.close();
      await _snapshots.close();
    } else {
      await _disposing;
    }
  }

  Future<void> _disposeIdle({bool force = false}) {
    if ((!force && _closed) || _active != null) return Future<void>.value();
    final existingDisposal = _disposing;
    if (existingDisposal != null) return existingDisposal;
    final player = _inner;
    if (player == null) return Future<void>.value();
    _inner = null;
    final previous = _disposing;
    final releaseSequence = _sequence;
    final release = Completer<void>();
    _disposing = release.future;
    unawaited(_releaseIdlePlayer(player, releaseSequence, previous, release));
    return release.future;
  }

  Future<void> _releaseIdlePlayer(
    LivePlayer player,
    int releaseSequence,
    Future<void>? previous,
    Completer<void> release,
  ) async {
    try {
      if (previous != null) await previous;
      await _subscription?.cancel();
      _subscription = null;
      if (player case LineRecoveryAware aware) aware.setLineRecovery(null);
      if (releaseSequence == _sequence && _active == null) _recovery = null;
      _viewGeneration++;
      if (!_viewChanges.isClosed) _viewChanges.add(_viewGeneration);
      await _release(player);
      release.complete();
      if (!_closed && _active != null) await _getOrCreate();
    } catch (error, stack) {
      release.completeError(error, stack);
    } finally {
      if (identical(_disposing, release.future)) _disposing = null;
    }
  }

  Future<LivePlayer?> _getOrCreate() async {
    if (_closed || _active == null) return null;
    final token = _active;
    final disposing = _disposing;
    if (disposing != null) await disposing;
    if (_closed || token != _active || _active == null) return null;
    final existing = _inner;
    if (existing != null) return existing;
    final created = _create();
    if (_closed || token != _active) {
      await _release(created);
      return null;
    }
    _inner = created;
    final aware = created;
    if (aware case LineRecoveryAware recoveryAware) {
      if (_recovery != null) recoveryAware.setLineRecovery(_recovery);
    }
    _subscription = created.snapshots.listen((s) {
      if (!_snapshots.isClosed) _snapshots.add(s);
    });
    _viewGeneration++;
    if (!_viewChanges.isClosed) _viewChanges.add(_viewGeneration);
    if (!_snapshots.isClosed) _snapshots.add(const PlayerSnapshot());
    return created;
  }

  void clearLineRecovery(int token) {
    if (_active == token) setLineRecovery(null);
  }

  @override
  void setLineRecovery(LineRecoveryHandler? handler) {
    _recovery = handler;
    final player = _inner;
    if (player case LineRecoveryAware recoveryAware) {
      recoveryAware.setLineRecovery(handler);
    }
  }

  @override
  Stream<PlayerSnapshot> get snapshots => _snapshots.stream;
  @override
  Widget buildVideoView({BoxFit fit = BoxFit.contain}) =>
      _inner?.buildVideoView(fit: fit) ?? const SizedBox.shrink();
  @override
  Future<void> open(
    StreamLine line, [
    List<StreamLine> fallbacks = const [],
    bool resetRetries = true,
  ]) async => (await _getOrCreate())?.open(line, fallbacks, resetRetries);
  @override
  Future<void> stop() async {
    await _inner?.stop();
  }

  @override
  Future<void> play() async {
    await _inner?.play();
  }

  @override
  Future<void> pause() async {
    await _inner?.pause();
  }

  @override
  Future<void> setVolume(double volume) async {
    await _inner?.setVolume(volume);
  }

  @override
  Future<void> setMuted(bool muted) async {
    await _inner?.setMuted(muted);
  }

  @override
  Future<void> setFullscreen(bool fullscreen) async {
    await _inner?.setFullscreen(fullscreen);
  }

  @override
  Future<void> toggleFullscreen() async {
    await _inner?.toggleFullscreen();
  }

  @override
  Future<void> enterPictureInPicture({double? aspectRatio}) async {
    await _inner?.enterPictureInPicture(aspectRatio: aspectRatio);
  }

  @override
  Future<void> exitPictureInPicture() async {
    await _inner?.exitPictureInPicture();
  }

  @override
  Widget wrapPipSurface(Widget child) => _inner?.wrapPipSurface(child) ?? child;
  @override
  void dispose() {
    if (_closed) return;
    unawaited(disposeAsync());
  }
}
