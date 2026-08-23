# Harness 适配指南（harness-adaptation.md）

面向 **Claude Code / codex / DeepSeek Harness (dsh)** 及 Trae/Cursor 的系统集成。
约定均已对照上游源码核验（2026-08）：openai/codex（`.codex/` 约定）、
OrcaWhisper/Claude-Code（Claude Code v2.1.88 源码归档，`src/skills/` 技能系统）、
deepseek-ai/deepseek-harness（`.agents/` 约定 + Claude 兼容技能格式）。

## 一键安装（推荐）

```powershell
# 安装到 Claude Code + codex + DeepSeek Harness（用户级）
powershell -File tools\install-harness.ps1 -All
# 单目标 / junction 方式（仓库更新自动同步）/ 查看全部目标
powershell -File tools\install-harness.ps1 -Targets codex -Symlink
powershell -File tools\install-harness.ps1 -List
```

## 各 harness 目录约定（源码核验）

| Harness | 用户级 skills 目录 | 项目级 | 附加要求 |
|---------|-------------------|--------|---------|
| **Claude Code** | `%USERPROFILE%\.claude\skills\win-c-clear-skill\` | `.claude\skills\` | 无：SKILL.md frontmatter（name+description）即被索引，按 description 触发 |
| **DeepSeek Harness (dsh)** | `%USERPROFILE%\.agents\skills\win-c-clear-skill\` | `.agents\skills\` | Claude 兼容技能格式；`.agents/` 亦承载 agent teams 定义 |
| **codex** | `%USERPROFILE%\.codex\skills\win-c-clear-skill\` | 项目 `.codex\skills\` | 在 `AGENTS.md`（项目或 `~/.codex/AGENTS.md`）加一行指针让 codex 主动发现 |
| Trae | `%USERPROFILE%\.trae\skills\` | `.trae/skills/` | — |
| Cursor | `%USERPROFILE%\.cursor\skills\` | `.cursor/skills/` | — |

### codex 的 AGENTS.md 指针（必需步骤）

```markdown
Windows C: cleanup: use the win-c-clear-skill (see .codex/skills/win-c-clear-skill/SKILL.md).
```

### 触发词（对三个 harness 通用，已写入 SKILL.md description）

- 中文：C盘满了 / 清理缓存 / 释放磁盘空间 / 磁盘清理 / C盘空间不足
- 英文：C drive full / clean disk caches / free up space / reclaim Windows space / win-c-clear-skill

## 引擎调用契约（所有 harness 通用）

```text
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill>\scripts\Invoke-CDriveCleanup.ps1" <args>
```

- **PS 5.1+ 零依赖**；路径含空格已验证
- **UTF-8 控制台**：引擎自设 OutputEncoding，中文 OS 无乱码
- **退出码**：0 成功 / 2 存在 need-admin / 3 致命
- **解析契约**：只信 stdout 中 `JSON_SUMMARY_BEGIN/END` 之间的**紧凑单行 JSON**；自由文本仅人读
- **幂等**：重复 Clean 不报错（already empty）

## Token 经济（为 Agent 上下文设计）

| 设计 | 效果 |
|------|------|
| 紧凑单行 JSON（`-PrettyJson` 供人读） | ~70% 体积缩减 |
| Scan 只出 Top-N 存在项（`-TopN`，默认 60；0=仅计数） | 15k 目标 → 15KB |
| `counts` 聚合 + `cacheHits` 字段 | 缺失项零成本全貌 |
| MergeConfig 仅聚合计数 | 完整清单留在 targets.merged.json 按需读 |
| message 截断 160 字符 | 防错误信息爆上下文 |

Agent 最佳实践：解析 JSON 后只转述 Top 项 + counts；需要完整清单时**分段读** targets.merged.json。

## 性能与 I/O 调度（物理瓶颈对策）

- **两级并行**：存在性快筛 → 大目录一级子目录 1:1 任务；小路径 16/批
- **扫描缓存（WindowsClear 技术）**：`config/scan-cache.json`，键=路径，值={字节, 目录 mtime, 缓存时刻}；mtime 未变且 15 分钟 TTL 内直接命中。实测：uv+npm 131.55GB 冷扫 188.6s → **二次 11ms（17,000x）**，数值逐字节一致。`-NoCache` 强制精确重测
- **Restart Manager（WindowsClear 技术）**：文件被锁时经 rstrtmgr.dll 原生 API 报告占用进程（名称+pid），写入 item.message；关闭动作仍受 `-AllowStop` 用户确认门控
- **BelowNormal 优先级**：测量期间进程降级，系统不卡顿
- **robocopy /L 原生回退**：.NET 枚举被拒时列表模式取体积
- **GPU 感知哈希**：独显时哈希线程 2x 核数；`hashPath` 透明标注
- **冷缓存现实**：首次全盘扫描受物理 I/O 限制；二次起享受缓存（同会话内 Agent 多轮扫描是主要受益场景）

## 策略层（-Policy）

| Policy | 语义 |
|--------|------|
| `conservative` | 仅 safe + 仅 builtin/merged 白名单（排除全部社区规则启用态） |
| `standard`（默认） | Clean=safe；Scan=safe,caution |
| `deep` | Clean 也纳入 caution 候选（ConfirmIds/AllowStop 门控不变） |

## 纯 Windows / 计划任务 / 双击

```powershell
scripts\Scan.bat        # 只读扫描
scripts\Clean-Safe.bat  # safe 档清理
schtasks /create /tn "WinCClean" /tr "powershell -NoProfile -ExecutionPolicy Bypass -File \"C:\path\to\win-c-clear-skill\scripts\Invoke-CDriveCleanup.ps1\" -Mode Clean -Tiers safe" /sc weekly /d SUN /st 03:00 /rl HIGHEST
```

## 原生命令优先清单（清理动作用 Windows 自带能力）

| 目的 | 原生命令/API |
|------|-------------|
| 事件日志清理 | `wevtutil cl <log>` |
| 休眠文件 | `powercfg /h off` |
| 回收站 | `Clear-RecycleBin` |
| Windows.old | `takeown` + `icacls` |
| 目录体积（被拒时） | `robocopy /L /BYTES` |
| 工作集截取 | `EmptyWorkingSet`（psapi P/Invoke） |
| 占用检测 | Restart Manager（rstrtmgr.dll P/Invoke） |
| 组件存储（仅建议） | `dism /online /cleanup-image /startcomponentcleanup` |
| 经典清理（仅建议） | `cleanmgr /sagerun` |
| 还原点（红线禁删） | `vssadmin`（永不执行） |
