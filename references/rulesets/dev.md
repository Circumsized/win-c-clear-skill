# 开发工具（dev）规则集

> IDE / 编译器 / 构建工具 / 移动开发工具链的可再生缓存与日志。

> ⚠️ **本表「评级」列不是引擎的实际分级。** 它由 `merge_rules.classify_tier`
> （独立的 Python 关键词启发式）生成，与引擎的 `Get-AutoTier` 双向分歧：例如含
> `User Data` 或 `dxcache` 的路径在此偏严（caution/dangerous），引擎按末段 `cache`
> 判 **safe** 并默认启用；`cookies`/`history` 在此偏松（caution），引擎判 **dangerous**。
> 真实分级与 enabled 状态以 `config/targets.merged.json` 或 `-Mode Scan` 输出为准。

| 名称 | 路径 | 类型 | 评级 | 需管理员 | 说明 |
|------|------|------|------|---------|------|
| Gradle Daemon 日志 | `%USERPROFILE%\.gradle\daemon` | dir | 🔴 dangerous (危险) |  | Gradle Daemon 日志与状态缓存 |
| Gradle 通知缓存 | `%USERPROFILE%\.gradle\notifications` | dir | 🔴 dangerous (危险) |  | Gradle 通知缓存 |
| ADB 日志 | `%USERPROFILE%\.android\adb.log` | file | 🟢 safe (安全) |  | ADB 运行日志 |
| Android Emulator 日志 | `%LOCALAPPDATA%\Android\Sdk\emulator\logs` | dir | 🟢 safe (安全) |  | Android 模拟器日志目录 |
| Android SDK 临时缓存 | `%LOCALAPPDATA%\Android\Sdk\.temp` | dir | 🟢 safe (安全) |  | Android SDK 临时缓存 |
| Android 模拟器日志 | `%USERPROFILE%\.android\logs` | dir | 🟢 safe (安全) |  | Android 模拟器日志 |
| Android 模拟器缓存 | `%USERPROFILE%\.android\cache` | dir | 🟢 safe (安全) |  | Android 模拟器与工具缓存 |
| Bruno GPU 缓存 | `%APPDATA%\Bruno\GPUCache` | dir | 🟢 safe (安全) |  | Bruno 图形渲染缓存 |
| Bruno 代码缓存 | `%APPDATA%\Bruno\Code Cache` | dir | 🟢 safe (安全) |  | Bruno 脚本缓存 |
| Bruno 日志 | `%APPDATA%\Bruno\logs` | dir | 🟢 safe (安全) |  | Bruno 运行日志 |
| Bruno 缓存 | `%APPDATA%\Bruno\Cache` | dir | 🟢 safe (安全) |  | Bruno 普通缓存 |
| DBeaver 日志 | `%APPDATA%\DBeaverData\logs` | dir | 🟢 safe (安全) |  | DBeaver 运行日志 |
| Docker Desktop 日志 | `%APPDATA%\Docker\log` | dir | 🟢 safe (安全) |  | Docker Desktop 日志 |
| Flutter 工具日志 | `%LOCALAPPDATA%\Flutter\logs` | dir | 🟢 safe (安全) |  | Flutter 工具日志 |
| GitHub Desktop GPU 缓存 | `%APPDATA%\GitHub Desktop\GPUCache` | dir | 🟢 safe (安全) |  | GitHub Desktop 图形渲染缓存 |
| GitHub Desktop 代码缓存 | `%APPDATA%\GitHub Desktop\Code Cache` | dir | 🟢 safe (安全) |  | GitHub Desktop 脚本缓存 |
| GitHub Desktop 代码缓存 | `%APPDATA%\GitHub Desktop\Code Cache` | dir | 🟢 safe (安全) |  | GitHub Desktop 前端脚本缓存 |
| GitHub Desktop 日志 | `%APPDATA%\GitHub Desktop\logs` | dir | 🟢 safe (安全) |  | GitHub Desktop 运行日志 |
| GitHub Desktop 缓存 | `%APPDATA%\GitHub Desktop\Cache` | dir | 🟢 safe (安全) |  | GitHub Desktop 普通缓存 |
| Godot 日志 | `%APPDATA%\Godot\logs` | dir | 🟢 safe (安全) |  | Godot 运行日志 |
| Insomnia GPU 缓存 | `%APPDATA%\Insomnia\GPUCache` | dir | 🟢 safe (安全) |  | Insomnia 图形渲染缓存 |
| Insomnia 代码缓存 | `%APPDATA%\Insomnia\Code Cache` | dir | 🟢 safe (安全) |  | Insomnia 脚本缓存 |
| Insomnia 代码缓存 | `%APPDATA%\Insomnia\Code Cache` | dir | 🟢 safe (安全) |  | Insomnia 前端脚本缓存 |
| Insomnia 日志 | `%APPDATA%\Insomnia\logs` | dir | 🟢 safe (安全) |  | Insomnia 运行日志 |
| Insomnia 缓存 | `%APPDATA%\Insomnia\Cache` | dir | 🟢 safe (安全) |  | Insomnia 普通缓存 |
| JetBrains Toolbox 日志 | `%LOCALAPPDATA%\JetBrains\Toolbox\logs` | dir | 🟢 safe (安全) |  | JetBrains Toolbox 运行日志 |
| MAUI 日志 | `%LOCALAPPDATA%\Microsoft\dotnet\MAUI\logs` | dir | 🟢 safe (安全) |  | MAUI 构建与运行日志 |
| Postman GPU 缓存 | `%APPDATA%\Postman\GPUCache` | dir | 🟢 safe (安全) |  | Postman 图形渲染缓存 |
| Postman Service Worker | `%APPDATA%\Postman\Service Worker\CacheStorage` | dir | 🟢 safe (安全) |  | Postman Service Worker 缓存 |
| Postman 代码缓存 | `%APPDATA%\Postman\Code Cache` | dir | 🟢 safe (安全) |  | Postman 前端脚本缓存 |
| Postman 日志 | `%APPDATA%\Postman\logs` | dir | 🟢 safe (安全) |  | Postman 运行日志 |
| Postman 缓存 | `%APPDATA%\Postman\Cache` | dir | 🟢 safe (安全) |  | Postman 普通缓存 |
| Rancher Desktop 日志 | `%LOCALAPPDATA%\rancher-desktop\logs` | dir | 🟢 safe (安全) |  | Rancher Desktop 运行日志 |
| SourceTree 日志 | `%LOCALAPPDATA%\Atlassian\SourceTree\logs` | dir | 🟢 safe (安全) |  | SourceTree 运行日志 |
| Trae GPU 缓存 | `%APPDATA%\Trae\GPUCache` | dir | 🟢 safe (安全) |  | Trae 图形渲染缓存 |
| Trae 日志 | `%APPDATA%\Trae\logs` | dir | 🟢 safe (安全) |  | Trae 运行日志 |
| Trae 缓存 | `%APPDATA%\Trae\Cache` | dir | 🟢 safe (安全) |  | Trae 普通缓存 |
| Trae 编译缓存 | `%APPDATA%\Trae\CachedData` | dir | 🟢 safe (安全) |  | Trae 扩展与脚本缓存 |
| Unity 缓存 | `%LOCALAPPDATA%\Unity\cache` | dir | 🟢 safe (安全) |  | Unity 通用缓存 |
| Unreal DerivedDataCache | `%LOCALAPPDATA%\UnrealEngine\Common\DerivedDataCache` | dir | 🟢 safe (安全) |  | Unreal Engine 派生数据缓存 |
| VS Code Insiders GPU 缓存 | `%APPDATA%\Code - Insiders\GPUCache` | dir | 🟢 safe (安全) |  | VS Code Insiders 图形渲染缓存 |
| VS Code Insiders Service Worker | `%APPDATA%\Code - Insiders\Service Worker\CacheStorage` | dir | 🟢 safe (安全) |  | VS Code Insiders Service Worker 缓存 |
| VS Code Insiders 日志 | `%APPDATA%\Code - Insiders\logs` | dir | 🟢 safe (安全) |  | VS Code Insiders 运行日志 |
| VS Code Insiders 缓存 | `%APPDATA%\Code - Insiders\Cache` | dir | 🟢 safe (安全) |  | VS Code Insiders 普通缓存 |
| VS Code Insiders 编译缓存 | `%APPDATA%\Code - Insiders\CachedData` | dir | 🟢 safe (安全) |  | VS Code Insiders 扩展与脚本缓存 |
| VSCodium GPU 缓存 | `%APPDATA%\VSCodium\GPUCache` | dir | 🟢 safe (安全) |  | VSCodium 图形渲染缓存 |
| VSCodium 日志 | `%APPDATA%\VSCodium\logs` | dir | 🟢 safe (安全) |  | VSCodium 运行日志 |
| VSCodium 缓存 | `%APPDATA%\VSCodium\Cache` | dir | 🟢 safe (安全) |  | VSCodium 普通缓存 |
| VSCodium 编译缓存 | `%APPDATA%\VSCodium\CachedData` | dir | 🟢 safe (安全) |  | VSCodium 扩展与脚本缓存 |
| Windsurf GPU 缓存 | `%APPDATA%\Windsurf\GPUCache` | dir | 🟢 safe (安全) |  | Windsurf 图形渲染缓存 |
| Windsurf 日志 | `%APPDATA%\Windsurf\logs` | dir | 🟢 safe (安全) |  | Windsurf 运行日志 |
| Windsurf 缓存 | `%APPDATA%\Windsurf\Cache` | dir | 🟢 safe (安全) |  | Windsurf 普通缓存 |
| Windsurf 编译缓存 | `%APPDATA%\Windsurf\CachedData` | dir | 🟢 safe (安全) |  | Windsurf 扩展与脚本缓存 |
| Xamarin 日志 | `%LOCALAPPDATA%\Xamarin\Logs` | dir | 🟢 safe (安全) |  | Xamarin 运行日志 |
| 本地 Docker 日志 | `%LOCALAPPDATA%\Docker\log` | dir | 🟢 safe (安全) |  | Docker Desktop 本地日志 |

## 评级分布
| 评级 | 数量 |
|------|------|
| 🟢 safe（安全） | 53 |
| 🟡 caution（谨慎） | 0 |
| 🔴 dangerous（危险） | 2 |

共 55 条规则。引擎的实际默认启用规则是「引擎判定为 safe 且未被护栏降级」，
与本表评级不一定一致（见文首警告）；caution/dangerous 一律需 `-ConfirmIds` 显式确认。
