# References (load on demand)

按需加载的深度参考文档。SKILL.md 只承载工作流与红线；细节在这里下钻。

| 文档 | 何时读 |
|------|--------|
| [rules-and-merging.md](rules-and-merging.md) | 需要理解/升级/调试规则合并（assets/rules 来源、7 步管线、规则集分类、源分类策略） |
| [rules-catalog.md](rules-catalog.md) | 清理规则的**分类评级索引**：11 类规则集规模、tier 分布、引导用户选规则的场景话术。⚠️ 其 tier 评级是独立启发式，**不等于引擎实际分级**，详见该文顶部说明 |
| [rulesets/](rulesets/) | 各分类规则的**逐条评级明细**（general/cn/dev/design/ai/game/media），由 `tools/generate_rules_catalog.py` 生成；同上，评级仅供选集参考，真实分级以 `config/targets.merged.json` 为准 |
| [bleachbit-design.md](bleachbit-design.md) | 需要 BleachBit 系统清理设计对照、新增系统目标（事件日志/Defender/字体缓存等）的原理 |
| [winapp2-adaptation.md](winapp2-adaptation.md) | winapp2.ini 格式、通配符路径语义、社区规则适配细节 |
| [guardrails.md](guardrails.md) | 受保护路径黑名单规格、门禁层级、围栏（Plan 门禁/热文件/扩展名/重解析点）、advisory 目语义 |
| [harness-adaptation.md](harness-adaptation.md) | 在 Claude Code / codex / DeepSeek Harness / 纯 Windows 环境下集成与调优 |
| [windows-api.md](windows-api.md) | Windows API 深度参考：MFT 直读实现细节、Restart Manager、删除 API 层级、VSS/CBS/Storage Sense 全谱 |
| [../SECURITY-AUDIT.md](../SECURITY-AUDIT.md) | 已知缺陷、修复内容、刻意保留的 open items，以及验收命令 |
| [AUDIT-REPORT-20260823.md](AUDIT-REPORT-20260823.md) | 2026-08-23 全量安全审计报告快照（验收结论 + 修复建议，人类读者向） |

规则**数据**（非文档）位于 [../assets/rules/](../assets/rules/)（自包含依赖层，~15.4k 条目标）。

## 扫描白名单 / 黑名单（R5）

- [../config/scan-lists.json](../config/scan-lists.json)：预设**可安全清理目录白名单** + **系统核心区域黑名单** + 四级扫描模式（fast/standard/deep/diagnostic）。
- 引擎 `-PathFilter off|whitelist|blacklist|both` / `-NoWhitelist` / `-NoBlacklist`、`-ScanMode`、`Get-ScanRating` 分级评级。
