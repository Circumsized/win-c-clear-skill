#!/usr/bin/env python3
# -*- coding: utf-8 -*-
r"""
generate_rules_catalog.py — 从 assets/rules/ 生成「分类评级」的规则参考文档。

用途
----
把社区精选规则集（common_custom_rules + rules_*）逐个转换改写
为可读的 Markdown 参考文档，写入 references/rulesets/，并在 references/ 生成一份
分类评级总览 rules-catalog.md，供 skill 执行时引导用户选择规则集。

评级语义
--------
tier 评级来自 merge_rules.classify_tier —— 那是一套**独立的 Python 关键词启发式**，
与引擎实际执行的 Get-AutoTier（Invoke-CDriveCleanup.ps1 内的编译正则）**并非同源**，
两者存在双向分歧（例：含 "User Data" 的路径在此判 dangerous，引擎按末段 "cache" 判 safe；
"cookies"/"history" 在此判 caution，引擎判 dangerous）。

因此本脚本产出的文档只用于「选哪些规则集」的规模与风险感知，**不可**用来判断某条规则
会不会被自动清理。真实分级以引擎合并产物 config/targets.merged.json 为唯一权威。
社区大源（winapp2/bleachbit/cdisk_自定义）只做统计数据、不逐条列出（体量过大且默认 opt-in）。

用法
----
    python tools/generate_rules_catalog.py

规则集更新后重跑本脚本即可同步 reference 文档。
"""

import json
import os
import sys
from collections import OrderedDict, defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
# NOTE: 独立启发式，非引擎同源（见上方「评级语义」）。merge_rules 模块级只有常量定义且带
# __main__ 保护，因此 import 不会触发它对 config/source 等缺失目录的读取。
from merge_rules import classify_tier

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
RULES_DIR = os.path.join(ROOT, 'assets', 'rules')
OUT_DIR = os.path.join(ROOT, 'references', 'rulesets')

# 分类映射：源文件 -> (category key, 中文分类名)
# 与引擎 Get-CategoryForSource 保持一致（general/cn/dev/design/ai/game/media）
CATEGORY = OrderedDict([
    ('common_custom_rules.json', ('general', '通用规则')),
    ('rules_cn_apps.json', ('cn', '国产软件')),
    ('rules_dev_tools.json', ('dev', '开发工具')),
    ('rules_mobile_dev_tools.json', ('dev', '开发工具（移动端）')),
    ('rules_design_3d_cad.json', ('design', '设计建模')),
    ('rules_ai_tools.json', ('ai', 'AI 软件')),
    ('rules_game_platforms.json', ('game', '游戏平台')),
    ('rules_media_creation.json', ('media', '影音创作')),
])

# 描述性中文分类说明（用于文档导读）
CATEGORY_DESC = {
    'general': '跨应用的通用临时/缓存/日志目录，覆盖面广、默认 opt-in，需按机况勾选。',
    'cn': '国产应用（腾讯/金山/字节/百度/360/搜狗等）的缓存与日志，国内用户常装。',
    'dev': 'IDE / 编译器 / 构建工具 / 移动开发工具链的可再生缓存与日志。',
    'design': '3D / CAD / 设计类软件的临时与着色器缓存（建模项目本身不在这些目录）。',
    'ai': '本地大模型运行时与 AI 客户端的日志 / Electron 缓存（模型权重不在此处）。',
    'game': '游戏平台 / 启动器的下载落地缓存、嵌入式浏览器缓存与日志。',
    'media': '影音剪辑 / 直播 / 创作类软件的日志、崩溃转储与预览缓存。',
}

# 中文分类名（用于文档标题）
CATEGORY_DESC_CN = {
    'general': '通用规则',
    'cn': '国产软件',
    'dev': '开发工具',
    'design': '设计建模',
    'ai': 'AI 软件',
    'game': '游戏平台',
    'media': '影音创作',
}

# 社区/系统大源：只统计（体量过大，不逐条列出）
BULK_SOURCES = [
    ('winapp2_latest.json', 'community', 'Winapp2 社区规则（MoscaDotTo，opt-in）', 'tuple'),
    ('community_cleaners.json', 'community', 'BleachBit cleaners（仅 Windows 路径，opt-in）', 'tuple'),
    ('cdisk_cleaner_custom_rules.json', 'community', '社区自定义规则导出（opt-in）', 'tuple'),
    # system 类：运行时勾选状态，双重编码 v2（order 内每个元素 = [规则JSON字符串, 勾选状态]）
    ('cdisk_cleaner_config.json', 'system', '应用勾选状态（含系统规则，双重编码 v2，opt-in）', 'double_encoded'),
]

TIER_EMOJI = {'safe': '🟢 safe', 'caution': '🟡 caution', 'dangerous': '🔴 dangerous'}
TIER_CN = {'safe': '安全', 'caution': '谨慎', 'dangerous': '危险'}


def derive_admin(path):
    # 同时识别环境变量形式与绝对路径形式（cdisk_cleaner_config 存的是绝对路径）
    p = (path or '').upper()
    for seg in ('%WINDIR%', '%PROGRAMDATA%', '%PROGRAMFILES%', '%SYSTEMDRIVE%\\WINDOWS',
                'C:\\WINDOWS', 'C:\\PROGRAMDATA', 'C:\\PROGRAM FILES'):
        if p.startswith(seg):
            return True
    return False


def parse_tuple_file(path):
    """解析 5/6 元组规则集，返回 rule dict 列表。"""
    with open(path, encoding='utf-8') as f:
        data = json.load(f)
    out = []
    for r in data:
        if not isinstance(r, list) or len(r) < 3:
            continue
        name = str(r[0])
        rpath = str(r[1])
        rtype = str(r[2] or 'dir')
        note = str(r[4]) if len(r) >= 5 else ''
        rule = {'name': name, 'path': rpath, 'type': rtype,
                'tier': None, 'requiresAdmin': None, 'note': note}
        tier, _ = classify_tier(rule)
        # r[3] 显式为 True 时尊重；否则按系统路径推断（与引擎 merge 期 admin 推导一致）
        if len(r) >= 4 and isinstance(r[3], bool) and r[3]:
            admin = True
        else:
            admin = derive_admin(rpath)
        out.append({'name': name, 'path': rpath, 'type': rtype,
                    'tier': tier, 'admin': admin, 'note': note})
    return out


def parse_double_encoded_config(path):
    """解析 cdisk_cleaner_config.json 双重编码 v2 格式。

    结构：{"order": ["[<规则JSON字符串>, <勾选状态>]", ...], "states": {...}}
    每个 order 元素经两层 json.loads 还原成 6 元组
    [名称, 路径, 类型, 说明, 是否勾选, glob]。
    """
    with open(path, encoding='utf-8') as f:
        data = json.load(f)
    out = []
    for e in data.get('order', []):
        if not isinstance(e, str):
            continue
        try:
            outer = json.loads(e)          # -> [规则JSON字符串, 勾选状态]
        except (ValueError, TypeError):
            continue
        if not isinstance(outer, list) or len(outer) < 1 or not isinstance(outer[0], str):
            continue
        try:
            inner = json.loads(outer[0])   # -> 6 元组
        except (ValueError, TypeError):
            continue
        if not isinstance(inner, list) or len(inner) < 3:
            continue
        name = str(inner[0])
        rpath = str(inner[1])
        rtype = str(inner[2] or 'dir')
        note = str(inner[3]) if len(inner) >= 4 else ''
        rule = {'name': name, 'path': rpath, 'type': rtype,
                'tier': None, 'requiresAdmin': None, 'note': note}
        tier, _ = classify_tier(rule)
        admin = derive_admin(rpath)
        out.append({'name': name, 'path': rpath, 'type': rtype,
                    'tier': tier, 'admin': admin, 'note': note})
    return out


def build_tier_histogram(rules):
    hist = defaultdict(int)
    for r in rules:
        hist[r['tier']] += 1
    return OrderedDict((k, hist[k]) for k in ('safe', 'caution', 'dangerous'))


def write_ruleset_doc(key, title, desc, rules, notes=None):
    """写单个规则集明细文档。"""
    out_path = os.path.join(OUT_DIR, f'{key}.md')
    lines = []
    lines.append(f'# {title}（{key}）规则集')
    lines.append('')
    lines.append(f'> {desc}')
    lines.append('')
    lines.append('> ⚠️ **本表「评级」列不是引擎的实际分级。** 它由 `merge_rules.classify_tier`')
    lines.append('> （独立的 Python 关键词启发式）生成，与引擎的 `Get-AutoTier` 双向分歧：例如含')
    lines.append('> `User Data` 或 `dxcache` 的路径在此偏严（caution/dangerous），引擎按末段 `cache`')
    lines.append('> 判 **safe** 并默认启用；`cookies`/`history` 在此偏松（caution），引擎判 **dangerous**。')
    lines.append('> 真实分级与 enabled 状态以 `config/targets.merged.json` 或 `-Mode Scan` 输出为准。')
    lines.append('')
    lines.append('| 名称 | 路径 | 类型 | 评级 | 需管理员 | 说明 |')
    lines.append('|------|------|------|------|---------|------|')
    for r in sorted(rules, key=lambda x: (x['tier'], x['name'].lower())):
        tier_txt = f"{TIER_EMOJI[r['tier']]} ({TIER_CN[r['tier']]})"
        admin = '是' if r['admin'] else ''
        note = (r['note'] or '').replace('|', '\\|').strip()
        name = (r['name'] or '').replace('|', '\\|').strip()
        path = (r['path'] or '').replace('|', '\\|').strip()
        lines.append(f'| {name} | `{path}` | {r["type"]} | {tier_txt} | {admin} | {note} |')
    lines.append('')
    hist = build_tier_histogram(rules)
    lines.append('## 评级分布')
    lines.append(f'| 评级 | 数量 |')
    lines.append('|------|------|')
    for k in ('safe', 'caution', 'dangerous'):
        lines.append(f'| {TIER_EMOJI[k]}（{TIER_CN[k]}） | {hist[k]} |')
    lines.append('')
    lines.append(f'共 {len(rules)} 条规则。引擎的实际默认启用规则是「引擎判定为 safe 且未被护栏降级」，')
    lines.append('与本表评级不一定一致（见文首警告）；caution/dangerous 一律需 `-ConfirmIds` 显式确认。')
    lines.append('')
    if notes:
        lines.append('## 说明')
        for n in notes:
            lines.append(f'- {n}')
        lines.append('')
    with open(out_path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines))
    return out_path, hist, len(rules)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)

    per_category = defaultdict(list)   # key -> rules
    total = 0

    for filename, (key, title) in CATEGORY.items():
        path = os.path.join(RULES_DIR, filename)
        if not os.path.exists(path):
            print(f'[skip] {filename} 不存在')
            continue
        rules = parse_tuple_file(path)
        per_category[key].extend(rules)
        total += len(rules)
        print(f'[parsed] {filename}: {len(rules)} 条 -> {key}')

    # 每类写一个明细文档（dev 含 dev+mobile 两个源）
    catalog_rows = []
    for key in per_category:
        rules = per_category[key]
        if not rules:
            continue
        title = CATEGORY_DESC_CN.get(key, key)
        out_path, hist, cnt = write_ruleset_doc(key, title, CATEGORY_DESC[key], rules)
        catalog_rows.append((key, title, cnt, hist))
        print(f'[wrote] {os.path.relpath(out_path, ROOT)} ({cnt} 条)')

    # BULK 源统计（体量大，仅统计 tier 分布，不逐条列出）
    bulk_stats = []
    for filename, key, desc, parser in BULK_SOURCES:
        path = os.path.join(RULES_DIR, filename)
        if not os.path.exists(path):
            continue
        if parser == 'double_encoded':
            rules = parse_double_encoded_config(path)
        else:
            rules = parse_tuple_file(path)
        hist = build_tier_histogram(rules)
        bulk_stats.append((key, desc, len(rules), hist))
        print(f'[bulk] {filename}: {len(rules)} 条 ({parser})')

    # 写总览 rules-catalog.md
    catalog_path = os.path.join(ROOT, 'references', 'rules-catalog.md')
    lines = []
    lines.append('# 规则目录与分类评级（rules-catalog.md）')
    lines.append('')
    lines.append('本文件是 skill 清理规则集的**分类评级索引**，用于引导用户按需选择规则集。')
    lines.append('明细见 [references/rulesets/](rulesets/) 下各分类文档。')
    lines.append('')
    lines.append('> ⚠️ **评级权威性说明**')
    lines.append('>')
    lines.append('> 本目录及 `rulesets/` 下的 tier 评级由 `tools/generate_rules_catalog.py` 调用')
    lines.append('> `merge_rules.classify_tier` 生成，那是一套**独立的关键词启发式**，与引擎实际执行的')
    lines.append('> `Get-AutoTier`（`Invoke-CDriveCleanup.ps1` 内的编译正则）**并非同源**。')
    lines.append('>')
    lines.append('> 两者已知分歧（双向都有）：')
    lines.append('>')
    lines.append('> | 路径特征 | 本目录评级 | 引擎实际 tier | 方向 |')
    lines.append('> |---------|-----------|--------------|------|')
    lines.append('> | `dxcache` / `glcache` / `computecache` / `nv_cache` | caution | **safe** | 文档偏严 |')
    lines.append('> | 含 `User Data` 的路径（如 Chrome 缓存） | dangerous | **safe**（末段 `cache` 命中） | 文档偏严 |')
    lines.append('> | `cookies` / `history` | caution | **dangerous** | 文档偏松 |')
    lines.append('> | `快照` / `遥测` / `workspace` / 裸 `update` | safe / dangerous | **dangerous**（无信号→红线兜底） | 视条目而定 |')
    lines.append('>')
    lines.append('> **引擎是唯一权威**：实际 tier、enabled 与门控一律以 `config/targets.merged.json`')
    lines.append('> （由引擎合并管线生成）为准。本目录仅用于「选哪些规则集」的规模感知，')
    lines.append('> **不要**用它判断某条规则会不会被自动清理。要看真实分级，读 merged 产物或跑 `-Mode Scan`。')
    lines.append('')
    lines.append('## 分类总览')
    lines.append('')
    lines.append('| RuleSets 参数 | 分类 | 规则数 | safe | caution | dangerous | 明细文档 |')
    lines.append('|--------------|------|--------|------|---------|-----------|---------|')
    for key, title, cnt, hist in catalog_rows:
        lines.append(f'| `{key}` | {title} | {cnt} | {hist["safe"]} | {hist["caution"]} | {hist["dangerous"]} | [rulesets/{key}.md](rulesets/{key}.md) |')
    for key, desc, cnt, hist in bulk_stats:
        lines.append(f'| `{key}` | {desc} | {cnt} | {hist["safe"]} | {hist["caution"]} | {hist["dangerous"]} | （体量过大，仅统计） |')
    lines.append('')
    lines.append(f'**curated 规则合计 {total} 条**；另有社区/系统大源见上表（默认 opt-in，不逐条列出）。')
    lines.append('')
    lines.append('## 引导选择（skill 执行第 1 步话术）')
    lines.append('')
    lines.append('默认 `-RuleSets minimal`（仅内置白名单，最安全）。如需扩展到某类应用，按用户已装软件')
    lines.append('选择，多选用逗号，例如 `-RuleSets cn,dev,ai`。')
    lines.append('')
    lines.append('| 用户场景 | 推荐 RuleSets |')
    lines.append('|---------|--------------|')
    lines.append('| 只想安全清理、不确定装了什么 | `minimal` |')
    lines.append('| 深度清理开发环境缓存 | `minimal,dev` |')
    lines.append('| 国内办公电脑（WPS/微信/钉钉/飞书等） | `minimal,cn` |')
    lines.append('| 设计 / 3D / CAD 工作站 | `minimal,design` |')
    lines.append('| 本地跑大模型 / AI 客户端 | `minimal,ai` |')
    lines.append('| 游戏玩家（Steam/Epic/Riot 等） | `minimal,game` |')
    lines.append('| 剪辑 / 直播 / 创作 | `minimal,media` |')
    lines.append('| 全量（含社区万级规则，慎用） | `all` |')
    lines.append('')
    lines.append('> 提示：caution/dangerous 规则默认禁用，清理前需 `-ConfirmIds` 逐项确认；')
    lines.append('> `system`/`community` 类规则默认 opt-in，仅当用户明确需要时才加载。')
    lines.append('')
    with open(catalog_path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines))
    print(f'[wrote] references/rules-catalog.md')


if __name__ == '__main__':
    main()