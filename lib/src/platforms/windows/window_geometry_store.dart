/// 窗口几何持久化:主窗口(尺寸/位置/maximized)+ PiP 小窗(横/竖两套几何)。
///
/// 对齐参考实现 pure_live 的 `WindowSizeController` / `WindowPipGeometry`
/// (见 purelive-upstream lib/common/services/settings/window_size_controller.dart)
/// 的**语义**:主窗口几何 + PiP 横竖两套几何各自记住,拖拽期间 debounce 落盘;
/// 但**不搬其 Hive / GetX 基建**,改用项目既有的 `SharedPreferencesAsync`
/// (与 `danmaku_settings_provider` 等同一口径),key 前缀 `zishu.` 避免冲突。
///
/// 所有读写都 try/catch 吞错:非桌面平台、VM 单测(未注册 shared_preferences
/// 平台实现)下静默降级——读回 null,写入丢弃,绝不抛异常。
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/widgets.dart' show Offset, Size;
import 'package:shared_preferences/shared_preferences.dart';

/// 一组窗口几何:尺寸 + 位置(+ 主窗口的最大化态)。
@immutable
class WindowGeometry {
  const WindowGeometry({
    required this.size,
    required this.position,
    this.maximized = false,
  });

  final Size size;
  final Offset position;

  /// 主窗口是否处于最大化;PiP 几何恒为 false(小窗不参与最大化)。
  final bool maximized;

  /// 尺寸/位置是否为可落盘的有效值(有限、非空)。
  bool get isValid => size.isFinite && !size.isEmpty && position.isFinite;
}

/// 窗口几何的落盘读写:主窗口 + PiP 横/竖两套。
class WindowGeometryStore {
  WindowGeometryStore({
    SharedPreferencesAsync? preferences,
    Duration? debounce,
  }) : _injectedPreferences = preferences,
       _debounce = debounce ?? const Duration(milliseconds: 500);

  /// 主窗口几何 key。
  static const String _kMainWidth = 'zishu.window.width';
  static const String _kMainHeight = 'zishu.window.height';
  static const String _kMainX = 'zishu.window.x';
  static const String _kMainY = 'zishu.window.y';
  static const String _kMainMaximized = 'zishu.window.maximized';

  /// PiP 小窗几何 key 前缀(横/竖各一套)。
  static const String _kPipLandscapePrefix = 'zishu.pip.landscape';
  static const String _kPipPortraitPrefix = 'zishu.pip.portrait';

  final SharedPreferencesAsync? _injectedPreferences;
  final Duration _debounce;

  Timer? _mainDebounceTimer;
  WindowGeometry? _pendingMain;

  /// 惰性取实例:构造函数在平台未注册时会抛 [StateError],故只在 try 内调用。
  SharedPreferencesAsync _prefs() =>
      _injectedPreferences ?? SharedPreferencesAsync();

  /// 读取主窗口几何;无存档或任一字段非法时返回 null。
  Future<WindowGeometry?> loadMainWindow() async {
    try {
      final prefs = _prefs();
      final width = await prefs.getDouble(_kMainWidth);
      final height = await prefs.getDouble(_kMainHeight);
      final x = await prefs.getDouble(_kMainX);
      final y = await prefs.getDouble(_kMainY);
      final maximized = await prefs.getBool(_kMainMaximized) ?? false;
      if (width == null || height == null || x == null || y == null) {
        return null;
      }
      final geometry = WindowGeometry(
        size: Size(width, height),
        position: Offset(x, y),
        maximized: maximized,
      );
      return geometry.isValid ? geometry : null;
    } catch (_) {
      return null;
    }
  }

  /// 主窗口几何延迟落盘:拖拽/缩放期间高频调用,只保留最后一次,500ms 后写盘。
  void saveMainWindowDebounced(WindowGeometry geometry) {
    if (!geometry.isValid) return;
    _pendingMain = geometry;
    _mainDebounceTimer?.cancel();
    _mainDebounceTimer = Timer(_debounce, () {
      _mainDebounceTimer = null;
      final pending = _pendingMain;
      _pendingMain = null;
      if (pending != null) {
        unawaited(_writeMainWindow(pending));
      }
    });
  }

  /// 立即把待写几何落盘(退出前 flush;无待写项时空操作)。
  Future<void> flush() async {
    _mainDebounceTimer?.cancel();
    _mainDebounceTimer = null;
    final pending = _pendingMain;
    _pendingMain = null;
    if (pending != null) {
      await _writeMainWindow(pending);
    }
  }

  /// 读取 PiP 小窗几何;[portrait] 为 true 取竖屏套,否则取横屏套。
  Future<WindowGeometry?> loadPip({required bool portrait}) async {
    try {
      final prefs = _prefs();
      final prefix = _pipPrefix(portrait);
      final width = await prefs.getDouble('$prefix.width');
      final height = await prefs.getDouble('$prefix.height');
      final x = await prefs.getDouble('$prefix.x');
      final y = await prefs.getDouble('$prefix.y');
      if (width == null || height == null || x == null || y == null) {
        return null;
      }
      final geometry = WindowGeometry(
        size: Size(width, height),
        position: Offset(x, y),
      );
      return geometry.isValid ? geometry : null;
    } catch (_) {
      return null;
    }
  }

  /// 写入 PiP 小窗几何(横/竖分套,size + position)。
  Future<void> savePip({
    required bool portrait,
    required WindowGeometry geometry,
  }) async {
    if (!geometry.isValid) return;
    try {
      final prefs = _prefs();
      final prefix = _pipPrefix(portrait);
      await prefs.setDouble('$prefix.width', geometry.size.width);
      await prefs.setDouble('$prefix.height', geometry.size.height);
      await prefs.setDouble('$prefix.x', geometry.position.dx);
      await prefs.setDouble('$prefix.y', geometry.position.dy);
    } catch (_) {
      // 存储不可用:内存态仍生效,下次进入回退默认几何。
    }
  }

  String _pipPrefix(bool portrait) =>
      portrait ? _kPipPortraitPrefix : _kPipLandscapePrefix;

  Future<void> _writeMainWindow(WindowGeometry geometry) async {
    try {
      final prefs = _prefs();
      await prefs.setDouble(_kMainWidth, geometry.size.width);
      await prefs.setDouble(_kMainHeight, geometry.size.height);
      await prefs.setDouble(_kMainX, geometry.position.dx);
      await prefs.setDouble(_kMainY, geometry.position.dy);
      await prefs.setBool(_kMainMaximized, geometry.maximized);
    } catch (_) {
      // 存储不可用:静默丢弃本次落盘。
    }
  }
}
