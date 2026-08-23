# 游戏平台（game）规则集

> 游戏平台 / 启动器的下载落地缓存、嵌入式浏览器缓存与日志。

> ⚠️ **本表「评级」列不是引擎的实际分级。** 它由 `merge_rules.classify_tier`
> （独立的 Python 关键词启发式）生成，与引擎的 `Get-AutoTier` 双向分歧：例如含
> `User Data` 或 `dxcache` 的路径在此偏严（caution/dangerous），引擎按末段 `cache`
> 判 **safe** 并默认启用；`cookies`/`history` 在此偏松（caution），引擎判 **dangerous**。
> 真实分级与 enabled 状态以 `config/targets.merged.json` 或 `-Mode Scan` 输出为准。

| 名称 | 路径 | 类型 | 评级 | 需管理员 | 说明 |
|------|------|------|------|---------|------|
| Battle.net 日志 | `%PROGRAMDATA%\Battle.net\Agent\Logs` | dir | 🟢 safe (安全) | 是 | Battle.net Agent 日志 |
| Battle.net 缓存 | `%PROGRAMDATA%\Battle.net\Agent\Cache` | dir | 🟢 safe (安全) | 是 | Battle.net Agent 缓存 |
| CurseForge GPU 缓存 | `%APPDATA%\CurseForge\GPUCache` | dir | 🟢 safe (安全) |  | CurseForge 图形渲染缓存 |
| CurseForge 代码缓存 | `%APPDATA%\CurseForge\Code Cache` | dir | 🟢 safe (安全) |  | CurseForge 脚本缓存 |
| CurseForge 日志 | `%APPDATA%\CurseForge\Logs` | dir | 🟢 safe (安全) |  | CurseForge 运行日志 |
| CurseForge 缓存 | `%APPDATA%\CurseForge\Cache` | dir | 🟢 safe (安全) |  | CurseForge 普通缓存 |
| EA app 日志 | `%LOCALAPPDATA%\Electronic Arts\EA Desktop\Logs` | dir | 🟢 safe (安全) |  | EA app 运行日志 |
| EA app 缓存 | `%LOCALAPPDATA%\Electronic Arts\EA Desktop\Cache` | dir | 🟢 safe (安全) |  | EA app 普通缓存 |
| Epic 启动器日志 | `%LOCALAPPDATA%\EpicGamesLauncher\Saved\Logs` | dir | 🟢 safe (安全) |  | Epic Games Launcher 运行日志 |
| Epic 启动器网页缓存 | `%LOCALAPPDATA%\EpicGamesLauncher\Saved\webcache` | dir | 🟢 safe (安全) |  | Epic Games Launcher 内置网页缓存 |
| Epic 崩溃报告 | `%LOCALAPPDATA%\EpicGamesLauncher\Saved\Crashes` | dir | 🟢 safe (安全) |  | Epic Games Launcher 崩溃报告 |
| GOG Galaxy 日志 | `%PROGRAMDATA%\GOG.com\Galaxy\logs` | dir | 🟢 safe (安全) | 是 | GOG Galaxy 运行日志 |
| Heroic GPU 缓存 | `%APPDATA%\heroic\GPUCache` | dir | 🟢 safe (安全) |  | Heroic Games Launcher 图形渲染缓存 |
| Heroic 代码缓存 | `%APPDATA%\heroic\Code Cache` | dir | 🟢 safe (安全) |  | Heroic Games Launcher 前端脚本缓存 |
| Heroic 日志 | `%APPDATA%\heroic\logs` | dir | 🟢 safe (安全) |  | Heroic Games Launcher 运行日志 |
| Heroic 缓存 | `%APPDATA%\heroic\Cache` | dir | 🟢 safe (安全) |  | Heroic Games Launcher 普通缓存 |
| HoYoPlay 日志 | `%APPDATA%\Cognosphere\HYP\logs` | dir | 🟢 safe (安全) |  | HoYoPlay 启动器日志 |
| HoYoPlay 网页缓存 | `%APPDATA%\Cognosphere\HYP\webCaches` | dir | 🟢 safe (安全) |  | HoYoPlay 内置网页缓存 |
| Minecraft 启动器日志 | `%APPDATA%\.minecraft\logs` | dir | 🟢 safe (安全) |  | Minecraft 启动器与游戏日志 |
| Minecraft 崩溃报告 | `%APPDATA%\.minecraft\crash-reports` | dir | 🟢 safe (安全) |  | Minecraft 崩溃报告 |
| Overwolf 日志 | `%LOCALAPPDATA%\Overwolf\Log` | dir | 🟢 safe (安全) |  | Overwolf 日志 |
| Overwolf 缓存 | `%LOCALAPPDATA%\Overwolf\Cache` | dir | 🟢 safe (安全) |  | Overwolf 缓存 |
| Playnite 日志 | `%APPDATA%\Playnite\Logs` | dir | 🟢 safe (安全) |  | Playnite 运行日志 |
| PP 平台日志 | `%APPDATA%\Perfect World\PWP\logs` | dir | 🟢 safe (安全) |  | 完美平台日志 |
| Riot Client GPU 缓存 | `%LOCALAPPDATA%\Riot Games\Riot Client\GPUCache` | dir | 🟢 safe (安全) |  | Riot Client 图形渲染缓存 |
| Riot Client Service Worker | `%LOCALAPPDATA%\Riot Games\Riot Client\Service Worker\CacheStorage` | dir | 🟢 safe (安全) |  | Riot Client Service Worker 缓存 |
| Riot Client 日志 | `%LOCALAPPDATA%\Riot Games\Riot Client\Logs` | dir | 🟢 safe (安全) |  | Riot Client 运行日志 |
| Riot Client 缓存 | `%LOCALAPPDATA%\Riot Games\Riot Client\Cache` | dir | 🟢 safe (安全) |  | Riot Client 普通缓存 |
| Roblox 日志 | `%LOCALAPPDATA%\Roblox\logs` | dir | 🟢 safe (安全) |  | Roblox 客户端日志 |
| Steam 崩溃转储 | `%LOCALAPPDATA%\Steam\dumps` | dir | 🟢 safe (安全) |  | Steam 崩溃转储与异常信息 |
| Steam 日志 | `%LOCALAPPDATA%\Steam\logs` | dir | 🟢 safe (安全) |  | Steam 客户端日志 |
| Ubisoft Connect 日志 | `%LOCALAPPDATA%\Ubisoft Game Launcher\logs` | dir | 🟢 safe (安全) |  | Ubisoft Connect 运行日志 |
| Ubisoft Connect 缓存 | `%LOCALAPPDATA%\Ubisoft Game Launcher\cache` | dir | 🟢 safe (安全) |  | Ubisoft Connect 普通缓存 |
| Vortex GPU 缓存 | `%APPDATA%\Vortex\GPUCache` | dir | 🟢 safe (安全) |  | Nexus Mods Vortex 图形渲染缓存 |
| Vortex 缓存 | `%APPDATA%\Vortex\Cache` | dir | 🟢 safe (安全) |  | Nexus Mods Vortex 普通缓存 |
| WeGame 日志 | `%APPDATA%\Tencent\WeGame\logs` | dir | 🟢 safe (安全) |  | WeGame 客户端日志 |
| WeGame 缓存 | `%APPDATA%\Tencent\WeGame\Cache` | dir | 🟢 safe (安全) |  | WeGame 普通缓存 |
| 战网崩溃日志 | `%PROGRAMDATA%\Battle.net\Agent\errors` | dir | 🟢 safe (安全) | 是 | Battle.net Agent 错误日志 |

## 评级分布
| 评级 | 数量 |
|------|------|
| 🟢 safe（安全） | 38 |
| 🟡 caution（谨慎） | 0 |
| 🔴 dangerous（危险） | 0 |

共 38 条规则。引擎的实际默认启用规则是「引擎判定为 safe 且未被护栏降级」，
与本表评级不一定一致（见文首警告）；caution/dangerous 一律需 `-ConfirmIds` 显式确认。
