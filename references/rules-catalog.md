# 规则目录与分类评级（rules-catalog.md）

本文件是 skill 清理规则集的**分类评级索引**，用于引导用户按需选择规则集。
明细见 [references/rulesets/](rulesets/) 下各分类文档；评级语义与引擎合并管线同源
（`tools/generate_rules_catalog.py` 复用 `merge_rules.classify_tier`），可复现。

## 分类总览

| RuleSets 参数 | 分类 | 规则数 | safe | caution | dangerous | 明细文档 |
|--------------|------|--------|------|---------|-----------|---------|
| `general` | 通用规则 | 110 | 105 | 1 | 4 | [rulesets/general.md](rulesets/general.md) |
| `cn` | 国产软件 | 20 | 20 | 0 | 0 | [rulesets/cn.md](rulesets/cn.md) |
| `dev` | 开发工具 | 55 | 53 | 0 | 2 | [rulesets/dev.md](rulesets/dev.md) |
| `design` | 设计建模 | 12 | 12 | 0 | 0 | [rulesets/design.md](rulesets/design.md) |
| `ai` | AI 软件 | 63 | 57 | 0 | 6 | [rulesets/ai.md](rulesets/ai.md) |
| `game` | 游戏平台 | 38 | 38 | 0 | 0 | [rulesets/game.md](rulesets/game.md) |
| `media` | 影音创作 | 38 | 34 | 1 | 3 | [rulesets/media.md](rulesets/media.md) |
| `community` | Winapp2 社区规则（MoscaDotTo，opt-in） | 14117 | 6726 | 1737 | 5654 | （体量过大，仅统计） |
| `community` | BleachBit cleaners（仅 Windows 路径，opt-in） | 986 | 366 | 317 | 303 | （体量过大，仅统计） |
| `community` | c_cleaner_plus 自定义规则导出（opt-in） | 4229 | 2435 | 396 | 1398 | （体量过大，仅统计） |
| `system` | c_cleaner_plus 应用勾选状态（含系统规则，双重编码 v2，opt-in） | 4265 | 2457 | 406 | 1402 | （体量过大，仅统计） |

**curated 规则合计 336 条**；另有社区/系统大源见上表（默认 opt-in，不逐条列出）。

## 引导选择（skill 执行第 1 步话术）

默认 `-RuleSets minimal`（仅内置白名单，最安全）。如需扩展到某类应用，按用户已装软件
选择，多选用逗号，例如 `-RuleSets cn,dev,ai`。

| 用户场景 | 推荐 RuleSets |
|---------|--------------|
| 只想安全清理、不确定装了什么 | `minimal` |
| 深度清理开发环境缓存 | `minimal,dev` |
| 国内办公电脑（WPS/微信/钉钉/飞书等） | `minimal,cn` |
| 设计 / 3D / CAD 工作站 | `minimal,design` |
| 本地跑大模型 / AI 客户端 | `minimal,ai` |
| 游戏玩家（Steam/Epic/Riot 等） | `minimal,game` |
| 剪辑 / 直播 / 创作 | `minimal,media` |
| 全量（含社区万级规则，慎用） | `all` |

> 提示：caution/dangerous 规则默认禁用，清理前需 `-ConfirmIds` 逐项确认；
> `system`/`community` 类规则默认 opt-in，仅当用户明确需要时才加载。
