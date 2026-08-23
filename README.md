<div align="center">

# 🧹 win-c-clear-skill

**面向 AI Agent 的 Windows C 盘清理技能 — 扫描 → 解释 → 确认 → 清理 → 汇报 → 复用**

[![CI](https://github.com/Circumsized/win-c-clear-skill/actions/workflows/ci.yml/badge.svg)](https://github.com/Circumsized/win-c-clear-skill/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Windows%2010%20%7C%2011%20%7C%20Server-blue)](https://github.com/Circumsized/win-c-clear-skill)
[![Agent Skills](https://img.shields.io/badge/Agent%20Skills-spec-orange)](https://agentskills.io/specification)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?logo=powershell&logoColor=white)](https://learn.microsoft.com/powershell/)

简体中文 | *English: see git history*

典型首次清理可回收 **20–150 GB** 可再生缓存
(开发缓存为主：uv / pnpm / npm / IDE / 浏览器 / GPU 着色器 / Windows Update)

</div>

> ⚠️ **安全第一。** 本技能会删除真实机器上的文件。它围绕**先扫描后删除的 Plan 门禁**、
> **三级风险确认模型**与**引擎级强制护栏**(无论 Agent 请求什么,受保护系统路径一律拦截)
> 构建。确认任何清理前,请务必审阅扫描报告。详见 [SECURITY.md](SECURITY.md) 与
> [references/guardrails.md](references/guardrails.md)。

---

## 📑 目录

- [为什么需要这个技能](#-为什么需要这个技能)
- [快速入门(3 分钟)](#-快速入门3-分钟)
  - [方式 ⓪ — 让 Agent 自己安装(自然语言)](#方式-⓪--让-agent-自己安装自然语言最省事)
  - [方式 A — 配合 AI Agent 使用(推荐)](#方式-a--配合-ai-agent-使用推荐)
  - [方式 B — 独立 PowerShell 运行(无需 Agent)](#方式-b--独立-powershell-运行无需-agent)
  - [方式 C — 双击脚本运行](#方式-c--双击脚本运行)
  - [一次典型会话](#一次典型会话你会看到什么)
- [工作原理](#️-工作原理)
- [技术架构与设计](#️-技术架构与设计)
  - [分层架构](#分层架构)
  - [核心算法详解](#核心算法详解)
- [功能全景](#-功能全景)
- [安全模型](#️-安全模型)
- [规则集](#-规则集)
  - [规则集说明](#规则集说明)
  - [自添加规则模板](#自添加规则模板)
- [CLI 参数参考](#-cli-参数参考)
- [JSON_SUMMARY 数据契约](#-json_summary-数据契约)
- [配置说明](#-配置说明)
- [性能实测](#-性能实测)
- [报告与日志](#-报告与日志)
- [免责声明](#-免责声明)
- [安全政策(中文版)](#-安全政策中文版)
- [项目结构与社区文件](#-项目结构与社区文件)
- [参与贡献与技术支持](#-参与贡献与技术支持)
- [致谢与许可证](#-致谢与许可证)

---

## 💡 为什么需要这个技能

Windows 用久了,C 盘总会被各种**可再生缓存**悄悄占满:包管理器的下载仓库、IDE 的索引与
编译缓存、浏览器积攒的临时文件、GPU 着色器缓存、Windows Update 残留的安装包……这些文件
删了完全没事,软件下次启动就会重建,但手动翻找既费时又怕误删;市面上的"清理大师"类工具
倒是省心,可惜是个黑盒——你无从知道它删了什么、依据是什么。

本技能换了一种思路:让 AI Agent 来执行整个清理流程,但用**工程化的安全约束**框住它的每一步。
扫描先行、分级确认、全程留痕,做到安全、可解释、可复现:

| 能力 | 说明 |
|------|------|
| 🗣️ 自然语言驱动 | 一句 *"C 盘满了，帮我清理"* —— Agent 自动扫描、逐项解释风险,删除前征求你的确认 |
| 🛡️ 三级风险模型 | `safe`(一次确认)· `caution`(须点名目标 id)· `dangerous`(两段式确认协议) |
| 📦 15,400+ 社区规则 | 内置 Winapp2.ini v260730 与 BleachBit cleaners 规则数据,离线可用 |
| ⚡ 极速扫描 | 并行引擎配合智能尺寸缓存:首次冷扫 188.6 秒,**二次扫描仅 11 毫秒**,数值完全一致 |
| 🔒 引擎级护栏 | Plan 门禁、白名单强制、受保护路径黑名单 —— 独立于 Agent 行为,无法被绕过 |
| 📄 稳定数据契约 | 标准输出输出紧凑的 `JSON_SUMMARY`,同时生成中文结构化 Markdown 报告 |
| 🔁 可恢复 | 提供回收站与隔离区两种模式,误删项一条命令即可找回 |

---

## 🚀 快速入门(3 分钟)

提供四种启动方式:让 Agent 代劳安装(最省事)、配合 Agent 使用(推荐)、独立 PowerShell 运行、双击批处理运行。用户可按熟悉程度任选其一。

### 方式 ⓪ — 让 Agent 自己安装(自然语言,最省事)

如果你的 Agent 已在运行,**无需手动 clone**——直接把仓库地址发给它,让它代劳:

```text
请帮我安装这个 Agent Skill:https://github.com/Circumsized/win-c-clear-skill
把它放到你的技能目录(Claude Code 是 ~/.claude/skills/,其他 agent 见仓库 README),
安装完成后重启加载,然后告诉我怎么用。
```

Agent 会自动完成:克隆/下载仓库 → 放入对应技能目录 → 提示你重启会话。
适合不熟悉命令行的用户;若你倾向手动操作,可选择下面的方式 A / B / C。

### 方式 A — 配合 AI Agent 使用(推荐)

**第 1 步:安装到 Agent 的技能目录**(以 Claude Code 为例):

```powershell
git clone https://github.com/Circumsized/win-c-clear-skill.git "$env:USERPROFILE\.claude\skills\win-c-clear-skill"
```

或使用自带的一键安装器,同时为 Claude Code、codex、DeepSeek Harness 装齐:

```powershell
powershell -File tools\install-harness.ps1 -All      # 或 -Targets codex,trae,cursor -Symlink / -List
```

各 Agent 手动安装路径一览:

| Agent | 安装路径 |
|-------|----------|
| Claude Code | `%USERPROFILE%\.claude\skills\win-c-clear-skill\`(项目级:`.claude\skills\`) |
| DeepSeek Harness (dsh) | `%USERPROFILE%\.agents\skills\win-c-clear-skill\`(项目级:`.agents\skills\`) |
| codex | `%USERPROFILE%\.codex\skills\win-c-clear-skill\` + 在 `AGENTS.md` 加一行指引 |
| Trae | `%USERPROFILE%\.trae\skills\win-c-clear-skill\`(或项目 `.trae/skills/`) |
| Cursor | `%USERPROFILE%\.cursor\skills\win-c-clear-skill\` |

**第 2 步:重启 Agent 或新开会话**,然后直接发一句自然语言指令:

```text
C 盘满了,用 win-c-clear-skill 扫描一下
My C: is full — scan and suggest what to clean
```

**第 3 步:按确认提示操作。** Agent 会按以下流程推进:

```text
Cleanup progress:
- [x] 1) 识别系统 + 引导选择规则集(默认极简内置规则)
- [ ] 2) 扫描(不删除)→ 呈现可清理清单及大小 / 风险档
- [ ] 3) 等待你的批准          ← 你回复:全部 safe / 具体 id / 取消
- [ ] 4) 仅清理你确认的目标    ← caution 档需再次点名 id
- [ ] 5) 汇报每项释放空间 + C 盘可用空间变化
- [ ] 6) 询问是否生成可复用脚本(仅问一次)
```

每一步的主动权始终在你手里:**未获明确批准前,引擎不会删除任何文件。**

### 方式 B — 独立 PowerShell 运行(无需 Agent)

不依赖任何 Agent,直接调引擎脚本:

```powershell
$S = "C:\path\to\win-c-clear-skill\scripts\Invoke-CDriveCleanup.ps1"

# 0)(可选)合并社区规则——规则数据过期时会自动执行
powershell -NoProfile -ExecutionPolicy Bypass -File $S -Mode MergeConfig

# 1) 扫描——只读,按风险档列出各项体积
powershell -NoProfile -ExecutionPolicy Bypass -File $S -Mode Scan -Tiers safe,caution,dangerous

# 2) 清理——仅处理 safe 档(涉及管理员权限的目标时会弹出 UAC)
powershell -NoProfile -ExecutionPolicy Bypass -File $S -Mode Clean -Tiers safe -Elevate

#    …或仅指定目标;caution 档必须同时传 -ConfirmIds
powershell -NoProfile -ExecutionPolicy Bypass -File $S -Mode Clean -Ids "uv-cache,wu-download" `
  -ConfirmIds "wu-download" -Tiers safe,caution -Elevate -AllowStop

#    完整走一遍流程但零删除(用于审计演练)
powershell -NoProfile -ExecutionPolicy Bypass -File $S -Mode Clean -Tiers safe -DryRun

# 3) 缓存不多但 C 盘依然告急?用只读诊断模式排查:
powershell -NoProfile -ExecutionPolicy Bypass -File $S -Mode Analyze
```

### 方式 C — 双击批处理运行

| 文件 | 作用 |
|------|------|
| `scripts\Scan.bat` | 仅执行扫描,零删除 |
| `scripts\Clean-Safe.bat` | 仅清理 `safe` 档(必要时弹出 UAC) |

### 一次典型会话(你会看到什么)

```text
你:    C 盘快满了,帮我看看能清多少
Agent: 扫描完成:发现约 13.98 GB 可清理项(36 个现存目标,C 盘可用 12.68 GB)
       ├─ safe     32 项 ≈ 13.6 GB(user-temp 4.03、剪映 2.39、dot-cache 1.85 …)
       ├─ caution   4 项 ≈ 0.4 GB(wu-download、package-cache … 需点名确认)
       └─ dangerous 默认关闭
       回复:全部 safe / 具体 id / 取消
你:    全部 safe
Agent: 清理完成:释放 13.60 GB,C 盘可用 12.68 → 26.28 GB(+13.60)
       报告:C:\...\reports\win-c-clear-report_20260822_163000.md
```

---

## ⚙️ 工作原理

```text
┌─────────────┐   ┌──────────────────┐   ┌──────────────────┐   ┌───────────────┐
│ config/      │   │ assets/rules/    │   │ MergeConfig      │   │ user-overrides│
│ targets.json │ + │ winapp2/BleachBit│──▶│ 发现→解析→去重→  │──▶│ .json          │
│ (87 内置)    │   │ 精选社区规则      │   │ 分级→合并        │   │ (你的勾选结果) │
└─────────────┘   └──────────────────┘   └──────────────────┘   └───────────────┘
                                                        │ targets.merged.json
                                                        ▼
┌────────────────┐   ┌───────────────────────┐   ┌────────────────────────────┐
│ ① 扫描          │──▶│ ② 呈现清单并等待核准    │──▶│ ③ 仅清理已确认目标          │
│ 仅白名单范围    │   │ (引擎 exit-4 门禁       │   │ 门控:ConfirmIds/AllowStop  │
│ 写入扫描计划    │   │  阻止跳步)             │   │ BackupDangerous/DryRun     │
│ (≤30 分钟有效) │   │                        │   │ RecoveryMode               │
└────────────────┘   └───────────────────────┘   └────────────────────────────┘
                                                        │
                              ┌─────────────────────────┴─────────────────────────┐
                              ▼                                                   ▼
                   ┌──────────────────────┐                          ┌──────────────────────┐
                   │ JSON_SUMMARY(stdout) │                          │ Markdown 报告 + 日志  │
                   │ Agent 解析这个        │                          │ 人类阅读这个          │
                   └──────────────────────┘                          └──────────────────────┘
```

引擎提供**四种模式**,彼此独立、可单独调用:`Scan` 只做体积测量不触及任何文件;
`Clean` 在通过 Plan 门禁与确认后删除已核准的目标;`Analyze` 是只读诊断模式,用于
回答"C 盘到底被什么吃掉了"这类问题(Top 目录排行、≥1GB 大文件、重复文件分组);
`MergeConfig` 重建合并规则,通常会在首次运行或规则数据过期时自动触发。

---

## 🏗️ 技术架构与设计

### 分层架构

项目采用**五层职责分离**设计,每一层只依赖其紧邻的下层,因而任何一层都可以独立替换、
独立演进而不波及其他层:

```text
┌─────────────────────────────────────────────────────────────────────┐
│  L5 交互层   SKILL.md(Agent 协议)+ reference.md(确认协议)          │
│              职责:自然语言工作流、确认话术、红线声明                  │
├─────────────────────────────────────────────────────────────────────┤
│  L4 契约层   JSON_SUMMARY(schemaVersion 1)+ 中文 Markdown 报告      │
│              职责:机器可解析的结果通道 + 人类可读的审计报告           │
├─────────────────────────────────────────────────────────────────────┤
│  L3 引擎层   Invoke-CDriveCleanup.ps1(约 3200 行,单文件引擎)       │
│              四模式状态机:Scan / Clean / Analyze / MergeConfig       │
│              门控编排:Plan 门禁 → ConfirmIds → admin → exists → 锁   │
├─────────────────────────────────────────────────────────────────────┤
│  L2 算法层   ParallelScanner.cs(Task.WhenAll 并行测量)              │
│              MftScanner.cs(NTFS MFT 直读)                           │
│              规则合并管线 + 自动分级 + 守卫正则引擎                    │
├─────────────────────────────────────────────────────────────────────┤
│  L1 数据层   config/(targets.json 白名单 + scan-lists.json 黑白名单)│
│              assets/rules/(1.54 万条内置社区规则,vendored 自包含)    │
└─────────────────────────────────────────────────────────────────────┘
```

**关键设计决策**:

| 决策 | 理由 |
|------|------|
| 单文件 PowerShell 引擎 | 部署零依赖:目标机器只需 Windows 自带的 PowerShell 5.1,无需额外安装任何运行时或框架 |
| C# 热插(`Add-Type`) | 并行扫描、MFT 直读等性能敏感路径以内嵌 C# 编译执行;加载失败时自动回退到纯 PowerShell 实现,不因缺失 .NET 而阻断 |
| 数据与逻辑分离 | 清理目标全部外置为 JSON 配置,新增或修改清理项不需要动任何脚本代码 |
| origin 溯源合并 | 每条合并规则携带 `builtin\|community-sourced\|merged` 来源标记,内置白名单项在任何合并场景下都永不被覆盖 |
| 双通道输出 | stdout 只承载机器可读的 JSON 契约,人类阅读内容全部走 Markdown 报告文件,两者互不污染 |

### 使用的 Windows API

引擎不依赖任何第三方库，全部能力构建在 Windows 自带的系统接口之上。下表按功能层给出 API 与实现的对应关系，作为快速索引；其后的小节则聚焦几个关键 API 的技术语义与选型理由——说明为什么选用这一套接口、又刻意排除了哪些备选方案。

| 功能层 | API / 命令 | 用途 | 调用方式 |
|--------|-----------|------|----------|
| 卷信息 | `DeviceIoControl(FSCTL_GET_NTFS_VOLUME_DATA)` | 读取 NTFS 卷参数(MFT 起点 LCN、文件记录大小、簇大小),MFT 直读的前置步骤 | MftScanner.cs P/Invoke |
| 磁盘画像 | MFT 记录解析(`$FILE_NAME` 0x30 / `$DATA` 0x80 属性) | 全卷文件枚举与真实大小统计,绕过逐目录遍历 | MftScanner.cs P/Invoke |
| 并行扫描 | .NET TPL(`Task.WhenAll` + `SemaphoreSlim`) | 有界并发的目录树测量 | ParallelScanner.cs |
| 文件删除 | `DeleteFileW`(POSIX 语义)/ `SHFileOperation`(回收站)/ `MoveFileEx` + manifest(隔离) | 三档恢复模式的底层实现 | Clear-OnePath |
| 锁检测 | Restart Manager(`RmStartSession`/`RmRegisterResources`/`RmGetList`,rstrtmgr.dll) | 查询被锁文件的精确占用进程(名称+PID) | WinRm C# 类 P/Invoke |
| 内存整理 | `EmptyWorkingSet`(psapi.dll) | 对已清理目标的进程截取工作集,释放物理内存 | P/Invoke,仅 `-TrimWorkingSet` 时启用 |
| 提权 | `Start-Process -Verb RunAs`(UAC) | 需管理员的目标触发提权重启,结果经临时文件回传 | PowerShell 原生 |
| 所有权接管 | `takeown` / `icacls` | 仅用于两段式确认后的 Windows.old 删除前置 | 原生命令 |
| 系统能力 | `wevtutil`(事件日志)、`powercfg /h off`(休眠文件)、`Clear-RecycleBin`、`robocopy /L`(访问拒绝时的列表回退) | 官方途径优先于裸删 | preCommands 原生命令 |
| 仅建议不执行 | DISM `StartComponentCleanup`、`cleanmgr`、`vssadmin` | WinSxS 清理等高危操作只作为建议输出,引擎绝不代为执行 | suggestions 输出 |

引擎对 Windows API 的选用遵循两条原则：**能走官方受支持接口的绝不用未文档化手段，能查证的绝不抢权限强删**。下面对几个关键 API 的技术语义作进一步说明。

#### 扫描层：为什么要绕过目录遍历直读 MFT

常规的 `FindFirstFileEx` / `FindNextFile` 逐目录枚举在深层嵌套目录下成本随深度线性上升，且 `.NET` 的 `Directory.Enumerate*` 会重复计入硬链接——同一份数据经多个目录项累加，虚增占用。`MftScanner.cs` 改为直读 NTFS 主文件表：先用 `DeviceIoControl(FSCTL_GET_NTFS_VOLUME_DATA)` 取得 MFT 起始 LCN 与每记录字节数，再经裸卷设备 `\\.\C:` 顺序解析 `$FILE_NAME`（0x30）与 `$DATA`（0x80）属性。因为一张 MFT 记录挂多个硬链接时 `$DATA` 只计一次，所以 MFT 口径得到的正是**真实独占占用**，目录树递归口径则会重复计数——两种口径的差额恰好揭示硬链接共享规模。

这条路径有三个实测才暴露的坑：MFT 虽为逻辑文件，磁盘上却可能碎片化为多个 extent，必须解析 MFT 自身记录 0 的 `$DATA` run-list（VCN→LCN 映射）按段遍历；每段记录先做 USN fixup 校验（每扇区末两字节替换）再定位属性；nonresident `$DATA` 的尺寸以 `RealSize`（0x30）为准，`0x2C` 偏移读出的其实是垃圾——多源文档在属性布局上存在分歧，最终以三偏移对照实验定案。

#### 删除层：三种恢复模式对应 Win32 API 的三个语义层级

| 恢复模式 | 底层 API | 语义 |
|---------|---------|------|
| `permanent`（默认） | `DeleteFileW` / `RemoveDirectory` | 直接删除、不进回收站，唯一即时释放空间的模式 |
| `recycle` | `SHFileOperation`（`FOF_ALLOWUNDO`） | 送进回收站，经 VB 的 `FileIO` 封装调用 |
| `quarantine` | `MoveFileEx` + manifest | 移入隔离区，原文件不删除 |

`IFileOperation`、`MoveFileEx(MOVEFILE_DELAY_UNTIL_REBOOT)`、`FILE_FLAG_DELETE_ON_CLOSE`、POSIX 删除语义等备选方案均被有意排除：要么与"扫描先行、占用可见"的语义冲突，要么会静默挂起删除，不如显式报告占用者来得透明。

#### 占用与提权：只查证，不强抢

被锁文件不靠猜测，引擎通过 Restart Manager（`RmStartSession` / `RmRegisterResources` / `RmGetList`，rstrtmgr.dll）查询精确的占用进程名称与 PID；`RmShutdown` / `RmRestart` 被有意不用——关闭进程必须经 `-AllowStop` 门控，由 `Stop-Process` 显式执行并记录。提权走 `Start-Process -Verb RunAs`（UAC 的 runas 动词），结果经临时文件回传以免提权后输出丢失。`takeown` / `icacls` 保留在代码里作为 Windows.old 的接管前置，但实际不可达：`\windows.old` 属受保护路径，护栏必然命中，该目标恒返回 `blocked-by-guardrail` 且零删除（请改用 cleanmgr 的「以前的 Windows 安装」）；至于 WinSxS、Installer 等 TrustedInstaller 区域，引擎的选择是**永不触碰**（黑名单 guardrail），而非像传统清理工具那样抢所有权强删——WinSxS 唯一安全的官方通道是 DISM `StartComponentCleanup`，引擎只建议、不执行。系统还原点（VSS）同理列为红线，任何模式都不代为删除。

完整的分层映射与未采纳方案的理由，见 [references/windows-api.md](references/windows-api.md)。

### 核心算法详解

#### 1. 三级风险自动分级(Get-AutoTier)

每条规则路径都要过一遍**保守优先序**的信号匹配:危险信号排在最前,一旦命中立刻
归入 `dangerous`,不再往下试探。这套逻辑正是"宁可错杀分级、不可误判安全"红线的
算法化落地——它把"未知绝不猜为 safe"这一条硬约束写进了判断流程本身。

```text
输入:规范化路径 p 与条目类型 t(dir 或 file)
 ① RxDanger(p 或 leaf 命中)?     → dangerous   ← 最优先:cookie/session/backup/data 等关键词
 ② RxProgDirs(p 命中)?            → dangerous   ← 程序主目录(Program Files 等)
 ③ RxCaution(p 或 leaf 命中)?     → caution     ← download/package/installer/log
 ④ RxSafe(leaf 命中)?             → safe        ← cache/temp/shader/dump
 ⑤ t == file?                     → dangerous   ← 文件型条目通常为数据,不默认 safe
 ⑥ 以上皆未命中                   → dangerous   ← 未知目标一律降为最高风险档
```

每次分级时,触发哪一条信号会被写入该目标的 `signals` 字段
(如 `safe-signal` / `danger-signal` / `unknown`),并在合并阶段汇总为
`signalsHistogram`——所以每个目标落到哪个风险档,都能倒查出是依据哪条规则、哪一层
信号判定的,做到了分级可解释、决策可追溯。

#### 2. NTFS MFT 直读(MftScanner.cs,Analyze 模式)

常规扫描逐目录枚举,遇到深层嵌套目录效率会明显下降。MFT 直读换了一种思路:跳过
文件系统 API,直接解析 NTFS 卷的**主文件表**($MFT),从磁盘层面读取全卷文件画像,
从而绕过目录树遍历的成本。

```text
① DeviceIoControl(FSCTL_GET_NTFS_VOLUME_DATA)
     取卷参数:MFT 起始 LCN、文件记录段大小、簇大小——这是定位 MFT 的前置条件

② 解析记录 0($MFT 自身)的 $DATA 属性 run-list
     得到 MFT 在磁盘上的全部 extents。这里有一个实测踩过的大坑:MFT 在卷上通常是
     碎片化的,只顺序读第一个区段会漏掉大量记录

③ 沿每个 extent 顺序读取 1KB 文件记录
     a. 先做 fixup/USN 完整性校验(还原扇区尾保护字节,剔除损坏记录)
     b. 遍历属性链:0x30 $FILE_NAME(父目录 FRN + 文件名),0x80 $DATA 未命名流(真实大小)

④ 由父目录 FRN 自底向上回溯,重建完整路径

⑤ 边界过滤:仅保留规则根路径下的条目;黑名单命中者计数但不对外呈现

⑥ 硬链接感知:同一 FRN 的多路径只计一次独占占用
     (典型发现:uv 名义占 113.64GB,硬链接去重后真实独占仅 8.32GB)
```

当运行环境为非管理员、卷非 NTFS,或解析任一步骤失败时,引擎会**透明回退**到
.NET 并行遍历,并通过 `scanPath` 字段告知最终采用的是 `ntfs-mft` 还是
`dotnet-parallel` 路径;用户也可以用 `-NoMft` 强制关闭这一快速通道。

#### 3. 两级并行扫描(ParallelScanner.cs)

15,000 多个目标若逐一串行测量,时间成本会非常高。本技能把测量分成两级:先剔除
"根本不存在"的路径,再对有界并发的有效目标并行测量,把大部分 I/O 压力压到
几十秒量级。

```text
第一级 · 快筛:.NET 存在性预检查(通配符感知)
    数千条"目标路径不存在"的条目在此以 O(1) 判定剔除,不进入重量级测量队列。
    这是 15k 目标能压到约 53 秒的关键前提。

第二级 · 测量:Task.WhenAll + SemaphoreSlim(maxDop) 有界并发
    ├─ 大目录:按一级子目录 1:1 切分为独立任务,天然按规模负载均衡
    ├─ 小路径:16 条一批合并提交,摊薄调度开销
    ├─ 预算守卫:maxDepth / maxFiles / maxDirs 三重熔断
    │    fast      = 3 层 / 50 万文件
    │    standard  = 6 层 / 200 万文件
    │    deep      = 12 层 / 不限
    ├─ 重解析点守卫:junction / symlink 一律不跟随(防循环 + 防越界)
    └─ BelowNormal I/O 优先级:测量期间系统保持日常操作响应
```

#### 4. 智能尺寸缓存(mtime + TTL)

大目录的体积测量最耗时,而相邻两次扫描之间这些目录往往并没有实质变化。本技能为
每个规范化路径维护一条缓存记录:

```text
key   = 规范化路径
value = { bytes(测量值), dirMtime(目录最后修改时刻), cachedAt(缓存写入时刻) }

命中条件:dirMtime 未变化  且  (now - cachedAt) ≤ 15 分钟 TTL
失效语义:目录内任何增删都会改变 dirMtime → 缓存自动失效重测,无需手动清理
```

实测:uv 与 npm 缓存共 131.55GB,首次冷扫 188.6 秒,**缓存命中后二次扫描仅 11 毫秒**——
约 17,000 倍加速,且数值与冷扫结果逐字节一致,不存在精度折损。`-NoCache` 可强制
精确重测。

#### 5. Restart Manager 锁检测(rstrtmgr.dll P/Invoke)

文件被进程占用是清理失败的常见原因。本技能不再让这类失败沉默地出现,而是通过
Windows 原生的 Restart Manager 会话(`RmStartSession` → `RmRegisterResources` →
`RmGetList`)查询**精确占用进程列表**(进程名 + PID),写入 `item.message` 供用户
决策。

是否结束这些进程,由 `-AllowStop` 门控单独控制——**检测与处置解耦**,把"删不删得
了"和"要不要为此停进程"分开交给用户判断,避免引擎自行越权。

#### 6. 重复文件哈希级联(Analyze 模式)

全卷文件数量庞大,对每个文件做全量哈希既不必要也不现实。本技能采用三级漏斗,
用尽量少的哈希运算筛掉尽可能多的假阳性:

```text
第一级:按字节数分组
    相同大小才有重复的可能,不同大小直接进入"排除"队列

第二级:64KB 头部 + 64KB 尾部 MD5
    同一分组内先用首尾片段哈希快速排除,绝大多数不同内容文件在此被过滤掉

第三级:全量 MD5 流式比对(1MB 缓冲,并行池执行)
    GPU 感知线程倍增:检测到独立显卡时,自动 ×2 哈希线程,使 I/O 与 CPU 重叠计算
```

`hashPath` 字段会标注实际使用的哈希路径,方便审计时核对。

#### 7. 确定性规则 id 生成

社区规则的稳定标识由 `MD5(规范化路径小写) 前 8 位十六进制` 构成,格式为
`ccp-<来源标签>-<路径短哈希>`。

这里的"规范化路径"经过两步预处理:绝对路径回写为 `%LOCALAPPDATA%` 等环境变量形式、
大小写归一化。因此同一规则无论在谁机器上、何时重建,得到的 id 都完全一致——
用户在 `user-overrides.json` 里做的启用/禁用勾选,因此可以在规则升级、跨版本重建
后依然持久有效。

---

## 🧰 功能全景

### 功能矩阵

| 功能域 | 功能点 | 说明 |
|--------|--------|------|
| **扫描测量** | 白名单定向扫描 | 仅进入预设的可安全清理目录(约 124 条白名单),系统核心区域永不触碰 |
| | 四档扫描深度 | `fast`(顶层)/ `standard`(3 层)/ `deep`(白名单内全递归)/ `diagnostic`(黑名单审计) |
| | 通配符路径支持 | 与 Winapp2 一致的 `Chrome*\User Data\*` 通配符,全链路贯通(快筛前缀→解析→测量→清理→守卫) |
| | 智能缓存复扫 | mtime + TTL 双重校验,二次扫描可在毫秒级返回 |
| | 扫描评级 A–F | 按可回收量、跳过数、黑名单命中综合评分,直观呈现"系统凌乱度" |
| **风险分级** | 三档风险模型 | safe / caution / dangerous 三级门控(详见安全模型章节) |
| | 自动分级信号审计 | 每条规则携带 `signals` 触发依据,汇总为 histogram 可追溯 |
| | 未知目标兜底 | 无法分类的路径一律归入 `dangerous` 并默认禁用 |
| **清理执行** | 四种工作模式 | Scan / Clean / Analyze / MergeConfig |
| | 精确点名清理 | `-Ids` 限定清理范围 + `-ConfirmIds` 二次确认 |
| | 三档恢复模式 | permanent 直接删除 / recycle 送回收站 / quarantine 移入隔离区并生成 manifest,可一键还原 |
| | 原生命令优先 | `uv cache clean`、`pip cache purge`、`wevtutil`、`powercfg /h off`、takeown 等官方途径优先于裸删 |
| | 进程与服务编排 | 清理前受控停止进程(-AllowStop 门控),完成后自动重启服务 |
| | 工作集整理 | 对已清理目标所属进程执行 EmptyWorkingSet,释放物理内存(-TrimWorkingSet) |
| **诊断分析** | Top-N 目录画像 | 启用规则根路径下的首层目录排行 |
| | 大文件清单 | 定位 ≥1GB 的文件 |
| | 重复文件分组 | 三级哈希级联,GPU / CPU 路径在 hashPath 字段中透明标注 |
| | MFT 全卷直读 | 约 27 秒遍历 342 万条 MFT 记录、223.59GB 数据,并正确识别硬链接的真实独占占用 |
| | Storage Sense 感知 | 读取系统存储感知开关状态并纳入建议 |
| | 迁移建议 | junction 化 / 搬家 / 卸载三类建议,只提供建议不代为执行 |
| **安全护栏** | 七层防线 | Plan 门禁 / 扫描范围围栏 / 白名单强制 / 热文件围栏 / 危险扩展名围栏 / RM 锁上报 / 审计日志 |
| | 受保护路径黑名单 | WinSxS、System32 核心、Installer、GAC、Boot\BCD、页面文件等 30 余组正则,合并期降级、删除期拦截,双保险 |
| | advisory 目标 | pagefile 等特殊目标永不删除,即使经过两段式确认也只返回设置指引 |
| **规则生态** | 11 类规则集引导 | 默认 minimal,按需开启 cn / dev / ai / game / community 等分类 |
| | 15,400+ 社区规则 | Winapp2 v260730 + BleachBit cleaners + 精选社区规则,全部 vendored 自包含 |
| | 确定性合并管线 | 七步管线:origin 溯源、id 跨重建稳定、内置项永不被覆盖 |
| | 用户勾选持久化 | `user-overrides.json` 记录逐项启用/禁用,规则升级后仍有效 |
| **Agent 协作** | 自然语言工作流 | 六步进度清单驱动,确认话术遵循三要素(选项 + 后果 + 默认) |
| | JSON_SUMMARY 数据契约 | schemaVersion 1,紧凑单行,TopN + counts 兼顾信息量与 token 开销 |
| | 多 Harness 一键安装 | Claude Code / codex / DeepSeek / Trae / Cursor,junction 同步模式 |
| | 可复用脚本生成 | 会话末询问一次,基于本次确认的目标生成桌面快捷脚本 |
| **报告审计** | 中文结构化报告 | 11 章节模块化 Markdown,路径可通过 `-ReportFile` 自定义 |
| | 模块化审计日志 | 8 章节日志,含门禁拦截与提权结果 |
| | 隔离区还原工具 | manifest 驱动,支持 `-List` / `-Only <关键词>` 选择性找回 |

### 支持的清理目标类别(节选)

<details>
<summary><b>展开查看内置 87 个白名单目标的主要类别</b></summary>

| 类别 | 代表目标(id) |
|------|---------------|
| 开发工具缓存 | `uv-cache` `npm-cache` `pnpm-store` `yarn-cache` `cargo-cache` `go-build-cache` `nuget-cache` `gradle-caches` `pip-cache` |
| IDE 缓存 | `vscode-caches` `cursor-small-caches` `trae-caches` `jetbrains-caches` `vs-componentcache` |
| 浏览器缓存 | `edge-caches` `chrome-caches`(仅 Cache 类目录,不动 Cookie/密码/历史) |
| GPU 着色器缓存 | `nvidia-dxcache` `nvidia-glcache` `nvidia-computecache` `amd-shader-caches` `d3dscache` |
| 系统可再生缓存 | `user-temp` `windows-temp` `windows-prefetch` `thumbnail-cache` `font-cache` `icon-cache` `delivery-optimization` |
| 错误转储 | `crashdumps-user` `wer-reports` `minidump` `memory-dmp`(调试需求者请保留) |
| 国产应用缓存 | `wps-caches` `wxwork-logs` `jianying-caches` |
| AI 工具缓存 | `claude-desktop-caches` `cherry-studio-caches` `ollama-logs` `lmstudio-caches` |
| 媒体创作 | `obs-logs` `playwright-browsers` |
| 游戏平台 | `steam-logs` `epic-webcache` |
| caution 档 | `wu-download` `package-cache` `huggingface-cache` `conda-pkgs` `win-event-logs`(影响修复/更新,需点名) |
| dangerous 档 | `cursor-state-vscdb` `wps-doc-backup` `texlive` `hiberfil` `windows-old` `win-event-logs-security`(默认禁用,两段式协议) |

完整清单见 [references/rules-catalog.md](references/rules-catalog.md) 与各分类明细
[references/rulesets/](references/rulesets/)。社区扩展(winapp2+BleachBit)另有 15,000+ 条可选启用。

</details>

---

## 🛡️ 安全模型

删除类工具最怕两件事:Agent 自作主张,以及"看起来删了其实没删干净"。为此,本技能采用
纵深防御设计——**Agent 协议**与**引擎门控**各自独立地执行同一套规则,即便 Agent 行为异常,
引擎也会在最后一道关卡把危险操作拦下来:

| 层级 | 机制 |
|------|------|
| 工作流约束 | 未扫描绝不执行清理;呈现完整清单后等待明确批准 |
| Plan 门禁 | Clean 要求 30 分钟内的扫描计划(`last-scan.json`)——过期或缺失一律以退出码 4 拒绝 |
| 白名单强制 | `-Ids` 只接受白名单内的目标 id;裸路径(如 `C:\Windows\System32`)直接以 `status:"error"` 拒绝 |
| 受保护路径黑名单 | WinSxS、System32 核心、Installer、NTUSER.DAT、pagefile.sys、Boot\BCD 等,在合并期降级为 dangerous 并在删除期二次拦截 |
| 危险档两段式确认 | 先讲清风险,再要求用户复述目标 id,最后须回复 `确认删除 <id>`,缺一不可([reference.md](reference.md)) |
| 热文件围栏 | 最近 30 分钟(可用 `-HotMinutes` 调整)内修改过的文件视为"使用中",跳过不删 |
| 危险扩展名围栏 | 永久模式下,非内置目标的 exe/dll/sys/msi 一律跳过 |
| 锁定上报 | 文件被占用时,经 Restart Manager 查出占用进程(名称+PID)如实上报;是否结束进程由 `-AllowStop` 单独决定 |
| 如实汇报 | UAC 被拒绝时,如实标记 `need-admin` 并给出精确的重跑命令——绝不虚报成功 |

对无法识别的目标,本技能的态度是**宁可保守**:一律归入 `dangerous` 并默认禁用,
绝不猜测为安全。

---

## 📚 规则集

规则**默认不全量加载**——这是"安全优先"设计原则的又一个体现:引擎不会在用户没有明确
意图时,把 15 万条以上的社区规则一股脑塞进执行队列。首次使用,你会看到一份规则集菜单
(`-RuleSets`,默认 `minimal` = 87 个精选内置目标),按需勾选即可:

```text
极简(minimal) / 通用(general) / 国产软件(cn) / 开发工具(dev) / 设计建模(design) /
AI 软件(ai) / 游戏平台(game) / 影音创作(media) / 系统缓存(system) /
社区扩展(community = winapp2+BleachBit) / all 全量 / none 同 minimal
```

```powershell
-RuleSets minimal        # 默认:仅内置白名单——最稳
-RuleSets cn,dev         # 例如:国产软件 + 开发工具
-RuleSets all            # 全量,含 15k 社区规则
```

各类别的规则数量、覆盖范围与风险分布明细见
[references/rules-catalog.md](references/rules-catalog.md)。
规则数据可手动升级:`python tools/fetch_rules.py`。

### 规则集说明

规则系统在底层由三层构成,理解这种分层关系,有助于你在日常使用、添加规则、排查问题
时快速定位到正确的层级:

| 层级 | 位置 | 说明 |
|------|------|------|
| **内置白名单** | `config/targets.json` | 87 个精选目标,`category: builtin`,始终随 `minimal` 加载。手工编辑的主入口 |
| **社区规则库** | `assets/rules/*.json` | 约 1.54 万条 vendored 规则(Winapp2/BleachBit/精选社区规则),按 11 个 `-RuleSets` 分类选择性加载,默认关闭 |
| **合并产物** | `config/targets.merged.json` | 引擎自动生成(勿手改):三层合并 + 去重 + 自动分级 + origin 溯源的结果,运行时唯一数据源 |

**规则条目的生命周期**:

```text
assets/rules/ 或 config/targets.json
   │ MergeConfig(-Mode MergeConfig 或过期自动触发)
   ▼
发现 → 解析 → 路径规范化(环境变量形式) → 去重(保守档优先)
   → 自动分级(未知 → dangerous+禁用) → 与内置合并(builtin 永不被覆盖)
   ▼
config/targets.merged.json(带 id/tier/origin/signals)
   │ 运行时
   ▼
-RuleSets 过滤 → enabled 过滤 → user-overrides.json 勾选生效
```

**分级规则**(自动,不可绕过):路径含 cache/temp/log 等关键词 → `safe`;
download/package/installer 等 → `caution`;cookie/session/backup/data 或语义不明 → `dangerous`
(默认禁用,需两段式确认)。每条规则的分级依据记录在 `signals` 字段。

### 分类规则集逐项说明

以下六个分类规则集各自覆盖一类软件。**只清理缓存、日志、崩溃转储等可再生数据**;
软件本体、用户配置、项目文件均不在规则范围内。逐条评级明细见 [references/rulesets/](references/rulesets/)。

#### 国产软件(cn)— 20 条,全部 safe

覆盖国内用户高频安装的国产应用,按厂商划分:

| 厂商 | 覆盖软件 | 清理内容 |
|------|----------|----------|
| 腾讯 | QQ 浏览器、QQ 音乐、企业微信、腾讯会议 | 浏览器三件套缓存(GPU/Code/普通)、音乐缓存、客户端日志 |
| 金山 | WPS Office | 运行日志与缓存(文档备份 `wps-doc-backup` 属 dangerous,不在此列) |
| 字节跳动 | 剪映桌面版 | 客户端日志 |
| 阿里 | 钉钉 | 运行日志 |
| 字节跳动 | 飞书(Lark) | 客户端日志 |
| 360 | 360 安全浏览器 | GPU/Code/普通缓存 |
| 搜狗 | 搜狗浏览器 | WebKit 缓存 |
| 阿里 | 夸克浏览器 | GPU/Code/普通缓存 |
| 百度 | 百度网盘 | 用户日志 |
| 迅雷 | 迅雷 | 运行日志(需管理员,位于 ProgramData) |

这一类规则全部落在 safe 档:国产软件的缓存目录位置固定、内容可再生,清理后首次启动会自动重建。
聊天记录、云盘文件、下载目录均不受影响。

#### 开发工具(dev)— 55 条(53 safe + 2 dangerous)

覆盖面最广的规则集,按工具链划分:

| 工具链 | 覆盖软件 | 清理内容 |
|--------|----------|----------|
| 语言运行时 | Gradle(daemon 日志/通知缓存) | 日志与状态缓存(daemon 日志标 dangerous:可能含构建排错线索) |
| 移动开发 | Android SDK/模拟器、ADB、Flutter、Xamarin、MAUI | 模拟器日志、SDK 临时缓存、构建日志 |
| IDE 与编辑器 | VS Code Insiders、VSCodium、Windsurf、Trae | GPU 缓存、Code Cache、编译缓存、日志(Electron 四件套) |
| JetBrains 系 | JetBrains Toolbox | Toolbox 日志(各 IDE 的缓存归 builtin `jetbrains-caches`) |
| 容器与虚拟化 | Docker Desktop、Rancher Desktop | 客户端日志(镜像/容器数据不在范围内) |
| API 工具 | Postman、Insomnia、Bruno | Electron 缓存四件套 |
| 数据库工具 | DBeaver | 运行日志 |
| 版本控制 | GitHub Desktop、SourceTree | Electron 缓存与日志 |
| 游戏引擎 | Unity、Unreal Engine、Godot | Unity 通用缓存、Unreal DerivedDataCache(派生数据,重打开项目自动重建) |

对开发者而言这是收益最高的规则集:IDE 的 Code Cache 与编译缓存动辄数 GB,且完全可再生。

#### 设计建模(design)— 12 条,全部 safe

覆盖 3D 建模与设计渲染软件:

| 软件 | 清理内容 |
|------|----------|
| Adobe Substance 3D 全家桶(Designer/Painter/Sampler/Stager) | 各组件运行日志 |
| Unity 与 Unity Hub | 通用缓存与 Hub 的 Electron 缓存 |
| Unreal Engine | DerivedDataCache(着色器与资产派生数据) |
| Godot | 运行日志 |
| Blender | 崩溃日志(`%TEMP%\blender.crash.txt`) |

注意:建模工程文件(.blend/.uasset/.unity 等)保存在用户项目目录,与这些缓存路径完全无关。
Unreal 的 DDC 清理后体积可观,代价是下次打开项目需重新编译着色器(耗时取决于项目规模)。

#### AI 软件(ai)— 100+ 条

覆盖本地大模型运行时与 AI 编程客户端。**模型权重不在此范围内**——Ollama 的模型、
Hugging Face 缓存(`huggingface-cache`,caution 档)需单独决策:

| 类别 | 覆盖软件 | 清理内容 |
|------|----------|----------|
| AI 编程客户端 | Claude Desktop、Claude Code、Codex CLI、Antigravity、Kiro、JoyCode、Devin、Windsurf(AI 部分) | Electron 缓存、崩溃报告、遥测暂存 |
| 本地推理运行时 | LM Studio、Jan、Ollama(仅日志) | GPU 缓存、Service Worker 缓存、运行日志 |
| 国内 AI 客户端 | Cherry Studio、Kimi 桌面版 | Electron 缓存四件套 |
| 会话产物 | Claude Code shell 快照、Codex 归档会话、opencode 快照 | **dangerous 档**:清理后历史会话无法回滚,默认禁用 |

这一类的特点是 Electron 客户端居多(每个客户端的 Cache/Code Cache/GPUCache 组合约 5 条),
以及把"会话历史类"数据严格标为 dangerous——AI 工具的对话记录对用户往往有留存价值。

#### 游戏平台(game)— 39 条,全部 safe

覆盖主流游戏平台与启动器:

| 平台 | 清理内容 |
|------|----------|
| Steam | 客户端日志、崩溃转储(游戏本体与 `steamapps` 不动) |
| Epic Games Launcher | 启动器日志、内置网页缓存、崩溃报告 |
| Riot Client(英雄联盟/无畏契约) | 客户端 Electron 缓存与日志 |
| Battle.net(战网) | Agent 日志与缓存(需管理员,位于 ProgramData) |
| Ubisoft Connect、EA app、GOG Galaxy | 客户端日志与缓存 |
| WeGame、完美平台、HoYoPlay | 国产平台客户端日志与网页缓存 |
| Minecraft | 启动器日志、崩溃报告(`.minecraft` 存档不动) |
| 模组生态 | CurseForge、Overwolf、Vortex(Nexus Mods)、Playnite、Heroic | 
| Roblox | 客户端日志 |

游戏平台是"下载落地缓存"的重灾区——启动器更新包、清单文件常驻数 GB。
已安装游戏、存档、创意工坊内容均不受影响。

#### 影音创作(media)— 38 条(34 safe + 1 caution + 3 dangerous)

覆盖视频剪辑、直播与平面创作软件:

| 软件 | 清理内容 | 特别说明 |
|------|----------|----------|
| Adobe 全家桶 | Premiere/AE 媒体缓存、Bridge 缩略图缓存、Camera Raw 缓存、各组件日志 | 媒体缓存可安全清理,重新打开工程时自动重建(首次打开会慢) |
| Adobe 峰值文件 | 音频波形缓存 | **dangerous**:大工程重新生成波形耗时明显,默认禁用 |
| 剪映专业版 / CapCut | Electron 缓存四件套 | 崩溃报告标 dangerous(可能含工程恢复线索) |
| DaVinci Resolve | 崩溃记录、运行日志 | |
| OBS Studio | 运行日志、崩溃转储、浏览器源插件缓存 | 直播录制文件在用户自选目录,不受影响 |
| Lightroom / Lightroom Classic | 运行日志(目录/编目数据库不动) | |
| Creative Cloud | 组件日志、临时文件 | |
| Adobe 安装器日志 | 安装与更新临时日志 | **caution**:排查 Adobe 安装问题前请保留 |

### 自添加规则模板

**方式一:加入内置白名单**(推荐,立即生效且默认加载)

编辑 `config/targets.json`,在 `targets` 数组中追加:

```json
{
  "id": "myapp-cache",
  "name": "MyApp cache",
  "enabled": true,
  "tier": "safe",
  "requiresAdmin": false,
  "type": "dir",
  "category": "builtin",
  "paths": ["%LOCALAPPDATA%\\MyApp\\Cache"],
  "preCommands": [],
  "stopProcesses": [],
  "stopServices": [],
  "glob": "",
  "risk": "regenerable cache; app rebuilds it on next launch"
}
```

**方式二:自建规则文件**(适合批量或分享,经合并管线获得完整守卫)

在 `assets/rules/` 下新建 `my_rules.json`(5 元组数组,与社区规则同格式):

```json
[
  ["myapp | Cache", "%LOCALAPPDATA%\\MyApp\\Cache", "contents", false, "safe cache dir, rebuilt on launch", true],
  ["myide | Old logs", "%APPDATA%\\MyIDE\\logs\\*.log", "file", false, "rotated logs, safe to remove", true]
]
```

字段语义(5 元组):

| # | 字段 | 说明 |
|---|------|------|
| 1 | 名称 | `来源 \| 描述` 格式,便于审计 |
| 2 | 路径 | **必须**用环境变量(`%LOCALAPPDATA%` 等);支持通配符 `*` |
| 3 | 动作 | `contents`(清空目录内容,保留目录)/ `file`(删文件)|
| 4 | 预留 | 惯例为 `false` |
| 5 | 备注 | 写清"为什么这是安全的"——这是审计的关键 |
| 6 | 启用 | `true` = 参与合并;分级仍由引擎自动判定 |

然后触发合并:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\Invoke-CDriveCleanup.ps1 -Mode MergeConfig
```

**添加规则的三条铁律**:

1. **只添加能证明可再生的目标** —— 不确定就标 `dangerous` 让协议兜底,绝不猜测 `safe`
2. **路径必须环境变量化** —— 硬编码机器路径会被拒绝合并
3. **先 DryRun 验证** —— 添加后先 `-Mode Scan` 确认大小与分级符合预期,再考虑清理

---

## 🔖 CLI 参数参考

<details>
<summary><b>全部参数</b>(点击展开)</summary>

| 参数 | 说明 |
|------|------|
| `-Mode Scan\|Clean\|Analyze\|MergeConfig` | 操作模式 |
| `-Tiers safe,caution,dangerous` | 风险档过滤(Clean 默认 safe;Scan 默认 safe,caution) |
| `-Ids a,b` | 限定目标 id |
| `-ConfirmIds a,b` | 用户已显式确认的 id —— **caution/dangerous 档必需** |
| `-Elevate` | 需要时触发 UAC 重启;JSON_SUMMARY 经结果文件回传 |
| `-DryRun` | 完整流程,零删除 |
| `-AllowStop` | 允许停止列出的进程/服务(须经用户确认后传入) |
| `-BackupDangerous` | 删除前将 dangerous 目标备份到 `<skill-root>\backups\`(skill 在 C: 时为同盘,不释放空间) |
| `-TrimWorkingSet` | 对已清理目标的进程执行 EmptyWorkingSet |
| `-MaxThreads N` | 并行线程数(默认=逻辑核数) |
| `-Policy conservative\|standard\|deep` | 策略层(conservative = safe 档 + 仅内置) |
| `-RuleSets minimal\|general\|cn\|dev\|design\|ai\|game\|media\|system\|community\|all\|none` | 规则集引导选择(默认 **minimal**) |
| `-RecoveryMode permanent\|recycle\|quarantine` | 删除语义:直接删 / 回收站 / 隔离区(manifest + 一键还原) |
| `-HotMinutes N` | 热文件围栏窗口(默认 30) |
| `-NoCache` / `-NoMft` | 绕过尺寸缓存 / 关闭 MFT 快速通道 |
| `-PlanFile path` | 自动化场景的预核准扫描计划 |
| `-TopN N` / `-PrettyJson` | 扫描条目上限(默认 60)/ 人类友好 JSON |
| `-Config path` / `-CCPDirs d1,d2` | 自定义 targets.json / 覆盖规则目录 |
| `-LogPath path` / `-ReportFile path` | 自定义日志 / Markdown 报告路径 |

退出码:`0` 成功 · `2` 存在需管理员项 · `3` 致命错误(缺配置) · `4` Plan 门禁拦截。

</details>

---

## 📊 JSON_SUMMARY 数据契约

每次运行都会在 stdout(UTF-8)输出被 `JSON_SUMMARY_BEGIN` … `JSON_SUMMARY_END` 包围的
JSON 块。**Agent 只解析这一块内容,绝不从控制台自由文本中推断结果**——这一"数据通道"
与"人类日志通道"的彻底分离,是整个技能保证机器可读性与人类可读性互不污染的关键契约。

```json
{
  "schemaVersion": 1,
  "mode": "Clean",
  "os": {"caption":"...","build":"26200","isServer":false},
  "drive": {"letter":"C","freeGB_before":3.58,"freeGB_after":3.74},
  "items": [{
    "id":"uv-cache", "name":"uv cache", "tier":"safe", "origin":"builtin",
    "enabled":true, "exists":true, "requiresAdmin":false,
    "sizeGB_before":113.64, "sizeGB_after":0, "freedGB":113.64,
    "status":"cleaned", "message":""
  }],
  "totals": {"freedGB":113.64,"cleaned":1,"skipped":0,"needAdmin":0,"errors":0},
  "logPath": "...",
  "reportPath": "..."
}
```

`status` 字段可取以下值之一:`scanned` / `cleaned` / `skipped` / `need-admin` /
`locked` / `dryrun` / `error` / `blocked-by-guardrail` / `advisory`。其中
`blocked-by-guardrail` 与 `advisory` 分别表示被引擎护栏拦下与仅提供建议不执行,
便于 Agent 区分"删不了"与"不该删"两类情况。

---

## 🧩 配置说明

`config/targets.json` 是内置白名单的编辑入口,可按每台机器的实际情况自由增删:

```json
{
  "id": "my-app-cache",
  "name": "My App cache",
  "enabled": true,
  "tier": "safe",
  "requiresAdmin": false,
  "type": "dir",
  "paths": ["%LOCALAPPDATA%\\MyApp\\Cache"],
  "preCommands": [],
  "stopProcesses": [],
  "stopServices": [],
  "risk": "regenerable"
}
```

编辑准则:

- 路径**必须**使用环境变量形式(`%LOCALAPPDATA%`、`%APPDATA%`、`%USERPROFILE%`、`%TEMP%`、
  `%ProgramData%`、`%WinDir%`、`%ProgramFiles%`、`%SystemDrive%`)——这既是跨机可移植的前提,
  也是合并管线校验的硬门槛
- 只添加能证明"可再生"的目标;语义不明的一律默认 `dangerous`,把决策权交回协议层
- 生成的产物(`targets.merged.json`、`user-overrides.json`、`scan-cache.json`)位于 `config/`,
  已被 gitignore 排除,不会混入版本控制

社区规则层(`assets/rules/`,约 1.54 万条 vendored 目标)按以下文件组织:

```text
winapp2_latest.json        # Winapp2.ini v260730(14,117 条,CC-BY-SA-4.0)
community_cleaners.json    # BleachBit cleaners Windows 路径(986 条,GPL-3.0+)
rules_*.json               # 精选社区规则集(ai / cn / dev / design / game / media / mobile)
cdisk_cleaner_*.json       # 社区自定义规则 + 应用勾选状态
```

**确定性合并管线**依次经过:发现 → 解析 → 规范化(环境变量形式)→ 去重(保守档优先)→
自动分级(未知目标一律降为 `dangerous` 并禁用)→ 合并(origin 溯源、内置项永不被覆盖)→ 持久化。
由于每一步都基于规范化后的输入,重复运行会生成完全一致的规则 id,用户在 `user-overrides.json`
里做的勾选,在规则升级或重建后依然有效。

详见 [references/rules-and-merging.md](references/rules-and-merging.md)。

---

## ⚡ 性能实测

以下数据均来自实际机器的测量记录,而非理论推算:

| 技术 | 实测结果 |
|------|----------|
| 智能尺寸缓存(mtime + TTL 15 分钟) | uv 与 npm 缓存共 131.55 GB:首次冷扫耗时 188.6 秒,**二次扫描仅 11 毫秒**,两次数值完全一致 |
| 两级并行扫描 | 15,403 个目标冷扫约 53 秒(线程数等于逻辑核数) |
| NTFS MFT 直读(Analyze) | 约 27 秒遍历 342 万条 MFT 记录、223.59 GB 数据,并正确识别硬链接的真实独占占用 |
| Restart Manager 锁检测 | 被占用的文件直接给出占用进程名称与 PID,而非笼统报错 |
| BelowNormal I/O 优先级 | 扫描期间日常操作无明显卡顿 |
| 重复文件哈希级联 | 大小分组 → 首尾 64KB MD5 → 全量 MD5 三级漏斗,独立显卡环境下自动加倍哈希线程 |

---

## 📄 报告与日志

每次运行都会在本地留痕,产出以下三类结构化工件,
**仅写入本机磁盘,绝不上传网络、不采集遥测**:

1. **Markdown 结构化报告** —— `<skill-root>\reports\win-c-clear-report_<时间戳>.md`
   按 11 个章节模块化组织(概要 / 环境 / 磁盘变化 / 目标统计 / 结果 / 围栏命中 /
   Top10 明细 / 性能 / 产物路径),方便人类读者在会话、工单或审计中快速引用。路径可由
   `-ReportFile` 自定义。
2. **JSON 全量报告** —— 与 Markdown 摘要并存的完整结构化数据,包含每一条规则的 id、
   大小、状态、失败原因以及总览与护栏统计,是 Agent 二次决策的权威数据源。
3. **审计日志** —— `<skill-root>\logs\win-c-clear-skill_log_<时间戳>.txt`,按 8 个章节
   记录每一次护栏触发、确认协议结果与跳过原因,是"七层防线可审计"承诺的落地证据。
   路径可由 `-LogPath` 覆盖。

> 三份产物共同构成"结果可查、原因可追、责任可溯"的审计闭环。

### 数据找回

引擎提供两种安全回收模式,均优于直接永久删除:

- **回收站模式**(`-RecoveryMode recycle`):被删除项先进入系统回收站,可随时还原
- **隔离模式**(`-RecoveryMode quarantine`):被删除项移入带 manifest 清单的隔离目录,
  可通过 `tools\restore-quarantine.ps1 -Manifest <path> [-List|-Only <关键词>]`
  一键还原任意子集,适合自动化场景下分批回滚

对于 `-BackupDangerous` 备份的危险档目标,引擎会在真正删除前将其拷贝至
`<skill-root>\backups\`,作为最后一道保险。

---

## 📁 项目结构与社区文件

仓库按"引擎 + 数据 + 深度文档 + 工具链 + 社区"五类组织,层次清晰、职责分明:

```text
win-c-clear-skill/
├── SKILL.md                  # Agent 入口:工作流 + 红线
├── reference.md              # 确认协议细则(按需加载)
├── CHANGELOG.md              # 版本发布记录(Keep a Changelog + SemVer)
├── scripts/                  # Invoke-CDriveCleanup.ps1(引擎)+ .bat 入口 + C# 扫描器
├── config/                   # targets.json(可编辑)+ 生成的合并/缓存文件
├── assets/rules/             # 内置社区规则数据(约 1.54 万条)
├── references/               # 深度文档 + 审计报告快照(guardrails / merging / windows-api …)
├── tools/                    # 安装器 + 测试套件 + 规则刷新 + 还原工具(含 tools/audit/ 审计探针)
└── .github/                  # CI 工作流 + issue/PR 模板
```

关键文件速查:

| 文件 | 定位 |
|------|------|
| [SKILL.md](SKILL.md) | Agent 视角的技能入口,记录工作流与三条红线 |
| [reference.md](reference.md) | 确认协议与红线的实施细则,按需加载 |
| [CHANGELOG.md](CHANGELOG.md) | 版本发布记录 |
| [CONTRIBUTING.md](CONTRIBUTING.md) | 贡献指南 + 测试套件使用方式 |
| [SECURITY.md](SECURITY.md) | 面向 Agent 的安全政策(漏洞上报 + 安全边界) |
| [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) | 社区行为准则 |
| [LICENSE](LICENSE) | MIT 许可证 |

---

## 📜 免责声明

以下条款在使用本技能之前请务必逐条阅读——它们既是对风险的正视,也是对本项目"审慎而非激进"
设计哲学的说明:

1. **本软件按"现状"(as-is)提供,不附带任何明示或默示的担保。**  在真实机器上执行删除操作
   存在固有的数据风险,因使用本技能产生的一切后果由使用者自行承担。
2. **删除操作可能是不可逆的。**  `permanent` 恢复模式下文件将被直接删除,不经过回收站。
   重要数据请提前备份;若对清理结果没有把握,建议先以 `-DryRun` 演练,
   或改用 `-RecoveryMode quarantine` 隔离模式验证无误后再实际清理。
3. **请勿在生产服务器、存放唯一数据副本的机器,或任何无法承受误删损失的环境中使用。**
   本技能面向个人桌面与开发机,不覆盖企业运维场景。
4. **清理规则由社区维护,个别规则可能与你的实际使用场景不符。**  审阅并确认清理清单是使用者的
   责任——引擎护栏只能拦截已知类型的危险,不能替代人的判断。
5. **本项目与任何商业软件无关;** 所引用的第三方规则数据,其许可归属仍属各自的上游项目。
6. **一旦使用本技能,即视为你已阅读、理解并同意 [MIT 许可证](LICENSE) 的全部条款。**

---

## 🔐 安全政策(中文版)

> 本节为面向**使用者**的摘要。两份深度安全文档 —— [SECURITY.md](SECURITY.md) 与
> [references/guardrails.md](references/guardrails.md) —— 是写给 **Agent(被加载后自主执行
> 的 AI)** 看的:Agent 会在处理风险目标、提权失败或用户施压时按需加载它们,以约束自身行为。
> 人类读者了解下面这份摘要即可。

### 发现安全问题怎么办?

**请勿公开提交 issue。** 本技能会删除文件,漏洞细节一旦公开可能被恶意利用。请通过 GitHub 的
私有漏洞上报通道(**Security 标签页 → Report a vulnerability**)私下联系维护者。我们承诺
7 天内确认收悉。以下情况均视为安全问题:

- 任何绕过受保护路径黑名单的途径(WinSxS / System32 核心 / Installer / NTUSER.DAT 等)
- 任何绕过 Plan 门禁或确认门控直接删除的方式
- 未完成两段式协议即可将 unknown / dangerous 目标降级为 safe
- 任何形式的网络外传(文件内容 / 扫描结果 / 日志)

### 你的数据去了哪里?

- 扫描结果、日志、报告**仅写入本地磁盘**(`<skill-root>\logs\` 与 `reports\`),
  **零网络上传、零遥测**
- 唯一的网络访问是可选的规则升级工具 `tools/fetch_rules.py`(手动触发,拉取上游规则仓库)。
  运行时引擎本身完全离线,不依赖任何云服务

### 七层引擎防线速览

| # | 防线 | 拦截什么 |
|---|------|----------|
| 0 | Plan 门禁(exit 4) | 跳过扫描直接清理 / 计划超过 30 分钟未使用 / **清理目标不在已扫描的计划范围内** |
| 1 | 扫描范围围栏 | 扫描行为闯入系统核心区域(白名单 + 黑名单双重过滤,**逐路径**判定) |
| 2 | 白名单强制 | 通过裸路径或编造 id 指定白名单之外的目标 |
| 3 | 受保护路径黑名单 | 合并期降级为 dangerous + 禁用;删除期二次断言拦截;合并末尾不变量清扫兜底 |
| 4 | 热文件围栏 | 删除最近 30 分钟内仍在修改的"使用中"文件(仅顶层子项自身 mtime) |
| 5 | 危险扩展名围栏 | 非内置目标的 exe / dll / sys / msi 在永久模式下跳过 |
| 6 | 重解析点围栏 | 穿透 junction / symlink 删除链接目标的数据(常在另一块盘上) |
| 7 | RM 锁上报 + 审计日志 | 盲删被锁文件;每一次行为全程留痕、可审计 |

此外:`-Mode Clean` 禁止与只读审计档 `-ScanMode diagnostic` 组合(exit 3);
`-Ids` / `-ConfirmIds` 与路径类参数拒绝可用于提权子进程命令行注入的字符(exit 3)。

完整规格见 [references/guardrails.md](references/guardrails.md)(Agent 向深度文档)。

---

## 🤝 参与贡献与技术支持

欢迎贡献。请先通读 [CONTRIBUTING.md](CONTRIBUTING.md) 了解工作流。由于本项目会
在真实机器上删除文件,所有变更均执行高安全标准,且必须通过以下测试套件:

```powershell
tools\verify_safety.ps1            # 护栏、分级、契约、unknown-id 回归
tools\verify-engine.ps1            # 语法 + C# 扫描器编译 + 黑名单正则
tools\test-regression.ps1          # glob 作用域、重解析点围栏、计划范围绑定、注入防护
python tools\test-scan-lists.py    # 白名单 / 黑名单语义
```

同一套检查会在每个 PR 的 CI(Windows runner)上自动运行,确保合入主分支前已覆盖所有
已知攻击面。

- 🐛 **发现 Bug?**  请使用 [Bug 报告模板](.github/ISSUE_TEMPLATE/bug_report.yml) 提交,
  优先提供 `-DryRun` 复现步骤,便于维护者安全复现。
- 🔒 **安全问题:** 见 [SECURITY.md](SECURITY.md)(私有上报,切勿开公开 issue)。

---

## 🙏 致谢与许可证

本项目采用 [MIT 许可证](LICENSE) 开源。

在设计与实现过程中,以下开源项目提供了重要的思路与数据支撑,谨在此致谢:

| 参考 | 来源 | 说明 |
|------|------|------|
| [One-click-cleaning-of-C-drive](https://github.com/JIEKE66633/One-click-cleaning-of-C-drive)(MIT) | 基础架构参考:"扫描 → 选择 → 清理"的交互范式、备份与恢复管理、大文件扫描、模拟预览等能力设计 |
| [MoscaDotTo/Winapp2](https://github.com/MoscaDotTo/Winapp2)(CC-BY-SA-4.0) | 内置的 14,117 条社区清理规则数据 |
| [BleachBit](https://github.com/bleachbit/bleachbit)(GPL-3.0+) | 内置的 986 条 Windows 清理器定义 |

以上第三方规则数据的许可归属仍属各自的上游项目;再分发本仓库时,请一并保留对应的
归属声明,以遵循上游项目的许可要求。
