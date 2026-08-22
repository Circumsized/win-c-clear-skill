# BleachBit 设计研究与采纳（bleachbit-design.md）

研究 [BleachBit](https://github.com/bleachbit/bleachbit)（GPL-3.0）的 system cleaners 设计，
转化为本 skill 的内置目标。原则：**只用其"目标识别 + 原生命令"知识，不复刻其注册表清理与自由删除语义**。

## BleachBit system cleaner → 本 skill 映射

| BleachBit cleaner/option | 本 skill 目标 | tier | 执行方式 |
|--------------------------|--------------|------|---------|
| windows_explorer > mru (UserAssist winreg) | — | — | **不采纳**：注册表清理超出本 skill 边界 |
| windows_explorer > thumbnails | `thumbnail-cache` | safe | glob thumbcache*.db |
| （对应）icon cache | `icon-cache` | safe | glob IconCache*.db @ %LOCALAPPDATA% |
| system > windows_event_logs | `win-event-logs` | caution | **wevtutil cl Application/System/Setup**（原生命令） |
| system > security 日志 | `win-event-logs-security` | dangerous | **wevtutil cl Security**（审计轨迹，两段确认） |
| microsoft_defender > scan_history | `win-defender-history` | caution | %ProgramData%\...\Scans\History |
| microsoft_defender > logs | `win-defender-logs` | safe | %ProgramData%\...\Support |
| system > memory_dump / minidump | `memory-dmp` / `minidump` | caution | 文件/目录删除 |
| system > recycle_bin | `recycle-bin` | caution | **Clear-RecycleBin**（PS 原生 cmdlet） |
| system > temporary_files | `user-temp` / `windows-temp` | safe | 目录清空 |
| system > windows_updates | `wu-download` | caution | SoftwareDistribution\Download + 停 wuauserv/bits/DoSvc |
| system > free_disk_space (wipe) | — | — | **不采纳**：擦除空闲空间耗时且非清理目标 |
| deepscan > 各种 | `crashdumps-user`、`wer-reports` 等 | safe | 目录删除 |
| 字体缓存（FontCache 服务） | `font-cache` | safe | 停 FontCache 服务 → 删缓存库 |
| BranchCache | `branchcache` | caution | 停 PeerDistSvc → 删 BCCache |
| Windows.old（升级残留） | `windows-old` | dangerous | **takeown /A /R /D Y + icacls + 删除**（原生序列） |
| hiberfil.sys | `hiberfil` | dangerous | **powercfg /h off**（原生、干净；可 powercfg /h on 恢复） |
| pagefile.sys / swapfile.sys | `pagefile-swapfile` | dangerous | **advisory-only**：永不删除，给出 sysdm.cpl 迁移指引 |
| setupapi.dev.log | `win-setupapi-logs` | caution | glob setupapi*.log @ %WinDir%\inf（INF 文件永不动） |
| Panther（安装迁移日志） | `win-panther` | caution | %WinDir%\Panther |
| WindowsUpdate.log | `win-update-log` | safe | 旧式文本日志文件 |

## 采纳的关键设计原则

1. **原生命令优先**：wevtutil/powercfg/takeown/icacls/robocopy/Clear-RecycleBin——比直接删文件更安全
   （如 wevtutil 正确处理日志服务状态；powercfg 干净移除 hiberfil）
2. **服务感知**：清理系统服务托管数据前停服务（FontCache/PeerDistSvc/wuauserv），完成后重启——
   全部经 `-AllowStop` 用户确认门控
3. **永不动注册表**：BleachBit 大量 winreg 动作（MRU/键值清理）不在本 skill 范围（红线）
4. **advisory 语义**：pagefile 这类"动了会坏系统"的目标 → 报尺寸 + 给方案，永不执行
5. **社区规则作参考依赖**：BleachBit cleaners XML（104 个）解析为 community 源（opt-in），
   不自动启用——与其 GUI 默认不勾选高级项的保守哲学一致

## Windows 更新垃圾全景（本 skill 覆盖清单）

- `wu-download`：SoftwareDistribution\Download（更新载荷，重下无害）—— caution
- `win-update-log`：WindowsUpdate.log 旧文本日志 —— safe
- `cbs-logs` / `dism-logs`：组件服务日志 —— caution/safe
- `win-event-logs`：Application/System/Setup 事件日志 —— caution（诊断历史丢失）
- `delivery-optimization(-system)`：传递优化缓存 —— safe/caution
- `win-panther`：升级迁移日志 —— caution
- `windows-old`：旧系统树（10-30GB 大头）—— dangerous 两段确认
- 建议（不执行）：`dism /online /cleanup-image /startcomponentcleanup`（WinSxS 唯一安全路径）、
  `cleanmgr /sagerun`、Storage Sense
