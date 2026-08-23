# Security audit

Full-engine audit of v1.0.0 (`307e018`) and the fixes applied on top of it.
Scope: `scripts/Invoke-CDriveCleanup.ps1` (3279 lines), `scripts/*.cs` (685 lines), the 87 builtin
targets, the ~15.4k merged rule set, `tools/`, CI, and the six reference documents.

> **Verification status:** the fixes below were applied and reviewed by hand. The verification
> commands in the last section had **not** been executed at the time of writing (the tooling that
> runs commands was unavailable during the session). Run them before trusting this build —
> `tools/verify-engine.ps1` is the syntax/compile gate and must pass first.

---

## CRITICAL

### C1 — glob-scoped targets deleted the whole directory

`$items` (built in the Scan/Clean measure phase) never carried a `glob` property, but the deletion
point read `$it.glob`. `Clear-OnePath` therefore received an empty `GlobPattern` and fell through to
its whole-directory branch, deleting **every** child of the path.

Measurement used `$t.glob` (correct, small) while deletion and re-measurement used `$it.glob`
(empty, whole directory), so `freedGB` clamped to 0 and the item was reported as
`locked` / "files in use; nothing freed" — **after** the directory had been emptied.

Affected builtin targets: `thumbnail-cache` (`%LOCALAPPDATA%\Microsoft\Windows\Explorer`),
`icon-cache` (`%LOCALAPPDATA%`), `powershell-transcripts` (`%USERPROFILE%\Documents`),
`win-setupapi-logs` (`%WinDir%\inf`).

At v1.0.0 the blast radius was masked by three unrelated gates (the `explorer` stopProcesses lock,
the scan-scope whitelist, and the `%WinDir%\inf` guard) — a latent, not live, catastrophe.

**Fix:** `glob = [string]$t.glob` added to the item object.
**Test:** `test-regression.ps1` → C1 (asserts a non-matching file and a subdirectory survive).

### C2 — deletion recursed through junctions and symlinks

`Clear-OnePath` had no reparse-point check anywhere. Scanning guarded reparse points in three places
(`Invoke-CDriveCleanup.ps1` Analyze walk, `ParallelScanner.cs` root + both recursion levels), but the
delete path used `Remove-Item -Recurse -Force`, which on Windows PowerShell 5.1 **follows directory
junctions** and deletes the link target's contents.

The triggering setup is the one this skill itself recommends: Analyze suggests
"prefer migrate/junction over deletion", and junctioning a cache directory to another drive is the
common way users do that. Cleaning C: would then delete data on D:.

**Fix:** new `Test-IsReparsePoint` / `Remove-ReparsePointOnly` helpers, wired into all three deletion
branches:

| Situation | Behaviour |
|---|---|
| target path itself is a link | refuse, return `reparse` → item status `skipped` with an explanation |
| link found among a directory's children | unlink only (`Directory.Delete(path, false)`), never recurse |
| link matched by a glob | unlink only |

Consequence worth knowing: a cache directory the user junctioned to another drive is now **skipped**
rather than cleaned. That is consistent with the skill's documented C:-only scope (cleaning through
the link would be cleaning the other drive), and the item message says so.

The same hazard existed in `tools/install-harness.ps1`, where re-installing over a previous
`-Symlink` install could delete the source repository through the junction. Fixed there too.

**Test:** `test-regression.ps1` → C2 / C2b (assert the link target's data survives).

---

## HIGH

### H1 — the whitelist silently dropped ~1/3 of the builtin targets

Builtin targets were subjected to `config/scan-lists.json`, whose ~124 paths do not cover them. On
the audited machine 87 builtin targets reduced to 56 (Scan reported `existing 37 + missing 19`).
Dropped enabled/safe targets included `unity-cache`, `unreal-ddc`, `cursor-snapshots`,
`nuget-plugins-cache`, `edgeupdate-logs`, `win-update-log`, `win-defender-logs`,
`python-broken-torch`, `baidu-tmp`, `nvidia-nvcache`, `package-cache`.

It was invisible: the only signal was `白名单过滤：跳过 15076 项`, pooling those ~27 curated targets
with 15k community rules.

**Fix:** `origin` `builtin`/`merged` targets bypass the scan-scope whitelist — `config/targets.json`
*is* the curated whitelist, which is what `-RuleSets minimal` means. The blacklist and the hardcoded
engine `GuardPatterns` still apply unconditionally, and tier / `enabled` / `-ConfirmIds` gates are
unchanged. Bypass and narrowing counts are now reported separately from community skips.

> **Coupling to note:** this bypass is what first brings `icon-cache` (`%LOCALAPPDATA%`) and
> `powershell-transcripts` (`%USERPROFILE%\Documents`) into scan scope. Their safety now rests
> entirely on C1 being correct, where previously the whitelist happened to exclude them. The C1
> regression assertions are load-bearing — do not skip them.

### H2 — `-ScanMode diagnostic` weakened the fences during Clean

The `diagnostic` profile sets `useWhitelist:false`, `skipBlacklist:false`, `followJunctions:true`.
The engine used `useWhitelist` as the master switch, so `-Mode Clean -ScanMode diagnostic` removed
the scan-scope whitelist from a deletion run. Documented as "audit mode: report blacklist hits
without cleaning", it neither reported hits nor prevented cleaning.

**Fix:** `-Mode Clean -ScanMode diagnostic` exits 3 with an explanation. Docs corrected to describe
it as a read-only audit profile.

### H3 — multi-path targets smuggled unauthorized paths past the whitelist

The whitelist was evaluated per **target** with any-match semantics; a target that matched on one
path was then deleted across **all** its paths. `vscode-caches` passed on `%APPDATA%\Code\Cache` and
carried `CachedExtensionVSIXs` and `Service Worker` with it; `notion-caches` carried
`DawnGraphiteCache` and `blob_storage`.

**Fix:** filtering is per **path**. Matching paths are kept, unauthorized paths are dropped, and the
target is discarded only when nothing matches. Narrowed targets are counted and reported.

### H4 — the plan gate checked freshness, not approval

The gate only verified that `config/last-scan.json` was under 30 minutes old. It did not check which
ids were scanned, so a Scan of one selection authorized cleaning any other. `scripts/Clean-Safe.bat`
demonstrated the weakness: it runs Scan then Clean back-to-back with no confirmation in between,
satisfying the gate automatically. `SECURITY.md` lists "any way to delete without … the required
confirmation gates" as a security issue.

**Fix:** Scan records the full `scannedIds` set; Clean requires the selected ids to be a subset and
exits 4 otherwise. Freshness is still required.

---

## MEDIUM

| # | Finding | Fix |
|---|---|---|
| M1 | `-Ids`/`-ConfirmIds` and seven path parameters were interpolated into the **elevated** child's command line inside double quotes; an embedded quote injected extra script parameters (`-ConfirmIds`, `-Tiers dangerous`, `-PathFilter off`, `-HotMinutes 0`) into an admin process | reject `"`, backtick, `$`, newline in ids; reject `"` in path parameters. The documented raw-path→`status:"error"` contract is deliberately preserved |
| M2 | `preCommands` run via `cmd /c $cmd` with no validation. Only builtin targets carry them (merge forces `@()`), but any edited or third-party `targets.json` becomes an arbitrary-command sink | **not changed** — see Open items |
| M3 | The merge parser never read `$arr[6]`, so the 7-tuple glob form used by `rules_ai_tools.json` lost its pattern (`*.lock`, `.claude.json.backup.*`, `rollout-*.jsonl`) and became whole-directory deletes | read index 6 in the bool branch; both glob positions documented |
| M4 | `type:"contents"` (144 rules in `community_cleaners.json`) was silently coerced to `dir`. 16 of those are `fetch_rules.py`'s deliberate app-root guard — including `%USERPROFILE%\.claude`, where this skill installs itself | unsupported types are flagged `[unsupported-type:*]` and forced to dangerous + disabled instead of being promoted |
| M5 | The headline "可清理 X GB" summed every existing target, including caution and disabled ones | added `cleanableGB` / `cleanableCount` / `needsConfirmGB`; report distinguishes one-click-cleanable from confirmation-required |
| M6 | The text log's section `[04]` tested only `existingTotal`, which both modes have, so Clean runs printed blank `缺失目标`/`禁用目标` lines and never showed their own figures (reproduced in `logs/…_112514.txt`) | require the full Scan key set; added a Clean branch |
| M7 | `\windows\servicing` and `\windows\inf` guards existed only in absolute form, so they did not match the normalized `%WINDIR%\…` form used at the deletion point; `guardrails.md` claimed a `^%windir%\boot$` pattern that did not exist | added `^%windir%\servicing`, `^%windir%\inf`, `^%windir%\boot`, `^[a-z]:\windows\boot` |
| M8 | `-not $ex.sources -contains $f.Name` parses as `($false) -contains $name` → always false, so merge provenance was never appended | parenthesised |
| M9 | `verify_safety.ps1` tested `Test-PathAgainstWhitelist` while production used `Test-WhitelistFast`; the tested one's `-like '*\*'` means "contains a backslash", not "contains an asterisk" | fixed to `IndexOf('*')`; the production function is now covered by regression tests |

---

## LOW

- **Backup/log locations contradicted the code** in four places (`SKILL.md`, `reference.md` ×2,
  `README.md` said Desktop; the code writes `<skill-root>\backups` and `<skill-root>\logs`, which
  `reference.md` also stated correctly elsewhere). Corrected, and `-BackupDangerous` now warns when
  the backup lands on the same volume as the target — it frees no space and is not off-drive
  protection.
- **`windows-old` was documented as a working capability** in four documents, but the guardrail
  `\windows\.old($|\)` always matches, so it can only ever return `blocked-by-guardrail`. Docs and
  the target's `risk` text now say so; users are pointed at cleanmgr.
- **`win-setupapi-logs` is likewise permanently guard-blocked** (`%WinDir%\inf`); its `risk` text now
  states that instead of describing a deletion that cannot happen.
- **Release/install packaging shipped `.git` and generated artifacts.** The CI release job copied the
  whole tree (full history plus the 19 MB `targets.merged.json`), and `install-harness.ps1` copied the
  same into `~/.claude/skills/` — including `config/last-scan.json`, i.e. a ready-made approval plan
  for the Clean gate. Both now exclude `.git`, the four generated config files, caches and `.pyc`.
- **Rule-set filtering ran after path filtering**, so every run walked all ~15k merged targets through
  the whitelist even for `-RuleSets minimal`, and polluted the reported skip counts. Reordered.
- **Doc drift:** `rules-and-merging.md` said builtin was 77 in one place and 87 in another; the tuple
  spec covered only 5/6 elements while the data uses 7; `guardrails.md` claimed "单测 16/16" against
  35 guard cases; the `-LogPath` example used a stale filename. All corrected.
- **Hot-file fence semantics were overstated** as a "hot subtree skip". It compares only the
  top-level child's own `LastWriteTime`, and a directory's mtime does not change when a nested file
  is written, so deeply nested new files are not protected. Documented precisely rather than changed.

---

## Not a defect (checked and dismissed)

`Test-ShKey $o 'k' -and (...)` without parentheses (10 occurrences) parses correctly — PowerShell
treats `-and` as the logical operator in command-argument position. Confirmed against real output:
sections `[04]`, `[09]` and `[10]` render in `logs/win-c-clear-skill_log_20260823_112901.txt`.

---

## Open items (deliberately not changed)

- **M2 `preCommands`**: still `cmd /c $cmd`. Closing it properly means an allow-list of permitted
  commands (`uv`, `pip`, `npm`, `wevtutil`, `powercfg`, `takeown`, `icacls`) plus argument validation.
  That is a behavioural change to a documented feature and wants its own review.
- **`fetch_rules.py` supply chain**: fetches `Winapp2.ini` from `master` with no commit pin and no
  checksum. Downstream mitigations (community rules are opt-in, conservative auto-tiering, guardrail
  demotion) contain it, but pinning to a tag plus a recorded SHA-256 would be better.
- **Global `$ErrorActionPreference = 'SilentlyContinue'`** plus many empty `catch {}` blocks hide
  real failures. Worth narrowing for a deletion tool, but it needs a full pass with tests running.

---

## Second pass — merge pipeline, rule data, and tooling

### INV — a state source could re-enable a `dangerous` entry (red-line breach)

`Invoke-ConfigMerge`'s dedupe branch lets a `state` source (`cdisk_cleaner_config*`) overwrite
`enabled`, but it never re-asserted "dangerous ⇒ disabled" on the **surviving** entry. The enable
value is computed from the state row's *own* tier, while the kept tier is the more conservative of
the two — so a state row whose tier is `safe` could switch on an entry another source had classified
`dangerous`.

This held at v1.0.0 only by accident: `Get-AutoTier` was effectively a pure function of the path, so
both rows always agreed on tier. **The C1/M4 fix in the first pass broke that invariant** — an
unsupported source type (BleachBit's `contents`) now forces `dangerous` from source metadata rather
than from the path, creating exactly the divergence the missing re-assert allowed.

Empirically, the shipped `targets.merged.json` has **0** violations (63 enabled = 59 safe + 4
caution, 0 dangerous), confirming it was latent rather than live.

**Fix:** re-assert after every override in the dedupe branch, plus a **final invariant sweep** over
all merged targets before persisting — `tier == dangerous ⇒ enabled == false`, and any
guardrail-protected path is forced to `dangerous` + disabled. Corrections are counted in
`stats.invariantForcedDisable` and marked `[invariant:forced-disable]` in the entry's risk text; new
stats fields `dangerousEnabledViolations` and `unsupportedTypeEntries` make a regression visible.
Builtin targets are swept too, since a hand-edited `targets.json` is a real source of
"dangerous + enabled".
**Test:** `test-regression.ps1` → INV builds exactly this two-source collision and asserts the entry
stays disabled.

### Annotation was prepended repeatedly

`[guardrail:protected-path]` was prefixed once per duplicate occurrence of a path, producing 2477
markers across 1338 entries in the shipped artifact. Now idempotent (same for
`[unsupported-type:*]`).

### Rule-data integrity (measured against the shipped assets)

| Source | Documented | Measured | Verdict |
|---|---|---|---|
| `winapp2_latest.json` | 14117 | 14117 | ✅ |
| `community_cleaners.json` | 986 | 986 | ✅ |
| `cdisk_cleaner_custom_rules.json` | 4229 | 4229 | ✅ |
| `common_custom_rules.json` | 110 | 110 | ✅ |
| `cdisk_cleaner_config.json` | 4265 | **8530 elements / 4265 unique** | ❌ every entry duplicated |
| merged tier split | safe 4796 / caution 2560 / dangerous 8047 | **safe 4171 / caution 2604 / dangerous 8628** | ❌ doc stale |
| guardrail-demoted | 98 | **1338** | ❌ doc stale |

The duplication is absorbed by the dedupe key (no functional harm) but inflated
`stats.discovered`/`parsed` and drove the repeated-annotation bug above. Notably **all 8530 state
entries are checkbox `0`** — the only source class that can turn a target *on* currently turns
nothing on. Documentation corrected to the measured values.

### The rule catalog's tier ratings are not the engine's

`references/rulesets/*.md` and `rules-catalog.md` are generated by `merge_rules.classify_tier`, an
independent Python keyword heuristic, while the engine uses the compiled regexes in `Get-AutoTier`.
The docs claimed the two were "同源" (same source). They diverge in **both** directions — e.g.
`dxcache`/`glcache`/`nv_cache` and any path containing `User Data` read as caution/dangerous in the
catalog but are `safe` to the engine; `cookies`/`history` read as caution in the catalog but are
`dangerous` to the engine. Corrected: the catalog is now explicitly labelled a sizing aid, with the
engine's merged artifact named as the sole authority and the known divergences tabulated.

### Dead tooling

`tools/merge_rules.py` and `tools/extract_builtin_rules.py` read `config/builtin/`,
`config/source/` and `config/generated/` — **none of which exist** in the shipped repo (all
gitignored). They cannot run out of the box. `merge_rules.py` survives only as a function library
for `generate_rules_catalog.py` (`classify_tier` reads no files). `fetch_rules.py`'s stale-entry
audit step depends on the same missing tree and silently skips. The engine does not depend on any of
them — rule data is vendored in `assets/rules/`. Documented rather than deleted.

### `tools/__smoke_analyze.ps1` was broken and destructive-by-accident

It dot-sourced the engine and then called `Invoke-CDriveCleanup -Mode Analyze …` as if it were a
function. The engine is a *script*, so: the call failed as an unknown command, and dot-sourcing
**executed a full default-parameter run** (`-Mode Scan`) in the caller's scope, whose terminal
`exit 0` then tore down the host. Rewritten to invoke the script as a child process.

### Two more reparse-point exposures in helpers

- `Backup-TargetPaths` used `Copy-Item -Recurse`, which follows junctions — "backing up" a
  junctioned path would copy the link target's entire tree (potentially many GB on another drive).
  Now refuses with an explanation.
- `-BackupDangerous` writing to `<skill-root>\backups` on the same volume as the target frees no
  space and is not off-drive protection. Now warns.

### Working-set trim contract was unenforced

`SKILL.md` claimed the trim "never [touches] system-critical processes", but the code trimmed
whatever a target's `stopProcesses` named. Added an explicit deny-list (System/smss/csrss/wininit/
winlogon/services/lsass/svchost/dwm/…) so behaviour matches the claim; skipped names are reported.

### `targets.example.json` did not document `glob`

The template users copy showed all three tiers but no `glob` target — the exact field whose
mis-scoping caused C1. Added a `type: glob` example plus an explicit note that `paths` is the
*containing directory* and that an empty `glob` empties the whole directory.

---

## Verification

Run in order; the first is the syntax/compile gate.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\verify-engine.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\verify_safety.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test-regression.ps1
python tools\test-scan-lists.py
```

`tools/test-regression.ps1` is new and covers the areas that had no coverage before — which is
precisely where these defects lived: glob scoping, the reparse fence, plan scope binding, the
diagnostic/Clean combination, per-path whitelisting, id injection, 7-tuple parsing and guard
symmetry. All of its filesystem cases run in a private sandbox under the system temp directory and
assert on canary files that must survive. It is wired into CI after the existing safety suite.

---

## Third pass — first EXECUTED verification + fixes found by running it

The first two passes were applied but never executed ("Verification status" above). This pass ran
the full gate chain on Windows 11 26200 (zh-CN), found that **5 regression assertions failed**,
root-caused each one, and split them into engine defects vs. test-harness defects. All are fixed;
all suites now pass end to end (`verify-engine` ✅ · `test-scan-lists.py` ✅ · `verify_safety` ✅ ·
`test-regression` 47/47 ✅).

### Engine defect E1 — after-measure overwrote fence verdicts with `cleaned` (C2b failure)

Every target that reached the delete phase was registered for the batched after-measurement,
whose residual-size heuristics then assigned `cleaned / partial / locked` **unconditionally**.
A target the reparse fence had refused (`status skipped`) or a guardrail-blocked path was
re-marked `cleaned` whenever its residual size rounded to ≤0.01 GB — reporting a deletion that
never happened. C2b exposed it: the junction-root target's canaries survived (deletion was
fenced correctly) yet JSON_SUMMARY said `cleaned`. Direct violation of red line 4 (truthful
reporting).

**Fix:** terminal fence statuses (`skipped`, `blocked-by-guardrail`, `advisory`, `error`) are now
preserved through the after-measure block; sizes still update, status/freedGB do not.

### Engine defect E2 — measurement went THROUGH link roots (the size half of C2b)

The measure phase enumerated root files via `$di.EnumerateFiles()` before any scanner ran, so a
target path that IS a junction reported the **link target's** bytes as its own (C2b's victim tree
surfaced as a nonzero "cache"). The PS fallback `Measure-One` additionally followed nested
junctions at every level — disagreeing with `ParallelScanner.cs`, which guards root + children +
recursion.

**Fix:** explicit reparse-point short-circuit on every measured path (wildcards untouched; they
resolve to concrete items guarded downstream), plus matching root/child reparse guards inside
`Measure-One` so the fallback path agrees with the C# scanner.

### Engine defect E3 — elevated relaunch dropped scan-behaviour parameters

The UAC child rebuilt its command line without `-ScanMode`, `-TopN`, `-PrettyJson`,
`-PathFilter`, `-NoWhitelist`, `-NoBlacklist`: an approved `-ScanMode deep -PathFilter off` run
silently executed standard/whitelisted after elevation. Safe direction, wrong behaviour.

**Fix:** all six are passed through. Injection surface unchanged — every added value is
ValidateSet-bound, `[int]`, or `[switch]`, and string params already cleared the quote guard.

### M2 CLOSED — `preCommands` allowlist (previously "deliberately not changed")

`cmd /c $cmd` on config-supplied strings is now gated twice: tool must be on the fixed allowlist
(`uv pip pip3 npm yarn pnpm wevtutil powercfg`) AND the command must contain no shell
metacharacter (`& | < > ^ % "` + backtick). Refusals are loud (`[GUARD] pre command blocked`),
reported in `item.message`, and never executed. Verified adversarially in a sandbox:
`cmd /c whoami > pwned.txt` produced no file, `notepad.exe` (which would have hung the engine on
a GUI window) was refused, an absent-but-allowed tool degrades to the documented
"tool not found" skip, and normal cleanup of both targets was unaffected. SKILL.md updated.

### Test-harness defects (assertions were wrong, engine was right)

| # | Failure | Root cause | Fix |
|---|---|---|---|
| T1 | `verify_safety` §10 threw mid-JSON (zh-CN only) | child emits UTF-8; harness decoded with GBK codepage — the last multibyte byte of `家庭中文版` paired with the closing quote's 0x22 and ate it (`After parsing a value ... position 84`) | harness sets `[Console]::OutputEncoding = UTF8`; §10 regex now anchors on `JSON_SUMMARY_END` instead of "first `}` + newline", which also survives console line-wrapping |
| T2 | INV: probe tier=`safe`, state override "breach" | fixture wrote `@(,@(tuple))` **through the pipeline**, which enumerates the outer array and flattened `[[tuple]]` → `[tuple]`; every row parsed as a bare string, the curated file silently produced zero entries, and only the state row survived | serialize with `ConvertTo-Json -InputObject`. With intact input the engine's dedupe + re-assert + final sweep behave exactly as designed |
| T3 | C1b regex never matched | pattern `\{.*?\}` stopped at the first nested `}` (script blocks inside the hashtable); the glob-bearing object also lives in a method call (`$items.Add`), not an assignment | AST extraction of the `$items.Add(...)` invocation node |
| T4 | M1 quote-breakout case exited 0 | PS 5.1 native argument binding wraps space-containing args WITHOUT escaping embedded quotes, so `'globtest" -Tiers dangerous'` was split by the child's CRT parser into innocent separate parameters — the payload never reached the engine as one string | new `Invoke-EngineRaw` helper builds the command line by hand with doubled quotes (the same encoding the engine's own elevated relaunch uses); quote case now asserts exit 3 + guard message, plus a positive control proving legitimate quoted ids still pass the same path |

### Checked and dismissed (with evidence)

- **Nested-junction traversal during delete** — hypothesis that `Remove-Item -Recurse` follows a
  junction at depth ≥2 inside a cleaned directory. Empirically refuted on Windows PowerShell 5.1
  (build 26200 machine, `cache\sub\nest -> victim` with canary): canary survived, subtree removed.
  The top-level-child reparse fence plus PS 5.1's actual recursion semantics are sufficient; no
  change made.

### Remaining open items (unchanged)

- **`fetch_rules.py` supply chain**: still unpinned `master`, no checksum (re-confirmed this pass).
- **Global `SilentlyContinue` + empty `catch {}`**: unchanged; needs a dedicated pass.

---

## Audit round 2026-08-23 (independent re-audit + fixes)

Scope: full engine (3,647 lines post-fix), both C# scanners, all tools, config assets,
plus execution of verify-engine / verify_safety / test-regression and end-to-end
Scan + Clean-DryRun on the host machine.

### PSD (new) — ParallelScanner depth cap truncated sibling subtrees  [FIXED]

`Recurse()` flagged `BudgetHit=true` when `depth > maxDepth`. Every ancestor treats
BudgetHit as budget exhaustion and breaks out of its remaining-sibling loop, so ONE chain
deeper than the preset (Fast=3, Standard=6 — pip/npm/Electron caches exceed this routinely)
zeroed or partialized the measured size of unrelated sibling directories.

Empirically confirmed pre-fix: `a\a2\a3\a4\pay.bin` (10MB) + `b\pay.bin` (10MB) under
`-ScanMode fast` measured **0 bytes** (`budgetHit=1`, silently dropped by
`Invoke-MeasureParallel`, which reads only Sizes/Denied) → Scan underreported and Clean
classified the target "already empty" and never cleaned it. The PowerShell runspace fallback
(`Measure-One`) has NO depth cap, so the two engines also disagreed on identical trees.

**Fix:** depth exhaustion now returns without setting BudgetHit (traversal limit, not a
budget event); file/dir-count budgets and cancellation remain the only BudgetHit sources.
Permanent probe added as `verify-engine.ps1` section 3b (Fast must measure exactly the
reachable sibling; Deep must measure everything).

### PSD2 (new) — after-measure denied results inflated freedGB  [FIXED]

The batched after-measurement summed only `bytes > 0`; a denied subtree (-1 bytes)
silently contributed zero residual, inflating freedGB and potentially marking a still-locked
target `cleaned`. Now tracked per target; affected items get
"after-measure partially unreadable; freedGB is an estimate" appended to `message`.

### PSD3 (new) — Analyze GPU hashPath message overwrite  [FIXED]

With GPU present but no cupy, hashPath was set to "cpu-parallel (GPU present, no cupy;
fell back)" and then unconditionally overwritten by the "cpu-parallel-boosted (...)" label,
losing the no-cupy caveat. Boost branch now only upgrades the plain `cpu-parallel` label.

### PSD4 (new, hardening) — injection guard asymmetry on string params  [FIXED]

`-Config/-Tiers/-LogPath/-ReportFile/-PlanFile/-CCCPDirs/-RuleSets` reached the elevated
child's command line with only a double-quote check, while `-Ids/-ConfirmIds` also rejected
CR/LF/NUL. All seven now reject `["\r\n\0]`; CR/LF/NUL are illegal in Windows paths, so no
legitimate use is affected.

### Verification after fixes

| Suite | Result |
|---|---|
| tools/verify-engine.ps1 (incl. new depth-cap probe) | 6/6 OK |
| tools/test-regression.ps1 | 47/47 PASS |
| tools/verify_safety.ps1 | ALL PASSED (34 guardrail tests) |
| check-json.ps1 (config + assets/rules) | PASS |
| End-to-end `-Mode Scan -Tiers safe` | exit 0, JSON_SUMMARY emitted |
| End-to-end `-Mode Clean -Tiers safe -DryRun` | exit 0, 0.00 GB freed (by design), size-cache serving |

### Still open (unchanged)

- **fetch_rules.py supply chain**: still unpinned `master`, no checksum (re-confirmed).
  Recommend pinning to an exact upstream commit/tag at the next rule refresh.
- **Global `$ErrorActionPreference = 'SilentlyContinue'`**: unchanged; needs a dedicated pass.
