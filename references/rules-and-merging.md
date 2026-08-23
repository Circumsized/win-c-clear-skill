# Rules & Merging（规则源与合并管线）

## 规则数据源（assets/rules/，自包含）

| 文件 | 来源 | 规模 | 源类别 |
|------|------|------|--------|
| `winapp2_latest.json` | [MoscaDotTo/Winapp2](https://github.com/MoscaDotTo/Winapp2) v260730（CC-BY-SA-4.0） | 14117 条 | community（opt-in） |
| `community_cleaners.json` | [BleachBit cleaners](https://github.com/bleachbit/bleachbit/tree/master/cleaners)（GPL-3.0+，仅 Windows 路径） | 986 条 | community（opt-in） |
| `cdisk_cleaner_custom_rules.json` | 社区自定义规则导出 | 4229 条 | community（opt-in） |
| `rules_*.json`（8 个） | 人工精选社区规则（AI工具/国内应用/开发工具/游戏/设计/媒体/移动） | ~210 条 | curated |
| `common_custom_rules.json` | 通用精选社区规则 | 110 条 | curated |
| `cdisk_cleaner_config.json` | 应用勾选状态导出（双重编码 v2 格式，含系统规则绝对路径） | 8530 元素 / 4265 唯一（每条重复两次，见文末） | state |

另可配置 `externalMergeSources`（默认**为空**，保证 GitHub 下载即可用；如本机装有
原始规则导出目录，可自行填入绝对路径，存在时一并合并，勿提交机器特定路径）。

## 统一元组格式

所有规则统一为 5/6/7 元组数组：

```
[name, path, type, bool, meta, bool?, glob?]
  [0] name  : 显示名
  [1] path  : 环境变量形式路径（支持 %LOCALAPPDATA% 等；winapp2 源可含 * 通配符）
  [2] type  : "dir" | "file" | "glob"（其他值如 BleachBit 的 "contents" 视为不支持 →
              强制 dangerous+disabled 并打 [unsupported-type:*] 标记，绝不静默升级成整目录删除）
  [3] bool  : requiresAdmin（或 default_checked，视来源）
  [4] meta  : 描述/溯源元数据
  [5] bool? : advanced 标记（或 enabled，视来源）
  [6] glob? : glob 模式（仅当 [3] 为 bool 的 7 元组形式；rules_ai_tools.json 使用此形式）
```

> 注意两种 glob 位置：`[3]` 为 **bool** 时 glob 在 `[6]`；`[3]` 为 **string** 时 glob 在 `[5]`。
> 两者都必须解析——漏掉任一处都会让「只删 *.lock」退化成「删光整个目录」。

`cdisk_cleaner_config.json` 为双重编码 v2：`{"order": ["[\"[元组]\", 状态int]", ...]}`。

## 7 步合并管线（确定性、可复现）

1. **发现**：递归枚举 mergeSources + externalMergeSources 下 `.json/.ini/.txt/.yaml/.yml`
2. **解析**：按格式解析为统一元组；失败条目进 `unparsed`（fail-soft）
3. **规范化**：绝对路径回写环境变量形式（最长前缀优先，大小写不敏感；通配符保留）
4. **去重**：以规范化路径为主键；冲突取**更保守 tier**；源分类决定 enable 覆盖权
5. **分级**：关键词+类型自动 tier（见下）；**不确定→dangerous+disabled**（红线）
6. **归并**：builtin（87 条，永不覆盖）→ origin 标注 `builtin|community-sourced|merged`
7. **呈现**：生成 `config/targets.merged.json`（UTF-8 BOM）；Agent 用聚合计数呈现，完整清单在文件中

### 源分类策略（处理顺序与启用语义）

| 类别 | 文件 | 处理顺序 | 默认 enabled |
|------|------|---------|--------------|
| curated | rules_*、common_custom | 第 1 批（字母序） | tier==safe → true |
| community | winapp2_latest、community_cleaners、cdisk_custom_rules | 第 2 批 | **false（opt-in）** |
| state | cdisk_cleaner_config | 第 3 批（最后） | 应用勾选状态（覆盖前面的 enable） |

去重时：later 仅 state 类可覆盖 enabled；community 的 false 不会禁用已启用的 curated 条目。

### 自动分级 v2（Get-AutoTier，编译式正则 + 保守优先序）

三级信号类各编译为单条正则，按 **dangerous > 程序目录 > caution > safe** 的优先序判定
（参考 bleachbit cleaners 语义 + winapp2 社区惯例 + WindowsClear/zhenhuaDiskCleaner 保守哲学）：

| 优先级 | 信号类（编译正则，匹配路径/末段） | 判定 |
|-------|--------------------------------|------|
| 1 | backup/.met/.bak/.cfg/.dat/.evtx/.sqlite/.db、cookies/history/password/session/bookmark/known/clients/saved/wallet/token/credential/login/seed/keystore、windows.old | dangerous |
| 2 | `\bin|\src|\lib|\site-packages|\node_modules|\include|\share` 主程序目录 | dangerous |
| 3 | download/package/installer/prefetch/deliveryoptimization/softwaredistribution/setupapi/windowsupdate/windowsdefender/panther/recycle | caution |
| 4 | cache/temp/tmp/log/dump/crash/shader/webcache/htmlcache/crashpad/gpucache/d3ds/thumb/icon、.log/.dmp/.etl/.tmp 扩展 | safe |
| 5 | file 型条目（数据文件） | dangerous |
| 6 | **其他（无信号）** | **dangerous + disabled**（红线：绝不猜 safe） |

每条合并产物带 `signals` 字段（danger-signal/caution-signal/safe-signal/program-dir/file-type/unknown）
供审计；`stats.signalsHistogram` 汇总。相比 v1 的改进：`Package Cache`→caution（不再被 'cache' 误判 safe）、
`windows.old`→dangerous、cookies/downloads.sqlite→dangerous。

受保护路径（WinSxS/Installer/NTUSER.DAT/pagefile 等，见 [guardrails.md](guardrails.md)）在合并时
强制降级 dangerous+disabled 并打 `[guardrail:protected-path]` 标记（实测当前源中 **1338 条**）。

合并末尾还有一道**不变量清扫**（红线，纵深防御）：无论源类别、去重顺序、tier 提升或 state 覆盖
如何组合，落盘产物必须满足 `tier==dangerous ⇒ enabled==false`，且受保护路径必须同时是
dangerous+disabled。被强制纠正的条数记入 `stats.invariantForcedDisable`，并在 risk 字段打
`[invariant:forced-disable]`。这道清扫的必要性来自一个真实教训：tier 曾经**恰好**是路径的纯函数，
所以「dangerous 必禁用」在去重分支里没有重新断言也没出问题；一旦 tier 开始依赖源侧元数据
（如不支持的 type），state 源就能把已被判为 dangerous 的条目重新打开。

## 规则集分类（-RuleSets 引导选择）

规则**不默认全量加载**：引擎按 `-RuleSets` 过滤（默认 `minimal`=仅 builtin 白名单）。每条合并产物带 `category` 字段（来源文件映射）：

| RuleSets | category | 来源 | 规模（本机） |
|----------|----------|------|-------------|
| `minimal` / `none` | builtin | config/targets.json（87 条精选） | 87 |
| `general` | general | common_custom_rules.json | ~110 |
| `cn` | cn | rules_cn_apps.json（WPS/钉钉/飞书/夸克/搜狗…） | ~20 |
| `dev` | dev | rules_dev_tools + rules_mobile_dev_tools | ~55 |
| `design` | design | rules_design_3d_cad.json | ~12 |
| `ai` | ai | rules_ai_tools.json（Ollama/LM Studio/Claude/Cherry…） | ~63 |
| `game` | game | rules_game_platforms.json（Steam/Epic/Riot…） | ~38 |
| `media` | media | rules_media_creation.json（OBS…） | ~38 |
| `system` | system | cdisk_cleaner_config（含系统规则绝对路径，规范化后并入） | ~4265 |
| `community` | community | winapp2_latest + community_cleaners（opt-in） | ~15100 |
| `all` | 全部 | 上述全部 | 15403 |

引导话术见 SKILL.md 工作流第 1 步；多选逗号组合（`-RuleSets cn,dev`）。

分类评级索引见 [rules-catalog.md](rules-catalog.md)；逐条明细见 [rulesets/](rulesets/)（由 `tools/generate_rules_catalog.py` 从 assets/rules/ 生成）。

> ⚠️ 注意：`rulesets/` 的评级来自 `merge_rules.classify_tier`（独立的 Python 关键词启发式），
> **与引擎的 `Get-AutoTier` 不同源**，两者存在双向分歧。真实分级以引擎产出的
> `config/targets.merged.json` 为准，详见 [rules-catalog.md](rules-catalog.md) 顶部的权威性说明。

### 工具现状

`tools/merge_rules.py` 与 `tools/extract_builtin_rules.py` 的输入目录
（`config/builtin/`、`config/source/`、`config/generated/`）**在发布仓库中不存在**（均被
gitignore），因此这两个脚本在开箱状态下**无法独立运行**。`merge_rules.py` 目前仅作为
`generate_rules_catalog.py` 的 `classify_tier` 函数库被 import（该函数不读文件，可用）。
`fetch_rules.py` 的第 3 步「陈旧条目审计」同样依赖缺失的 `config/source/...`，会静默跳过。
引擎运行时**完全不依赖**这些脚本 —— 规则数据已 vendored 在 `assets/rules/`。

## 升级规则

```powershell
# 刷新上游（Winapp2.ini + BleachBit cleaners）→ tools/_cache/ → 重新解析输出到 assets/rules/
python tools/fetch_rules.py

# 重生成 rulesets/ 分类评级明细文档 + references/rules-catalog.md
python tools/generate_rules_catalog.py

# 或手动：把新 JSON 放入 assets/rules/（同名覆盖），删除生成物触发重合并
Remove-Item config/targets.merged.json
```

引擎启动时检测 mergeSources 目录 mtime > merged.json mtime 即自动重合并。

## 实测规模（本机实测值）

- 合并产物 **15403** 目标（builtin 87 / merged / community-sourced 其余），id 全唯一
- tier 分布（实测 grep 计数）：**safe 4171 / caution 2604 / dangerous 8628**
- 默认启用 **63** 项 = safe 59 + caution 4，**dangerous 启用 0 项**（红线成立，已加不变量清扫固化）
- 受保护路径降级：**1338** 条带 `[guardrail:protected-path]`

> 上一版文档记的是 safe 4796 / caution 2560 / dangerous 8047 与 98 条降级，与实际产物不符
> （偏差方向是「文档高估 safe、低估 dangerous」）。以上数字改为按实际 `targets.merged.json` 实测。

### 已知数据质量问题：state 源条目重复

`cdisk_cleaner_config.json` 的 `order` 有 **8530** 个元素，但唯一条目只有 **4265** —— 每条都出现两次。
去重管线能吸收（同一规范化路径命中已有条目），因此无功能影响，但会造成：

- `stats.discovered` / `parsed` 计数虚高一倍
- 去重分支对同一路径执行两次，注解被重复前置（曾产出 2477 个标记 / 1338 条目）——已用幂等判断修掉
- 全部 8530 条的勾选状态均为 `0`（禁用），即这个唯一能「打开」目标的源类别当前不打开任何东西
