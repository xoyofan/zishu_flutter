# -*- coding: utf-8 -*-
"""Windows 实机截图 / 模拟点击助手(纯 ctypes,无第三方依赖)。

用法(由 Bash 驱动):
  python tool/bin/_shots.py shot <out.png>          # 截全屏
  python tool/bin/_shots.py click <x> <y> [wait_ms] # 移动并左键单击
  python tool/bin/_shots.py win                     # 打印 pure_live 主窗口矩形
"""
import ctypes
import struct
import sys
import time
import zlib
from ctypes import wintypes

user32 = ctypes.WinDLL("user32", use_last_error=True)
gdi32 = ctypes.WinDLL("gdi32", use_last_error=True)
kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)

try:
    user32.SetProcessDPIAware()
except Exception:
    pass

SRCCOPY = 0x00CC0020
DIB_RGB_COLORS = 0
BI_RGB = 0


class BITMAPINFOHEADER(ctypes.Structure):
    _fields_ = [
        ("biSize", wintypes.DWORD),
        ("biWidth", ctypes.c_int),
        ("biHeight", ctypes.c_int),
        ("biPlanes", wintypes.WORD),
        ("biBitCount", wintypes.WORD),
        ("biCompression", wintypes.DWORD),
        ("biSizeImage", wintypes.DWORD),
        ("biXPelsPerMeter", ctypes.c_int),
        ("biYPelsPerMeter", ctypes.c_int),
        ("biClrUsed", wintypes.DWORD),
        ("biClrImportant", wintypes.DWORD),
    ]


class BITMAPINFO(ctypes.Structure):
    _fields_ = [("bmiHeader", BITMAPINFOHEADER), ("bmiColors", wintypes.DWORD * 3)]


def _screen_size():
    return user32.GetSystemMetrics(0), user32.GetSystemMetrics(1)


def write_png(path, w, h, bgra, stride, flip=False):
    """bgra: 每行 stride 字节的 BGRA 数据 → PNG(RGBA)。flip 时按自下而上解读。"""
    rows = []
    for y in (range(h - 1, -1, -1) if flip else range(h)):
        start = y * stride
        row = bytearray(b"\xff" * (w * 4))
        src = bgra[start:start + w * 4]
        row[0::4] = src[2::4]  # R
        row[1::4] = src[1::4]  # G
        row[2::4] = src[0::4]  # B
        rows.append(bytes(row))
    raw = b"".join(b"\x00" + r for r in rows)

    def chunk(tag, data):
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)
    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(raw, 6))
        + chunk(b"IEND", b"")
    )
    with open(path, "wb") as f:
        f.write(png)


def grab(region=None):
    """抓屏 → (w, h, bytes, stride)。数据为 BGRA 且自上而下。"""
    if region is None:
        x, y = 0, 0
        w, h = _screen_size()
    else:
        x, y, w, h = (int(v) for v in region)
    hdc = user32.GetDC(0)
    mem = gdi32.CreateCompatibleDC(hdc)
    hbmp = gdi32.CreateCompatibleBitmap(hdc, w, h)
    gdi32.SelectObject(mem, hbmp)
    gdi32.BitBlt(mem, 0, 0, w, h, hdc, x, y, SRCCOPY)

    bmi = BITMAPINFO()
    bmi.bmiHeader.biSize = ctypes.sizeof(BITMAPINFOHEADER)
    bmi.bmiHeader.biWidth = w
    bmi.bmiHeader.biHeight = -h  # top-down
    bmi.bmiHeader.biPlanes = 1
    bmi.bmiHeader.biBitCount = 32
    bmi.bmiHeader.biCompression = BI_RGB
    stride = ((w * 32 + 31) // 32) * 4
    buf = (ctypes.c_char * (stride * h))()
    gdi32.GetDIBits(mem, hbmp, 0, h, buf, ctypes.byref(bmi), DIB_RGB_COLORS)
    gdi32.DeleteObject(hbmp)
    gdi32.DeleteDC(mem)
    user32.ReleaseDC(0, hdc)
    return w, h, buf.raw, stride


def shot(path, region=None, flip=False):
    """region=(x, y, w, h) 只抓该区域;缺省抓全屏。"""
    w, h, data, stride = grab(region)
    write_png(path, w, h, data, stride, flip=flip)
    return w, h


def probe(points):
    """打印采样点颜色(屏幕坐标,RGB)。用于校验坐标映射。"""
    w, h, data, stride = grab()
    out = []
    for (x, y) in points:
        if not (0 <= x < w and 0 <= y < h):
            out.append((x, y, None))
            continue
        i = y * stride + x * 4
        b, g, r = data[i], data[i + 1], data[i + 2]
        out.append((x, y, (r, g, b)))
    return out


def click(x, y, wait_ms=250):
    user32.SetCursorPos(int(x), int(y))
    time.sleep(0.05)
    user32.mouse_event(0x0002, 0, 0, 0, 0)  # LEFTDOWN
    time.sleep(0.05)
    user32.mouse_event(0x0004, 0, 0, 0, 0)  # LEFTUP
    time.sleep(wait_ms / 1000.0)


def window_rect():
    hwnd = user32.FindWindowW(None, None)
    found = []

    @ctypes.WINFUNCTYPE(ctypes.c_bool, wintypes.HWND, wintypes.LPARAM)
    def cb(h, _):
        pid = wintypes.DWORD()
        user32.GetWindowThreadProcessId(h, ctypes.byref(pid))
        if user32.IsWindowVisible(h):
            length = user32.GetWindowTextLengthW(h)
            if length:
                buf = ctypes.create_unicode_buffer(length + 1)
                user32.GetWindowTextW(h, buf, length + 1)
                r = wintypes.RECT()
                user32.GetWindowRect(h, ctypes.byref(r))
                found.append(
                    (int(pid.value), buf.value, int(h), r.left, r.top, r.right, r.bottom)
                )
        return True

    user32.EnumWindows(cb, 0)
    return found


def place(pid, x, y, w, h):
    """恢复窗口并移动到精确矩形(用于校验坐标映射)。"""
    for row in window_rect():
        if row[0] != int(pid):
            continue
        hwnd = row[2]
        user32.ShowWindow(hwnd, 9)  # SW_RESTORE
        time.sleep(0.3)
        user32.MoveWindow(hwnd, int(x), int(y), int(w), int(h), True)
        user32.BringWindowToTop(hwnd)
        user32.SetForegroundWindow(hwnd)
        time.sleep(0.8)
        r = wintypes.RECT()
        user32.GetWindowRect(hwnd, ctypes.byref(r))
        return row[1], (r.left, r.top, r.right, r.bottom)
    return None, None


def focus(pid, maximize=False):
    """把目标进程的主窗口恢复并置前;maximize=True 时最大化。"""
    for row in window_rect():
        if row[0] != int(pid):
            continue
        hwnd = row[2]
        user32.ShowWindow(hwnd, 3 if maximize else 9)  # SW_MAXIMIZE / SW_RESTORE
        user32.BringWindowToTop(hwnd)
        user32.SetForegroundWindow(hwnd)
        time.sleep(0.8)
        r = wintypes.RECT()
        user32.GetWindowRect(hwnd, ctypes.byref(r))
        return row[1], (r.left, r.top, r.right, r.bottom)
    return None, None


def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        return 1
    if args[0] == "shot":
        w, h = shot(args[1])
        print("shot %dx%d -> %s" % (w, h, args[1]))
    elif args[0] == "crop":
        w, h = shot(args[5], region=args[1:5])
        print("crop %dx%d -> %s" % (w, h, args[5]))
    elif args[0] == "click":
        click(int(args[1]), int(args[2]), int(args[3]) if len(args) > 3 else 250)
        print("clicked %s,%s" % (args[1], args[2]))
    elif args[0] == "win":
        for row in window_rect():
            print(row)
    elif args[0] == "focus":
        title, rect = focus(args[1], maximize=len(args) > 2 and args[2] == "max")
        print("focused %r rect=%s" % (title, rect))
    elif args[0] == "probe":
        pts = [(int(args[i]), int(args[i + 1])) for i in range(1, len(args) - 1, 2)]
        for (x, y, c) in probe(pts):
            print("(%d,%d) -> %s" % (x, y, c))
    elif args[0] == "place":
        title, rect = place(args[1], args[2], args[3], args[4], args[5])
        print("placed %r rect=%s" % (title, rect))
    return 0


if __name__ == "__main__":
    sys.exit(main())
