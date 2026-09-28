#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""斗鱼 9999 卡顿方案 A/B 实测编排(基线 / B / A+B 三窗口对照)。

每个窗口:启动 exe -> 记录日志字节偏移 -> 实跑 WINDOW 秒 -> 用 bench_playback.py
按偏移测量该段卡顿指标。基线用磁盘上预编译的 pre-B exe;随后构建 B exe;最后改
mpv_tuning.json 提 cache 构成 A+B。结果分别写 tool/bench_{baseline,B,AB}.txt。

用法(沙箱内):
  python3 tool/run_stall_experiment.py
"""
import json
import os
import subprocess
import sys
import time

ROOT = r"F:\project\zishu_flutter"
EXE = os.path.join(ROOT, "build", "windows", "x64", "runner", "Release", "zishu_flutter.exe")
LOG = os.path.join(
    os.environ.get("APPDATA", os.path.expanduser("~")),
    "zishu_flutter", "logs", "playback.log",
)
CONFIG = os.path.join(
    os.environ.get("APPDATA", os.path.expanduser("~")),
    "zishu_flutter", "config", "mpv_tuning.json",
)
WINDOW = 600  # 每个方案实跑 10 分钟
SITE, ROOM = "douyu", "9999"


def log_size():
    return os.path.getsize(LOG)


def launch():
    p = subprocess.Popen([EXE, "--site", SITE, "--room", ROOM])
    return p


def kill():
    subprocess.run(["taskkill", "/IM", "zishu_flutter.exe", "/F"],
                   capture_output=True)


def measure(offset, out_path):
    cmd = [sys.executable, os.path.join(ROOT, "tool", "bench_playback.py"),
           "--from-offset", str(offset), "--log", LOG]
    with open(out_path, "w", encoding="utf-8") as f:
        subprocess.run(cmd, cwd=ROOT, stdout=f, stderr=subprocess.STDOUT)
    return out_path


def run_window(label, out_path):
    print(f"[exp] === {label}: launch ===", flush=True)
    offset = log_size()
    proc = launch()
    time.sleep(WINDOW)
    kill()
    time.sleep(2)
    measure(offset, out_path)
    print(f"[exp] {label}: done -> {out_path}", flush=True)


def build_b():
    print("[exp] === build B (release, ZISHU_REAL_PARSER) ===", flush=True)
    cmd = [sys.executable, os.path.join(ROOT, "tool", "_frun.py"), "build",
           "windows", "--release", "-t", "lib/main.dart",
           "--dart-define=ZISHU_REAL_PARSER=true"]
    r = subprocess.run(cmd, cwd=ROOT)
    print(f"[exp] build exit={r.returncode}", flush=True)
    return r.returncode == 0


def patch_config_for_a():
    """提 cache:cache-secs=20 / readahead=15 / max-bytes=256MiB,保留其余。"""
    with open(CONFIG, "r", encoding="utf-8") as f:
        cfg = json.load(f)
    cfg["cache-secs"] = "20"
    cfg["demuxer-readahead-secs"] = "15"
    cfg["demuxer-max-bytes"] = "268435456"
    with open(CONFIG, "w", encoding="utf-8") as f:
        json.dump(cfg, f, indent=2, ensure_ascii=False)
    print("[exp] config patched for A (cache-secs=20/readahead=15/max-bytes=256MiB)",
          flush=True)


def main():
    t0 = time.time()
    # 1) 基线:磁盘上 pre-B exe(默认 cache 10/10)
    run_window("baseline(pre-B, cache 10/10)", os.path.join(ROOT, "tool", "bench_baseline.txt"))

    # 2) 构建 B exe
    if not build_b():
        print("[exp] BUILD FAILED; 仅输出基线结果", flush=True)
        return 1

    # 3) B:多线路恢复(默认 cache 10/10,隔离 B 贡献)
    run_window("B(multi-line recovery, cache 10/10)", os.path.join(ROOT, "tool", "bench_B.txt"))

    # 4) A+B:改 cache 配置(隔离 A 贡献)
    patch_config_for_a()
    run_window("A+B(multi-line recovery + cache 20/15)", os.path.join(ROOT, "tool", "bench_AB.txt"))

    elapsed = (time.time() - t0) / 60
    print(f"[exp] ALL DONE in {elapsed:.1f} min. 看 tool/bench_*.txt", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
