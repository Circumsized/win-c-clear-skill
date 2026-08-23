# 通用规则（general）规则集

> 跨应用的通用临时/缓存/日志目录，覆盖面广、默认 opt-in，需按机况勾选。

> ⚠️ **本表「评级」列不是引擎的实际分级。** 它由 `merge_rules.classify_tier`
> （独立的 Python 关键词启发式）生成，与引擎的 `Get-AutoTier` 双向分歧：例如含
> `User Data` 或 `dxcache` 的路径在此偏严（caution/dangerous），引擎按末段 `cache`
> 判 **safe** 并默认启用；`cookies`/`history` 在此偏松（caution），引擎判 **dangerous**。
> 真实分级与 enabled 状态以 `config/targets.merged.json` 或 `-Mode Scan` 输出为准。

| 名称 | 路径 | 类型 | 评级 | 需管理员 | 说明 |
|------|------|------|------|---------|------|
| Adobe Installer 日志 | `%TEMP%\AdobeInstallers` | dir | 🟡 caution (谨慎) |  | Adobe 安装器与更新器临时日志 |
| Adobe 峰值文件 | `%APPDATA%\Adobe\Common\Peak Files` | dir | 🔴 dangerous (危险) |  | 音频峰值与波形缓存 |
| Brave Crashpad 报告 | `%LOCALAPPDATA%\BraveSoftware\Brave-Browser\User Data\Crashpad\reports` | dir | 🔴 dangerous (危险) |  | Brave 崩溃报告 |
| Chrome Crashpad 报告 | `%LOCALAPPDATA%\Google\Chrome\User Data\Crashpad\reports` | dir | 🔴 dangerous (危险) |  | Google Chrome 崩溃报告 |
| Edge Crashpad 报告 | `%LOCALAPPDATA%\Microsoft\Edge\User Data\Crashpad\reports` | dir | 🔴 dangerous (危险) |  | Microsoft Edge 崩溃报告 |
| Adobe CEP 日志 | `%APPDATA%\Adobe\CEP\logs` | dir | 🟢 safe (安全) |  | Adobe CEP 扩展日志 |
| Adobe UXP 日志(本地) | `%LOCALAPPDATA%\Adobe\UXP\Logs` | dir | 🟢 safe (安全) |  | Adobe UXP 插件本地日志 |
| Adobe UXP 日志(漫游) | `%APPDATA%\Adobe\UXP\Logs` | dir | 🟢 safe (安全) |  | Adobe UXP 插件漫游日志 |
| Adobe 公共日志 | `%APPDATA%\Adobe\Common\Logs` | dir | 🟢 safe (安全) |  | Adobe Common 公共日志 |
| Adobe 媒体缓存 | `%APPDATA%\Adobe\Common\Media Cache` | dir | 🟢 safe (安全) |  | Premiere Pro / After Effects 媒体缓存 |
| Adobe 媒体缓存文件 | `%APPDATA%\Adobe\Common\Media Cache Files` | dir | 🟢 safe (安全) |  | Premiere Pro / After Effects 媒体缓存文件 |
| Adobe 崩溃转储 | `%LOCALAPPDATA%\Adobe\CrashDumps` | dir | 🟢 safe (安全) |  | Adobe 应用崩溃转储 |
| Battle.net Agent 日志 | `%PROGRAMDATA%\Battle.net\Agent\Logs` | dir | 🟢 safe (安全) | 是 | Battle.net 更新代理日志 |
| Brave GPU 缓存 | `%LOCALAPPDATA%\BraveSoftware\Brave-Browser\User Data\Default\GPUCache` | dir | 🟢 safe (安全) |  | Brave 图形渲染缓存 |
| Brave Service Worker | `%LOCALAPPDATA%\BraveSoftware\Brave-Browser\User Data\Default\Service Worker\CacheStorage` | dir | 🟢 safe (安全) |  | Brave Service Worker 缓存 |
| Brave 代码缓存 | `%LOCALAPPDATA%\BraveSoftware\Brave-Browser\User Data\Default\Code Cache` | dir | 🟢 safe (安全) |  | Brave 前端脚本缓存 |
| Brave 缓存 | `%LOCALAPPDATA%\BraveSoftware\Brave-Browser\User Data\Default\Cache` | dir | 🟢 safe (安全) |  | Brave 普通缓存 |
| Bridge 日志 | `%APPDATA%\Adobe\Bridge\logs` | dir | 🟢 safe (安全) |  | Adobe Bridge 运行日志 |
| Bridge 缩略图缓存 | `%APPDATA%\Adobe\Bridge Cache` | dir | 🟢 safe (安全) |  | Adobe Bridge 缩略图与索引缓存 |
| Camera Raw 缓存 | `%APPDATA%\Adobe\CameraRaw\Cache` | dir | 🟢 safe (安全) |  | Adobe Camera Raw 缓存 |
| Chrome GPU 缓存 | `%LOCALAPPDATA%\Google\Chrome\User Data\Default\GPUCache` | dir | 🟢 safe (安全) |  | Google Chrome 图形渲染缓存 |
| Chrome Service Worker | `%LOCALAPPDATA%\Google\Chrome\User Data\Default\Service Worker\CacheStorage` | dir | 🟢 safe (安全) |  | Google Chrome Service Worker 缓存 |
| Creative Cloud ACC 日志 | `%LOCALAPPDATA%\Adobe\Creative Cloud\ACC\logs` | dir | 🟢 safe (安全) |  | Creative Cloud ACC 组件日志 |
| Creative Cloud 临时文件 | `%LOCALAPPDATA%\Adobe\Creative Cloud\ACC\Temp` | dir | 🟢 safe (安全) |  | Creative Cloud 临时文件 |
| Creative Cloud 日志 | `%LOCALAPPDATA%\Adobe\Creative Cloud\Logs` | dir | 🟢 safe (安全) |  | Adobe Creative Cloud 运行日志 |
| Cursor GPU 缓存 | `%APPDATA%\Cursor\GPUCache` | dir | 🟢 safe (安全) |  | Cursor 图形渲染缓存 |
| Cursor Service Worker | `%APPDATA%\Cursor\Service Worker\CacheStorage` | dir | 🟢 safe (安全) |  | Cursor Service Worker 缓存 |
| Cursor 日志 | `%APPDATA%\Cursor\logs` | dir | 🟢 safe (安全) |  | Cursor 运行日志 |
| Cursor 缓存 | `%APPDATA%\Cursor\Cache` | dir | 🟢 safe (安全) |  | Cursor 普通缓存 |
| Cursor 编译缓存 | `%APPDATA%\Cursor\CachedData` | dir | 🟢 safe (安全) |  | Cursor 扩展与脚本缓存 |
| Discord GPU 缓存 | `%APPDATA%\discord\GPUCache` | dir | 🟢 safe (安全) |  | Discord 图形渲染缓存 |
| Discord Service Worker | `%APPDATA%\discord\Service Worker\CacheStorage` | dir | 🟢 safe (安全) |  | Discord Service Worker 缓存 |
| Discord 代码缓存 | `%APPDATA%\discord\Code Cache` | dir | 🟢 safe (安全) |  | Discord 前端脚本缓存 |
| Discord 缓存 | `%APPDATA%\discord\Cache` | dir | 🟢 safe (安全) |  | Discord 普通缓存 |
| Docker Desktop 崩溃记录 | `%LOCALAPPDATA%\Docker\Crashpad` | dir | 🟢 safe (安全) |  | Docker Desktop 崩溃转储 |
| Docker Desktop 日志 | `%LOCALAPPDATA%\Docker\log` | dir | 🟢 safe (安全) |  | Docker Desktop 日志目录 |
| EA app 日志 | `%LOCALAPPDATA%\Electronic Arts\EA Desktop\Logs` | dir | 🟢 safe (安全) |  | EA app 运行日志 |
| Edge GPU 缓存 | `%LOCALAPPDATA%\Microsoft\Edge\User Data\Default\GPUCache` | dir | 🟢 safe (安全) |  | Microsoft Edge 图形渲染缓存 |
| Edge Service Worker | `%LOCALAPPDATA%\Microsoft\Edge\User Data\Default\Service Worker\CacheStorage` | dir | 🟢 safe (安全) |  | Microsoft Edge Service Worker 缓存 |
| Epic 启动器日志 | `%LOCALAPPDATA%\EpicGamesLauncher\Saved\Logs` | dir | 🟢 safe (安全) |  | Epic Games Launcher 日志 |
| Epic 启动器网页缓存 | `%LOCALAPPDATA%\EpicGamesLauncher\Saved\webcache` | dir | 🟢 safe (安全) |  | Epic Games Launcher 内置网页缓存 |
| JetBrains Toolbox 日志 | `%LOCALAPPDATA%\JetBrains\Toolbox\logs` | dir | 🟢 safe (安全) |  | JetBrains Toolbox 日志 |
| JetBrains Toolbox 缓存 | `%LOCALAPPDATA%\JetBrains\Toolbox\cache` | dir | 🟢 safe (安全) |  | JetBrains Toolbox 下载与安装缓存 |
| Notion GPU 缓存 | `%APPDATA%\Notion\GPUCache` | dir | 🟢 safe (安全) |  | Notion 图形渲染缓存 |
| Notion Service Worker | `%APPDATA%\Notion\Service Worker\CacheStorage` | dir | 🟢 safe (安全) |  | Notion Service Worker 缓存 |
| Notion 代码缓存 | `%APPDATA%\Notion\Code Cache` | dir | 🟢 safe (安全) |  | Notion 前端脚本缓存 |
| Notion 缓存 | `%APPDATA%\Notion\Cache` | dir | 🟢 safe (安全) |  | Notion 普通缓存 |
| OBS Studio 崩溃记录 | `%APPDATA%\obs-studio\crashes` | dir | 🟢 safe (安全) |  | OBS Studio 崩溃转储与报告 |
| OBS Studio 日志 | `%APPDATA%\obs-studio\logs` | dir | 🟢 safe (安全) |  | OBS Studio 运行日志 |
| OBS 浏览器缓存 | `%APPDATA%\obs-studio\plugin_config\obs-browser\Cache` | dir | 🟢 safe (安全) |  | OBS 浏览器源缓存 |
| Obsidian GPU 缓存 | `%APPDATA%\obsidian\GPUCache` | dir | 🟢 safe (安全) |  | Obsidian 图形渲染缓存 |
| Obsidian 代码缓存 | `%APPDATA%\obsidian\Code Cache` | dir | 🟢 safe (安全) |  | Obsidian 前端脚本缓存 |
| Obsidian 缓存 | `%APPDATA%\obsidian\Cache` | dir | 🟢 safe (安全) |  | Obsidian 普通缓存 |
| Opera GPU 缓存 | `%APPDATA%\Opera Software\Opera Stable\GPUCache` | dir | 🟢 safe (安全) |  | Opera 图形渲染缓存 |
| Opera GX GPU 缓存 | `%APPDATA%\Opera Software\Opera GX Stable\GPUCache` | dir | 🟢 safe (安全) |  | Opera GX 图形渲染缓存 |
| Opera GX 缓存 | `%APPDATA%\Opera Software\Opera GX Stable\Cache` | dir | 🟢 safe (安全) |  | Opera GX 普通缓存 |
| Opera 代码缓存 | `%APPDATA%\Opera Software\Opera Stable\Code Cache` | dir | 🟢 safe (安全) |  | Opera 前端脚本缓存 |
| Opera 缓存 | `%APPDATA%\Opera Software\Opera Stable\Cache` | dir | 🟢 safe (安全) |  | Opera 普通缓存 |
| Postman GPU 缓存 | `%APPDATA%\Postman\GPUCache` | dir | 🟢 safe (安全) |  | Postman 图形渲染缓存 |
| Postman 代码缓存 | `%APPDATA%\Postman\Code Cache` | dir | 🟢 safe (安全) |  | Postman 前端脚本缓存 |
| Postman 日志 | `%APPDATA%\Postman\logs` | dir | 🟢 safe (安全) |  | Postman 运行日志 |
| QQ 日志 | `%APPDATA%\Tencent\QQ\logs` | dir | 🟢 safe (安全) |  | QQ 客户端日志 |
| Riot Client GPU 缓存 | `%LOCALAPPDATA%\Riot Games\Riot Client\GPUCache` | dir | 🟢 safe (安全) |  | Riot Client 图形渲染缓存 |
| Riot Client 日志 | `%LOCALAPPDATA%\Riot Games\Riot Client\Logs` | dir | 🟢 safe (安全) |  | Riot Client 运行日志 |
| Signal GPU 缓存 | `%APPDATA%\Signal\GPUCache` | dir | 🟢 safe (安全) |  | Signal 图形渲染缓存 |
| Signal Service Worker | `%APPDATA%\Signal\Service Worker\CacheStorage` | dir | 🟢 safe (安全) |  | Signal Service Worker 缓存 |
| Signal 代码缓存 | `%APPDATA%\Signal\Code Cache` | dir | 🟢 safe (安全) |  | Signal 前端脚本缓存 |
| Signal 日志 | `%APPDATA%\Signal\logs` | dir | 🟢 safe (安全) |  | Signal 运行日志 |
| Signal 缓存 | `%APPDATA%\Signal\Cache` | dir | 🟢 safe (安全) |  | Signal 普通缓存 |
| Skype 日志 | `%APPDATA%\Microsoft\Skype for Desktop\logs` | dir | 🟢 safe (安全) |  | Skype for Desktop 运行日志 |
| Slack GPU 缓存 | `%APPDATA%\Slack\GPUCache` | dir | 🟢 safe (安全) |  | Slack 图形渲染缓存 |
| Slack Service Worker | `%APPDATA%\Slack\Service Worker\CacheStorage` | dir | 🟢 safe (安全) |  | Slack Service Worker 缓存 |
| Slack 代码缓存 | `%APPDATA%\Slack\Code Cache` | dir | 🟢 safe (安全) |  | Slack 前端脚本缓存 |
| Slack 日志 | `%APPDATA%\Slack\logs` | dir | 🟢 safe (安全) |  | Slack 运行日志 |
| Slack 缓存 | `%APPDATA%\Slack\Cache` | dir | 🟢 safe (安全) |  | Slack 普通缓存 |
| Steam 网页 GPU 缓存 | `%LOCALAPPDATA%\Steam\htmlcache\GPUCache` | dir | 🟢 safe (安全) |  | Steam 图形渲染缓存 |
| Steam 网页代码缓存 | `%LOCALAPPDATA%\Steam\htmlcache\Code Cache` | dir | 🟢 safe (安全) |  | Steam 前端脚本缓存 |
| Steam 网页缓存 | `%LOCALAPPDATA%\Steam\htmlcache\Cache` | dir | 🟢 safe (安全) |  | Steam 内置网页缓存 |
| Teams GPU 缓存 | `%APPDATA%\Microsoft\Teams\GPUCache` | dir | 🟢 safe (安全) |  | Microsoft Teams 图形渲染缓存 |
| Teams Service Worker | `%APPDATA%\Microsoft\Teams\Service Worker\CacheStorage` | dir | 🟢 safe (安全) |  | Microsoft Teams Service Worker 缓存 |
| Teams 代码缓存 | `%APPDATA%\Microsoft\Teams\Code Cache` | dir | 🟢 safe (安全) |  | Microsoft Teams 前端脚本缓存 |
| Teams 日志 | `%APPDATA%\Microsoft\Teams\logs` | dir | 🟢 safe (安全) |  | Microsoft Teams 运行日志 |
| Teams 缓存 | `%APPDATA%\Microsoft\Teams\Cache` | dir | 🟢 safe (安全) |  | Microsoft Teams 普通缓存 |
| Telegram Desktop GPU 缓存 | `%APPDATA%\Telegram Desktop\GPUCache` | dir | 🟢 safe (安全) |  | Telegram Desktop 图形渲染缓存 |
| Telegram Desktop 日志 | `%APPDATA%\Telegram Desktop\tdata\logs` | dir | 🟢 safe (安全) |  | Telegram Desktop 运行日志 |
| TIM 日志 | `%APPDATA%\Tencent\TIM\logs` | dir | 🟢 safe (安全) |  | TIM 客户端日志 |
| Ubisoft Connect 缓存 | `%LOCALAPPDATA%\Ubisoft Game Launcher\cache` | dir | 🟢 safe (安全) |  | Ubisoft Connect 缓存 |
| Vivaldi GPU 缓存 | `%LOCALAPPDATA%\Vivaldi\User Data\Default\GPUCache` | dir | 🟢 safe (安全) |  | Vivaldi 图形渲染缓存 |
| Vivaldi Service Worker | `%LOCALAPPDATA%\Vivaldi\User Data\Default\Service Worker\CacheStorage` | dir | 🟢 safe (安全) |  | Vivaldi Service Worker 缓存 |
| Vivaldi 代码缓存 | `%LOCALAPPDATA%\Vivaldi\User Data\Default\Code Cache` | dir | 🟢 safe (安全) |  | Vivaldi 前端脚本缓存 |
| Vivaldi 缓存 | `%LOCALAPPDATA%\Vivaldi\User Data\Default\Cache` | dir | 🟢 safe (安全) |  | Vivaldi 普通缓存 |
| VS Code GPU 缓存 | `%APPDATA%\Code\GPUCache` | dir | 🟢 safe (安全) |  | Visual Studio Code 图形渲染缓存 |
| VS Code Service Worker | `%APPDATA%\Code\Service Worker\CacheStorage` | dir | 🟢 safe (安全) |  | Visual Studio Code Service Worker 缓存 |
| VS Code 日志 | `%APPDATA%\Code\logs` | dir | 🟢 safe (安全) |  | Visual Studio Code 运行日志 |
| VS Code 缓存 | `%APPDATA%\Code\Cache` | dir | 🟢 safe (安全) |  | Visual Studio Code 普通缓存 |
| VS Code 编译缓存 | `%APPDATA%\Code\CachedData` | dir | 🟢 safe (安全) |  | Visual Studio Code 扩展与脚本缓存 |
| WhatsApp GPU 缓存 | `%APPDATA%\WhatsApp\GPUCache` | dir | 🟢 safe (安全) |  | WhatsApp Desktop 图形渲染缓存 |
| WhatsApp Service Worker | `%APPDATA%\WhatsApp\Service Worker\CacheStorage` | dir | 🟢 safe (安全) |  | WhatsApp Desktop Service Worker 缓存 |
| WhatsApp 代码缓存 | `%APPDATA%\WhatsApp\Code Cache` | dir | 🟢 safe (安全) |  | WhatsApp Desktop 前端脚本缓存 |
| WhatsApp 日志 | `%APPDATA%\WhatsApp\logs` | dir | 🟢 safe (安全) |  | WhatsApp Desktop 运行日志 |
| WhatsApp 缓存 | `%APPDATA%\WhatsApp\Cache` | dir | 🟢 safe (安全) |  | WhatsApp Desktop 普通缓存 |
| Zoom 日志 | `%APPDATA%\Zoom\logs` | dir | 🟢 safe (安全) |  | Zoom 运行日志 |
| 应用崩溃转储 | `%LOCALAPPDATA%\CrashDumps` | dir | 🟢 safe (安全) |  | Windows 为应用生成的用户态崩溃转储 |
| 微信日志 | `%APPDATA%\Tencent\WeChat\XPlugin\Logs` | dir | 🟢 safe (安全) |  | 微信插件与运行日志 |
| 钉钉 GPU 缓存 | `%APPDATA%\DingTalk\GPUCache` | dir | 🟢 safe (安全) |  | 钉钉图形渲染缓存 |
| 钉钉代码缓存 | `%APPDATA%\DingTalk\Code Cache` | dir | 🟢 safe (安全) |  | 钉钉前端脚本缓存 |
| 钉钉缓存 | `%APPDATA%\DingTalk\Cache` | dir | 🟢 safe (安全) |  | 钉钉普通缓存 |
| 飞书 GPU 缓存 | `%APPDATA%\LarkShell\GPUCache` | dir | 🟢 safe (安全) |  | 飞书图形渲染缓存 |
| 飞书代码缓存 | `%APPDATA%\LarkShell\Code Cache` | dir | 🟢 safe (安全) |  | 飞书前端脚本缓存 |
| 飞书缓存 | `%APPDATA%\LarkShell\Cache` | dir | 🟢 safe (安全) |  | 飞书普通缓存 |

## 评级分布
| 评级 | 数量 |
|------|------|
| 🟢 safe（安全） | 105 |
| 🟡 caution（谨慎） | 1 |
| 🔴 dangerous（危险） | 4 |

共 110 条规则。引擎的实际默认启用规则是「引擎判定为 safe 且未被护栏降级」，
与本表评级不一定一致（见文首警告）；caution/dangerous 一律需 `-ConfirmIds` 显式确认。
