/// 桌面窗口表现控制:系统窗口全屏 + 画中画(PiP)窗口。
///
/// 对齐参考实现 pure_live 的 `WindowService` / `WindowHelper`(见
/// pure_live lib/player/utils/window_helper.dart:94-199)的职责划分,并做两点简化:
/// - PiP 窗口定位只用 Flutter 的 `Display` 逻辑尺寸算右下角,不引入
///   `screen_retriever` 的多显示器 work-area 查询(zishu 当前单显示器优先);
/// - 全屏与 PiP 之间互斥,进出 PiP 时记住/恢复窗口 bounds 与置顶态。
///
/// 全部方法在非 Windows 平台静默空操作,且原生调用一律 try/catch 吞错:
/// 单元测试(VM)与 Web 端不会因插件缺失而抛错,UI 侧状态不依赖这些返回值。
library;

import 'dart:io';

import 'package:flutter/widgets.dart' show Offset, Size, WidgetsBinding;
import 'package:window_manager/window_manager.dart';

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

/// 窗口表现控制器:全屏与 PiP 的唯一去处。
class WindowPresentation {
  WindowPresentation();

  /// 默认单例:播放器实例与页面共用同一份窗口状态记忆。
  static final WindowPresentation instance = WindowPresentation();

  /// 正常窗口的最小尺寸(PiP 期间会临时解除限制才能缩小)。
  static const Size _normalMinimumSize = Size(800, 600);

  /// PiP 窗口长边尺寸。
  static const double _pipMaxSide = 360;

  /// 全屏切换防重入:桌面重复调用 `setFullScreen` 会让 Windows 侧边任务栏的
  /// work-area bounds 抖动(参考实现里明确记录过该现象)。
  bool _fullscreenTransitioning = false;

  bool _pip = false;
  _WindowBounds? _boundsBeforePip;

  /// 当前是否处于画中画窗口态。
  bool get isPip => _pip;

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
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) {
      return false;
    }
    try {
      return await windowManager.isFullScreen();
    } catch (_) {
      return false;
    }
  }

  /// 进入画中画:记住当前 bounds,解除最小尺寸限制,置顶并缩到屏幕右下角。
  /// [aspectRatio] 为视频宽高比(宽/高),非法时按 16:9。
  Future<void> enterPip({double? aspectRatio}) async {
    if (_pip || _fullscreenTransitioning) return;
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
      final horizontal = ratio >= 1;
      final size = horizontal
          ? Size(_pipMaxSide, _pipMaxSide / ratio)
          : Size(_pipMaxSide * ratio, _pipMaxSide);
      final screen = _primaryDisplayLogicalSize();
      const margin = 20.0;
      // 底部额外留出任务栏高度余量,避免小窗被任务栏压住。
      final left = (screen.width - size.width - margin).clamp(
        0.0,
        double.infinity,
      );
      final top = (screen.height - size.height - 60).clamp(
        0.0,
        double.infinity,
      );

      await windowManager.setMinimumSize(Size.zero);
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setSize(size);
      await windowManager.setPosition(Offset(left, top));
      _pip = true;
    } catch (_) {
      // 原生不可用:不进入 PiP 态,UI 侧读 isPip 为 false 自然回退。
      _boundsBeforePip = null;
    }
  }

  /// 退出画中画:恢复最小尺寸、置顶态与进入前的 bounds。
  Future<void> exitPip() async {
    if (!_pip) return;
    final saved = _boundsBeforePip;
    _pip = false;
    _boundsBeforePip = null;
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
