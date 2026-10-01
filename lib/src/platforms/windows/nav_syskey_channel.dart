/// Alt+方向键系统级兜底通道(仅 Windows runner 下发)。
///
/// ## 为什么需要(2026-09-30 键盘注入实验定性)
///
/// 鼠标手势软件回放的 Alt+←/→/Home 到不了 framework 快捷键层:
/// - 队列注入(SendInput/keybd_event):引擎在注入的 Alt keydown 之后立刻
///   合成一个 keyup(物理键并未真的按住),80ms 后到达的 ArrowLeft 修饰已丢,
///   `SingleActivator(arrowLeft, alt: true)` 匹配失败 —— 实测注入序列在
///   framework 侧变成 `Alt down → Alt up(合成) → Arrow Left(无修饰)`;
/// - PostMessage 直投顶层窗口:消息进了 wndproc,但引擎不向 framework 派发,
///   framework 侧零事件。
///
/// 三种形态(真实按键/队列注入/直投)在 lParam 里都带 `KF_ALTDOWN` 上下文位,
/// runner 的 `flutter_window.cpp` 在消息层识别后经本通道下发 `back` /
/// `forward` / `home`,并消费掉原始消息 —— 真实按键与注入共用同一条单路径,
/// 不会双触发;CallbackShortcuts 里的 Alt 绑定在 Windows 上退为兼容兜底。
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, VoidCallback;
import 'package:flutter/services.dart';

const MethodChannel _navSyskeyChannel =
    MethodChannel('zishu/windows/nav_syskey');

/// 挂接 runner 下发的导航键消息;非 Windows/Web 返回 null(无清理动作)。
///
/// 返回的清理函数随调用方 dispose 执行,解除 handler 防泄漏。
VoidCallback? installNavSyskeyChannel({
  required VoidCallback onBack,
  required VoidCallback onForward,
  required VoidCallback onHome,
}) {
  if (kIsWeb || !Platform.isWindows) return null;
  _navSyskeyChannel.setMethodCallHandler((call) async {
    switch (call.method) {
      case 'back':
        onBack();
      case 'forward':
        onForward();
      case 'home':
        onHome();
    }
    return null;
  });
  return () => _navSyskeyChannel.setMethodCallHandler(null);
}
