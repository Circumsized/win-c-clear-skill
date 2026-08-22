# 影音创作（media）规则集

> 影音剪辑 / 直播 / 创作类软件的日志、崩溃转储与预览缓存。

| 名称 | 路径 | 类型 | 评级 | 需管理员 | 说明 |
|------|------|------|------|---------|------|
| Adobe Installer 日志 | `%TEMP%\AdobeInstallers` | dir | 🟡 caution (谨慎) |  | Adobe 安装器与更新器临时日志 |
| Adobe 峰值文件 | `%APPDATA%\Adobe\Common\Peak Files` | dir | 🔴 dangerous (危险) |  | 音频峰值与波形缓存 |
| CapCut Crashpad 报告 | `%LOCALAPPDATA%\CapCut\User Data\Crashpad\reports` | dir | 🔴 dangerous (危险) |  | CapCut 崩溃报告 |
| 剪映专业版 Crashpad 报告 | `%LOCALAPPDATA%\JianyingPro\User Data\Crashpad\reports` | dir | 🔴 dangerous (危险) |  | 剪映专业版崩溃报告 |
| Adobe CEP 日志 | `%APPDATA%\Adobe\CEP\logs` | dir | 🟢 safe (安全) |  | Adobe CEP 扩展日志 |
| Adobe Lightroom 日志 | `%APPDATA%\Adobe\Lightroom\Logs` | dir | 🟢 safe (安全) |  | Adobe Lightroom 运行日志 |
| Adobe UXP 日志(本地) | `%LOCALAPPDATA%\Adobe\UXP\Logs` | dir | 🟢 safe (安全) |  | Adobe UXP 插件本地日志 |
| Adobe UXP 日志(漫游) | `%APPDATA%\Adobe\UXP\Logs` | dir | 🟢 safe (安全) |  | Adobe UXP 插件漫游日志 |
| Adobe XD 日志 | `%APPDATA%\Adobe\Adobe XD\logs` | dir | 🟢 safe (安全) |  | Adobe XD 运行日志 |
| Adobe 公共日志 | `%APPDATA%\Adobe\Common\Logs` | dir | 🟢 safe (安全) |  | Adobe Common 公共日志 |
| Adobe 媒体缓存 | `%APPDATA%\Adobe\Common\Media Cache` | dir | 🟢 safe (安全) |  | Premiere Pro / After Effects 媒体缓存 |
| Adobe 媒体缓存文件 | `%APPDATA%\Adobe\Common\Media Cache Files` | dir | 🟢 safe (安全) |  | Premiere Pro / After Effects 媒体缓存文件 |
| Adobe 崩溃转储 | `%LOCALAPPDATA%\Adobe\CrashDumps` | dir | 🟢 safe (安全) |  | Adobe 应用崩溃转储 |
| Bridge 日志 | `%APPDATA%\Adobe\Bridge\logs` | dir | 🟢 safe (安全) |  | Adobe Bridge 运行日志 |
| Bridge 缩略图缓存 | `%APPDATA%\Adobe\Bridge Cache` | dir | 🟢 safe (安全) |  | Adobe Bridge 缩略图与索引缓存 |
| Camera Raw 缓存 | `%APPDATA%\Adobe\CameraRaw\Cache` | dir | 🟢 safe (安全) |  | Adobe Camera Raw 缓存 |
| CapCut GPU 缓存 | `%LOCALAPPDATA%\CapCut\User Data\GPUCache` | dir | 🟢 safe (安全) |  | CapCut 图形渲染缓存 |
| CapCut Service Worker | `%LOCALAPPDATA%\CapCut\User Data\Service Worker\CacheStorage` | dir | 🟢 safe (安全) |  | CapCut Service Worker 缓存 |
| CapCut 代码缓存 | `%LOCALAPPDATA%\CapCut\User Data\Code Cache` | dir | 🟢 safe (安全) |  | CapCut 前端脚本缓存 |
| CapCut 日志 | `%LOCALAPPDATA%\CapCut\User Data\logs` | dir | 🟢 safe (安全) |  | CapCut 运行日志 |
| CapCut 缓存 | `%LOCALAPPDATA%\CapCut\User Data\Cache` | dir | 🟢 safe (安全) |  | CapCut 普通缓存 |
| Creative Cloud ACC 日志 | `%LOCALAPPDATA%\Adobe\Creative Cloud\ACC\logs` | dir | 🟢 safe (安全) |  | Creative Cloud ACC 组件日志 |
| Creative Cloud 临时文件 | `%LOCALAPPDATA%\Adobe\Creative Cloud\ACC\Temp` | dir | 🟢 safe (安全) |  | Creative Cloud 临时文件 |
| Creative Cloud 日志 | `%LOCALAPPDATA%\Adobe\Creative Cloud\Logs` | dir | 🟢 safe (安全) |  | Adobe Creative Cloud 运行日志 |
| DaVinci Resolve 崩溃记录 | `%APPDATA%\Blackmagic Design\DaVinci Resolve\Support\CrashLogs` | dir | 🟢 safe (安全) |  | DaVinci Resolve 崩溃记录 |
| DaVinci Resolve 日志 | `%APPDATA%\Blackmagic Design\DaVinci Resolve\Support\logs` | dir | 🟢 safe (安全) |  | DaVinci Resolve 运行日志 |
| Lightroom Classic 日志 | `%APPDATA%\Adobe\Lightroom Classic\Logs` | dir | 🟢 safe (安全) |  | Lightroom Classic 运行日志 |
| OBS Studio 崩溃记录 | `%APPDATA%\obs-studio\crashes` | dir | 🟢 safe (安全) |  | OBS Studio 崩溃转储与报告 |
| OBS Studio 日志 | `%APPDATA%\obs-studio\logs` | dir | 🟢 safe (安全) |  | OBS Studio 运行日志 |
| OBS 浏览器 GPU 缓存 | `%APPDATA%\obs-studio\plugin_config\obs-browser\GPUCache` | dir | 🟢 safe (安全) |  | OBS 浏览器源图形渲染缓存 |
| OBS 浏览器 Service Worker | `%APPDATA%\obs-studio\plugin_config\obs-browser\Service Worker\CacheStorage` | dir | 🟢 safe (安全) |  | OBS 浏览器源 Service Worker 缓存 |
| OBS 浏览器代码缓存 | `%APPDATA%\obs-studio\plugin_config\obs-browser\Code Cache` | dir | 🟢 safe (安全) |  | OBS 浏览器源前端脚本缓存 |
| OBS 浏览器缓存 | `%APPDATA%\obs-studio\plugin_config\obs-browser\Cache` | dir | 🟢 safe (安全) |  | OBS 浏览器源缓存 |
| 剪映专业版 GPU 缓存 | `%LOCALAPPDATA%\JianyingPro\User Data\GPUCache` | dir | 🟢 safe (安全) |  | 剪映专业版图形渲染缓存 |
| 剪映专业版 Service Worker | `%LOCALAPPDATA%\JianyingPro\User Data\Service Worker\CacheStorage` | dir | 🟢 safe (安全) |  | 剪映专业版 Service Worker 缓存 |
| 剪映专业版 代码缓存 | `%LOCALAPPDATA%\JianyingPro\User Data\Code Cache` | dir | 🟢 safe (安全) |  | 剪映专业版前端脚本缓存 |
| 剪映专业版 日志 | `%LOCALAPPDATA%\JianyingPro\User Data\logs` | dir | 🟢 safe (安全) |  | 剪映专业版运行日志 |
| 剪映专业版 缓存 | `%LOCALAPPDATA%\JianyingPro\User Data\Cache` | dir | 🟢 safe (安全) |  | 剪映专业版普通缓存 |

## 评级分布
| 评级 | 数量 |
|------|------|
| 🟢 safe（安全） | 34 |
| 🟡 caution（谨慎） | 1 |
| 🔴 dangerous（危险） | 3 |

共 38 条规则。safe 默认启用，caution/dangerous 需 `-ConfirmIds` 显式确认。
