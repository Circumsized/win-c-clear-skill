---
name: win-c-clear-skill
description: >-
  当用户提到 C 盘满了 / C 盘空间不足 / 清理缓存 / 释放磁盘空间 / 磁盘清理 / 清理垃圾 /
  释放空间 / reclaim Windows space / C drive full / clean disk caches / free up space /
  disk cleanup,或点名 win-c-clear-skill 时使用本技能。面向 Agent 的 Windows C 盘清理技能:
  先扫描后删除、三级风险分级(safe/caution/dangerous)、社区规则合并(1.5 万+目标:winapp2.ini
  v260730、BleachBit cleaners、c_cleaner_plus)、并行扫描+智能尺寸缓存(重复扫描瞬时返回)、
  Restart Manager 锁检测、GPU/CPU 重复文件哈希级联、工作集整理、稳定的紧凑 JSON_SUMMARY
  数据契约。适配 Claude Code、DeepSeek Harness (dsh)、codex、Trae、Cursor。
  首次清理通常可回收 20-150 GB 可再生缓存。
license: MIT
compatibility: >-
  Windows 10/11/Server (x64). Requires PowerShell 5.1+ (bundled with Windows);
  Python 3.8+ only for optional rule-refresh tooling. No network access needed
  at runtime (community rules are vendored in assets/rules/).
metadata:
  author: win-c-clear-skill contributors
  version: "1.0.0"
  homepage: https://github.com/Circumsized/win-c-clear-skill
---

# win-c-clear-skill

Free space on Windows `C:` by scanning and cleaning **configurable, mostly regenerable caches**,
driven by natural language through any agent that loads `SKILL.md`. Respond in the **user's language**.
Engine highlights: c_cleaner_plus rule merging, parallel scanning, and engine-level safety gates.

## When to use

- User mentions C: full / low disk / clean caches / reclaim space / C盘清理
- User says to use this skill (`win-c-clear-skill`)
- User asks what is eating disk space (→ run Analyze)
- User wants a reusable cleanup script generated from this machine

## Do NOT use for

- Deleting random project source trees or user documents
- Manual `WinSxS` / system restore deletion
- Uninstalling software without explicit per-app user request
- Cleaning D:/E: drives (this skill is C:-only by design; say so and suggest alternatives)

## Layout (progressive disclosure)

```text
win-c-clear-skill/
  SKILL.md                     # this file - workflow + red lines (read first)
  reference.md                 # confirmation protocols, red-line details (read on demand)
  README.md                    # install / standalone usage (read on demand)
  CONTRIBUTING.md / SECURITY.md / CODE_OF_CONDUCT.md / LICENSE
                               # open-source community & compliance files
  references/                  # loadable reference DOCS (read on demand)
    README.md                  # index
    rules-and-merging.md       # rule sources, merge pipeline, rule-set categories, upgrade how-to
    rules-catalog.md           # rule-set catalog: per-category counts + tier distribution + selection guide
    rulesets/                  # per-category rated rule details (general/cn/dev/design/ai/game/media)
    bleachbit-design.md        # BleachBit design study & what we adopted
    winapp2-adaptation.md      # winapp2.ini format & wildcard adaptation
    harness-adaptation.md      # claude code / codex / deepseek harness notes
    guardrails.md              # protected-path spec, fences, plan gate (engine blacklist)
    windows-api.md             # Windows API deep reference (MFT/RM/deletion/VSS/CBS...)
  assets/rules/                # SELF-CONTAINED rule data (~15.4k targets, vendored)
    winapp2_latest.json        #   fresh Winapp2.ini v260730 (14117 entries)
    community_cleaners.json    #   fresh BleachBit cleaners (986 entries)
    rules_*.json + cdisk_*.json#   curated c_cleaner_plus rules + app state
  config/targets.json          # builtin whitelist (87 targets, editable per machine)
  config/scan-lists.json       # scan whitelist (safe dirs) + blacklist (system core) + scan modes
  config/targets.merged.json   # [generated] builtin + rules merged (origin + signals trace)
  config/user-overrides.json   # [generated] user enable/disable choices
  config/scan-cache.json       # [generated] smart size cache (mtime+TTL)
  scripts/Invoke-CDriveCleanup.ps1   # engine: Scan|Clean|Analyze|MergeConfig
  scripts/Scan.bat / Clean-Safe.bat # double-click entries
  tools/install-harness.ps1    # one-click install: claude / codex / deepseek harness dirs
  tools/fetch_rules.py         # rule refresh tooling + _cache
  tools/generate_rules_catalog.py   # regen references/rulesets/ + rules-catalog.md from assets/rules
  tools/test-scan-lists.py     # unit test: blacklist/whitelist pattern semantics (39 cases)
  tools/restore-quarantine.ps1 # restore quarantined items from manifest
  logs/                        # [generated] audit logs (structured modular reports)
  quarantine/                  # [generated] quarantine roots (-RecoveryMode quarantine)
  backups/                     # [generated] dangerous-tier backups (-BackupDangerous)
```

**Harness install**: `powershell -File tools\install-harness.ps1 -All` (Claude Code
`~/.claude/skills`, codex `~/.codex/skills` + AGENTS.md pointer, DeepSeek Harness
`~/.agents/skills`; `-Symlink` for junctions). Details: [references/harness-adaptation.md](references/harness-adaptation.md).

**Rule dependency**: self-contained and portable — `assets/rules/` vendors the community rule set
(Winapp2 v260730 + BleachBit cleaners + curated c_cleaner_plus rules) and `mergeSources` points to it
via a skill-relative path. `externalMergeSources` is empty by default; add ABSOLUTE paths only if you
have a local c_cleaner_plus install (never required). Refresh via `tools/fetch_rules.py`.
Details: [references/rules-and-merging.md](references/rules-and-merging.md).

## Mandatory workflow (track visibly, never skip steps)

```text
Cleanup progress:
- [ ] 1) Detect OS + guide rule-set selection (NOT loaded by default; present the menu)
- [ ] 2) Scan (no deletion), parse JSON_SUMMARY — this creates the approval plan
- [ ] 3) Present the cleanable list and WAIT for explicit user approval (engine-enforced plan gate)
- [ ] 4) Clean only user-confirmed targets (tier gates + recovery mode + elevation rules)
- [ ] 5) Report in user's language: per-item before/after/freed, totals, C: free delta, leftovers, log path
- [ ] 6) Offer reusable script generation (ask once)
```

Copy this checklist into the conversation and tick items as you go.
**Never** run Clean before a Scan. **Never** delete without user approval — the engine
blocks Clean without a scan plan ≤30 min old (exit 4), but the agent must still present
the list and get a clear yes first.

### 1) Rule-set selection guidance (rules are NOT all loaded by default)

Always offer the menu on first use of a session (default = `minimal`, builtin whitelist only):

> 规则集选择（默认极简）：**极简**（内置白名单，最稳）/ 通用 / 国产软件 / 开发工具 /
> 设计建模 / AI 软件 / 游戏平台 / 影音创作 / 系统缓存 / 社区扩展（winapp2+BleachBit，量大）/
> all 全量。可多选逗号组合。当前装了什么就开什么类。

```powershell
-RuleSets minimal     # default: builtin only (87 curated targets)
-RuleSets cn,dev      # e.g. CN apps + dev tools
-RuleSets all         # everything incl. 15k community rules
```

`none` is an alias of `minimal` (rule-free execution = builtin whitelist only).

### 1b) Config merge (automatic)

The engine auto-merges `mergeSources` directories (bundled `assets/rules/` by default; optional
absolute-path extras via `externalMergeSources`) into `targets.merged.json` when stale. Manual re-merge:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill>/scripts/Invoke-CDriveCleanup.ps1" -Mode MergeConfig
```

Merge pipeline (deterministic, reproducible): discover → parse (5/6-tuple JSON, double-encoded v2 format) →
normalize paths to env vars → dedupe by normalized path (conservative tier wins) → auto-tier
(cache/temp/log→safe; download/package→caution; backup/data/file→dangerous; **unknown→dangerous**) →
merge with builtin (origin: builtin|c_cleaner_plus|merged; builtin never overwritten) → persist.

### 2) Scan (never delete in this step)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill>/scripts/Invoke-CDriveCleanup.ps1" -Mode Scan -Tiers safe,caution,dangerous
```

Parse the `JSON_SUMMARY` block from stdout (between `JSON_SUMMARY_BEGIN`/`JSON_SUMMARY_END`).
**Trust only JSON_SUMMARY** — never infer results from console text. Note `drive.freeGB_before`.
Missing paths → `exists:false` and are excluded from totals. Large dirs unreadable in part are
flagged `message:"partial: ... estimate"`.

#### Scan scope control (whitelist/blacklist — default ON)

The engine scans **only preset safe-to-clean directories** (config/scan-lists.json whitelist,
~124 paths: user temp / browser caches / dev tool caches / GPU shader caches / Windows
regenerable caches / app caches) and **never enters system core areas** (blacklist ∪ engine
GuardPatterns: WinSxS, System32 config/drivers, Installer, GAC, Program Files, Windows.old,
NTUSER.DAT, pagefile/hiberfil, Boot/BCD, Winevt, EFI, Recovery...). This replaces full-disk
scans → much faster, and scanning cannot stray into protected zones.

```powershell
-PathFilter whitelist   # default: whitelist-only scanning (blacklist always enforced)
-PathFilter both        # explicit whitelist + blacklist (blacklist is ALWAYS unioned with engine GuardPatterns)
-PathFilter off         # disable path filtering (not recommended; deletion-point guardrails still apply)
-NoWhitelist / -NoBlacklist  # individually disable either list
```

#### Scan modes (speed vs depth)

```powershell
-ScanMode fast       # depth 1 — quickest, top-level cache dirs only
-ScanMode standard   # default: depth 3, no junctions
-ScanMode deep       # full recursion within whitelist, blacklist enforced
-ScanMode diagnostic # audit mode: report blacklist hits without cleaning
```

Scan rating (A–F) is computed from reclaimable size / skips / blacklist hits and printed
in the summary (`scanRating: {grade, score, status}`) — present it to the user as the
"system clutter grade" in step 5 reporting.

### 3) Report + selection prompt

Present a concise table: id / name / sizeGB / tier / exists, plus C: free. Then prompt with
options + consequences + default (three elements mandatory):

> 建议清理 safe 档共 N 项（约 X GB）；caution 档 M 项需点名确认（可能影响修复/更新）；
> dangerous 档默认跳过（可能丢数据）。回复：全部safe / 具体id（如 uv-cache,wu-download）/ 取消。

For c_cleaner_plus merged rules (origin `c_cleaner_plus`), proactively list them (top ones by size)
and offer per-id enable/disable. Write the user's choices to `config/user-overrides.json`
(`{"version":1,"enabled":{"<id>":true|false}}`); the engine applies them on next run.

### 4) Clean confirmed targets only

```powershell
# safe tier only (one confirmation is enough)
... -Mode Clean -Tiers safe -Elevate -LogPath "<skill-root>\logs\wincc_log_<ts>.txt"

# specific ids incl. caution (user must have named them):
... -Mode Clean -Ids "uv-cache,wu-download" -ConfirmIds "wu-download" -Tiers safe,caution -Elevate
```

Engine-level gates (defense in depth; agent must ALSO follow reference.md protocols):

- `-ConfirmIds` required for any caution/dangerous id (two-phase confirmation, see reference.md)
- `-AllowStop` required before any process/service stop; ask user first, list affected apps
- `-BackupDangerous` backs up dangerous targets to Desktop before deletion
- `-DryRun` rehearses everything with zero deletion (use for audits)
- `-Elevate` triggers UAC; on decline → clean non-admin targets, report `need-admin` with exact
  rerun command, never claim full success

### 5) Report (user's language)

From JSON_SUMMARY only: per-item before/after/freed, `totals.freedGB`, C: free before→after,
`need-admin`/`locked` leftovers with suggestions, `logPath`. Numbers are 2-decimal GB.

### 6) Reusable script (ask once)

After a successful clean, offer once: generate ASCII-named `.ps1`/`.bat` on Desktop (UTF-8 BOM)
based on current confirmed ids. Skip silently if user declines.

## Target tiers

| Tier | Meaning | Confirmation |
|------|---------|--------------|
| `safe` | Regenerable caches | Confirm selection once after scan |
| `caution` | May affect repair/update downloads | User must name the id (`-ConfirmIds`) |
| `dangerous` | Data/app loss risk | `enabled:false` default + two-phase protocol (reference.md) |

Unknown/unclassifiable targets are **always dangerous + disabled** — never guess safe.

## JSON_SUMMARY contract (v1)

```json
{
  "schemaVersion": 1,
  "mode": "Scan|Clean|Analyze|MergeConfig",
  "os": {"caption":"", "build":"", "isServer":false},
  "drive": {"letter":"C", "freeGB_before":0, "freeGB_after":0},
  "items": [{"id":"","name":"","tier":"safe|caution|dangerous","origin":"builtin|c_cleaner_plus|merged",
             "enabled":true,"exists":true,"requiresAdmin":false,
             "sizeGB_before":0,"sizeGB_after":0,"freedGB":0,
             "status":"scanned|cleaned|skipped|need-admin|locked|dryrun|error","message":""}],
  "totals": {"freedGB":0,"cleaned":0,"skipped":0,"needAdmin":0,"errors":0},
  "logPath": ""
}
```

Analyze mode adds: `topDirs[]`, `largeFiles[]`, `duplicateGroups[]`, `hashPath` (gpu-cupy or cpu-parallel),
`storageSenseEnabled`, `suggestions[]`. MergeConfig mode adds `merge` stats + compact `items` for selection UI.

## Analyze (diagnostic mode — when caches are small but C: is still full)

```powershell
... -Mode Analyze
```

Read-only. Scan roots are resolved from **enabled rule targets only** (never generic
USERPROFILE/ProgramData/Program Files recursion); reports Top-20 first-level dirs under those
roots, files ≥1GB, duplicate groups (size → 64KB head+tail hash → full MD5 cascade, GPU-cupy when
available else CPU-parallel, path noted in `hashPath`), Storage Sense state, and
migrate/junction/uninstall suggestions. Depth/file budgets follow `-ScanMode`
(fast 3/500k, standard 6/2M, deep 12/unlimited); MFT pass applies the same boundary filter
(paths outside rule roots or matching the blacklist are counted but never reported).
**Never delete from Analyze output without a separate confirmed Clean.**

## Windows-native integrations (native commands & APIs preferred)

- `wevtutil cl <log>` clears Event Logs (Application/System/Setup caution; Security dangerous)
- `powercfg /h off` removes hiberfil.sys cleanly (never direct file deletion)
- `uv cache clean` / `pip cache purge` / `npm cache clean --force` as `preCommands` (auto-skipped if
  tool absent)
- `takeown` / `icacls` + delete for Windows.old (two-phase confirmed dangerous)
- `robocopy /L` as native fallback when .NET enumeration is access-denied
- **Restart Manager (`rstrtmgr.dll` P/Invoke)**: when files are locked, reports the holding
  processes (name+pid) in item.message — adopted from WindowsClear; closing stays behind `-AllowStop`
- `Clear-RecycleBin` (special target, caution, disabled by default)
- Working-set trim (`EmptyWorkingSet` via psapi P/Invoke) — only with `-TrimWorkingSet`, only for
  cleaned targets' processes, never system-critical processes
- Storage Sense state read (registry) in Analyze; DISM `StartComponentCleanup`, `cleanmgr` and
  `vssadmin` are **suggestions only** — never executed by this skill

## Strategy & performance layer

- `-Policy conservative|standard|deep`: conservative = safe + builtin-only (ignores community
  enablement); deep = adds caution candidates to Clean (gates unchanged). Explicit `-Tiers` overrides
- **Smart size-cache** (`config/scan-cache.json`, mtime+TTL validated): repeat scans in the same
  session return instantly — measured 188.6s cold → **11ms cached** with byte-identical numbers.
  Use `-NoCache` for exact re-measurement (e.g., right after a clean)
- **Modern scan engines** (C#, [references/windows-api.md](references/windows-api.md)):
  - `ParallelScanner` — Task.WhenAll + SemaphoreSlim async recursive scan with **scan-mode budgets**
    (fast: depth3/500k files/60s · standard: depth6/2M/300s · deep: depth12/unlimited/900s),
    reparse-point guards (junctions/symlinks never followed), per-root budget tracking, and
    BelowNormal I/O priority; falls back to a runspace pool when the C# type fails to load
  - `MftScanner` — **NTFS MFT direct read** in Analyze: parses MFT's own run-list, boundary-filtered
    (only paths under rule roots and not blacklist-matched appear in output); reports true exclusive
    usage (hardlink-aware). `scanPath:"ntfs-mft"` vs `dotnet-parallel`; auto-fallback on
    non-admin/non-NTFS/parse failure; `-NoMft` disables
- Two-level parallel scanning + small-task batching + BelowNormal priority

## Recovery modes (万一需要找回)

```powershell
-RecoveryMode permanent   # default: direct delete — the ONLY mode that frees space immediately
-RecoveryMode recycle     # send to Recycle Bin (SHFileOperation) — restore from the bin
-RecoveryMode quarantine  # move to <skill-root>\quarantine\wincc-quarantine_<ts>\ + manifest.json
                          #   restore: powershell -File tools\restore-quarantine.ps1 -Manifest <path> [-List|-Only <substr>]
```

Quarantine keeps a full audit manifest (original→quarantined, sizes) and a one-command restore.
Note: recycle/quarantine move data within C: — disk free does not increase until purged; offer them
when the user asks "能找回吗", default to permanent when they just want space.

## Engine-enforced safety fences (defense in depth)

1. **Plan gate**: Clean (non-DryRun) requires a Scan plan ≤30 min old (`config/last-scan.json`,
   written by every Scan) — exit 4 otherwise. Automation: `-PlanFile <path>`
2. **Scan-scope fence**: scanning runs only inside the preset safe-dir whitelist
   (`config/scan-lists.json`); system core areas are blacklisted from scanning
   (blacklist ∪ engine GuardPatterns — triple guarantee: scan filter + merge demotion + deletion re-assert)
3. **Whitelist-only ids** + **protected-path blacklist** (see Guardrails section)
4. **Hot-file fence**: items modified < `-HotMinutes` (default 30) are skipped as "likely in
   active use" and survive (verified: fresh temp file survives a clean; root dir only removed when empty)
5. **Risky-extension fence**: exe/dll/sys/msi/... files are skipped in permanent mode for
   non-builtin safe/caution targets (builtin curated targets own their extensions)
6. **RM lock reporting**: locked files report the holding process (name+pid)
7. **Audit trail**: every run writes a structured modular report (8 sections: overview /
   environment / drive / target stats / results / fences / top-10 details / artifacts) to
   `<skill-root>\logs\win-c-clear-skill_log_<ts>.txt` (portable; override with `-LogPath`)

## Guardrails (engine-enforced, beyond agent protocol)

- **Whitelist-only**: `-Ids` referencing unknown ids (including raw paths like `C:\Windows\System32`)
  are rejected with status `error` — no way to clean non-whitelist paths
- **Protected-path blacklist**: WinSxS, System32 (root/config/drivers/driverstore/winevt),
  SysWOW64, `C:\Windows\Installer`, assembly, Boot/BCD, `pagefile.sys`/`swapfile.sys`/`hiberfil.sys`
  (direct deletion), `NTUSER.DAT`/`UsrClass.dat`, DumpStack — blocked at merge (demoted to
  dangerous+disabled) AND at clean time (`blocked-by-guardrail`). Spec: [references/guardrails.md](references/guardrails.md)
- **Advisory-only targets**: `pagefile-swapfile` never deletes; returns status `advisory` with
  sysdm.cpl instructions even after two-phase confirmation
- **Windows.old**: dangerous special — takeown/icacls native sequence, only after two-phase confirm

## Token economy (agent-friendly)

- JSON_SUMMARY is **compact by default** (`-PrettyJson` for humans)
- Scan emits Top-N existing items only (default 60, `-TopN`); missing/disabled become `counts`
- MergeConfig emits aggregate counts only (full list stays in `targets.merged.json` on disk)
- Console text is English; translate only the essentials for the user

## Red lines (summary — full list in reference.md)

1. Scan before delete; no deletion in Scan/Analyze/MergeConfig modes
2. Dangerous targets: default disabled, two-phase confirmation, backup or migrate/junction first
3. Paths only via env vars; no hardcoded machine paths
4. Elevation decline → truthful `need-admin` report, never fake success
5. Prefer fewer deletions over wrong deletions ("宁可少删，也不误删")
6. No WinSxS/restore-point manual deletion; no unrequested uninstalls; no network upload of any data
7. Stop processes/services only after separate user confirmation (`-AllowStop`)

## Examples

**User: "C 盘满了帮我看看"**
1. Run Scan → present table + tier totals + C: free
2. Prompt selection (全部safe / ids / 取消)
3. On confirm → Clean with appropriate gates
4. Report from JSON_SUMMARY, offer reusable script once

**User: "把 NVIDIA 着色器缓存清掉，还有 Windows Update 下载缓存"**
1. Scan (still required)
2. `nvidia-dxcache` is safe; `wu-download` is caution → named by user, satisfies ConfirmIds semantics
3. Clean `-Ids "nvidia-dxcache,wu-download" -ConfirmIds "wu-download" -Tiers safe,caution -Elevate -AllowStop`
   (wu-download stops wuauserv/bits/DoSvc → confirm with user first)

**User: "删掉 Cursor 的 state.vscdb 主库"**
1. Dangerous → follow reference.md two-phase protocol exactly
2. Only after explicit "确认删除 cursor-state-vscdb" → Clean with `-Ids cursor-state-vscdb -ConfirmIds cursor-state-vscdb -Tiers dangerous -BackupDangerous`

**User: "缓存没多少了但 C 盘还是红"**
1. Run Analyze → top dirs, large files, duplicates, suggestions
2. Present migrate/junction/uninstall options; do not delete anything

## Further reading

- Red lines + two-phase confirmation protocol: [reference.md](reference.md)
- Install paths (Cursor/Claude Code/standalone) + config guide: [README.md](README.md)
