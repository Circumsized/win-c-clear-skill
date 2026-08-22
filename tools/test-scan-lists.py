#!/usr/bin/env python3
# -*- coding: utf-8 -*-
r"""
test-scan-lists.py — scan-lists.json 白名单/黑名单模式单元测试。

覆盖
----
1. JSON 合法性与黑名单 pattern 计数
2. 黑名单正则：系统核心区域（WinSxS/System32\config/Drivers/Installer/GAC/
   Program Files/Windows.old/NTUSER.DAT/pagefile/Boot/Winevt/Inf/Wbem/Servicing/
   Recovery/EFI/Volume GUID）必须 blocked=True
3. 黑名单不误伤：可安全清理目录（Prefetch/Temp/SoftwareDistribution\Download/
   CBS logs/用户 Temp/浏览器缓存）必须 blocked=False
4. 白名单命中：展开环境变量后（Windows 环境变量名不区分大小写），
   Prefetch/Temp/SoftwareDistribution/Logs\CBS 应命中；系统核心区不命中
5. 引擎 GuardPatterns union 语义由 Invoke-CDriveCleanup.ps1 运行时保证，
   此处仅验证 scan-lists.json 自身模式。

用法
----
    python tools/test-scan-lists.py
退出码 0=全部通过，1=有失败。仅依赖 Python 标准库（可移植性要求）。
"""

import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SL_PATH = os.path.join(ROOT, 'config', 'scan-lists.json')
SL = json.load(open(SL_PATH, encoding='utf-8'))

pats = [p for e in SL['blacklist']['entries'] for p in e['patterns']]
print('JSON OK, %d blacklist patterns' % len(pats))

cases = [
    # (path, expected_blocked) — 系统核心区域严禁扫描
    (r'c:\windows\winsxs\manifests', True),
    (r'c:\windows\winsxs', True),
    (r'c:\windows\system32\config\system', True),
    (r'c:\windows\system32\drivers\nvlddmkm.sys', True),
    (r'c:\windows\system32\driverstore\filerepository', True),
    (r'c:\windows\installer\abc.msi', True),
    (r'c:\windows\assembly\gac', True),
    (r'c:\program files\app', True),
    (r'c:\program files (x86)\app', True),
    (r'c:\windows\system32\kernel32.dll', True),
    (r'c:\windows.old\windows', True),
    (r'c:\users\x\ntuser.dat', True),
    (r'c:\pagefile.sys', True),
    (r'c:\boot\bcd', True),
    (r'c:\windows\explorer.exe', True),
    (r'c:\windows\system32\winevt\logs', True),
    (r'c:\windows\inf\oem.inf', True),
    (r'c:\windows\system32\wbem\repository', True),
    (r'c:\windows\servicing\packages', True),
    (r'c:\recovery', True),
    (r'c:\efi\microsoft', True),
    (r'\\?\volume{12345678-0000-0000-0000-000000000000}\efi', True),
    # 可安全清理目录必须放行
    (r'c:\windows\prefetch', False),
    (r'c:\windows\temp', False),
    (r'c:\windows\softwaredistribution\download', False),
    (r'c:\windows\logs\cbs', False),
    (r'c:\users\x\appdata\local\temp', False),
    (r'c:\users\x\.cache', False),
    (r'c:\users\x\appdata\local\microsoft\edge\user data\default\cache', False),
    (r'c:\windows\system32\winevt2', False),  # winevt2 ≠ winevt（目录名精确匹配）
]

fails = 0
for path, exp in cases:
    got = any(re.search(p, path.lower()) for p in pats)
    ok = (got == exp)
    if not ok:
        fails += 1
    print('%s  %-60s blocked=%s (expect %s)' % ('PASS' if ok else 'FAIL', path, got, exp))


# 白名单命中测试（展开环境变量；Windows 环境变量名不区分大小写）
def expand(p):
    def _sub(m):
        name = m.group(1).upper()
        return os.environ.get(name, m.group(0))
    return re.sub(r'%([^%]+)%', _sub, p)


wl = []
for e in SL['whitelist']['entries']:
    for p in e.get('paths', []):
        wl.append(expand(p).lower())
print('\nwhitelist entries: %d' % len(wl))

# 测试机 WinDir 展开后的实际盘符（可移植：不假设 C:）
windir = expand('%WinDir%').lower()
wl_cases = [
    (windir + r'\prefetch', True),
    (windir + r'\temp\xxx', True),
    (windir + r'\softwaredistribution\download\x', True),
    (windir + r'\logs\cbs\cbs.log', True),
    (windir + r'\system32\config', False),
    (windir + r'\winsxs', False),
    (r'c:\program files\app', False),
    (r'c:\users\x\documents\myproject', False),
]


def in_wl(path):
    p = path.lower()
    for w in wl:
        if p == w or p.startswith(w + '\\'):
            return True
        if '*' in w:
            rx = '^' + re.escape(w).replace(r'\*', '.*') + '$'
            if re.match(rx, p):
                return True
    return False


for path, exp in wl_cases:
    got = in_wl(path)
    ok = (got == exp)
    if not ok:
        fails += 1
    print('%s  %-60s in-whitelist=%s (expect %s)' % ('PASS' if ok else 'FAIL', path, got, exp))

print('\n%s: %d failures' % ('RESULT FAIL' if fails else 'RESULT ALL PASS', fails))
sys.exit(1 if fails else 0)
