# -*- coding: utf-8 -*-
"""PrintWindow 直抓指定 PID 的窗口表面(不受遮挡影响),无点击操作。"""
import ctypes
import sys
from ctypes import wintypes

sys.path.insert(0, "tool")
import _shots as S  # noqa: E402  复用 write_png 与窗口枚举

u32 = S.user32
g32 = S.gdi32

PW_CLIENTONLY = 1
PW_RENDERFULLCONTENT = 2


def shoot(pid, out):
    rows = [r for r in S.window_rect() if r[0] == pid]
    if not rows:
        print("no visible window for pid", pid)
        return 1
    _, title, hwnd, l, t, r, b = rows[0]
    w, h = r - l, b - t

    hdc = u32.GetWindowDC(hwnd)
    mem = g32.CreateCompatibleDC(hdc)
    bmp = g32.CreateCompatibleBitmap(hdc, w, h)
    old = g32.SelectObject(mem, bmp)
    ok = u32.PrintWindow(hwnd, mem, PW_RENDERFULLCONTENT)
    g32.DeleteObject(old)
    if not ok:
        print("PrintWindow failed")
        return 1

    class BMI(ctypes.Structure):
        _fields_ = [
            ("biSize", wintypes.DWORD),
            ("biWidth", ctypes.c_long),
            ("biHeight", ctypes.c_long),
            ("biPlanes", wintypes.WORD),
            ("biBitCount", wintypes.WORD),
            ("biCompression", wintypes.DWORD),
            ("biSizeImage", wintypes.DWORD),
            ("biXPels", ctypes.c_long),
            ("biYPels", ctypes.c_long),
            ("biClrUsed", wintypes.DWORD),
            ("biClrImportant", wintypes.DWORD),
        ]

    bmi = BMI()
    bmi.biSize = ctypes.sizeof(BMI)
    bmi.biWidth = w
    bmi.biHeight = -h  # 自上而下
    bmi.biPlanes = 1
    bmi.biBitCount = 32
    bmi.biCompression = 0
    buf = ctypes.create_string_buffer(w * 4 * h)
    got = g32.GetDIBits(mem, bmp, 0, h, buf, ctypes.byref(bmi), 0)
    g32.DeleteObject(bmp)
    g32.DeleteDC(mem)
    u32.ReleaseDC(hwnd, hdc)
    if got != h:
        print("GetDIBits failed", got)
        return 1
    S.write_png(out, w, h, buf.raw, w * 4, flip=False)
    print("pwshot %dx%d pid=%s title=%r -> %s" % (w, h, pid, title, out))
    return 0


if __name__ == "__main__":
    sys.exit(shoot(int(sys.argv[1]), sys.argv[2]))
