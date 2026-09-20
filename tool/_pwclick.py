# -*- coding: utf-8 -*-
"""PostMessage 合成点击直投指定 PID 窗口(client 坐标),不移动真实光标。"""
import ctypes
import sys
import time
from ctypes import wintypes

sys.path.insert(0, "tool")
import _shots as S  # noqa: E402

u32 = S.user32
WM_MOUSEMOVE = 0x0200
WM_LBUTTONDOWN = 0x0201
WM_LBUTTONUP = 0x0202
MK_LBUTTON = 1


def lparam(x, y):
    return y << 16 | (x & 0xFFFF)


def hwnd_of(pid):
    rows = [r for r in S.window_rect() if r[0] == pid]
    return rows[0][2] if rows else None


def title_of(pid):
    rows = [r for r in S.window_rect() if r[0] == pid]
    return rows[0][1] if rows else None


def click(pid, x, y, wait_ms=400):
    hwnd = hwnd_of(pid)
    if not hwnd:
        print("no window")
        return
    u32.PostMessageW(hwnd, WM_MOUSEMOVE, 0, lparam(x, y))
    time.sleep(0.05)
    u32.PostMessageW(hwnd, WM_LBUTTONDOWN, MK_LBUTTON, lparam(x, y))
    time.sleep(0.06)
    u32.PostMessageW(hwnd, WM_LBUTTONUP, 0, lparam(x, y))
    time.sleep(wait_ms / 1000.0)
    print("posted click (%d,%d) title=%r" % (x, y, title_of(pid)))


if __name__ == "__main__":
    click(int(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3]),
          int(sys.argv[4]) if len(sys.argv) > 4 else 400)
