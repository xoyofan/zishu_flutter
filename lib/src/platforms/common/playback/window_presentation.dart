/// 桌面窗口表现控制:系统窗口全屏 + 画中画(PiP)窗口 + 窗口几何记忆。
///
/// 对齐参考实现 pure_live 的 `WindowService` / `WindowHelper`(见
/// purelive-upstream lib/player/utils/window_helper.dart:94-320)的职责划分,
/// 并做两点简化:
/// - PiP 定位只在主显示器逻辑尺寸内计算(单屏优先),不引入
///   `screen_retriever` 的多显示器 work-area 查询;
/// - 窗口几何(主窗口 + PiP 横/竖两套)统一落盘到 [WindowGeometryStore],
///   不搬参考实现的 Hive / GetX 基建。
///
/// 全屏与 PiP 互斥,进出 PiP 时记住/恢复窗口 bounds 与置顶态;PiP 小窗按视频
/// 宽高比分档定尺寸,并记住用户最后一次的小窗尺寸与位置。
///
/// 全部方法在非桌面平台静默空操作,且原生调用一律 try/catch 吞错:
/// 单元测试(VM)与 Web 端不会因插件缺失而抛错,UI 侧状态不依赖这些返回值。
///
/// **单一状态源**:窗口级呈现态(PiP 态与几何记忆)只在本类持有——播放器与
/// UI 都经由它,避免历史缺陷「UI 态与窗口态漂移」。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/widgets.dart' show Offset, Rect, Size, WidgetsBinding;
import 'package:window_manager/window_manager.dart';

import '../../windows/window_geometry_store.dart';

/// 进入 PiP 前的窗口快照,退出时据此还原。
class _WindowBounds {
  const _WindowBounds({
    required this.size,
    required this.position,
    required this.alwaysOnTop,
  });

  final Size size;
  final Offset position;
  final bool alwaysOnTop;
}

/// PiP 小窗长边尺寸:横屏 / 近方形 / 竖屏三档(参考实现同款分档)。
const double _pipMaxSideLandscape = 360;
const double _pipMaxSideSquare = 280;
const double _pipMaxSidePortrait = 380;

/// 竖屏小窗最小宽度:低于此值按宽度反推高度,避免极端竖屏把窗口压成细条。
const double _pipMinWidth = 140;

/// 小窗贴边内边距(右 / 下),越界回退到右下角时使用。
const double _pipMargin = 20;

/// 底部额外余量:主屏逻辑尺寸含任务栏,小窗贴底需再抬高,避免被任务栏压住。
const double _pipBottomMargin = 60;

/// 小窗钳制到屏内时允许的最小高度。
const double _pipMinHeight = 90;

/// 判定存档小窗"可见"所需的最小重叠边长(参考实现取 48)。
const double _pipVisibleOverlap = 48;

/// 按视频宽高比解析 PiP 小窗尺寸(纯函数,便于单测):
/// 横屏 `ratio > 1.05` 长边 360;竖屏 `ratio < 0.95` 长边 380,宽不足
/// `_pipMinWidth` 时反推 `w = 140, h = w / ratio`;近方形 `0.95..1.05` 长边 280。
/// 对齐参考实现 pure_live `WindowHelper.enterPiP`(window_helper.dart:110-140)。
@visibleForTesting
Size resolvePipSize(double ratio) {
  final safeRatio = ratio.isFinite && ratio > 0 ? ratio : 16 / 9;
  if (safeRatio > 1.05) {
    return Size(_pipMaxSideLandscape, _pipMaxSideLandscape / safeRatio);
  }
  if (safeRatio < 0.95) {
    var width = _pipMaxSidePortrait * safeRatio;
    if (width < _pipMinWidth) width = _pipMinWidth;
    return Size(width, width / safeRatio);
  }
  return safeRatio >= 1.0
      ? Size(_pipMaxSideSquare, _pipMaxSideSquare / safeRatio)
      : Size(_pipMaxSideSquare * safeRatio, _pipMaxSideSquare);
}

/// 在单屏区域内解析 PiP 目标 bounds(纯函数,便于单测):
/// 有存档且仍在屏内可见 → 用存档尺寸(钳制到屏内)与位置;无存档或越界 →
/// 用默认尺寸并贴右下角 [_pipMargin] 内边距(底部另留 [_pipBottomMargin] 余量)。
@visibleForTesting
Rect resolvePipBounds({
  required Size defaultSize,
  required Size screen,
  Rect? savedBounds,
}) {
  final area = screen.isFinite && !screen.isEmpty
      ? Rect.fromLTWH(0, 0, screen.width, screen.height)
      : const Rect.fromLTWH(0, 0, 1920, 1080);
  final minWidth = area.width < _pipMinWidth ? area.width : _pipMinWidth;
  final minHeight = area.height < _pipMinHeight ? area.height : _pipMinHeight;
  final saved = savedBounds != null && savedBounds.isFinite && !savedBounds.isEmpty
      ? savedBounds
      : null;
  final requested = saved?.size ?? defaultSize;
  final width = requested.width.clamp(minWidth, area.width).toDouble();
  final height = requested.height.clamp(minHeight, area.height).toDouble();

  final visibleSaved =
      saved != null && _isVisibleOnScreen(saved, area) ? saved : null;
  final anchorLeft = visibleSaved?.left ?? (area.right - width - _pipMargin);
  final anchorTop = visibleSaved?.top ?? (area.bottom - height - _pipBottomMargin);
  final left = anchorLeft.clamp(area.left, area.right - width).toDouble();
  final top = anchorTop.clamp(area.top, area.bottom - height).toDouble();
  return Rect.fromLTWH(left, top, width, height);
}

/// 存档矩形是否在屏内留有足够可见面积(重叠不足视为越界,回退默认位置)。
bool _isVisibleOnScreen(Rect rect, Rect area) {
  final overlap = rect.intersect(area);
  return overlap.width >= _pipVisibleOverlap &&
      overlap.height >= _pipVisibleOverlap;
}

/// 窗口表现控制器:全屏、PiP 与窗口几何记忆的唯一去处。
class WindowPresentation {
  WindowPresentation({WindowGeometryStore? geometryStore})
    : _geometryStore = geometryStore ?? WindowGeometryStore();

  /// 默认单例:播放器实例与页面共用同一份窗口状态记忆。
  static final WindowPresentation instance = WindowPresentation();

  /// 正常窗口的最小尺寸(PiP 期间会临时解除限制才能缩小)。
  static const Size _normalMinimumSize = Size(800, 600);

  /// 窗口几何落盘(主窗口 + PiP 横/竖两套)。
  final WindowGeometryStore _geometryStore;

  /// 全屏切换防重入:桌面重复调用 `setFullScreen` 会让 Windows 侧边任务栏的
  /// work-area bounds 抖动(参考实现里明确记录过该现象)。
  bool _fullscreenTransitioning = false;

  bool _pip = false;

  /// 当前 PiP 小窗归属的几何槽:竖屏(true)或横屏(false)。
  bool _pipPortrait = false;

  _WindowBounds? _boundsBeforePip;

  /// 当前是否处于画中画窗口态。
  bool get isPip => _pip;

  /// 当前平台是否有原生窗口管理器可用;否则全部窗口操作静默空操作。
  bool get _isDesktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  /// 幂等设置系统窗口全屏:目标态与当前窗口态一致时不发起原生调用。
  Future<void> setFullscreen(bool value) async {
    if (_fullscreenTransitioning) return;
    _fullscreenTransitioning = true;
    try {
      final current = await isSystemFullscreen();
      if (current == value) return;
      await windowManager.setFullScreen(value);
    } catch (_) {
      // 平台不支持 / 插件未就绪(VM、无窗口环境):静默降级。
    } finally {
      _fullscreenTransitioning = false;
    }
  }

  /// 兼容「切换」语义的调用点:按当前窗口态取反。
  Future<void> toggleFullscreen() async {
    final current = await isSystemFullscreen();
    await setFullscreen(!current);
  }

  /// 读取系统窗口全屏态;查询失败时按 false 处理(非桌面/未初始化)。
  Future<bool> isSystemFullscreen() async {
    if (!_isDesktop) {
      return false;
    }
    try {
      return await windowManager.isFullScreen();
    } catch (_) {
      return false;
    }
  }

  /// 进入画中画:记住当前 bounds,解除最小尺寸限制,置顶并缩到小窗。
  /// [aspectRatio] 为视频宽高比(宽/高),非法时按 16:9。
  ///
  /// 小窗尺寸按宽高比分档;位置优先复用上次记录的同向几何,越界或首次进入
  /// 时回退到屏幕右下角内边距。
  Future<void> enterPip({double? aspectRatio}) async {
    if (_pip || _fullscreenTransitioning || !_isDesktop) return;
    try {
      _boundsBeforePip = _WindowBounds(
        size: await windowManager.getSize(),
        position: await windowManager.getPosition(),
        alwaysOnTop: await windowManager.isAlwaysOnTop(),
      );
      // 先退出系统全屏再缩窗:全屏态下改尺寸会被窗口管理器忽略。
      if (await isSystemFullscreen()) {
        await windowManager.setFullScreen(false);
      }
      final ratio =
          (aspectRatio != null && aspectRatio.isFinite && aspectRatio > 0)
          ? aspectRatio
          : 16 / 9;
      final portrait = ratio < 0.95;
      final saved = await _geometryStore.loadPip(portrait: portrait);
      final bounds = resolvePipBounds(
        defaultSize: resolvePipSize(ratio),
        screen: _primaryDisplayLogicalSize(),
        savedBounds: saved == null
            ? null
            : Rect.fromLTWH(
                saved.position.dx,
                saved.position.dy,
                saved.size.width,
                saved.size.height,
              ),
      );

      await windowManager.setMinimumSize(Size.zero);
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setSize(bounds.size);
      await windowManager.setPosition(bounds.topLeft);
      _pip = true;
      _pipPortrait = portrait;
      // 记下本次解析出的几何:下次进入直接复用,用户后续拖动/缩放会覆盖它。
      await _geometryStore.savePip(
        portrait: portrait,
        geometry: WindowGeometry(size: bounds.size, position: bounds.topLeft),
      );
    } catch (_) {
      // 原生不可用:不进入 PiP 态,UI 侧读 isPip 为 false 自然回退。
      _boundsBeforePip = null;
      _pipPortrait = false;
    }
  }

  /// 退出画中画:先记下当前位置(下次进入复用),再恢复最小尺寸、置顶态与
  /// 进入前的 bounds。
  Future<void> exitPip() async {
    if (!_pip) return;
    final saved = _boundsBeforePip;
    final portrait = _pipPortrait;
    _pip = false;
    _boundsBeforePip = null;
    _pipPortrait = false;
    // 关闭前把当前位置记下;越界时下次进入由 resolvePipBounds 回退右下角。
    await _capturePipGeometry(portrait: portrait);
    try {
      await windowManager.setAlwaysOnTop(saved?.alwaysOnTop ?? false);
      await windowManager.setMinimumSize(_normalMinimumSize);
      if (saved != null) {
        await windowManager.setSize(saved.size);
        await windowManager.setPosition(saved.position);
      }
    } catch (_) {
      // 静默降级:窗口几何恢复失败不影响 UI 已经退出的 PiP 态。
    }
  }

  /// 窗口尺寸/位置/最大化落定后调用(由 app 壳转发原生窗口事件):
  /// PiP 态记小窗几何,否则记主窗口几何——后者拖拽期高频,走 500ms debounce。
  void scheduleGeometryCapture() {
    if (!_isDesktop) return;
    if (_pip) {
      unawaited(_capturePipGeometry(portrait: _pipPortrait));
    } else {
      unawaited(_captureMainWindow());
    }
  }

  /// 启动时恢复上一步保存的主窗口几何;无存档 / 平台不支持时空操作。
  Future<void> restoreMainWindowGeometry() async {
    if (!_isDesktop) return;
    try {
      final saved = await _geometryStore.loadMainWindow();
      if (saved == null) return;
      if (saved.maximized) {
        await windowManager.maximize();
        return;
      }
      // 单屏优先:把存档位置钳回首屏,避免显示器变化后窗口落到屏外找不回。
      final screen = _primaryDisplayLogicalSize();
      final maxLeft = (screen.width - saved.size.width).clamp(
        0.0,
        double.infinity,
      );
      final maxTop = (screen.height - saved.size.height).clamp(
        0.0,
        double.infinity,
      );
      final left = saved.position.dx.clamp(0.0, maxLeft).toDouble();
      final top = saved.position.dy.clamp(0.0, maxTop).toDouble();
      await windowManager.setSize(saved.size);
      await windowManager.setPosition(Offset(left, top));
    } catch (_) {
      // 无窗口环境 / 存储不可用:静默忽略。
    }
  }

  /// 退出前 flush:把 debounce 未触发的最后一次主窗口几何立即落盘。
  Future<void> flushGeometry() => _geometryStore.flush();

  /// 记录 PiP 小窗当前尺寸与位置(移动/缩放落定、关闭时调用)。
  Future<void> _capturePipGeometry({required bool portrait}) async {
    try {
      final size = await windowManager.getSize();
      final position = await windowManager.getPosition();
      await _geometryStore.savePip(
        portrait: portrait,
        geometry: WindowGeometry(size: size, position: position),
      );
    } catch (_) {
      // 无窗口环境:静默忽略。
    }
  }

  /// 记录主窗口当前几何;全屏态不记(全屏尺寸不是"正常"窗口几何)。
  Future<void> _captureMainWindow() async {
    try {
      if (await isSystemFullscreen()) return;
      final maximized = await windowManager.isMaximized();
      final size = await windowManager.getSize();
      final position = await windowManager.getPosition();
      _geometryStore.saveMainWindowDebounced(
        WindowGeometry(size: size, position: position, maximized: maximized),
      );
    } catch (_) {
      // 无窗口环境:静默忽略。
    }
  }

  /// 主显示器逻辑尺寸(物理像素 ÷ dpr);拿不到时退回 1920×1080。
  Size _primaryDisplayLogicalSize() {
    try {
      final views = WidgetsBinding.instance.platformDispatcher.views;
      if (views.isEmpty) return const Size(1920, 1080);
      final display = views.first.display;
      final dpr = display.devicePixelRatio == 0
          ? 1.0
          : display.devicePixelRatio;
      final size = Size(display.size.width / dpr, display.size.height / dpr);
      if (!size.isFinite || size.isEmpty) return const Size(1920, 1080);
      return size;
    } catch (_) {
      return const Size(1920, 1080);
    }
  }
}
