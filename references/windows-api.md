# Windows API 深度参考（windows-api.md）

win-c-clear-skill 所涉 Windows API 全谱：本 skill 的实现映射、已用/建议/红线分层。
深度适配自对 WindowsClear / zhenhuaDiskCleaner / BleachBit / ZyperWinOptimize 的设计研究与
Windows 官方文档（MSDN/Win32）。

---

## 一、文件系统层：扫描与遍历

### 1. 目录遍历 API

| API | 说明 | 本 skill 映射 |
|-----|------|--------------|
| `FindFirstFileEx` / `FindNextFile` | Win32 目录遍历基础；`FindExInfoBasic` 减少不必要数据获取 | **已用**（间接）：`Directory.Enumerate*` 与 ParallelScanner.cs 内部即基于它 |
| `GetFileAttributesEx` | 批量获取属性，避免逐文件打开句柄 | **已用**（间接）：`DirectoryInfo/FileInfo` 封装 |
| `NtQueryDirectoryFile` | NT Native API，一次返回多个 `FILE_BOTH_DIR_INFORMATION`，减少系统调用 | 未用（需不安全代码；.NET 枚举 + MFT 直读已覆盖收益） |

优化要点已采纳：`FindExInfoBasic` 语义（不取短名）、跳过重解析点（`ReparsePoint` 属性过滤防 junction 环）。

### 2. NTFS MFT 直读（本 skill 核心现代化算法）

| API / 机制 | 说明 | 本 skill 映射 |
|-----------|------|--------------|
| `FSCTL_GET_NTFS_VOLUME_DATA` (0x00090064) | `DeviceIoControl` 获取 NTFS 卷元数据：MFT 起始 LCN、每记录字节数、MftValidDataLength（**字节单位**） | **已用**：`MftScanner.cs` 直读引擎 |
| `FSCTL_GET_NTFS_FILE_RECORD` | 按文件引用号读取单条 MFT 记录 | 未用（顺序遍历更高效） |
| `\\.\C:` 裸卷设备 | 管理员 GENERIC_READ 打开，按 MFT 记录（1KB）顺序解析 `$FILE_NAME`/`$STANDARD_INFORMATION`/`$DATA` | **已用**：`CreateFile` + `SetFilePointerEx` + `ReadFile` P/Invoke |

**实现要点（实测踩坑记录）**：
- MFT 是**逻辑文件**（本机 4.3GB ≈ 422 万记录）但磁盘上**可碎片化为多个 extent**——必须解析 MFT 自身（记录 0）的 `$DATA` **run list**（VCN→LCN 映射）按段遍历；从 MftStartLcn 纯顺序读只能覆盖第一段
- 记录解析：'FILE' 签名 → **USN fixup**（每 sector 末 2 字节校验替换）→ 属性遍历（`0x30 $FILE_NAME` 取名/父引用；`0x80 $DATA` 未命名流取尺寸）
- **nonresident $DATA 布局**（实测验证）：`0x24 AllocatedSize` / `0x30 RealSize` / `0x38 InitializedSize`（注意 0x2C 偏移读出的是垃圾——多源文档布局分歧，以 s24/s2C/s30 三偏移统计对照实验定案）
- 路径重建：FRN→(父FRN, 名) 映射 + 父链回溯（父引用低 48 位 = FRN，高 16 位 = 序列号）
- **硬链接语义**：一个 MFT 记录可挂多个 FILE_NAME；$DATA 只计一次 → MFT 总量 = **真实独占占用**（本机实测：uv-cache 名义 113.64GB，独占仅 8.32GB——大量硬链接共享）。目录树递归（.NET 口径）会重复计数硬链接。Analyze 报告两种口径的差异是 MFT 直读的独有价值
- 性能：全卷 342 万记录 27s（含路径重建），比目录树递归快数倍

### 3. 文件属性与元数据

| API | 说明 | 本 skill 映射 |
|-----|------|--------------|
| `GetFileInformationByHandle` / `...Ex` (FileIdInfo) | 文件索引号、链接数、时间戳 | 部分间接（`FileInfo`）；链接数可用于硬链接识别（未来增强） |
| `GetCompressedFileSize` | 压缩文件实际磁盘占用 | 未用（MFT AllocatedSize 已覆盖语义） |
| `GetDiskFreeSpaceEx` | 磁盘可用/总空间 | **已用**（`Get-PSDrive` 封装） |
| `GetVolumeInformation` | 文件系统类型（是否 NTFS → 能否 MFT 扫描） | 间接（DeviceIoControl 失败即回退 .NET） |

---

## 二、文件删除与操作层

### 1. 删除 API 层级（本 skill 三种恢复模式的底层）

| API | 特点 | 本 skill 映射 |
|-----|------|--------------|
| `DeleteFile` / `RemoveDirectory` | 直接删除，不经回收站 | **已用**：`-RecoveryMode permanent`（默认，唯一即时释放空间的模式） |
| `SHFileOperation` (FOF_ALLOWUNDO) | Shell 封装，送入回收站 | **已用**：`-RecoveryMode recycle`（经 Microsoft.VisualBasic FileIO，底层即 SHFileOperation） |
| `IFileOperation` (COM) | Vista+ 现代替代，UAC 提升/事务/进度 | 未直接用（VB 封装已覆盖需求） |
| `MoveFileEx + MOVEFILE_DELAY_UNTIL_REBOOT` | 重启时删除（占用文件） | 未用（locked 项报告占用者 + 建议重启，不静默挂起删除） |
| `FILE_FLAG_DELETE_ON_CLOSE` | 关句柄自动删 | 未用（不符合扫描先行语义） |

### 2. POSIX 删除语义
`FILE_FLAG_POSIX_SEMANTICS` + `FILE_DISPOSITION_DELETE`（Win10 1809+）：句柄打开即从目录消失，避免"已标记删除仍可见"窗口期。未采纳：与 Restart Manager 占用检测协作时不透明。

### 3. 文件占用处理：Restart Manager（WindowsClear 核心方案）

| API | 说明 | 本 skill 映射 |
|-----|------|--------------|
| `RmStartSession` / `RmRegisterResources` / `RmGetList` | 查询哪些进程正在使用文件 | **已用**：`rstrtmgr.dll` P/Invoke（WinRm C# 类）；locked 时报告占用进程（名+pid） |
| `RmShutdown` / `RmRestart` | 请求关闭/恢复占用进程 | **有意不用**：关闭进程必须经用户确认（`-AllowStop` 门控），由引擎 `Stop-Process` 显式执行并记录 |

---

## 三、权限与安全层

| API | 说明 | 本 skill 映射 |
|-----|------|--------------|
| `GetNamedSecurityInfo` / `SetNamedSecurityInfo` | 读取/修改安全描述符 | 未直接用（icacls 原生命令替代） |
| `AdjustTokenPrivileges` | 提升进程特权（SE_BACKUP/SE_RESTORE/SE_TAKE_OWNERSHIP） | 未直接用（takeown/icacls 命令替代） |
| TakeOwnership | 获取 TrustedInstaller 所有权 | **已用（命令层）**：`windows-old` 目标的 `takeown /F ... /A /R /D Y` + `icacls /grant *S-1-5-32-544:F`（用内置 Administrators 组的固定 SID 而非本地化组名，跨语言系统通用）原生序列（两段确认后） |

**本 skill 立场**：C:\Windows\WinSxS、C:\Windows\Installer 等 TrustedInstaller 区域**永不触碰**（引擎黑名单 guardrail），不像传统清理工具抢所有权强删——WinSxS 唯一安全路径是 DISM StartComponentCleanup（仅建议不执行）。

### UAC 与完整性级别
`ShellExecuteEx`（runas 动词）/ `CreateProcessAsUser`：系统目录清理需管理员。**已用**：`-Elevate` 参数 `Start-Process -Verb RunAs` 提权 + 结果文件回传 JSON（防提权后输出丢失）。

---

## 四、Windows 更新与组件存储

### Component Store（WinSxS）

| 机制 | 说明 | 本 skill 映射 |
|------|------|--------------|
| 硬链接投射 | WinSxS 文件硬链接到 System32 等，**不能按目录大小算实际占用** | 理解采纳：MFT 口径的正确性正源于此；黑名单保护 WinSxS |
| `DISM /Online /Cleanup-Image /StartComponentCleanup` | 官方清理方式 | **仅建议**（Analyze suggestions），永不执行 |
| CBS API (`ICbsSession` COM) | 组件服务底层 | 不用（DISM 已封装） |

### Windows Update 缓存
- `C:\Windows\SoftwareDistribution\Download`（停 wuauserv 后安全清）→ **已用**：`wu-download` 目标（caution，stopServices 门控）
- `wuauclt` / `usoclient` / WUApi(COM)：**建议级**参考

### Delivery Optimization
`Delete-DeliveryOptimizationCache`（PS cmdlet / COM）：DO 缓存官方清理。**已用（等价路径）**：`delivery-optimization(-system)` 目标直接清缓存目录 + 停 DoSvc。

---

## 五、卷影复制与系统还原

| API / 组件 | 说明 | 本 skill 映射 |
|-----------|------|--------------|
| VSS (`IVssBackupComponents`) / `vssadmin delete shadows` | 快照/还原点管理 | **红线**：系统还原点永不删除（guardrail + 文档） |
| `SRSetRestorePoint` | 创建还原点 | 未用（删除缓存类操作无需新建还原点；dangerous 目标有备份机制） |

---

## 六、符号链接与 Junction（迁移策略核心）

| API | 说明 | 本 skill 映射 |
|-----|------|--------------|
| `CreateHardLink` | 同卷硬链接 | 理解采纳（MFT 口径正确性的基础） |
| `mklink /J` / junction | 目录联接，无需特权 | **建议层**：大目录（TeX Live 等）迁移方案；扫描时 ReparsePoint 过滤防环/防重复计数 |
| `CreateSymbolicLink` / `FSCTL_SET_REPARSE_POINT` | 符号链接/重解析点 | 同上（扫描过滤已实现） |

**立场**：迁移/junction 是"软件搬家"类工具（WindowsClear）的核心；本 skill 将其列为**建议**（mzcleaner 保守哲学 + 不可逆性低），不自动执行。

---

## 七、注册表操作

| API | 说明 | 本 skill 映射 |
|-----|------|--------------|
| `RegOpenKeyEx` / `RegQueryValueEx` | 读取配置 | **已用（等价）**：Storage Sense 状态读取（`StoragePolicy` 键，经 Get-ItemProperty） |
| `RegDeleteKey` / `RegDeleteValue` | 卸载残留清理 | **红线**：不做注册表深度清理（能力边界） |
| `SHGetKnownFolderPath` / `SHSetKnownFolderPath` | 用户目录迁移 | 未用（迁移仅建议） |
| User Shell Folders 双写 | 迁移后注册表路径映射 | 未用（同上） |

---

## 八、Storage Sense 与 Cleanmgr 架构

### Storage Sense（Win10 1703+，cleanmgr 的现代替代）
- 配置：`HKCU\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy` → **已读**（Analyze 报告 ON/OFF + 建议开启防反弹）
- 清理范围：临时文件/回收站/下载/OneDrive 脱水；触发：每天~磁盘紧张 → 建议用户启用

### Cleanmgr 插件式架构
`HKLM\...\Explorer\VolumeCaches` 每子键一个 COM Handler；`/sageset:n`+`/sagerun:n` → **建议级**引用（Analyze suggestions）。

---

## 九、进程与内存转储

| 路径 / API | 说明 | 本 skill 映射 |
|-----------|------|--------------|
| `C:\Windows\Minidump` / `MEMORY.DMP` | 系统崩溃转储 | **已用**：`minidump`/`memory-dmp` 目标（caution，默认关——调试者需要） |
| `LiveKernelReports` | 内核实时报告 | **已用**：`livekernelreports` 目标 |
| WER（`C:\ProgramData\Microsoft\Windows\WER`） | 应用崩溃报告 | **已用**：`wer-reports` 目标（safe） |
| `WerReportCreate/Submit` | WER API（生成机制理解） | 理解层：判断哪些可安全删 |

---

## 十、磁盘分析与配额

| API | 说明 | 本 skill 映射 |
|-----|------|--------------|
| `GetDiskFreeSpaceEx` / `SHGetDiskFreeSpaceEx` | 空间概况 | **已用**（每模式 before/after free 报告） |
| `FSCTL_QUERY_ALLOCATED_RANGES` | 稀疏文件实际分配 | 理解层（MFT AllocatedSize 等价覆盖） |
| `IDiskQuotaControl` | NTFS 配额 | 不适用（个人清理场景） |
| `GetVolumeInformation` | 判 NTFS 定 MFT 可用性 | **已用（等价）**：MFT 失败自动回退 .NET |

---

## 附：本 skill 原生 API 集成总表

| 层 | 已集成 | 方式 |
|----|--------|------|
| 扫描 | MFT 直读（FSCTL + run-list 遍历） | MftScanner.cs P/Invoke |
| 扫描 | Task.WhenAll + SemaphoreSlim 异步递归 | ParallelScanner.cs（runspace 池回退） |
| 删除 | 三恢复模式（DeleteFile / SHFileOperation / MoveFile+manifest） | Clear-OnePath |
| 占用 | Restart Manager 查询 | WinRm C# 类 |
| 内存 | EmptyWorkingSet 截取 | psapi P/Invoke |
| 提权 | UAC runas + 结果回传 | Start-Process -Verb RunAs |
| 所有权 | takeown/icacls（仅 Windows.old 两段确认） | 原生命令 |
| 系统命令 | wevtutil / powercfg / Clear-RecycleBin / robocopy /L / DISM(建议) / cleanmgr(建议) | preCommands + suggestions |
