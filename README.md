# DshKit

把 **DeepSeek Harness (DSH)** 的会话、工作区、插件、技能和外观配置放进 OneDrive，让两台 Windows 机器共用同一份状态。

> DshKit 不是 DSH 内部插件，而是一组 Windows PowerShell 启动/同步脚本：启动前 Pull，运行中写心跳，退出后 Push。

## 特性

- **启动前 Pull、退出后 Push**：不依赖 DSH 内部 API，DSH 升级后仍可用。
- **活动会话不丢**：DSH 运行时 `Push` 会拒绝执行，避免“跳过活动会话却报告成功”。
- **旧机器不覆盖新内容**：目标端会话文件更新时间更晚时跳过，保护另一台已同步的新内容。
- **单活动机器锁**：`DshKit/.active-machine.json` + 心跳，崩溃 10 分钟后另一台可自动接管。
- **崩溃兜底**：`Push-On-DshExit.ps1` 可在 DSH 退出后补一次 Push。
- **技能共享**：`~/.dsh/skills` 建成指向 `DshKit/skills` 的 Junction。

## 要求

- Windows 10/11
- DeepSeek Harness Desktop（默认路径 `%LOCALAPPDATA%\Programs\DeepSeek Harness`）
- OneDrive（默认 `%USERPROFILE%\OneDrive\DshKit`，也支持 `%OneDrive%`）
- 两台机器 **用户名和项目绝对路径一致**（工作区注册表存的是绝对路径）
- 同一时间只在一台机器上运行 DSH

## 安装

从 [Releases](https://github.com/wang22ti/dshkit/releases) 下载 zip，解压后运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

默认安装到 `%USERPROFILE%\OneDrive\DshKit`。自定义位置：

```powershell
.\install.ps1 -KitRoot "D:\OneDrive\DshKit"
```

### 第一台机器（已有 DSH 数据）

先完全退出 DSH，再执行：

```powershell
.\install.ps1 -InitialPush
```

### 第二台机器（从 OneDrive 取数据）

等 OneDrive 同步完 DshKit，退出 DSH，再执行：

```powershell
.\install.ps1 -InitialPull
```

之后两台机器都从开始菜单的 **「DeepSeek Harness」** 启动（安装器把它指向同步入口）；需要绕过同步时才用「DeepSeek Harness (原生启动)」。

## 使用

1. 双击开始菜单 **「DeepSeek Harness」**（同步入口）。
2. 脚本先 Pull，再启动 DSH。
3. 正常退出 DSH 后，脚本自动 Push。
4. 换机器前确认 DSH 已退出，并等 OneDrive 显示同步完成。

手动命令：

```powershell
$K = "$env:USERPROFILE\OneDrive\DshKit"
& "$K\Sync-DshKit.ps1" -Action Status
& "$K\Sync-DshKit.ps1" -Action Pull    # DSH 必须已退出
& "$K\Sync-DshKit.ps1" -Action Push    # DSH 必须已退出
```

`Push-DshKit.cmd` 是同一命令的批处理入口；`-Force` 用于接管崩溃机器留下的锁。

## 同步内容

| 内容 | 位置 |
| --- | --- |
| 会话 | `~/.dsh/sessions` → `DshKit/sessions` |
| 会话投影缓存（标题/摘要） | `~/.dsh/storages/session_projcache` → `DshKit/storages/session_projcache` |
| 附件 | `~/.dsh/attachments` → `DshKit/attachments` |
| 本地插件 | `~/.dsh/plugins` → `DshKit/plugins` |
| 工作区注册表 | `~/.dsh/storages/workspace.json` → `DshKit/state/workspace.json` |
| 工作区分组 | `~/.dsh/workspace-groups.yaml`、`workspace-groups.tabs.json` |
| Codex 同步配置 | `~/.dsh/codex-sync.json` |
| Profile 配置 | `~/.dsh/profiles/desktop/{package.json,cordis.patch.yml,cordis.yml,pnpm-lock.yaml,pnpm-workspace.yaml,compatibility.json}` |
| 技能 | `~/.dsh/skills` → `DshKit/skills`（Junction） |

**不同步**：`.credentials.yaml`（账号凭据）、`profiles/*/node_modules`（首次启动自动安装）、`cache`、`dsh-runtimes`、`agent-sync`、日志。

## 安全设计

- **DSH 运行中拒绝 Push**：活动会话是追加写入的 zstd 帧，复制到一半会产生坏帧。
- **目标更新则跳过**：比较文件修改时间，避免旧机器把新机器刚 Push 的会话覆盖。
- **锁 + 心跳**：`Acquire-Lock` 检查对方心跳；超过 10 分钟自动接管，否则要求退出对方 DSH。
- **配置备份**：每次 Pull 前把本机 `workspace.json`、profile 配置备份到 `~/.dsh/.dshkit-backup-<时间>`。
- **只覆盖程序文件**：安装/升级不会删除 `sessions`、`state` 或 `skills`。

## 恢复“另一台的新内容没同步”

在 **有最新内容的那台机器**：

1. 完全退出 DSH，确认 `Get-Process 'DeepSeek Harness'` 为空。
2. 运行：
   ```powershell
   & "$env:USERPROFILE\OneDrive\DshKit\Push-DshKit.cmd" -Force
   ```
3. 等 OneDrive 同步完成。
4. 回到另一台机器，退出 DSH 后从「DeepSeek Harness」同步入口重新启动。

## 故障排查

**`Sync-DshKit.ps1` 报 `Unexpected token` / 中文乱码**

脚本必须保存为 **UTF-8 with BOM + CRLF**。仓库里的 `.ps1` 已按此格式提供；如果手动编辑过，请另存为“UTF-8 带 BOM”。

**`Push-DshKit.cmd` 报 `'e' 不是内部或外部命令`**

批处理必须是 **ASCII + CRLF**。不要用 UTF-8 中文内容编辑 `.cmd`。

**`DSH 正在运行，本次 Push 已拒绝`**

这是预期行为。先完全退出 DSH；仅关闭窗口但后台进程还在时也会被拒绝。

**锁被占用**

正常退出会释放锁。机器崩溃后等 10 分钟，或确认对方已关机后：

```powershell
& "$env:USERPROFILE\OneDrive\DshKit\Sync-DshKit.ps1" -Action Unlock -Force
```

**OneDrive 路径不是 `%USERPROFILE%\OneDrive`**

安装时用 `-KitRoot` 指定，安装器会写入 `config.json`，后续脚本自动读取。

## 卸载

1. 删除开始菜单「DeepSeek Harness」和「DeepSeek Harness (原生启动)」快捷方式（或用 `%LOCALAPPDATA%\DshKit\shortcut-backups` 恢复）。
2. 删除 `~/.dsh/skills` Junction（只删链接，不要删 `DshKit/skills` 内容）。
3. 如不再需要同步，删除 `DshKit` 文件夹。**删除前先确认 `DshKit/sessions` 里的会话已经在本机 `~/.dsh/sessions` 有一份。**

## 目录结构

```text
dshkit/
  install.ps1                     安装/升级、写 config.json、建 Junction、装快捷方式
  src/
    Sync-DshKit.ps1               Pull / Push / Status / Heartbeat / Unlock
    Start-DshSynced.ps1           同步启动器：Pull → 启动 → 等退出 → Push
    Start-DshSynced.cmd           可见诊断入口
    Start-DshSynced.vbs           隐藏启动入口（快捷方式用）
    Install-DshKitShortcuts.ps1   创建两个开始菜单入口
    Push-DshKit.cmd               手动 Push
    Push-On-DshExit.ps1           退出兜底监视器
  tests/
  .github/workflows/
```

## License

MIT
