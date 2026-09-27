"""沙箱内跑 flutter 命令的助手(dart.exe 直调 flutter_tools.snapshot)。"""
import os, subprocess, sys

ROOT = r'F:\project\zishu_flutter'
DART = r'F:\flutter\bin\cache\dart-sdk\bin\dart.exe'
SNAPSHOT = r'F:\flutter\bin\cache\flutter_tools.snapshot'


def build_env():
    env = dict(os.environ)
    env.update({
        'PROGRAMFILES(X86)': r'C:\Program Files (x86)',
        'ProgramFiles(x86)': r'C:\Program Files (x86)',
        'PROGRAMFILES': r'C:\Program Files',
        'ProgramFiles': r'C:\Program Files',
        'COMMONPROGRAMFILES': r'C:\Program Files\Common Files',
        'CommonProgramFiles(x86)': r'C:\Program Files (x86)\Common Files',
        'ProgramData': r'C:\ProgramData',
        'ALLUSERSPROFILE': r'C:\ProgramData',
        'APPDATA': r'C:\Users\Administrator\AppData\Roaming',
        'LOCALAPPDATA': r'C:\Users\Administrator\AppData\Local',
        'USERPROFILE': r'C:\Users\Administrator',
        'HOMEDRIVE': 'C:', 'HOMEPATH': r'\Users\Administrator',
        'PROCESSOR_ARCHITECTURE': 'AMD64', 'OS': 'Windows_NT',
        'PATHEXT': '.COM;.EXE;.BAT;.CMD',
        'FLUTTER_ROOT': r'F:\flutter',
        'FLUTTER_SUPPRESS_ANALYTICS': 'true',
    })
    cleaned = []
    for entry in env.get('PATH', '').split(os.pathsep):
        item = entry.strip().strip('"')
        if not item or item in ('.', 'D', 'C') or len(item) == 1:
            continue
        cleaned.append(item)
    env['PATH'] = os.pathsep.join(cleaned)
    return env


def main():
    cmd = [DART, SNAPSHOT] + sys.argv[1:]
    r = subprocess.run(cmd, cwd=ROOT, env=build_env(), capture_output=True)
    sys.stdout.write(r.stdout.decode('utf-8', 'replace'))
    sys.stderr.write(r.stderr.decode('utf-8', 'replace'))
    return r.returncode


if __name__ == '__main__':
    sys.exit(main())
