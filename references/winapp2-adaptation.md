# Winapp2.ini 适配说明（winapp2-adaptation.md）

[Winapp2.ini](https://github.com/MoscaDotTo/Winapp2)（CC-BY-SA-4.0，当前 v260730，4067 节）
是 CCleaner 社区清理规则的事实标准。本 skill 通过 `assets/rules/winapp2_latest.json`（14117 条）
将其作为 **community 源（opt-in）** 纳入。

## INI 格式 → 统一元组

```ini
[Google Chrome Cache *]              ; 节名 = 规则名
LangSecRef=3029                      ; 分类（Internet/Browsers/Utilities/System/Multimedia...）
DetectFile=%LocalAppData%\Google\Chrome*   ; 应用存在性探测
FileKey1=%LocalAppData%\Google\Chrome*\User Data\*\Cache|*|RECURSE
;      路径（可含 *）                    |文件通配|RECURSE/REMOVESELF 标志
```

解析映射：
- 每个 FileKey 展开为一条元组 `[win2 | <节名>, <路径>, dir|file|glob, False, 溯源元数据, True]`
- `DetectFile` 与 `LangSecRef` 记入 meta（溯源与分类提示）
- `|*` 文件通配 → type=glob；`REMOVESELF`（删目录自身）→ type=dir；默认 dir（清内容留目录）

## 通配符路径语义（本 skill 的关键适配）

winapp2 路径可含多级 `*`（如 `%LOCALAPPDATA%\Google\Chrome*\User Data\*\Cache`）。本 skill 引擎：

1. **存在性快筛**：截取第一个通配符前的最长目录前缀做 O(1) `Directory.Exists`——
   应用未装时 14k 条规则秒级过滤（实测 14562 条 missing 仅耗数秒）
2. **通配符解析**：前缀存在时用 `Get-Item -Path <pattern>`（PowerShell 通配符展开）解析为具体路径
3. **测量/清理按具体路径执行**：解析后的每个具体目录独立测量与清理；clean 时重新解析（新鲜度）
4. **守卫对具体路径生效**：若通配符解析结果落入受保护路径（如 System32），清理时被黑名单拦截

## 分类（LangSecRef）与 tier 的关系

tier 由**路径语义**自动判定（cache→safe、cookies/history→dangerous），不信任 INI 的分类字段。
浏览器敏感数据（Cookies/密码/自动填充/历史）路径含 cookies/history/password 关键词 → 自动 dangerous+disabled，
与社区"默认不勾选敏感项"的惯例一致。

## 升级与修剪

- 升级：`python tools/fetch_rules.py`（拉取 master Winapp2.ini → 解析 → 覆盖 winapp2_latest.json）
- 修剪（可选）：若 14k 条扫描噪声大，可只保留 DetectFile 命中的节——当前靠引擎快筛实现同等效果，
  无需预修剪
- `tools/_cache/obsolete_report.json`：对比新旧版本的下线条目审计
