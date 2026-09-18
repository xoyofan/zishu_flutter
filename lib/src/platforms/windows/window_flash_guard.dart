/// 系统全屏切换的「防闪窗」保护(仅 Windows,FFI 直调 user32/dwmapi)。
///
/// ## 为什么需要:window_manager 0.4.3 的 SetFullScreen 不是原子操作
///
/// 插件源码(pub cache `window_manager-0.4.3/windows/window_manager.cpp:568`
/// 起)的进全屏时序:
/// 1. `SendMessage(WM_SYSCOMMAND, SC_MAXIMIZE, 0)` —— 先带边框最大化,任务栏
///    区域此刻仍露出,且触发 DWM 最大化动画;
/// 2. `SetWindowLongPtr(GWL_STYLE)` 去掉 WS_OVERLAPPEDWINDOW;
/// 3. `SetWindowPos(..., SWP_FRAMECHANGED)` 铺满显示器。
/// 第 1 步与第 2/3 步之间隔着完整一帧上屏,窗口尺寸/边框各变一次,中间帧直接
/// 露出桌面与背面窗口。
///
/// 插件 Dart 侧(`window_manager-0.4.3/lib/src/window_manager.dart:259`)在
/// 原生调用返回后还做 `setSize(+1px)` → `setSize` 的强制刷新抖动,再补两帧。
///
/// 退出方向的时序(同文件 else 分支):先 `PostMessage(SC_RESTORE)`(**异步**,
/// 排队等消息循环消费)、再重加边框样式并 `SWP_FRAMECHANGED`(标题栏会在满屏
/// 尺寸上闪现一帧),随后窗口才恢复原 bounds;若进全屏前是最大化态,还会再
/// `PostMessage(SC_MAXIMIZE)` 重播一次最大化动画。
///
/// 插件源码在 pub cache 内不可修改;直接绕过插件自管时序又会让插件内部
/// `g_is_window_fullscreen` 状态漂移(isFullScreen()/WM_SIZE 事件/enterPip 都
/// 依赖它)。因此选择在**调用侧**把上述多步变形包进一个「不重绘 + 无动画」
/// 的窗口期:
///
/// 1. `WM_SETREDRAW(FALSE)`:锁期间主窗口停止重绘,DWM 对窗口变形只拉伸呈现
///    旧帧——窗口与屏幕的遮挡关系不变,不会露出桌面/背面内容;
/// 2. `DwmSetWindowAttribute(DWMWA_TRANSITIONS_FORCEDISABLED)`:禁掉最小化/
///    最大化动画,让 SC_MAXIMIZE / SC_RESTORE 变成硬切(退出方向异步排队的
///    恢复消息同样被覆盖);
/// 3. 结束后按 MSDN 惯例 `WM_SETREDRAW(TRUE)` + `RedrawWindow`(帧 + 非客户区 +
///    全部子窗口,同步立即更新),确保解锁后立刻呈现目标帧,不留旧帧。
///
/// 退出方向的原生恢复是 PostMessage 异步消息,解锁前给消息循环一小段
/// (`_nativeSettleDelay`,120ms)时间把排队消息消费掉,避免恢复动作在解锁后才可见。
///
/// 全部原生调用 try/catch 吞错;拿不到主窗口 HWND(VM 单测 / 非标准 runner /
/// 焦点与查找均落空)时退化为直接执行目标操作,行为与不加锁完全一致。
/// 单元测试(VM)不会因本文件的存在而触达真实窗口。
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// 退出方向原生恢复(PostMessage 的 SC_RESTORE)的落定余量:动画已禁用,
/// 恢复本身瞬时完成,这段只是给消息循环消费排队消息的余量。
const Duration _nativeSettleDelay = Duration(milliseconds: 120);

/// 把 [body](一次完整的窗口全屏原生变形)包进防闪窗窗口期执行。
///
/// [waitForNativeSettle] 用于**退出全屏**方向:插件用 PostMessage 异步恢复
/// 窗口,解锁前等消息循环消费完排队消息,避免恢复中间帧在解锁后仍然可见。
///
/// 任何环境不满足(非 Windows / 原生符号缺失 / 找不到本进程主窗口)都直接
/// 执行 [body],不抛异常、不改变既有行为。
Future<T> flashFreeWindowTransition<T>(
  Future<T> Function() body, {
  bool waitForNativeSettle = false,
}) async {
  if (!Platform.isWindows) {
    return body();
  }
  final guard = _FullscreenFlashGuard.resolve();
  if (guard == null) {
    return body();
  }
  return guard.run(body, waitForNativeSettle: waitForNativeSettle);
}

/// 一次性的原生绑定 + HWND 解析结果:resolve 成功才值得加锁。
class _FullscreenFlashGuard {
  _FullscreenFlashGuard._({
    required this.hwnd,
    required this.sendMessageW,
    required this.redrawWindow,
    this.dwmSetWindowAttribute,
  });

  /// 解析原生符号并定位本进程主窗口;任一必要环节缺失返回 null(不加锁)。
  static _FullscreenFlashGuard? resolve() {
    try {
      final user32 = DynamicLibrary.open('user32.dll');
      final kernel32 = DynamicLibrary.open('kernel32.dll');

      final sendMessageW = user32
          .lookupFunction<_SendMessageWNative, _SendMessageWDart>(
            'SendMessageW',
          );
      final redrawWindow = user32
          .lookupFunction<_RedrawWindowNative, _RedrawWindowDart>(
            'RedrawWindow',
          );
      final getForegroundWindow = user32
          .lookupFunction<_GetForegroundWindowNative, _GetForegroundWindowDart>(
            'GetForegroundWindow',
          );
      final getAncestor = user32
          .lookupFunction<_GetAncestorNative, _GetAncestorDart>('GetAncestor');
      final getWindowThreadProcessId = user32
          .lookupFunction<_GetWindowThreadProcessIdNative,
              _GetWindowThreadProcessIdDart>('GetWindowThreadProcessId');
      final getCurrentProcessId = kernel32
          .lookupFunction<_GetCurrentProcessIdNative, _GetCurrentProcessIdDart>(
            'GetCurrentProcessId',
          );

      // FindWindowW / DwmSetWindowAttribute 属于增强项:缺失只降级对应能力。
      _FindWindowWDart? findWindowW;
      try {
        findWindowW = user32
            .lookupFunction<_FindWindowWNative, _FindWindowWDart>(
              'FindWindowW',
            );
      } catch (_) {
        // 找不到符号时跳过类名兜底查找。
      }
      _DwmSetWindowAttributeDart? dwmSetWindowAttribute;
      try {
        dwmSetWindowAttribute = DynamicLibrary.open('dwmapi.dll')
            .lookupFunction<_DwmSetWindowAttributeNative,
                _DwmSetWindowAttributeDart>('DwmSetWindowAttribute');
      } catch (_) {
        // 无 dwmapi(极旧系统):只锁重绘,不禁 DWM 动画。
      }

      final hwnd = _resolveMainWindowHwnd(
        getForegroundWindow: getForegroundWindow,
        getAncestor: getAncestor,
        getWindowThreadProcessId: getWindowThreadProcessId,
        getCurrentProcessId: getCurrentProcessId,
        findWindowW: findWindowW,
      );
      if (hwnd == 0) {
        return null;
      }
      return _FullscreenFlashGuard._(
        hwnd: hwnd,
        sendMessageW: sendMessageW,
        redrawWindow: redrawWindow,
        dwmSetWindowAttribute: dwmSetWindowAttribute,
      );
    } catch (_) {
      // 原生环境不符合预期(VM 单测 / 插件环境异常):不加锁。
      return null;
    }
  }

  /// 解析**本进程**主窗口 HWND(运行在平台线程的 Dart 可以直接操作它):
  /// 1) 前台窗口的根窗口属于本进程 —— 用户按 F / 点全屏按钮时几乎总是命中;
  /// 2) 退而按 Flutter runner 注册类名 `FLUTTER_RUNNER_WIN32_WINDOW` 查找
  ///    (覆盖焦点暂在本进程其它弹窗的场景)。
  /// 两条路径都做 pid 校验,防止在 VM 单测 / 多实例环境误伤无关窗口。
  static int _resolveMainWindowHwnd({
    required _GetForegroundWindowDart getForegroundWindow,
    required _GetAncestorDart getAncestor,
    required _GetWindowThreadProcessIdDart getWindowThreadProcessId,
    required _GetCurrentProcessIdDart getCurrentProcessId,
    required _FindWindowWDart? findWindowW,
  }) {
    bool belongsToCurrentProcess(int hwnd) {
      final pid = calloc<Uint32>();
      try {
        getWindowThreadProcessId(hwnd, pid);
        final windowPid = pid.value;
        return windowPid != 0 && windowPid == getCurrentProcessId();
      } finally {
        calloc.free(pid);
      }
    }

    // 路径 1:前台窗口的根窗口。
    final foreground = getForegroundWindow();
    if (foreground != 0) {
      final root = getAncestor(foreground, _gaRoot);
      if (root != 0 && belongsToCurrentProcess(root)) {
        return root;
      }
    }

    // 路径 2:按 runner 窗口类名查找(Flutter 模板注册的顶层窗口类)。
    final finder = findWindowW;
    if (finder != null) {
      final className = _runnerWindowClassName.toNativeUtf16();
      try {
        final found = finder(className.cast<Uint16>(), nullptr);
        if (found != 0 && belongsToCurrentProcess(found)) {
          return found;
        }
      } finally {
        calloc.free(className);
      }
    }
    return 0;
  }

  /// 锁期间不重绘;返回 false 表示锁未建立(调用方直接跳过解锁)。
  bool _suppressVisualUpdates() {
    var locked = false;
    try {
      sendMessageW(hwnd, _wmSetRedraw, 0, 0);
      locked = true;
    } catch (_) {
      // SendMessage 对本线程窗口不应失败;失败则不加锁,保持既有行为。
    }
    if (locked) {
      _setDwmTransitionsDisabled(true);
    }
    return locked;
  }

  /// 解锁并强制整窗同步重绘(顺序按 MSDN 惯例:先恢复重绘,再 RedrawWindow)。
  void _restoreVisualUpdates() {
    try {
      sendMessageW(hwnd, _wmSetRedraw, 1, 0);
      // 帧 + 擦背景 + 非客户区 + 全部子窗口,并立即同步更新(不上屏队列):
      // 不带 RDW_UPDATENOW 时首帧可能要等下一次消息循环才出现,解锁瞬间会闪旧帧。
      redrawWindow(hwnd, nullptr, 0, _redrawFlags);
    } catch (_) {
      // 解锁失败仅影响本轮观感,不向上抛。
    }
    _setDwmTransitionsDisabled(false);
  }

  void _setDwmTransitionsDisabled(bool disabled) {
    final dwm = dwmSetWindowAttribute;
    if (dwm == null) {
      return;
    }
    final value = calloc<Int32>()..value = disabled ? 1 : 0;
    try {
      dwm(hwnd, _dwmwaTransitionsDisabled, value, sizeOf<Int32>());
    } catch (_) {
      // DWM 调用失败:跳过动画禁用,重绘锁仍然有效。
    } finally {
      calloc.free(value);
    }
  }

  /// 锁内执行 [body]:期间窗口不重绘、无最小化/最大化动画。
  Future<T> run<T>(
    Future<T> Function() body, {
    required bool waitForNativeSettle,
  }) async {
    final suppressed = _suppressVisualUpdates();
    try {
      final result = await body();
      if (suppressed && waitForNativeSettle) {
        // 退出方向:等消息循环消费插件 PostMessage 的异步恢复消息后再解锁,
        // 否则恢复中间帧(标题栏在满屏尺寸上、恢复动画)会在解锁后冒出来。
        await Future<void>.delayed(_nativeSettleDelay);
      }
      return result;
    } finally {
      if (suppressed) {
        _restoreVisualUpdates();
      }
    }
  }

  /// 目标主窗口 HWND(已做本进程 pid 校验)。
  final int hwnd;

  final _SendMessageWDart sendMessageW;
  final _RedrawWindowDart redrawWindow;

  /// 可空:dwmap 不可用时仅跳过 DWM 动画禁用。
  final _DwmSetWindowAttributeDart? dwmSetWindowAttribute;
}

/// Win32 常量(winuser.h / dwmapi.h)与 Flutter runner 的窗口类名。
const int _wmSetRedraw = 0x000B;
const int _gaRoot = 2;
const int _dwmwaTransitionsDisabled = 3;

/// RedrawWindow 标志组合:重绘帧 | 擦背景 | 全部子窗口 | 立即同步更新 | 非客户区。
const int _redrawFlags = 0x0001 | 0x0004 | 0x0080 | 0x0100 | 0x0400;

/// Flutter Windows runner 注册的顶层窗口类名(windows/runner/win32_window.cpp)。
const String _runnerWindowClassName = 'FLUTTER_RUNNER_WIN32_WINDOW';

typedef _FindWindowWNative = IntPtr Function(
  Pointer<Uint16> className,
  Pointer<Uint16> title,
);
typedef _FindWindowWDart = int Function(
  Pointer<Uint16> className,
  Pointer<Uint16> title,
);
typedef _GetForegroundWindowNative = IntPtr Function();
typedef _GetForegroundWindowDart = int Function();
typedef _GetAncestorNative = IntPtr Function(IntPtr hwnd, Uint32 flags);
typedef _GetAncestorDart = int Function(int hwnd, int flags);
typedef _GetWindowThreadProcessIdNative = Uint32 Function(
  IntPtr hwnd,
  Pointer<Uint32> processId,
);
typedef _GetWindowThreadProcessIdDart = int Function(
  int hwnd,
  Pointer<Uint32> processId,
);
typedef _GetCurrentProcessIdNative = Uint32 Function();
typedef _GetCurrentProcessIdDart = int Function();
typedef _SendMessageWNative = IntPtr Function(
  IntPtr hwnd,
  Uint32 message,
  IntPtr wparam,
  IntPtr lparam,
);
typedef _SendMessageWDart = int Function(
  int hwnd,
  int message,
  int wparam,
  int lparam,
);
typedef _RedrawWindowNative = Int32 Function(
  IntPtr hwnd,
  Pointer<Void> updateRect,
  IntPtr updateRegion,
  Uint32 flags,
);
typedef _RedrawWindowDart = int Function(
  int hwnd,
  Pointer<Void> updateRect,
  int updateRegion,
  int flags,
);
typedef _DwmSetWindowAttributeNative = Int32 Function(
  IntPtr hwnd,
  Int32 attribute,
  Pointer<Int32> value,
  Int32 valueSize,
);
typedef _DwmSetWindowAttributeDart = int Function(
  int hwnd,
  int attribute,
  Pointer<Int32> value,
  int valueSize,
);
