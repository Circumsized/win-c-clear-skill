#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
extract_builtin_rules.py - Extract built-in system rules (with human-annotated
risk descriptions) from c_cleaner_plus runtime snapshot config.

Source: config/source/c_cleaner_plus/cdisk_cleaner_config.json
Output: config/source/c_cleaner_plus/builtin_system_rules.json

The runtime snapshot stores 4265 rules as double-nested tokens:
  states key = '["<rule_json_string>", 0]'
  rule_json_string parses to [name, absolute_path, type, risk_note, checked, ""]

Rules are classified by name prefix:
  - "win2 | ..."  -> winapp2 community rules (skipped here)
  - "Bit | ..."   -> BleachBit converted rules (skipped here)
  - everything else -> built-in system rules (339 entries, kept here)

Built-in rules carry human-annotated Chinese risk notes which map directly
onto the safe/caution/dangerous tier model -- far more accurate than
keyword heuristics. Paths are rewritten from absolute form to environment
variable form for portability across machines and users.

Usage:
  python extract_builtin_rules.py [--src PATH] [--out PATH]
"""
import argparse
import json
import os
import sys

DEFAULT_SRC = os.path.join(os.path.dirname(__file__), '..', 'config', 'source',
                           'c_cleaner_plus', 'cdisk_cleaner_config.json')
DEFAULT_OUT = os.path.join(os.path.dirname(__file__), '..', 'config', 'source',
                           'c_cleaner_plus', 'builtin_system_rules.json')

# Environment variables used for path portability, longest value first so that
# LOCALAPPDATA wins over USERPROFILE etc. Boundary-safe matching below.
ENV_VARS = [
    'LOCALAPPDATA', 'APPDATA', 'USERPROFILE', 'PROGRAMDATA',
    'ProgramFiles(x86)', 'ProgramFiles', 'WINDIR', 'PUBLIC', 'SYSTEMDRIVE',
]


def build_env_map():
    """Build (value, placeholder) pairs sorted by value length descending."""
    pairs = []
    for var in ENV_VARS:
        val = os.environ.get(var)
        if val:
            pairs.append((val.rstrip('\\'), '%' + var + '%'))
    # Custom fallback for LocalLow (no built-in Windows env var)
    userprofile = os.environ.get('USERPROFILE')
    if userprofile:
        locallow = os.path.join(userprofile, 'AppData', 'LocalLow')
        pairs.append((locallow, '%LOCALLOWAPPDATA%'))
    pairs.sort(key=lambda x: -len(x[0]))
    return pairs


def envize(path, env_map):
    """Rewrite an absolute path to environment-variable form (boundary safe)."""
    p = path.replace('/', '\\')
    for val, var in env_map:
        if p.lower().startswith(val.lower()):
            rest = p[len(val):]
            if rest == '' or rest.startswith('\\'):
                return var + rest
    return p


def classify_risk(note):
    """Map human-annotated risk note to (tier, requiresAdmin).

    Mapping rules (validated against the 339 built-in entries):
      safe       <- 常见垃圾，安全 / 较安全 / cache-like notes (缓存/日志/浏览器/JS)
      caution    <- 影响首次启动 / 内核转储 / 崩溃报告 / 崩溃转储 / 下载残留 / 更新缓存
      dangerous  <- 确认不调试时勾选 (MEMORY.DMP) / 会话 / 备份 / 工作区快照 / 历史无法恢复
      requiresAdmin <- 需管理员 / 可能需管理员 (mark, do not lower tier)
    """
    requires_admin = ('需管理员' in note)
    if '确认不调试' in note or '无法恢复' in note or '无法回滚' in note:
        tier = 'dangerous'
    elif any(k in note for k in ('影响首次启动', '内核转储', '崩溃报告', '崩溃转储',
                                 '下载残留', '更新缓存')):
        tier = 'caution'
    elif any(k in note for k in ('常见垃圾', '较安全', '缓存', '日志', '浏览器', 'JS',
                                 '着色器', 'OpenGL', 'CUDA', '包缓存', '编译缓存',
                                 '临时', '崩溃', '缩略图')):
        tier = 'safe'
    else:
        tier = 'caution'  # unknown -> conservative middle tier
    return tier, requires_admin


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--src', default=os.path.normpath(DEFAULT_SRC))
    ap.add_argument('--out', default=os.path.normpath(DEFAULT_OUT))
    args = ap.parse_args()

    with open(args.src, encoding='utf-8') as f:
        cfg = json.load(f)

    env_map = build_env_map()
    builtin = []
    skipped = {'win2': 0, 'Bit': 0}

    for token, state in cfg.get('states', {}).items():
        try:
            outer = json.loads(token)      # [rule_json_string, 0]
            arr = json.loads(outer[0])     # [name, path, type, note, checked, ""]
        except (json.JSONDecodeError, TypeError, IndexError):
            continue
        name = arr[0] if arr else ''
        if not isinstance(name, str):
            continue
        if name.startswith('win2 '):
            skipped['win2'] += 1
            continue
        if name.startswith('Bit '):
            skipped['Bit'] += 1
            continue
        tier, requires_admin = classify_risk(arr[3] if len(arr) > 3 else '')
        builtin.append({
            'name': name,
            'path': envize(arr[1] if len(arr) > 1 else '', env_map),
            'type': arr[2] if len(arr) > 2 else 'dir',
            'riskNote': arr[3] if len(arr) > 3 else '',
            'tier': tier,
            'requiresAdmin': requires_admin or None,  # null when false (compact)
            'defaultChecked': bool(state),
            'origin': 'c_cleaner_plus_builtin',
        })

    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, 'w', encoding='utf-8') as f:
        json.dump(builtin, f, ensure_ascii=False, indent=2)

    # Summary
    tiers = {}
    for r in builtin:
        tiers[r['tier']] = tiers.get(r['tier'], 0) + 1
    print(f'[extract_builtin_rules] built-in: {len(builtin)} '
          f'(skipped winapp2: {skipped["win2"]}, bleachbit: {skipped["Bit"]})')
    print(f'[extract_builtin_rules] tier distribution: {tiers}')
    admin = sum(1 for r in builtin if r['requiresAdmin'])
    print(f'[extract_builtin_rules] requiresAdmin: {admin}')
    print(f'[extract_builtin_rules] written -> {args.out}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
