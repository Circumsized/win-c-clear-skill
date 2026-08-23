#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
fetch_rules.py - Fetch and convert community cleaner rules for win-c-clear-skill.

Sources:
  1. MoscaDotTo/Winapp2 (CC-BY-SA-4.0): master Winapp2.ini
     https://raw.githubusercontent.com/MoscaDotTo/Winapp2/master/Winapp2.ini
  2. BleachBit official cleaners (GPL-3.0-or-later): cleaners/*.xml
     https://github.com/bleachbit/bleachbit/tree/master/cleaners

Outputs (all under config/generated/, git-ignored):
  - winapp2_latest.json      : latest Winapp2.ini converted to unified tuples
  - community_cleaners.json  : BleachBit cleaners converted (Windows-only paths)
  - obsolete_report.json     : stale-entry audit (local winapp2.json vs latest)

Unified rule tuple (compatible with community rule-source 6-element arrays):
  [name, path, type, default_checked, note, enabled]
  - name    : "win2 | <section>" or "BBC | <cleaner label> - <option label>"
  - path    : environment-variable form (%LocalAppData% etc.)
  - type    : "dir" | "file" | "glob"
  - default_checked : False (never pre-checked)
  - note    : source metadata for audit
  - enabled : True (present in library, subject to user opt-in)

Usage:
  python fetch_rules.py [--winapp2-local PATH] [--bleachbit-dir PATH]
                        [--skip-download] [--outdir DIR]
"""
import argparse
import json
import os
import re
import sys
import urllib.request
import xml.etree.ElementTree as ET
from collections import OrderedDict

WINAPP2_URL = 'https://raw.githubusercontent.com/MoscaDotTo/Winapp2/master/Winapp2.ini'
BLEACHBIT_REPO = 'https://github.com/bleachbit/bleachbit'

# LangSecRef -> category (community-standard section ids)
LANG_SEC_REF = {
    '3001': 'Utilities', '3002': 'Windows', '3021': 'Applications',
    '3022': 'Internet', '3023': 'Multimedia', '3024': 'Windows',
    '3025': 'Utilities', '3026': 'Windows', '3027': 'Internet',
    '3028': 'Utilities', '3029': 'Internet', '3030': 'Utilities',
    '3031': 'Multimedia', '3041': 'Applications', '3042': 'Games',
    '3043': 'Development', '3044': 'Utilities',
}

FLAG_TOKENS = {'RECURSE', 'REMOVESELF'}


# ---------------------------------------------------------------------------
# Winapp2.ini parsing
# ---------------------------------------------------------------------------

def parse_winapp2(ini_path):
    """Parse Winapp2.ini into unified rule tuples."""
    rules = []
    section = None
    meta = {}
    with open(ini_path, encoding='utf-8', errors='replace') as f:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith(';'):
                continue
            if line.startswith('[') and line.endswith(']'):
                section = line[1:-1]
                meta = {}
                continue
            if section is None or '=' not in line:
                continue
            key, _, val = line.partition('=')
            key = key.strip()
            val = val.strip()
            if key.startswith('FileKey'):
                for rule in convert_filekey(section, key, val, meta):
                    rules.append(rule)
            elif key in ('Detect', 'DetectFile'):
                meta['detect'] = val
            elif key == 'LangSecRef':
                meta['category'] = LANG_SEC_REF.get(val, 'Applications')
            elif key == 'Default':
                meta['default'] = val.lower() == 'true'
    return rules


def convert_filekey(section, key, val, meta):
    """Convert one FileKeyN=<path>|<mask>[|flags...] into rule tuples."""
    parts = [p.strip() for p in val.split('|')]
    if len(parts) < 2:
        return []
    base_path = parts[0]
    mask = parts[1]
    flags = {p.upper() for p in parts[2:] if p.upper() in FLAG_TOKENS}

    out = []
    if mask == '*' and 'RECURSE' in flags:
        typ, path = 'dir', base_path
    elif mask == '*':
        typ, path = 'dir', base_path  # clear contents; engine treats dir-with-contents
    elif '*' in mask or '?' in mask:
        typ, path = 'glob', base_path + '\\' + mask
    else:
        typ, path = 'file', base_path + '\\' + mask

    note = f'{key}: {val}'
    if meta.get('category'):
        note += f' category={meta["category"]}'
    out.append([f'win2 | {section}', normalize_path(path), typ, False, note, True])
    return out


def normalize_path(p):
    """Normalize separators and env-var casing (winapp2 mixes cases)."""
    p = p.replace('/', '\\')
    for var in ('LocalAppData', 'AppData', 'UserProfile', 'ProgramData',
                'ProgramFiles', 'WinDir', 'SystemDrive', 'Public', 'CommonAppData',
                'CommonProgramFiles', 'LocalAppDataLow', 'Documents'):
        p = re.sub(r'%' + var + '%', '%' + var.upper() + '%', p, flags=re.IGNORECASE)
    return p if p.endswith(':\\') else p.rstrip('\\')


# ---------------------------------------------------------------------------
# BleachBit cleaners XML parsing
# ---------------------------------------------------------------------------

def parse_bleachbit_dir(xml_dir):
    """Parse all cleaner XMLs; keep Windows-relevant delete actions only."""
    rules = []
    for fname in sorted(os.listdir(xml_dir)):
        if not fname.endswith('.xml'):
            continue
        path = os.path.join(xml_dir, fname)
        try:
            rules.extend(parse_bleachbit_xml(path, fname))
        except ET.ParseError as e:
            print(f'[fetch_rules] XML parse error in {fname}: {e}', file=sys.stderr)
    return rules


def parse_bleachbit_xml(path, fname):
    """Parse one BleachBit cleaner XML into unified rule tuples."""
    tree = ET.parse(path)
    root = tree.getroot()  # <cleaner id="...">
    cleaner_label = (root.findtext('label') or root.get('id') or '?').strip()

    # Collect windows-only variables defined via <var name="x"><value os="windows">
    variables = {}
    for var in root.findall('var'):
        name = var.get('name')
        for value in var.findall('value'):
            if value.get('os') == 'windows':
                variables['$$' + name + '$$'] = value.text.strip()
                break

    out = []
    for option in root.findall('option'):
        opt_label = (option.findtext('label') or option.get('id') or '?').strip()
        warning = option.find('warning') is not None
        for action in option.findall('action'):
            if action.get('command') != 'delete':
                continue  # json/regex/truncate actions are out of scope
            search = action.get('search', 'file')
            p = (action.get('path') or '').strip()
            if not p:
                continue
            # Expand cleaner variables; skip non-windows leftovers
            for var, val in variables.items():
                p = p.replace(var, val)
            if '$$' in p or p.startswith('$XDG'):
                continue  # unresolved Linux-only path
            if p.startswith('~/'):
                p = '%USERPROFILE%\\' + p[2:]
            p = p.replace('/', '\\')
            # Trailing slash marks directory semantics for BleachBit
            trailing_dir = p.endswith('\\')
            p = p.rstrip('\\')

            # BleachBit search semantics -> engine type:
            #   walk.all  : recursive delete of everything under path -> dir
            #   walk.files: delete files only, keep directory tree   -> contents
            #   file      : single file                                -> file
            #   glob      : wildcard match                             -> glob
            typ = {'walk.all': 'dir', 'walk.files': 'contents',
                   'file': 'file', 'glob': 'glob', 'walk.top': 'contents',
                   'depth': 'dir'}.get(search, 'dir')
            if search == 'file':
                typ = 'file'
            elif search == 'walk.all' and not trailing_dir:
                typ = 'dir'

            # App-root guard: a path that IS the application's home directory
            # (e.g. %USERPROFILE%\.claude) must never become a plain "dir"
            # delete target -- it would wipe configuration. Downgrade to
            # contents + warning so the merge pipeline can classify it as
            # dangerous (default disabled).
            rel = p.upper().replace('%USERPROFILE%\\', '') if p.upper().startswith('%USERPROFILE%\\') else None
            app_root = bool(rel) and ('\\' not in rel)
            if app_root and typ == 'dir':
                typ = 'contents'
                warning = True

            note = (f'BBC {fname} option={option.get("id")} command=delete '
                    f'search={search} path={action.get("path")}')
            if warning:
                note += ' WARNING=has-warning'
            if app_root:
                note += ' WARNING=app-root'
            name = f'BBC | {cleaner_label} - {opt_label}'
            out.append([name, p, typ, False, note, True])
    return out


# ---------------------------------------------------------------------------
# Stale-entry audit (local winapp2.json vs latest Winapp2.ini)
# ---------------------------------------------------------------------------

def audit_stale(local_winapp2_json, latest_rules):
    """Compare local converted winapp2 rules with the latest upstream set."""
    with open(local_winapp2_json, encoding='utf-8') as f:
        local_rules = json.load(f)

    def section_of(name):
        # local: "win2 | <section> | <cn> #N"; latest: "win2 | <section>"
        s = name.split('|', 1)[1].strip() if '|' in name else name
        s = re.sub(r'\s*#\d+$', '', s)
        s = s.split(' | ')[0].strip()
        return s.lower()

    local_sections = {section_of(r[0]) for r in local_rules}
    latest_sections = {section_of(r[0]) for r in latest_rules}

    stale = sorted(local_sections - latest_sections)
    fresh = sorted(latest_sections - local_sections)
    return {
        'localSectionCount': len(local_sections),
        'latestSectionCount': len(latest_sections),
        'staleSections': stale,
        'staleCount': len(stale),
        'newSections': fresh,
        'newCount': len(fresh),
    }


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    here = os.path.dirname(os.path.abspath(__file__))
    root = os.path.normpath(os.path.join(here, '..'))
    gen = os.path.join(root, 'config', 'generated')
    ap = argparse.ArgumentParser()
    ap.add_argument('--winapp2-local', default=os.path.join(gen, '_fetch', 'Winapp2.ini'))
    ap.add_argument('--bleachbit-dir',
                    default=os.path.join(gen, '_fetch', 'bb_repo', 'cleaners'))
    ap.add_argument('--skip-download', action='store_true')
    ap.add_argument('--outdir', default=gen)
    args = ap.parse_args()
    os.makedirs(args.outdir, exist_ok=True)

    # 1) Winapp2.ini
    ini_path = args.winapp2_local
    if not args.skip_download and not os.path.exists(ini_path):
        os.makedirs(os.path.dirname(ini_path), exist_ok=True)
        print(f'[fetch_rules] downloading {WINAPP2_URL}')
        urllib.request.urlretrieve(WINAPP2_URL, ini_path)
    if os.path.exists(ini_path):
        latest_rules = parse_winapp2(ini_path)
        out = os.path.join(args.outdir, 'winapp2_latest.json')
        with open(out, 'w', encoding='utf-8') as f:
            json.dump(latest_rules, f, ensure_ascii=False, indent=1)
        print(f'[fetch_rules] winapp2 latest: {len(latest_rules)} rules -> {out}')
    else:
        latest_rules = []
        print('[fetch_rules] Winapp2.ini not found; skipping', file=sys.stderr)

    # 2) BleachBit cleaners
    if os.path.isdir(args.bleachbit_dir):
        bb_rules = parse_bleachbit_dir(args.bleachbit_dir)
        out = os.path.join(args.outdir, 'community_cleaners.json')
        with open(out, 'w', encoding='utf-8') as f:
            json.dump(bb_rules, f, ensure_ascii=False, indent=1)
        print(f'[fetch_rules] bleachbit community: {len(bb_rules)} rules -> {out}')
        # Also stage a copy under config/source for provenance
        src_dir = os.path.join(root, 'config', 'source', 'bleachbit_community')
        os.makedirs(src_dir, exist_ok=True)
        staged = os.path.join(src_dir, 'community_cleaners.json')
        with open(staged, 'w', encoding='utf-8') as f:
            json.dump(bb_rules, f, ensure_ascii=False, indent=1)
        print(f'[fetch_rules] staged copy -> {staged}')
    else:
        print('[fetch_rules] bleachbit cleaners dir not found; '
              'run: git clone --depth 1 --sparse '
              'https://github.com/bleachbit/bleachbit.git && '
              'git sparse-checkout set cleaners', file=sys.stderr)

    # 3) Stale audit
    local_winapp2 = os.path.join(root, 'config', 'source', 'c_cleaner_plus',
                                 'winapp2.json')
    if latest_rules and os.path.exists(local_winapp2):
        report = audit_stale(local_winapp2, latest_rules)
        out = os.path.join(args.outdir, 'obsolete_report.json')
        with open(out, 'w', encoding='utf-8') as f:
            json.dump(report, f, ensure_ascii=False, indent=2)
        print(f'[fetch_rules] stale audit: {report["staleCount"]} stale / '
              f'{report["newCount"]} new sections -> {out}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
