# 国产软件（cn）规则集

> 国产应用（腾讯/金山/字节/百度/360/搜狗等）的缓存与日志，国内用户常装。

| 名称 | 路径 | 类型 | 评级 | 需管理员 | 说明 |
|------|------|------|------|---------|------|
| 360 浏览器 GPU 缓存 | `%LOCALAPPDATA%\360Chrome\Chrome\User Data\Default\GPUCache` | dir | 🟢 safe (安全) |  | 360 安全浏览器图形渲染缓存 |
| 360 浏览器代码缓存 | `%LOCALAPPDATA%\360Chrome\Chrome\User Data\Default\Code Cache` | dir | 🟢 safe (安全) |  | 360 安全浏览器脚本缓存 |
| 360 浏览器缓存 | `%LOCALAPPDATA%\360Chrome\Chrome\User Data\Default\Cache` | dir | 🟢 safe (安全) |  | 360 安全浏览器普通缓存 |
| QQ 浏览器 GPU 缓存 | `%LOCALAPPDATA%\Tencent\QQBrowser\User Data\Default\GPUCache` | dir | 🟢 safe (安全) |  | QQ 浏览器图形渲染缓存 |
| QQ 浏览器代码缓存 | `%LOCALAPPDATA%\Tencent\QQBrowser\User Data\Default\Code Cache` | dir | 🟢 safe (安全) |  | QQ 浏览器脚本缓存 |
| QQ 浏览器缓存 | `%LOCALAPPDATA%\Tencent\QQBrowser\User Data\Default\Cache` | dir | 🟢 safe (安全) |  | QQ 浏览器普通缓存 |
| QQ 音乐缓存 | `%APPDATA%\Tencent\QQMusic\Cache` | dir | 🟢 safe (安全) |  | QQ 音乐缓存目录 |
| WPS 日志 | `%LOCALAPPDATA%\Kingsoft\WPS Office\logs` | dir | 🟢 safe (安全) |  | WPS Office 运行日志 |
| WPS 缓存 | `%LOCALAPPDATA%\Kingsoft\WPS Office\cache` | dir | 🟢 safe (安全) |  | WPS Office 缓存 |
| 企业微信日志 | `%APPDATA%\Tencent\WXWork\log` | dir | 🟢 safe (安全) |  | 企业微信客户端日志 |
| 剪映日志 | `%LOCALAPPDATA%\JianyingPro\User Data\Default\logs` | dir | 🟢 safe (安全) |  | 剪映桌面版日志 |
| 夸克浏览器 GPU 缓存 | `%LOCALAPPDATA%\Quark\User Data\Default\GPUCache` | dir | 🟢 safe (安全) |  | 夸克浏览器图形渲染缓存 |
| 夸克浏览器代码缓存 | `%LOCALAPPDATA%\Quark\User Data\Default\Code Cache` | dir | 🟢 safe (安全) |  | 夸克浏览器脚本缓存 |
| 夸克浏览器缓存 | `%LOCALAPPDATA%\Quark\User Data\Default\Cache` | dir | 🟢 safe (安全) |  | 夸克浏览器普通缓存 |
| 搜狗浏览器缓存 | `%LOCALAPPDATA%\SogouExplorer\Webkit\Default\Cache` | dir | 🟢 safe (安全) |  | 搜狗浏览器普通缓存 |
| 百度网盘日志 | `%APPDATA%\BaiduNetdisk\users\default\log` | dir | 🟢 safe (安全) |  | 百度网盘运行日志 |
| 腾讯会议日志 | `%APPDATA%\Tencent\WeMeet\logs` | dir | 🟢 safe (安全) |  | 腾讯会议运行日志 |
| 迅雷日志 | `%PROGRAMDATA%\Thunder Network\Thunder\logs` | dir | 🟢 safe (安全) | 是 | 迅雷运行日志 |
| 钉钉日志 | `%APPDATA%\DingTalk\logs` | dir | 🟢 safe (安全) |  | 钉钉运行日志 |
| 飞书日志 | `%APPDATA%\LarkShell\logs` | dir | 🟢 safe (安全) |  | 飞书运行日志 |

## 评级分布
| 评级 | 数量 |
|------|------|
| 🟢 safe（安全） | 20 |
| 🟡 caution（谨慎） | 0 |
| 🔴 dangerous（危险） | 0 |

共 20 条规则。safe 默认启用，caution/dangerous 需 `-ConfirmIds` 显式确认。
