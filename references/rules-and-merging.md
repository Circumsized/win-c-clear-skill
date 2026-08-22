# Rules & Merging（规则源与合并管线）

## 规则数据源（assets/rules/，自包含）

| 文件 | 来源 | 规模 | 源类别 |
|------|------|------|--------|
| `winapp2_latest.json` | [MoscaDotTo/Winapp2](https://github.com/MoscaDotTo/Winapp2) v260730（CC-BY-SA-4.0） | 14117 条 | community（opt-in） |
| `community_cleaners.json` | [BleachBit cleaners](https://github.com/bleachbit/bleachbit/tree/master/cleaners)（GPL-3.0+，仅 Windows 路径） | 986 条 | community（opt-in） |
| `cdisk_cleaner_custom_rules.json` | c_cleaner_plus 自定义规则导出 | 4229 条 | community（opt-in） |
| `rules_*.json`（8 个） | c_cleaner_plus 人工精选（AI工具/国内应用/开发工具/游戏/设计/媒体/移动） | ~210 条 | curated |
| `common_custom_rules.json` | c_cleaner_plus 通用精选 | 110 条 | curated |
| `cdisk_cleaner_config.json` | c_cleaner_plus 应用勾选状态（双重编码 v2 格式，含系统规则绝对路径） | 4265 条 | state |

另可配置 `externalMergeSources`（默认**为空**，保证 GitHub 下载即可用；如本机装有
c_cleaner_plus 原始目录，可自行填入绝对路径，存在时一并合并，勿提交机器特定路径）。

## 统一元组格式

所有规则统一为 5/6 元组数组（与 c_cleaner_plus 兼容）：

```
[name, path, type, bool, meta, bool?]
  [0] name  : 显示名
  [1] path  : 环境变量形式路径（支持 %LOCALAPPDATA% 等；winapp2 源可含 * 通配符）
  [2] type  : "dir" | "file" | "glob"
  [3] bool  : requiresAdmin（或 default_checked，视来源）
  [4] meta  : 描述/溯源元数据
  [5] bool? : advanced 标记（或 enabled，视来源）
```

`cdisk_cleaner_config.json` 为双重编码 v2：`{"order": ["[\"[元组]\", 状态int]", ...]}`。

## 7 步合并管线（确定性、可复现）

1. **发现**：递归枚举 mergeSources + externalMergeSources 下 `.json/.ini/.txt/.yaml/.yml`
2. **解析**：按格式解析为统一元组；失败条目进 `unparsed`（fail-soft）
3. **规范化**：绝对路径回写环境变量形式（最长前缀优先，大小写不敏感；通配符保留）
4. **去重**：以规范化路径为主键；冲突取**更保守 tier**；源分类决定 enable 覆盖权
5. **分级**：关键词+类型自动 tier（见下）；**不确定→dangerous+disabled**（红线）
6. **归并**：builtin（77 条，永不覆盖）→ origin 标注 `builtin|c_cleaner_plus|merged`
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
强制降级 dangerous+disabled 并打 `[guardrail:protected-path]` 标记（当前源中 98 条）。

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

分类评级索引见 [rules-catalog.md](rules-catalog.md)；逐条明细见 [rulesets/](rulesets/)（由 `tools/generate_rules_catalog.py` 从 assets/rules/ 生成，评级与引擎 merge 期 tier 同源）。

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

## 实测规模（本机）

- 发现 40849 条（3 源：assets/rules + 2 外部目录）→ 15404 唯一 → 88 处与 builtin 冲突
- 合并产物 15403 目标（builtin 87 / merged 46 / c_cleaner_plus 其余），id 全唯一、
  重复运行确定性 PASS（id+tier+enabled+signals 四元组一致）
- tier 分布：safe 4796 / caution 2560 / dangerous 8047；默认启用仅 safe 59 + caution 4
- signals 分布：safe-signal 4783 / caution-signal 2549 / danger-signal 1889 / unknown 5435
  （unknown 全部按红线落 dangerous+disabled）/ file-type 614 / program-dir 46
