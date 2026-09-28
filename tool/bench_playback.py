#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""zishu_flutter 播放卡顿基准测量。

解析 %APPDATA%/zishu_flutter/logs/playback.log，按时间窗统计：
- stall_begin / stall_end('ms')：每次卡顿次数与 ms 分布
- reopen_requested：同 URL 重开次数
- single_line_escalate：单线路升级触发次数
- escalate_recover_ok / escalate_recover_fail：恢复重解析成功/失败
- open_to_first_frame('ms')：开流→首帧耗时
- external_pause_recover：外部自暂停恢复
- give_up：放弃自动重试

用法:
  python3 tool/bench_playback.py --since 22:31:00 --until 22:41:00
  python3 tool/bench_playback.py --last-minutes 10
  python3 tool/bench_playback.py --from-offset 123456   # 从指定字节偏移读到末尾
日志行格式: "HH:MM:SS.mmm <event> key=val key=val ..."
"""
import argparse
import os
import re
import statistics
import sys

DEFAULT_LOG = os.path.join(
    os.environ.get("APPDATA", os.path.expanduser("~")),
    "zishu_flutter", "logs", "playback.log",
)


def _to_sec_of_day(hms: str):
    """'22:39:54.888' -> 81594.888 (秒, 当天)。跨午夜窗口不可用, 但 10 分钟窗内无碍。"""
    m = re.match(r"(\d{1,2}):(\d{2}):(\d{2})(?:\.(\d{1,3}))?", hms)
    if not m:
        return None
    h, mi, s, ms = m.groups()
    ms = (ms or "0").ljust(3, "0")
    return int(h) * 3600 + int(mi) * 60 + int(s) + int(ms) / 1000.0


LINE_RE = re.compile(r"^(\d{1,2}:\d{2}:\d{2}(?:\.\d{1,3})?)\s+(\S+)\s*(.*)$")
KV_RE = re.compile(r"(\w+)=(.+?)(?=\s+\w+=|$)")


def parse_log(path: str, from_offset: int = 0):
    events = []
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        if from_offset:
            f.seek(from_offset)
        for raw in f:
            line = raw.rstrip("\n")
            if not line.strip():
                continue
            m = LINE_RE.match(line)
            if not m:
                continue
            ts = _to_sec_of_day(m.group(1))
            event = m.group(2)
            kv = {}
            for km, vv in KV_RE.findall(m.group(3) or ""):
                kv[km] = vv.strip()
            events.append((ts, event, kv))
    return events


def _num(x):
    try:
        return float(x)
    except (TypeError, ValueError):
        return None


def pct(values, p):
    if not values:
        return 0.0
    s = sorted(values)
    k = (len(s) - 1) * p
    lo = int(k)
    hi = min(lo + 1, len(s) - 1)
    if lo == hi:
        return s[lo]
    return s[lo] + (s[hi] - s[lo]) * (k - lo)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--log", default=DEFAULT_LOG)
    ap.add_argument("--since", help="HH:MM:SS 起始(含)")
    ap.add_argument("--until", help="HH:MM:SS 结束(含)")
    ap.add_argument("--last-minutes", type=float, help="只看最后 N 分钟")
    ap.add_argument("--from-offset", type=int, default=0, help="从指定字节偏移读到末尾")
    args = ap.parse_args()

    if not os.path.exists(args.log):
        print(f"日志不存在: {args.log}", file=sys.stderr)
        return 2

    events = parse_log(args.log, from_offset=args.from_offset)

    since_s = _to_sec_of_day(args.since) if args.since else None
    until_s = _to_sec_of_day(args.until) if args.until else None
    if args.last_minutes:
        max_ts = max((e[0] for e in events if e[0] is not None), default=0)
        since_s = max_ts - args.last_minutes * 60
        until_s = None

    filtered = [
        e for e in events
        if (since_s is None or (e[0] is not None and e[0] >= since_s))
        and (until_s is None or (e[0] is not None and e[0] <= until_s))
    ]

    total_ts = [e[0] for e in filtered if e[0] is not None]
    window = (max(total_ts) - min(total_ts)) if len(total_ts) >= 2 else 0.0

    stall_ms = []
    open_ms = []
    reopen = 0
    escalate = 0
    recover_ok = 0
    recover_fail = 0
    ext_pause = 0
    give_up = 0
    stall_begin = 0
    hosts = {}

    for ts, ev, kv in filtered:
        if "host" in kv:
            hosts[kv["host"]] = hosts.get(kv["host"], 0) + 1
        if ev == "stall_begin":
            stall_begin += 1
        elif ev == "stall_end":
            v = _num(kv.get("ms"))
            if v is not None:
                stall_ms.append(v)
        elif ev == "reopen_requested":
            reopen += 1
        elif ev == "single_line_escalate":
            escalate += 1
        elif ev == "escalate_recover_ok":
            recover_ok += 1
        elif ev == "escalate_recover_fail":
            recover_fail += 1
        elif ev == "external_pause_recover":
            ext_pause += 1
        elif ev == "give_up":
            give_up += 1
        elif ev == "open_to_first_frame":
            v = _num(kv.get("ms"))
            if v is not None:
                open_ms.append(v)

    def fmt_ms_list(vals):
        if not vals:
            return "n/a"
        return (f"n={len(vals)} avg={statistics.mean(vals):.0f}ms "
                f"p50={pct(vals,0.5):.0f}ms p95={pct(vals,0.95):.0f}ms "
                f"max={max(vals):.0f}ms >1s={sum(1 for v in vals if v>1000)} "
                f">5s={sum(1 for v in vals if v>5000)}")

    print("=" * 64)
    print(f"窗口时长: {window/60:.1f} 分钟  (事件 {len(filtered)} 条)")
    if args.from_offset:
        print(f"读取偏移: 字节 {args.from_offset} -> EOF")
    print("-" * 64)
    print(f"卡顿 stall_begin 次数 : {stall_begin}")
    print(f"卡顿 ms 分布          : {fmt_ms_list(stall_ms)}")
    print(f"重开 reopen_requested : {reopen}")
    print(f"单线升级 escalate     : {escalate}")
    print(f"恢复成功 recover_ok   : {recover_ok}")
    print(f"恢复失败 recover_fail : {recover_fail}")
    print(f"外部暂停恢复          : {ext_pause}")
    print(f"放弃 give_up          : {give_up}")
    print(f"开流→首帧 open_ms     : {fmt_ms_list(open_ms)}")
    print("-" * 64)
    print("hostname 出现次数:")
    for h, c in sorted(hosts.items(), key=lambda x: -x[1]):
        print(f"  {h or '(null)':32s} {c}")
    print("=" * 64)
    return 0


if __name__ == "__main__":
    sys.exit(main())
