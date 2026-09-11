# -*- coding: utf-8 -*-
"""win_tool.py — zishu_flutter 手动验收辅助(零编译,纯标准库 + PIL/pyautogui)。

用法:
  py tool/win_tool.py shot <out.png>            PrintWindow 抓主窗口(PW_RENDERFULLCONTENT)
  py tool/win_tool.py shotdesktop <out.png>     BitBlt 屏幕区域兜底(窗口需在可见桌面)
  py tool/win_tool.py move <x> <y> <w> <h>      移动/缩放主窗口
  py tool/win_tool.py click <x> <y>             点击屏幕绝对坐标(先置前台)
窗口定位:FindWindowW(None, "zishu_flutter"),找不到则报 NO_WINDOW。
"""

import ctypes
import sys
import time

from PIL import Image

u = ctypes.windll.user32
g32 = ctypes.windll.gdi32
u.SetProcessDPIAware()

PW_RENDERFULLCONTENT = 2
WINDOW_TITLE = "zishu_flutter"


class RECT(ctypes.Structure):
    _fields_ = [("left", ctypes.c_long), ("top", ctypes.c_long),
                ("right", ctypes.c_long), ("bottom", ctypes.c_long)]


WINDOW_CLASS = "FLUTTER_RUNNER_WIN32_WINDOW"  # Flutter Windows 嵌入器专属类名
WINDOW_TITLE = "zishu_flutter"


def find_hwnd():
    """枚举顶层窗口,按 Flutter 专属类名匹配(避免同名标题的其它窗口,
    如名为 zishu_flutter 的资源管理器窗),取面积最大的可见者。"""
    best = [0, 0]  # hwnd, area

    @ctypes.WINFUNCTYPE(ctypes.c_bool, ctypes.c_void_p, ctypes.c_void_p)
    def cb(hwnd, _lparam):
        cls = ctypes.create_unicode_buffer(64)
        u.GetClassNameW(hwnd, cls, 64)
        if cls.value != WINDOW_CLASS or not u.IsWindowVisible(hwnd):
            return True
        r = RECT()
        u.GetWindowRect(hwnd, ctypes.byref(r))
        area = (r.right - r.left) * (r.bottom - r.top)
        if area > best[1]:
            best[0], best[1] = hwnd, area
        return True

    u.EnumWindows(cb, None)
    if not best[0]:
        print("NO_WINDOW")
        sys.exit(3)
    return best[0]


def shot(hwnd, path, desktop=False):
    r = RECT()
    if not u.GetWindowRect(hwnd, ctypes.byref(r)):
        print("GET_RECT_FAIL")
        sys.exit(4)
    w, h = r.right - r.left, r.bottom - r.top
    if w <= 0 or h <= 0:
        print("BAD_RECT")
        sys.exit(4)
    img = Image.new("RGB", (w, h), "black")
    # 手动管理 DC:PIL 的 ImageWin 不便用于 PrintWindow,直接走 GDI。
    hdc_dst = u.GetDC(0)
    mem = g32.CreateCompatibleDC(hdc_dst)
    bm = g32.CreateCompatibleBitmap(hdc_dst, w, h)
    g32.SelectObject(mem, bm)
    ok = False
    if desktop:
        screen = u.GetDC(0)
        g32.BitBlt(mem, 0, 0, w, h, screen, r.left, r.top, 0x00CC0020)
        u.ReleaseDC(0, screen)
        ok = True
    else:
        ok = bool(u.PrintWindow(hwnd, mem, PW_RENDERFULLCONTENT))
    # GetDIBits 取回 BGRA 像素(自底向上),交给 PIL 转 PNG。
    class BMIH(ctypes.Structure):
        _fields_ = [("biSize", ctypes.c_uint32), ("biWidth", ctypes.c_int32),
                    ("biHeight", ctypes.c_int32), ("biPlanes", ctypes.c_uint16),
                    ("biBitCount", ctypes.c_uint16), ("biCompression", ctypes.c_uint32),
                    ("biSizeImage", ctypes.c_uint32), ("biXPelsPerMeter", ctypes.c_int32),
                    ("biYPelsPerMeter", ctypes.c_int32), ("biClrUsed", ctypes.c_uint32),
                    ("biClrImportant", ctypes.c_uint32)]
    bih = BMIH()
    bih.biSize = ctypes.sizeof(BMIH)
    bih.biWidth = w
    bih.biHeight = -h  # top-down
    bih.biPlanes = 1
    bih.biBitCount = 32
    bih.biCompression = 0  # BI_RGB
    buf = ctypes.create_string_buffer(w * h * 4)
    got = g32.GetDIBits(mem, bm, 0, h, buf, ctypes.byref(bih), 0)
    g32.DeleteObject(bm)
    g32.DeleteDC(mem)
    u.ReleaseDC(0, hdc_dst)
    if not got:
        print("GET_DIBITS_FAIL")
        sys.exit(5)
    raw = buf.raw
    # BGRA → RGB
    rgb = bytearray(w * h * 3)
    for i in range(w * h):
        rgb[i * 3] = raw[i * 4 + 2]
        rgb[i * 3 + 1] = raw[i * 4 + 1]
        rgb[i * 3 + 2] = raw[i * 4]
    img.putdata([(rgb[i * 3], rgb[i * 3 + 1], rgb[i * 3 + 2]) for i in range(w * h)])
    img.save(path)
    print(f"OK {w}x{h} {path} printwindow={not desktop} printok={ok}")


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    cmd = sys.argv[1]
    hwnd = find_hwnd()
    if cmd == "shot":
        shot(hwnd, sys.argv[2], desktop=(len(sys.argv) > 3 and sys.argv[3] == "desktop"))
    elif cmd == "shotdesktop":
        shot(hwnd, sys.argv[2], desktop=True)
    elif cmd == "move":
        x, y, w, h = map(int, sys.argv[2:6])
        u.MoveWindow(hwnd, x, y, w, h, True)
        time.sleep(0.3)
        print(f"OK move {x},{y} {w}x{h}")
    elif cmd == "click":
        x, y = int(sys.argv[2]), int(sys.argv[3])
        import pyautogui
        pyautogui.FAILSAFE = False
        if u.IsIconic(hwnd):
            u.ShowWindow(hwnd, 9)  # SW_RESTORE
            time.sleep(0.4)
        # 后台进程的 SetForegroundWindow 会被 Windows 拒绝(防抢焦点),
        # 点击会落进更上层的窗口(实测打进了 Chrome)。先用 TOPMOST 置顶
        # 绕过 z-order 问题,点完还原,不长期霸占置顶。
        SWP_NOSIZE, SWP_NOMOVE, SWP_SHOWWINDOW = 0x1, 0x2, 0x40
        u.SetWindowPos(hwnd, -1, 0, 0, 0, 0,  # HWND_TOPMOST
                       SWP_NOSIZE | SWP_NOMOVE | SWP_SHOWWINDOW)
        u.SetForegroundWindow(hwnd)
        time.sleep(0.35)
        pyautogui.click(x, y)
        time.sleep(0.25)
        u.SetWindowPos(hwnd, -2, 0, 0, 0, 0,  # HWND_NOTOPMOST
                       SWP_NOSIZE | SWP_NOMOVE | SWP_SHOWWINDOW)
        print(f"OK click {x},{y}")
    elif cmd == "restore":
        if u.IsIconic(hwnd):
            u.ShowWindow(hwnd, 9)
        u.SetForegroundWindow(hwnd)
        print("OK restore")
    elif cmd == "restorebg":
        # 后台恢复:显示窗口但不抢焦点(SW_SHOWNOACTIVATE + SWP_NOACTIVATE),
        # 供 PrintWindow 后台截图前把最小化的窗口恢复为可渲染状态。
        SWP_NOACTIVATE, SWP_NOMOVE, SWP_NOSIZE, SWP_SHOWWINDOW = 0x10, 0x2, 0x1, 0x40
        if u.IsIconic(hwnd):
            u.ShowWindow(hwnd, 4)  # SW_SHOWNOACTIVATE
        u.SetWindowPos(hwnd, -1, 0, 0, 0, 0,  # 短暂 TOPMOST 让 DWM 合成一帧
                       SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE)
        u.SetWindowPos(hwnd, -2, 0, 0, 0, 0,
                       SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE)
        print("OK restorebg")
    elif cmd == "state":
        r = RECT()
        u.GetWindowRect(hwnd, ctypes.byref(r))
        fg = u.GetForegroundWindow()
        print(f"iconic={bool(u.IsIconic(hwnd))} visible={bool(u.IsWindowVisible(hwnd))} "
              f"rect=({r.left},{r.top},{r.right},{r.bottom}) "
              f"foreground_is_self={fg == hwnd}")
    else:
        print("UNKNOWN_CMD " + cmd)
        sys.exit(1)


if __name__ == "__main__":
    main()
