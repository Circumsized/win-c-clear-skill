#!/usr/bin/env python3
# -*- coding: utf-8 -*-
r"""
merge_rules.py - Reproducible 7-step rule merge pipeline for win-c-clear-skill.

Pipeline: discover -> parse -> normalize -> dedup -> tier -> collapse -> present

Inputs (priority order, highest first):
  P1  config/builtin/builtin_targets.json            curated logical targets
  P2  config/source/c_cleaner_plus/builtin_system_rules.json
                                                      339 built-in rules with
                                                      human-annotated risk notes
  P3  config/source/c_cleaner_plus/{common_custom_rules,rules_*}.json
                                                      curated 5-tuple custom rules
  P4  config/source/bleachbit_community/community_cleaners.json
                                                      BleachBit official cleaners
  P5  config/generated/winapp2_latest.json           latest MoscaDotTo Winapp2.ini

Skipped (superseded or state-only):
  winapp2.json (old snapshot), bleachbit.json (old snapshot),
  cdisk_cleaner_config.json (runtime state), cdisk_cleaner_custom_rules.json
  (already-merged duplicate of the above).

Outputs:
  config/generated/targets.merged.json   full collapsed library (git-ignored)
  config/targets.json                    baseline: curated + built-in + custom
  config/targets.example.json            schema example
  config/generated/merge_report.json     statistics + unparsed list

Unified internal rule model:
  {name, path, type(dir|file|glob|contents), tier, requiresAdmin, origin,
   sourceFile, note, defaultChecked}

Dedup key: (normalized lowercase path, type). Priority keeps the higher-priority
source and the more conservative tier.

Collapse key (app_key): derived from the path with vendor awareness, e.g.
  %APPDATA%\Code\Cache                     -> code
  %LOCALAPPDATA%\Google\Chrome\...\Cache   -> google/chrome
  %USERPROFILE%\.claude\cache              -> .claude
  %WINDIR%\SoftwareDistribution\Download   -> softwaredistribution

Usage:
  python merge_rules.py [--root REPO_ROOT] [--baseline-out PATH]
"""
import argparse
import json
import os
import re
import sys
from collections import OrderedDict, defaultdict
from datetime import datetime, timezone

TIER_ORDER = {'safe': 0, 'caution': 1, 'dangerous': 2}

# Vendor segments: when the first path segment is one of these, the app key
# also includes the second segment for finer grouping.
VENDORS = {
    'google', 'microsoft', 'tencent', 'kingsoft', 'adobe', 'mozilla',
    'bravesoftware', 'nvidia', 'amd', 'electronic arts', 'riot games',
    'ubisoft game launcher', 'jetbrains', 'unity', 'baidu', 'baidunetdisk',
    '360chrome', 'opera software', 'vivaldi', 'atlassian', 'quark',
    'epicgameslauncher', 'sogouexplorer', 'nvidia corporation',
    'tencent files', 'wechat files', 'programs', 'packages', 'docker',
    # known folders under %USERPROFILE% -- second segment is the real app
    'documents', 'downloads', 'saved games', 'searches', 'links',
    'favorites', 'contacts', 'music', 'pictures', 'videos',
    '3d objects',
}

# Keyword tables for tier classification (checked against the leaf path
# segment first, then the full path, then the rule name).
SAFE_KW = ['cache', 'temp', 'tmp', 'log', 'gpucache', 'code cache', 'cachestorage',
           'crash', 'dumps', 'cacheddata', 'cached', 'shader', 'shadercache',
           '缓存', '日志', '临时', '崩溃', '缩略图', '着色器', '快照', '遥测',
           'telemetry', 'statsig', 'inetcache', 'webcache', 'crashpad',
           'minidump', 'wer', 'inetcaches', 'thumbnails', 'thumbcache']
CAUTION_KW = ['download', 'package', 'installer', 'update', 'history', 'cookies',
              '下载', '安装包', '更新', '历史', 'deliveryoptimization',
              'softwaredistribution', 'prefetch', 'components', 'downloading',
              'shader cache', 'dxcache', 'glcache', 'computecache', 'nv_cache']
DANGEROUS_KW = ['backup', 'session', 'file-history', 'file_history', 'workspace',
                'password', 'profile', '备份', '会话', '数据', '配置', '密钥',
                'projects', 'sessions', 'state.vscdb', 'user data', 'appdata\\ roaming\\x']


# ---------------------------------------------------------------------------
# Step 1+2: discover & parse
# ---------------------------------------------------------------------------

def parse_builtin_targets(path):
    """P1: curated logical targets (already collapsed)."""
    with open(path, encoding='utf-8') as f:
        data = json.load(f)
    out = []
    for t in data.get('targets', []):
        out.append({
            'name': t['name'], 'path': '', 'type': t.get('patternType', 'dir'),
            'tier': t.get('tier', 'caution'),
            'requiresAdmin': bool(t.get('requiresAdmin')),
            'origin': 'builtin', 'sourceFile': 'builtin_targets.json',
            'note': t.get('risk', ''), 'defaultChecked': t.get('enabled', False),
            'target': t,  # keep original; emitted verbatim
        })
    return out


def parse_builtin_system(path):
    """P2: built-in system rules with human risk notes (object format)."""
    with open(path, encoding='utf-8') as f:
        data = json.load(f)
    out = []
    for r in data:
        out.append({
            'name': r['name'], 'path': r['path'], 'type': r.get('type', 'dir'),
            'tier': r.get('tier', 'caution'),
            'requiresAdmin': bool(r.get('requiresAdmin')),
            'origin': 'c_cleaner_plus_builtin',
            'sourceFile': 'builtin_system_rules.json',
            'note': r.get('riskNote', ''),
            'defaultChecked': bool(r.get('defaultChecked')),
        })
    return out


def parse_tuple_rules(path, origin):
    """P3/P4/P5: 5-tuple / 6-tuple array rules."""
    with open(path, encoding='utf-8') as f:
        data = json.load(f)
    out = []
    for r in data:
        if not isinstance(r, list) or len(r) < 5:
            continue  # unparsed entries are recorded by the caller
        enabled = bool(r[5]) if len(r) >= 6 else True
        out.append({
            'name': str(r[0]), 'path': str(r[1]), 'type': str(r[2] or 'dir'),
            'tier': None,  # classified later
            'requiresAdmin': None,  # derived from path later
            'origin': origin, 'sourceFile': os.path.basename(path),
            'note': str(r[4] or ''), 'defaultChecked': bool(r[3]),
            'enabled': enabled,
        })
    return out


# ---------------------------------------------------------------------------
# Step 3: normalize
# ---------------------------------------------------------------------------

ENV_CASE_MAP = [
    ('%LocalAppData%', '%LOCALAPPDATA%'), ('%localappdata%', '%LOCALAPPDATA%'),
    ('%AppData%', '%APPDATA%'), ('%appdata%', '%APPDATA%'),
    ('%UserProfile%', '%USERPROFILE%'), ('%userprofile%', '%USERPROFILE%'),
    ('%ProgramData%', '%PROGRAMDATA%'), ('%programdata%', '%PROGRAMDATA%'),
    ('%ProgramFiles%', '%PROGRAMFILES%'), ('%programfiles%', '%PROGRAMFILES%'),
    ('%WinDir%', '%WINDIR%'), ('%windir%', '%WINDIR%'),
    ('%SystemDrive%', '%SYSTEMDRIVE%'), ('%systemdrive%', '%SYSTEMDRIVE%'),
    ('%Public%', '%PUBLIC%'), ('%public%', '%PUBLIC%'),
    ('%Temp%', '%TEMP%'), ('%temp%', '%TEMP%'),
    ('%Documents%', '%DOCUMENTS%'), ('%documents%', '%DOCUMENTS%'),
    ('%CommonProgramFiles%', '%COMMONPROGRAMFILES%'),
    ('%LocalAppDataLow%', '%LOCALLOWAPPDATA%'),
    ('%LocalLowAppData%', '%LOCALLOWAPPDATA%'),
]


def normalize_path(p):
    p = (p or '').strip().replace('/', '\\')
    for a, b in ENV_CASE_MAP:
        p = p.replace(a, b)
    if p.endswith('\\') and not p.endswith(':\\'):
        p = p.rstrip('\\')
    return p


# ---------------------------------------------------------------------------
# Step 5: tier classification
# ---------------------------------------------------------------------------

def classify_tier(rule):
    """Classify tier for rules without a human annotation."""
    if rule['tier']:
        return rule['tier'], bool(rule['requiresAdmin'])
    note = (rule.get('note') or '').lower()
    name = (rule.get('name') or '').lower()
    path = (rule.get('path') or '').lower()

    # BleachBit option semantics
    for opt, tier in (('option=cache', 'safe'), ('option=tmp', 'safe'),
                      ('option=logs', 'safe'), ('option=cookies', 'caution'),
                      ('option=history', 'caution'), ('option=session', 'dangerous'),
                      ('option=backup', 'dangerous'),
                      ('option=file_history', 'dangerous'),
                      ('option=file history', 'dangerous')):
        if opt in note:
            return tier, None
    if 'warning' in note:
        return 'dangerous', None

    # Leaf segment first
    leaf = path.rstrip('\\').split('\\')[-1]
    for kw in DANGEROUS_KW:
        if kw in leaf:
            return 'dangerous', None
    for kw in CAUTION_KW:
        if kw in leaf:
            return 'caution', None
    for kw in SAFE_KW:
        if kw in leaf:
            return 'safe', None
    # Full path
    for kw in DANGEROUS_KW:
        if kw in path:
            return 'dangerous', None
    for kw in CAUTION_KW:
        if kw in path:
            return 'caution', None
    for kw in SAFE_KW:
        if kw in path or kw in name:
            return 'safe', None
    # Fallback: unknown -> dangerous (red line: never guess "safe")
    return 'dangerous', None


def derive_requires_admin(path):
    p = path.upper()
    return any(p.startswith(v) for v in (
        '%PROGRAMFILES%', '%PROGRAMDATA%', '%WINDIR%', '%SYSTEMDRIVE%\\WINDIR',
        '%SYSTEMDRIVE%\\PROGRAM', '%SYSTEMDRIVE%\\USERS\\DEFAULT'))


# ---------------------------------------------------------------------------
# Step 6: collapse
# ---------------------------------------------------------------------------

def app_key_from_path(path):
    m = re.match(r'^%([^%\\]+)%\\?(.*)$', path or '')
    if not m:
        return '_misc'
    rest = m.group(2)
    if not rest:
        return m.group(1).lower()
    segs = []
    for s in rest.split('\\'):
        s = s.strip()
        if not s or s == '*':
            continue
        # normalize wildcard-bearing segments: "Chrome*" -> "chrome"
        s = s.rstrip('*?')
        if s:
            segs.append(s.lower())
    if not segs:
        return m.group(1).lower()
    first = segs[0]
    if first.startswith('.'):
        return first
    if first in VENDORS and len(segs) > 1:
        return first + '/' + segs[1]
    return first


def display_name_of(rule, key):
    name = rule.get('name') or ''
    if '|' in name:  # "win2 | X ..." / "BBC | X - Y"
        name = name.split('|', 1)[1].strip()
        name = re.sub(r'\s*\|.*$', '', name)
        name = re.sub(r'\s*\*+$', '', name).strip()
    # strip common suffixes
    for suf in ('缓存', ' 日志', ' logs', ' cache', ' caches', ' 临时', ' temp',
                ' gpu 缓存', ' 代码缓存', ' service worker', ' 崩溃报告',
                ' 崩溃转储', ' 小缓存', ' 编译缓存', ' shell 快照', ' 遥测缓存'):
        if name.lower().endswith(suf) and len(name) > len(suf) + 2:
            name = name[: -len(suf)]
            break
    if name:
        return name
    return key.replace('/', ' ').replace('\\', ' ').replace('.', '').strip().title() or key


def slugify(text):
    s = re.sub(r'[^a-z0-9]+', '-', text.lower()).strip('-')
    return s[:48] or 'target'


# ---------------------------------------------------------------------------
# Pipeline driver
# ---------------------------------------------------------------------------

def load_sources(root):
    src = os.path.join(root, 'config', 'source', 'c_cleaner_plus')
    gen = os.path.join(root, 'config', 'generated')
    sources = []          # list of (priority, rules)
    unparsed = []

    p1 = os.path.join(root, 'config', 'builtin', 'builtin_targets.json')
    if os.path.exists(p1):
        sources.append((1, parse_builtin_targets(p1)))

    p2 = os.path.join(src, 'builtin_system_rules.json')
    if os.path.exists(p2):
        sources.append((2, parse_builtin_system(p2)))

    # P3: curated 5-tuple custom rules
    custom_files = ['common_custom_rules.json', 'rules_ai_tools.json',
                    'rules_cn_apps.json', 'rules_dev_tools.json',
                    'rules_game_platforms.json', 'rules_design_3d_cad.json',
                    'rules_media_creation.json', 'rules_mobile_dev_tools.json']
    for cf in custom_files:
        fp = os.path.join(src, cf)
        if os.path.exists(fp):
            with open(fp, encoding='utf-8') as f:
                raw = json.load(f)
            bad = [r for r in raw if not (isinstance(r, list) and len(r) >= 5)]
            if bad:
                unparsed.append({'file': cf, 'count': len(bad),
                                 'sample': bad[0] if bad else None})
            sources.append((3, parse_tuple_rules(fp, 'c_cleaner_plus')))

    p4 = os.path.join(root, 'config', 'source', 'bleachbit_community',
                      'community_cleaners.json')
    if os.path.exists(p4):
        sources.append((4, parse_tuple_rules(p4, 'bleachbit_community')))

    p5 = os.path.join(gen, 'winapp2_latest.json')
    if os.path.exists(p5):
        sources.append((5, parse_tuple_rules(p5, 'winapp2_community')))
    else:
        print('[merge_rules] winapp2_latest.json missing; run fetch_rules.py first',
              file=sys.stderr)

    return sources, unparsed


def run(root, baseline_out):
    sources, unparsed = load_sources(root)

    # --- Step 3: normalize + Step 4: dedup ---
    dedup = OrderedDict()   # key -> rule
    stats = defaultdict(int)
    for priority, rules in sources:
        for r in rules:
            stats[r['origin']] += 1
            if r.get('target'):      # P1 curated targets pass through
                dedup[('builtin', r['name'])] = r
                continue
            r['path'] = normalize_path(r['path'])
            if not r['path']:
                stats['empty_path'] += 1
                continue
            if r.get('enabled') is False:
                stats['disabled_in_source'] += 1
                continue
            key = (r['path'].lower(), r['type'])
            if key in dedup:
                stats['deduped'] += 1
                continue
            dedup[key] = r

    # --- Step 5: tier + requiresAdmin ---
    for r in dedup.values():
        if r.get('target'):
            continue
        tier, admin = classify_tier(r)
        r['tier'] = tier
        r['requiresAdmin'] = bool(admin) if admin is not None else derive_requires_admin(r['path'])

    # --- Step 6: collapse by app key ---
    groups = OrderedDict()
    for r in dedup.values():
        if r.get('target'):
            # curated target: derive group key from its first path so that
            # peer rules from other sources fold into the same group
            gk = app_key_from_path(r['target']['paths'][0]['path'])
        else:
            gk = app_key_from_path(r['path'])
        groups.setdefault(gk, []).append(r)

    targets = []
    for gk, rules in groups.items():
        curated = next((r for r in rules if r.get('target')), None)

        # Split risky (dangerous) rules out of the main group so that a single
        # dangerous cache does not demote the whole application target.
        main_rules = [r for r in rules if not r.get('target') or
                      r['target'].get('tier') != 'dangerous']
        risky_rules = [r for r in rules if not r.get('target') and
                       r.get('tier') == 'dangerous']

        def build(group_rules, base_id, curated_def=None):
            if curated_def and group_rules is main_rules:
                t = dict(curated_def)
                existing = {p['path'].lower() for p in t['paths']}
                for r in group_rules:
                    if r.get('target') or r['path'].lower() in existing:
                        continue
                    t['paths'].append({'path': r['path'], 'type': r['type']})
                t['ruleCount'] = max(t.get('ruleCount', 1), len(group_rules))
                # do not silently demote curated tier, but do honor stricter peer
                return t

            paths, seen = [], set()
            tier, admin = 'safe', False
            origins, files = set(), set()
            for r in group_rules:
                pk = (r['path'].lower(), r['type'])
                if pk not in seen:
                    seen.add(pk)
                    paths.append({'path': r['path'], 'type': r['type']})
                if TIER_ORDER.get(r['tier'], 2) > TIER_ORDER.get(tier, 0):
                    tier = r['tier']
                admin = admin or bool(r['requiresAdmin'])
                origins.add(r['origin'])
                files.add(r['sourceFile'])
            if not paths:
                return None
            name = display_name_of(group_rules[0], gk)
            dangerous = tier == 'dangerous'
            # Very broad single-segment user-profile paths are treated dangerous
            broad = any(len(p['path'].rstrip('\\').split('\\')) <= 1 for p in paths)
            if broad:
                dangerous = True
            return {
                'id': base_id,
                'name': name,
                'category': category_of(group_rules[0]['sourceFile'], name),
                'enabled': not dangerous,
                'tier': tier,
                'requiresAdmin': admin,
                'origin': ('merged' if len(origins) > 1 else next(iter(origins), 'merged')),
                'sourceFiles': sorted(files),
                'ruleCount': len(group_rules),
                'patternType': paths[0]['type'] if paths else 'dir',
                'paths': paths,
                'preCommands': [],
                'stopProcesses': [],
                'stopServices': [],
                'risk': (group_rules[0].get('note') or '')[:160],
            }

        base_id = slugify(gk.replace('/', '-'))
        if curated and not main_rules:
            main_rules = [curated]
        t = build(main_rules, base_id, curated and curated.get('target'))
        if t:
            targets.append(t)
        if risky_rules:
            rt = build(risky_rules, base_id + '-risky')
            if rt:
                rt['name'] = rt['name'] + ' (risky parts)'
                targets.append(rt)

    targets.sort(key=lambda t: (t['tier'] not in ('safe',), -t.get('ruleCount', 1), t['id']))

    # Ensure unique ids (slug collisions across unrelated app keys)
    seen_ids = {}
    for t in targets:
        base = t['id']
        if base in seen_ids:
            seen_ids[base] += 1
            t['id'] = f"{base}-{seen_ids[base]}"
        else:
            seen_ids[base] = 1

    # --- Step 7: present ---
    gen = os.path.join(root, 'config', 'generated')
    os.makedirs(gen, exist_ok=True)
    merged_path = os.path.join(gen, 'targets.merged.json')
    with open(merged_path, 'w', encoding='utf-8') as f:
        json.dump({
            'schemaVersion': '1.0',
            'generatedAt': datetime.now(timezone.utc).isoformat(timespec='seconds'),
            'generatedBy': 'merge_rules.py',
            'targetCount': len(targets),
            'targets': targets,
        }, f, ensure_ascii=False, indent=1)
    print(f'[merge_rules] merged library: {len(targets)} targets -> {merged_path}')

    # Baseline: curated + built-in + custom only (exclude community bulk)
    baseline = [t for t in targets
                if t.get('origin') in ('builtin', 'c_cleaner_plus_builtin',
                                       'c_cleaner_plus', 'merged')
                and 'winapp2_community' not in (t.get('sourceFiles') or [])
                and 'community_cleaners.json' not in (t.get('sourceFiles') or [])]
    baseline_payload = {
        'schemaVersion': '1.0',
        'notes': 'Baseline target list (curated + c_cleaner_plus built-in/custom). '
                 'Full library incl. community rules lives in '
                 'config/generated/targets.merged.json (pass -ConfigPath to the engine).',
        'targets': baseline,
    }
    with open(baseline_out, 'w', encoding='utf-8') as f:
        json.dump(baseline_payload, f, ensure_ascii=False, indent=1)
    print(f'[merge_rules] baseline: {len(baseline)} targets -> {baseline_out}')

    example_path = os.path.join(root, 'config', 'targets.example.json')
    if not os.path.exists(example_path):
        example = {
            'schemaVersion': '1.0',
            'notes': 'Schema example. Copy to targets.json and edit per machine.',
            'targets': [baseline[0]] if baseline else [],
        }
        with open(example_path, 'w', encoding='utf-8') as f:
            json.dump(example, f, ensure_ascii=False, indent=1)
        print(f'[merge_rules] example schema -> {example_path}')

    report = {
        'generatedAt': datetime.now(timezone.utc).isoformat(timespec='seconds'),
        'inputCounts': dict(stats),
        'deduped': stats['deduped'],
        'mergedTargets': len(targets),
        'baselineTargets': len(baseline),
        'tierDistribution': {k: sum(1 for t in targets if t['tier'] == k)
                             for k in ('safe', 'caution', 'dangerous')},
        'unparsed': unparsed,
    }
    report_path = os.path.join(gen, 'merge_report.json')
    with open(report_path, 'w', encoding='utf-8') as f:
        json.dump(report, f, ensure_ascii=False, indent=2)
    print(f'[merge_rules] report -> {report_path}')
    print(f'[merge_rules] tiers: {report["tierDistribution"]}')
    return 0


def category_of(source_file, name):
    if source_file.startswith('rules_ai_tools'):
        return 'AI Tools'
    if source_file.startswith('rules_cn_apps'):
        return 'CN Apps'
    if source_file.startswith('rules_dev_tools'):
        return 'Dev Tools'
    if source_file.startswith('rules_game'):
        return 'Games'
    if source_file.startswith('rules_design'):
        return 'Design/3D/CAD'
    if source_file.startswith('rules_media'):
        return 'Media'
    if source_file.startswith('rules_mobile'):
        return 'Mobile Dev'
    if source_file in ('builtin_targets.json', 'builtin_system_rules.json'):
        return 'Curated'
    if source_file == 'community_cleaners.json':
        return 'BleachBit Community'
    if source_file == 'winapp2_latest.json':
        return 'Winapp2 Community'
    n = name.lower()
    if any(k in n for k in ('chrome', 'edge', 'firefox', 'brave', 'opera', 'vivaldi', '浏览器')):
        return 'Browsers'
    if any(k in n for k in ('wechat', 'qq', '微信', '钉钉', '飞书', 'wps', 'tim', 'wxwork')):
        return 'CN Apps'
    if any(k in n for k in ('nvidia', 'amd', 'shader', 'd3d', 'gpu')):
        return 'GPU'
    if any(k in n for k in ('temp', 'windows', 'update', 'wer', 'dump', 'system')):
        return 'System'
    return 'Applications'


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    root = os.path.normpath(os.path.join(here, '..'))
    ap = argparse.ArgumentParser()
    ap.add_argument('--root', default=root)
    ap.add_argument('--baseline-out',
                    default=os.path.join(root, 'config', 'targets.json'))
    args = ap.parse_args()
    return run(args.root, os.path.normpath(args.baseline_out))


if __name__ == '__main__':
    sys.exit(main())
