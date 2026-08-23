# Red lines and confirmation protocols

Read this on demand when handling risky targets, elevation, or user pushback.
Console output is English for encoding stability; all user-facing replies use the user's language.

## Hard red lines (never violate silently)

1. **Never manually delete** `C:\Windows\WinSxS`, system restore points, or random files under `C:\Windows`.
   (DISM `StartComponentCleanup` may be *suggested* for WinSxS; never executed by this skill.)
2. **Never delete** `dangerous` tier targets unless the two-phase protocol below fully succeeds.
3. **Never run Clean** before a scan report exists in the current conversation (or the user supplies
   a fresh scan JSON_SUMMARY and confirms it).
4. **Never expand cleanup** to arbitrary project folders (`Desktop`, `Documents` source repos)
   without explicit per-path user request.
5. **Prefer migrate / junction / official uninstall** over recursive delete for install trees
   (TeX Live, IDEs, game launchers).
6. **Never upload** any file, scan result, or log to the network. Logs stay local
   (`<skill-root>\logs\`).
7. **Never stop processes/services** without separate user confirmation naming the affected apps.
8. **Never claim success** when items are `need-admin`/`locked`/`error`. Report leftovers truthfully
   with the exact rerun command.
9. Unknown-risk targets default to `dangerous` + `enabled:false`. Never promote them to safe.

## Three-tier model

| Tier | Semantics | Gate |
|------|-----------|------|
| safe | Regenerable caches | one batch confirmation after scan |
| caution | Repair/update impact (installer caches, WU downloads, Prefetch...) | user must name the id; engine requires `-ConfirmIds` |
| dangerous | Data/app loss | `enabled:false` + two-phase protocol + backup or migrate plan |

## Two-phase confirmation for `dangerous` (mandatory, in order)

Phase 1 — risk disclosure + id recital:
- Explain in the user's language: what breaks, what data is lost, reversibility (usually none)
- Offer backup (`-BackupDangerous` writes to `<skill-root>\backups\`, or copy to another drive) or
  confirm no backup. NOTE: `<skill-root>\backups\` is on the same volume when the skill lives on C:,
  so it does not free space — for large dangerous targets prefer copying to another drive.
- Ask the user to **type the exact target id** (e.g. `cursor-state-vscdb`), not just "yes"

Phase 2 — explicit deletion phrase:
- User must reply with a phrase containing `确认删除 <id>` (or `DELETE <id> CONFIRM`)
- Only then: `... -Mode Clean -Ids "<id>" -ConfirmIds "<id>" -Tiers dangerous -BackupDangerous`

If ANY step is missing or ambiguous → abort that target. No exceptions, no "user probably meant yes".

Example (Chinese):

```text
Agent: 删除 state.vscdb 会永久丢失 IDE 聊天/编辑器状态，不可恢复。要先备份到桌面吗？
User: 备份吧
Agent: 已备份。请复述目标 id：cursor-state-vscdb
User: cursor-state-vscdb
Agent: 请回复：确认删除 cursor-state-vscdb
User: 确认删除 cursor-state-vscdb
Agent: (仅对该 id 执行 Clean)
```

## Caution tier notes

- `package-cache`: installer cache; repair/modify re-downloads installers
- `wu-download`: WU payloads; Windows re-downloads as needed (stops wuauserv/bits/DoSvc → confirm)
- `delivery-optimization-system`: system DO cache
- `windows-prefetch`: slower first launches while prefetch rebuilds
- `cbs-logs` / `minidump` / `livekernelreports` / `memory-dmp`: keep if debugging updates/crashes
- `esupport`: OEM driver leftovers; confirm not needed
- `recycle-bin`: permanent empty; unrecoverable
- `huggingface-cache` / `conda-pkgs`: re-download cost can be huge (tens of GB network traffic)
- `win-event-logs`: wevtutil clears Application/System/Setup — diagnostics history lost (rebuilds as events occur)
- `win-defender-history`: past detections list cleared
- `win-panther` / `win-setupapi-logs`: setup/device-install logs; keep while troubleshooting upgrades/drivers
- `branchcache`: peer cache re-fetches on demand
- `windows-old` (dangerous): rollback ability lost forever; prefer Disk Cleanup alternative stated in risk

## Process/service stop protocol

Before ANY stop (wps, msedge, chrome, explorer, wuauserv, bits, DoSvc...):
1. List the apps/services that will be interrupted
2. Remind: "save your work first / 保存工作后再继续"
3. Get explicit confirmation, then pass `-AllowStop`
Without `-AllowStop`, targets with running processes return status `locked` — that is by design.

## Admin / UAC protocol

1. When selected targets include `requiresAdmin:true`, prefer `-Elevate` (UAC prompt)
2. Elevated child writes JSON_SUMMARY to a temp result file; parent re-emits it (no lost output)
3. UAC declined → continue non-admin targets, mark the rest `need-admin` with the exact rerun
   command in `message`; exit code 2
4. Never fake admin success

## Idempotency & error handling (engine behavior)

- Rerunning a completed clean → `status:"skipped"`, `message:"already empty"`, `freedGB:0`
- Per-target failures are isolated (fail-soft): `status:"error"` + `message`, rest continue
- Locked files → `locked` status with retry advice (close app / reboot); never force-remove
- Missing paths → `exists:false`, excluded from totals

## DryRun (audit rehearsal)

`-DryRun` walks the full Clean pipeline (gates, stop detection, pre-command resolution) but deletes
nothing; items show `status:"dryrun"` with "would free ~X GB" messages. Use it to demonstrate a plan
before executing, or for compliance audits.

## Capability boundaries & escalation

- Caches small but C: still tight → switch to **Analyze** (read-only): Top-N dirs, ≥1GB files,
  duplicate groups (GPU hash when available, CPU-parallel fallback — path shown in `hashPath`),
  Storage Sense state + migrate/junction/uninstall suggestions. Report only; deletion needs a
  separate confirmed Clean.
- Requests outside scope (D:/E: cleaning, OS reinstall, deep registry cleanup) → state the boundary,
  suggest alternatives (Storage Sense, cleanmgr, Settings > Apps), do not improvise.
- Software "moving" (搬家) is deliberately NOT automated: propose junction/migration plans only.

## Log & privacy

- Default log: `<skill-root>\logs\win-c-clear-skill_log_<yyyyMMdd_HHmmss>.txt`
  (structured modular report: overview / environment / drive / target stats /
  results / fences / top-10 details / artifacts; override with `-LogPath`)
- Logs are local-only; no telemetry; paths can be redacted by the agent before sharing
- Backups (dangerous tier): `<skill-root>\backups\win-c-clear-skill_backup_<id>_<ts>\`
- Quarantine (recovery mode): `<skill-root>\quarantine\wincc-quarantine_<ts>\`

## Dangerous builtin targets (default disabled)

| id | Risk |
|----|------|
| `cursor-state-vscdb` | Lose IDE chat/composer history and editor state |
| `wps-doc-backup` | Lose WPS auto-saved document backups |
| `texlive` | Removes TeX Live; prefer migrate/junction |
| `hiberfil` | Disables hibernation/fast startup (powercfg /h off), frees 6-20 GB; reversible via `powercfg /h on` |
| `win-event-logs-security` | Clears Security audit log (wevtutil) — login/privilege forensics trail lost |
| `windows-old` | **Blocked by the engine guardrail** (`\windows.old` is a protected path): the target always returns `blocked-by-guardrail` and deletes nothing. Use Disk Cleanup (cleanmgr) → "Previous Windows installation(s)" or Settings > System > Storage instead |
| `pagefile-swapfile` | **ADVISORY-ONLY**: never deleted; engine returns `status:"advisory"` with sysdm.cpl instructions even after two-phase confirmation |

Merged community entries classified dangerous (file-type entries, backup/data/cookie/session
paths, unknown semantics) are likewise disabled until the user completes the protocol.
Protected system paths (WinSxS, Installer, NTUSER.DAT, pagefile.sys...) are additionally demoted
and blocked by the engine guardrail — see [references/guardrails.md](references/guardrails.md).
