# 设计建模（design）规则集

> 3D / CAD / 设计类软件的临时与着色器缓存（建模项目本身不在这些目录）。

> ⚠️ **本表「评级」列不是引擎的实际分级。** 它由 `merge_rules.classify_tier`
> （独立的 Python 关键词启发式）生成，与引擎的 `Get-AutoTier` 双向分歧：例如含
> `User Data` 或 `dxcache` 的路径在此偏严（caution/dangerous），引擎按末段 `cache`
> 判 **safe** 并默认启用；`cookies`/`history` 在此偏松（caution），引擎判 **dangerous**。
> 真实分级与 enabled 状态以 `config/targets.merged.json` 或 `-Mode Scan` 输出为准。

| 名称 | 路径 | 类型 | 评级 | 需管理员 | 说明 |
|------|------|------|------|---------|------|
| Blender 崩溃日志 | `%TEMP%\blender.crash.txt` | file | 🟢 safe (安全) |  | Blender 崩溃日志 |
| Godot 日志 | `%APPDATA%\Godot\logs` | dir | 🟢 safe (安全) |  | Godot 运行日志 |
| Substance 3D Designer 日志 | `%APPDATA%\Adobe\Adobe Substance 3D Designer\logs` | dir | 🟢 safe (安全) |  | Substance 3D Designer 运行日志 |
| Substance 3D Painter 日志 | `%APPDATA%\Adobe\Adobe Substance 3D Painter\logs` | dir | 🟢 safe (安全) |  | Substance 3D Painter 运行日志 |
| Substance 3D Sampler 日志 | `%APPDATA%\Adobe\Adobe Substance 3D Sampler\logs` | dir | 🟢 safe (安全) |  | Substance 3D Sampler 运行日志 |
| Substance 3D Stager 日志 | `%APPDATA%\Adobe\Adobe Substance 3D Stager\logs` | dir | 🟢 safe (安全) |  | Substance 3D Stager 运行日志 |
| Unity Hub GPU 缓存 | `%APPDATA%\UnityHub\GPUCache` | dir | 🟢 safe (安全) |  | Unity Hub 图形渲染缓存 |
| Unity Hub 代码缓存 | `%APPDATA%\UnityHub\Code Cache` | dir | 🟢 safe (安全) |  | Unity Hub 前端脚本缓存 |
| Unity Hub 日志 | `%APPDATA%\UnityHub\logs` | dir | 🟢 safe (安全) |  | Unity Hub 运行日志 |
| Unity Hub 缓存 | `%APPDATA%\UnityHub\Cache` | dir | 🟢 safe (安全) |  | Unity Hub 普通缓存 |
| Unity 缓存 | `%LOCALAPPDATA%\Unity\cache` | dir | 🟢 safe (安全) |  | Unity 通用缓存 |
| Unreal DerivedDataCache | `%LOCALAPPDATA%\UnrealEngine\Common\DerivedDataCache` | dir | 🟢 safe (安全) |  | Unreal Engine 派生数据缓存 |

## 评级分布
| 评级 | 数量 |
|------|------|
| 🟢 safe（安全） | 12 |
| 🟡 caution（谨慎） | 0 |
| 🔴 dangerous（危险） | 0 |

共 12 条规则。引擎的实际默认启用规则是「引擎判定为 safe 且未被护栏降级」，
与本表评级不一定一致（见文首警告）；caution/dangerous 一律需 `-ConfirmIds` 显式确认。
