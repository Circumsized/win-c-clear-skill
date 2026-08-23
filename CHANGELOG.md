# Changelog

本项目遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 与
[语义化版本](https://semver.org/lang/zh-CN/) 规范。

## [1.0.0] - 2026-08-24

### Added

- 面向 AI Agent 的 Windows C 盘清理技能首次发布（扫描 → 解释 → 确认 → 清理 → 汇报 → 复用）。
- 内置 87 个精选白名单目标 + ~15.4k 条社区规则（Winapp2 v260730、BleachBit cleaners、精选社区规则，vendored 自包含）。
- 三档风险分级（safe / caution / dangerous）+ 两段式确认协议。
- 并行扫描引擎（`ParallelScanner.cs`）+ NTFS MFT 直读（`MftScanner.cs`）+ 智能尺寸缓存（mtime + TTL）。
- Restart Manager 锁检测 + 重复文件哈希级联（GPU / CPU 自适应）。
- 引擎级纵深防御：Plan 门禁 / 白名单强制 / 受保护路径黑名单 / 热文件与危险扩展名围栏 / 重解析点围栏 / 审计日志。
- 稳定数据契约 `JSON_SUMMARY`（schemaVersion 1）+ 中文结构化 Markdown 报告。
- 多 Harness 一键安装（Claude Code / codex / DeepSeek / Trae / Cursor）。
- CI 工作流（静态分析 + 语法 + 回归 + 安全套件）与 GitHub Release 打包。

[1.0.0]: https://github.com/Circumsized/win-c-clear-skill/releases/tag/v1.0.0