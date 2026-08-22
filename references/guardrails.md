# 门禁围栏规格（guardrails.md）

七层防线，从 Agent 协议到引擎强制。**Agent 违反协议时，引擎仍会拦截。**

## 层级总览

| 层 | 位置 | 机制 |
|----|------|------|
| L0 | **Plan 门禁（核准前置）** | Clean（非 DryRun）要求 ≤30 分钟内的 Scan 计划（config/last-scan.json），否则 exit 4；`-PlanFile` 供自动化预核准 |
| L1 | Agent（SKILL.md 工作流） | 先扫后删、呈现清单待核准、分级确认、两段协议 |
| L2 | 配置默认值 | dangerous 一律 `enabled:false`；community 源一律 opt-in；规则集默认 minimal |
| L3 | 合并期守卫 | 受保护路径强制降级 dangerous+disabled（`[guardrail:protected-path]` 标记） |
| L4 | Clean 前置门控 | ConfirmIds（caution/dangerous）、AllowStop（进程/服务）、requiresAdmin |
| L5 | 删除点守卫 | 具体路径黑名单终检（二次断言）+ 白名单 id 校验 + advisory 目短路 |
| L6 | **数据围栏** | 热文件跳过（mtime < HotMinutes=活跃使用）+ 危险扩展名跳过（exe/dll/sys/msi… 非内置目标）+ 根目录仅空时移除（热文件幸存保证） |

## 扫描期白名单 / 黑名单（R5 新增，扫描不越界）

除删除点守卫外，R5 在**扫描/目标过滤阶段**即阻止越界（config/scan-lists.json）：

| 机制 | 参数 / 文件 | 作用 |
|------|------------|------|
| 白名单扫描 | `-PathFilter whitelist`（默认）/ `scan-lists.json.whitelist` | 只扫描预设「可安全清理」目录，不递归全盘 |
| 黑名单排除 | `-PathFilter blacklist|both` / `scan-lists.json.blacklist` | 系统核心区域（WinSxS/System32\\config/Drivers/Installer/GAC/NTUSER.DAT/pagefile/Boot/EFI 等）**严禁进入扫描** |
| 扫描模式 | `-ScanMode fast\|standard\|deep\|diagnostic` | 控制递归深度、是否跟随 junction、是否报告黑名单命中 |
| 评级分级 | `Get-ScanRating` | 按释放量/跳过/黑名单命中输出 A–F 评级，写入结构化报告 |

> 系统核心区域「严禁扫描」由黑名单在**扫描根扩展 + 递归遍历**两处拦截，且合并期已把命中规则降级 dangerous+disabled，形成「扫描—合并—删除」三重不越界保证。

## 审计日志与结构化报告（R5 新增）

- 每次执行默认写审计日志到 **skill 根目录 `logs/win-c-clear-skill_log_<时间戳>.txt`**（不再写桌面），可用 `-LogPath` 覆写。
- 日志与控制台均输出 `[01]…[08]` 分节结构化报告（执行概要 / 环境 / 磁盘 / 目标统计 / 结果 / 围栏 / 明细 / 产物），见 `Write-StructuredReport`。
- 门控开关（ConfirmIds/AllowStop/BackupDangerous）、白名单/黑名单跳过量、守护护栏命中量均入报告。

## 受保护路径黑名单（引擎 `$Script:GuardPatterns`）

| 模式 | 保护对象 |
|------|---------|
| `\winsxs($|\)` | 组件存储（唯一安全路径是 DISM StartComponentCleanup，仅建议） |
| `\system32\config($|\)` | 注册表配置单元（SAM/SYSTEM/SOFTWARE/SECURITY） |
| `\system32\drivers($|\)`、`\driverstore($|\)` | 驱动与驱动仓库 |
| `\windows\installer($|\)` + `^%windir%\installer($|\)` | MSI 缓存（删了无法卸载/修复） |
| `\assembly($|\)` | GAC |
| `^%windir%\system32$`、`^%windir%\syswow64$`、`^c:\windows$` | 系统核心目录本体 |
| `pagefile.sys$`、`swapfile.sys$`、`hiberfil.sys$`、`dumpstack.log.tmp$` | 内存页面/休眠/转储栈文件（直接删除=系统损坏） |
| `ntuser.dat`、`usrclass.dat` | 用户注册表配置单元 |
| `^%systemdrive%\boot$`、`^%windir%\boot$`、`^c:\boot$`、`\boot\bcd` | 引导 |
| `^%windir%\explorer.exe$`、`^%windir%\regedit.exe$` | 核心 EXE |
| `^%windir%\system32\winevt($|\)` | 事件日志文件（只能 wevtutil 清，不能删 .evtx） |

模式同时匹配**规范化形式**（`%WINDIR%\...`）与**绝对路径形式**（`C:\Windows\...`）。
单测 16/16 通过（含绝对路径 NTUSER.DAT/WinSxS 拦截、用户 Temp/CBS/Package Cache 放行）。

## 白名单强制（L5）

- `-Ids` 中未知 id（含裸路径如 `C:\Windows\System32`）→ `status:"error"` +
  `"blocked: id is not in the whitelist"`，控制台 `[GUARD]` 红字
- **不存在任何绕过白名单直接删路径的参数**

## 特殊目标语义

| id | 行为 |
|----|------|
| `pagefile-swapfile` | **advisory-only**：即使 enabled+两段确认，仍返回 `status:"advisory"` + sysdm.cpl 指引，零删除 |
| `hiberfil` | 仅 `powercfg /h off`（原生命令）；直接删 hiberfil.sys 被黑名单拦截 |
| `win-event-logs*` | 仅 `wevtutil cl`；.evtx 文件删除被黑名单拦截 |
| `windows-old` | takeown/icacls 原生序列 + 两段确认；建议 cleanmgr 替代方案写入 risk |
| `recycle-bin` | `Clear-RecycleBin`（原生 cmdlet） |

## 恢复模式（-RecoveryMode，可找回性分级）

| 模式 | 底层 API | 空间释放 | 找回方式 |
|------|---------|---------|---------|
| `permanent`（默认） | DeleteFile/RemoveDirectory | **立即** | 不可（dangerous 目标可先 `-BackupDangerous`） |
| `recycle` | SHFileOperation (FOF_ALLOWUNDO) | 回收站清空前不释放 | 回收站还原 |
| `quarantine` | MoveFile → `<skill-root>\quarantine\wincc-quarantine_\<ts\>\` | 不释放（同盘移动） | `tools\restore-quarantine.ps1 -Manifest <path>`（含 -List 预览 / -Only 过滤 / 防覆盖跳过 / 全恢复后标记 restoredAt） |

## 门控矩阵（Clean 模式逐项目判定顺序）

```
无有效 Scan 计划(>30min)    → exit 4 (plan gate, 全局拦截)
unknown id?                → error (whitelist)
tier≠safe 且无 ConfirmIds  → skipped (blocked)
requiresAdmin 且非管理员    → need-admin (含精确提权重跑命令)
!exists                    → skipped (幂等 no-op)
size=0 且非 special        → skipped (already empty)
进程运行 且无 AllowStop     → locked
DryRun                     → dryrun (零删除)
advisory 目(pagefile)      → advisory (短路，永不删除)
删除点黑名单命中            → blocked-by-guardrail (二次断言)
热文件 (mtime<HotMinutes)   → 跳过并计数 (fence: hot)
危险扩展名 (非 builtin)     → 跳过并计数 (fence: risky-ext)
否则                        → 按 RecoveryMode 清理 (可 locked: RM 报告占用者)
根目录仅当子项清空时移除     → 热文件幸存保证
```
