# -*- coding: utf-8 -*-
"""_smoke.py — Windows release 真实 smoke 驱动(临时工具,不提交)。

用法(窗口先 move 0 0 <w> <h>,使截图坐标==屏幕坐标):
  py tool/_smoke.py move 0 0 1400 900      移动窗口到指定位置尺寸
  py tool/_smoke.py shot out.png           PrintWindow 截图
  py tool/_smoke.py click x y [times]      真实鼠标点击(1)或双击(2),截图坐标系
  py tool/_smoke.py key esc                单键: esc/left/right/f/f11
  py tool/_smoke.py hot alt+left           组合键
  py tool/_smoke.py drag x1 y1 x2 y2       拖动(音量 slider)
  py tool/_smoke.py state                  窗口状态
坐标一律为窗口表面(截图)坐标;窗口位于 (0,0) 时即屏幕坐标。
"""
import ctypes
import sys
import time

sys.path.insert(0, "tool")
import win_tool as W  # noqa: E402

u = W.u


def _ensure_visible():
    if u.IsIconic(W.find_hwnd()):
        u.ShowWindow(W.find_hwnd(), 9)
        time.sleep(0.4)


def _focus():
    hwnd = W.find_hwnd()
    SWP_NOSIZE, SWP_NOMOVE, SWP_SHOWWINDOW = 0x1, 0x2, 0x40
    u.SetWindowPos(hwnd, -1, 0, 0, 0, 0, SWP_NOSIZE | SWP_NOMOVE | SWP_SHOWWINDOW)
    u.SetForegroundWindow(hwnd)
    time.sleep(0.35)
    return hwnd


def _unfocus():
    hwnd = W.find_hwnd()
    SWP_NOSIZE, SWP_NOMOVE, SWP_SHOWWINDOW = 0x1, 0x2, 0x40
    u.SetWindowPos(hwnd, -2, 0, 0, 0, 0, SWP_NOSIZE | SWP_NOMOVE | SWP_SHOWWINDOW)
    time.sleep(0.2)


def _click(x, y):
    import pyautogui
    pyautogui.FAILSAFE = False
    _ensure_visible()
    _focus()
    pyautogui.click(x, y)
    time.sleep(0.25)
    _unfocus()


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    cmd = sys.argv[1]
    if cmd == "move":
        x, y, w, h = map(int, sys.argv[2:6])
        hwnd = W.find_hwnd()
        if u.IsIconic(hwnd):
            u.ShowWindow(hwnd, 9)
            time.sleep(0.4)
        u.MoveWindow(hwnd, x, y, w, h, True)
        time.sleep(0.5)
        print(f"OK move {x},{y} {w}x{h}")
        return
    if cmd == "shot":
        W.shot(W.find_hwnd(), sys.argv[2])
        return
    if cmd == "click":
        x, y = int(sys.argv[2]), int(sys.argv[3])
        times = int(sys.argv[4]) if len(sys.argv) > 4 else 1
        for _ in range(times):
            _click(x, y)
        print(f"OK click x{times} {x},{y}")
        return
    if cmd == "key":
        import pyautogui
        pyautogui.FAILSAFE = False
        _ensure_visible()
        _focus()
        k = sys.argv[2].lower()
        m = {"esc": "esc", "left": "left", "right": "right", "f11": "f11",
             "space": "space", "enter": "enter", "up": "up", "down": "down"}
        pyautogui.press(m.get(k, k))
        time.sleep(0.25)
        _unfocus()
        print(f"OK key {k}")
        return
    if cmd == "hot":
        import pyautogui
        pyautogui.FAILSAFE = False
        _ensure_visible()
        _focus()
        parts = [p.strip().lower() for p in sys.argv[2].split("+")]
        pyautogui.hotkey(*parts)
        time.sleep(0.25)
        _unfocus()
        print(f"OK hotkey {sys.argv[2]}")
        return
    if cmd == "drag":
        import pyautogui
        pyautogui.FAILSAFE = False
        x1, y1, x2, y2 = map(int, sys.argv[2:6])
        _ensure_visible()
        _focus()
        pyautogui.moveTo(x1, y1)
        pyautogui.mouseDown()
        time.sleep(0.1)
        pyautogui.moveTo(x2, y2, duration=0.3)
        pyautogui.mouseUp()
        time.sleep(0.2)
        _unfocus()
        print(f"OK drag ({x1},{y1})->({x2},{y2})")
        return
    if cmd == "state":
        W.state_cmd() if hasattr(W, "state_cmd") else None
        hwnd = W.find_hwnd()
        r = W.RECT()
        u.GetWindowRect(hwnd, ctypes.byref(r))
        print(f"iconic={bool(u.IsIconic(hwnd))} rect=({r.left},{r.top},{r.right},{r.bottom})")
        return
    print("UNKNOWN_CMD " + cmd)
    sys.exit(1)


if __name__ == "__main__":
    main()
