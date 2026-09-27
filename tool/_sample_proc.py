"""进程级采样器(纯 ctypes 替代方案)。CPU%/WorkingSet/PrivateMB/Handles。"""
import ctypes, ctypes.wintypes as wt, time, sys

k32, psapi = ctypes.windll.kernel32, ctypes.windll.psapi

class PMCEX(ctypes.Structure):
    _fields_ = [('cb', wt.DWORD), ('PageFaultCount', wt.DWORD),
                ('PeakWorkingSetSize', ctypes.c_size_t), ('WorkingSetSize', ctypes.c_size_t),
                ('QuotaPeakPagedPoolUsage', ctypes.c_size_t), ('QuotaPagedPoolUsage', ctypes.c_size_t),
                ('QuotaPeakNonPagedPoolUsage', ctypes.c_size_t), ('QuotaNonPagedPoolUsage', ctypes.c_size_t),
                ('PagefileUsage', ctypes.c_size_t), ('PeakPagefileUsage', ctypes.c_size_t),
                ('PrivateUsage', ctypes.c_size_t)]

class FT(ctypes.Structure):
    _fields_ = [('dwLow', wt.DWORD), ('dwHigh', wt.DWORD)]

def ft_sec(ft):
    return (ft.dwHigh << 32 | ft.dwLow) / 1e7

pid = int(sys.argv[1]); dur = int(sys.argv[2]); itv = int(sys.argv[3]); out = sys.argv[4]
h = k32.OpenProcess(0x1000, False, pid)
if not h:
    print('OpenProcess failed', k32.GetLastError()); sys.exit(1)
prev_cpu = 0.0; prev_t = time.time(); t0 = prev_t
with open(out, 'w', encoding='utf-8') as f:
    f.write('TimeSec,CpuPercent,WorkingSetMb,PrivateMb,Handles\n')
    while time.time() - t0 < dur:
        mc = PMCEX(); mc.cb = ctypes.sizeof(PMCEX)
        if not psapi.GetProcessMemoryInfo(h, ctypes.byref(mc), mc.cb):
            break
        kt, ut, et, st = FT(), FT(), FT(), FT()
        k32.GetProcessTimes(h, ctypes.byref(et), ctypes.byref(st), ctypes.byref(kt), ctypes.byref(ut))
        cpu = ft_sec(kt) + ft_sec(ut)
        now = time.time()
        cpupct = (cpu - prev_cpu) / max(now - prev_t, 1e-3) * 100
        prev_cpu, prev_t = cpu, now
        hc = wt.DWORD()
        k32.GetProcessHandleCount(h, ctypes.byref(hc))
        f.write(f"{now - t0:.0f},{cpupct:.1f},{mc.WorkingSetSize/1048576:.1f},{mc.PrivateUsage/1048576:.1f},{hc.value}\n")
        f.flush()
        time.sleep(itv)
k32.CloseHandle(h)
print('sampler done')
