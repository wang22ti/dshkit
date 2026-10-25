param(
    [ValidateSet('Pull', 'Push', 'Status', 'Unlock', 'Heartbeat', 'Version')]
    [string]$Action = 'Status',
    [string]$KitRoot,
    [string]$DshHome,
    [string]$Profile,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$script:Version = '1.0.5'

if (-not $KitRoot) {
    $KitRoot = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
}
$Root = $KitRoot

$Config = @{}
$ConfigPath = Join-Path $Root 'config.json'
if (Test-Path -LiteralPath $ConfigPath) {
    try {
        $loaded = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($property in $loaded.PSObject.Properties) { $Config[$property.Name] = $property.Value }
    } catch {
        Write-Warning "config.json 无法解析，使用默认值: $($_.Exception.Message)"
    }
}

if (-not $DshHome) {
    $DshHome = if ($Config.ContainsKey('dshHome') -and $Config['dshHome']) { $Config['dshHome'] } else { Join-Path $env:USERPROFILE '.dsh' }
}
if (-not $Profile) {
    $DshProfile = if ($Config.ContainsKey('profile') -and $Config['profile']) { $Config['profile'] } else { 'desktop' }
} else {
    $DshProfile = $Profile
}
$Dsh = $DshHome
$ProfileDir = Join-Path $Dsh "profiles\$DshProfile"
$DshProcessName = if ($Config.ContainsKey('processName') -and $Config['processName']) { $Config['processName'] } else { 'DeepSeek Harness' }
$LockPath = Join-Path $Root '.active-machine.json'
$LogPath = Join-Path $Root 'sync.log'
$ProfileFiles = @('cordis.patch.yml', 'cordis.yml', 'package.json', 'pnpm-lock.yaml', 'pnpm-workspace.yaml', 'compatibility.json')

function Write-Log([string]$Message) {
    $line = "{0:o} [{1}] {2}" -f (Get-Date), $env:COMPUTERNAME, $Message
    Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
    Write-Host $line
}

function Test-DshRunning {
    return @(Get-Process -Name $DshProcessName -ErrorAction SilentlyContinue).Count -gt 0
}

function Read-Lock {
    if (-not (Test-Path -LiteralPath $LockPath)) { return $null }
    try { return Get-Content -LiteralPath $LockPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { return $null }
}

function Get-LockAge([object]$Lock) {
    if (-not $Lock) { return [TimeSpan]::MaxValue }
    $stamp = if ($Lock.heartbeat) { $Lock.heartbeat } elseif ($Lock.at) { $Lock.at } else { return [TimeSpan]::MaxValue }
    try { return (Get-Date) - [datetime]$stamp } catch { return [TimeSpan]::MaxValue }
}

function Acquire-Lock {
    $lock = Read-Lock
    if ($lock -and -not $Force) {
        $age = Get-LockAge $lock
        # 心跳超过 10 分钟视为上一台机器已崩溃/关机，自动接管，不再需要人工 -Force
        if ($lock.machine -ne $env:COMPUTERNAME -and $age.TotalMinutes -lt 10) {
            throw "DshKit 正在被 $($lock.machine) 使用（心跳 $([math]::Round($age.TotalMinutes,1)) 分钟前）。请先关闭那台机器的 DSH。"
        }
    }
    $now = (Get-Date).ToString('o')
    @{ machine = $env:COMPUTERNAME; at = $now; heartbeat = $now; pid = $PID } |
        ConvertTo-Json | Set-Content -LiteralPath $LockPath -Encoding UTF8
}

function Update-Heartbeat {
    $lock = Read-Lock
    if ($lock -and $lock.machine -ne $env:COMPUTERNAME) { return }
    $now = (Get-Date).ToString('o')
    @{ machine = $env:COMPUTERNAME; at = $(if ($lock -and $lock.at) { $lock.at } else { $now }); heartbeat = $now; pid = $PID } |
        ConvertTo-Json | Set-Content -LiteralPath $LockPath -Encoding UTF8
}

function Release-Lock {
    $lock = Read-Lock
    if ($lock -and $lock.machine -eq $env:COMPUTERNAME) {
        Remove-Item -LiteralPath $LockPath -Force -ErrorAction SilentlyContinue
    }
}

function Copy-Tree([string]$Source, [string]$Destination) {
    if (-not (Test-Path -LiteralPath $Source)) { return }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    $result = & robocopy $Source $Destination /E /XO /R:1 /W:1 /NP /NFL /NDL
    if ($LASTEXITCODE -ge 8) { throw "robocopy failed ($LASTEXITCODE): $Source -> $Destination" }
}

# 会话文件是追加写入的 zstd 帧；DSH 运行时只复制 2 分钟未变更的文件，
# 避免把正在写入的最后一帧复制成半截。
# 目标文件比源文件新时一律跳过：另一台机器 Push 过来的新内容不会被这台机器的旧状态覆盖。
function Copy-Sessions([string]$Source, [string]$Destination) {
    if (-not (Test-Path -LiteralPath $Source)) { return }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    $running = Test-DshRunning
    if (-not $running) {
        Copy-Tree $Source $Destination
        return
    }
    $cutoff = (Get-Date).AddMinutes(-2)
    $copied = 0
    $skippedRecent = 0
    $skippedNewer = 0
    foreach ($file in Get-ChildItem -LiteralPath $Source -Recurse -File) {
        if ($running -and $file.LastWriteTime -gt $cutoff) { $skippedRecent++; continue }
        $rel = $file.FullName.Substring($Source.Length).TrimStart('\')
        $target = Join-Path $Destination $rel
        if (Test-Path -LiteralPath $target) {
            $existing = Get-Item -LiteralPath $target
            if ($existing.LastWriteTime -gt $file.LastWriteTime.AddSeconds(1)) { $skippedNewer++; continue }
            if ($existing.Length -eq $file.Length -and $existing.LastWriteTime -eq $file.LastWriteTime) { continue }
        }
        New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination $target -Force
        $copied++
    }
    Write-Log "复制 $copied 个；跳过近期 $skippedRecent 个；跳过远端更新 $skippedNewer 个"
}

function Copy-FileIfExists([string]$Source, [string]$Destination) {
    if (Test-Path -LiteralPath $Source) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $Destination) -Force | Out-Null
        Copy-Item -LiteralPath $Source -Destination $Destination -Force
    }
}

# 仅用于 Push：目标端已经有更新的版本时不要覆盖。
function Copy-FileIfNewer([string]$Source, [string]$Destination) {
    if (-not (Test-Path -LiteralPath $Source)) { return }
    if (Test-Path -LiteralPath $Destination) {
        $src = Get-Item -LiteralPath $Source
        $dst = Get-Item -LiteralPath $Destination
        if ($dst.LastWriteTime -gt $src.LastWriteTime.AddSeconds(1)) { return }
    }
    Copy-FileIfExists $Source $Destination
}

function Backup-LocalConfig {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backup = Join-Path $Dsh ".dshkit-backup-$stamp"
    New-Item -ItemType Directory -Path $backup -Force | Out-Null
    Copy-FileIfExists (Join-Path $Dsh 'storages\workspace.json') (Join-Path $backup 'workspace.json')
    Copy-FileIfExists (Join-Path $Dsh 'workspace-groups.yaml') (Join-Path $backup 'workspace-groups.yaml')
    Copy-FileIfExists (Join-Path $Dsh 'workspace-groups.tabs.json') (Join-Path $backup 'workspace-groups.tabs.json')
    foreach ($name in $ProfileFiles) {
        Copy-FileIfExists (Join-Path $ProfileDir $name) (Join-Path $backup $name)
    }
    return $backup
}

function Pull-State {
    if ((Test-DshRunning) -and -not $Force) {
        throw 'DSH 正在运行，Pull 会覆盖会话文件。请先退出 DSH，或使用 -Force（不推荐）。'
    }
    Acquire-Lock
    try {
        $backup = Backup-LocalConfig
        Write-Log "本地配置备份: $backup"

        Copy-Sessions (Join-Path $Root 'sessions') (Join-Path $Dsh 'sessions')
        Copy-Sessions (Join-Path $Root 'storages\session_projcache') (Join-Path $Dsh 'storages\session_projcache')
        Copy-Tree (Join-Path $Root 'attachments') (Join-Path $Dsh 'attachments')
        Copy-Tree (Join-Path $Root 'plugins') (Join-Path $Dsh 'plugins')

        Copy-FileIfExists (Join-Path $Root 'state\workspace.json') (Join-Path $Dsh 'storages\workspace.json')
        Copy-FileIfExists (Join-Path $Root 'workspace-groups.yaml') (Join-Path $Dsh 'workspace-groups.yaml')
        Copy-FileIfExists (Join-Path $Root 'workspace-groups.tabs.json') (Join-Path $Dsh 'workspace-groups.tabs.json')
        Copy-FileIfExists (Join-Path $Root 'codex-sync.json') (Join-Path $Dsh 'codex-sync.json')

        foreach ($name in $ProfileFiles) {
            Copy-FileIfExists (Join-Path $Root "profiles\$DshProfile\$name") (Join-Path $ProfileDir $name)
        }

        Write-Log 'Pull 完成'
    } catch {
        Release-Lock
        throw
    }
}

function Push-State {
    if (Test-DshRunning) {
        throw 'DSH 正在运行，活动会话仍在写入；本次 Push 已拒绝。请先正常退出 DSH，再运行 Push（否则会漏掉最新内容）。'
    }
    $lock = Read-Lock
    if (-not $lock -or $lock.machine -ne $env:COMPUTERNAME) {
        Acquire-Lock
    }
    try {
        Copy-Sessions (Join-Path $Dsh 'sessions') (Join-Path $Root 'sessions')
        Copy-Sessions (Join-Path $Dsh 'storages\session_projcache') (Join-Path $Root 'storages\session_projcache')
        Copy-Tree (Join-Path $Dsh 'attachments') (Join-Path $Root 'attachments')
        Copy-Tree (Join-Path $Dsh 'plugins') (Join-Path $Root 'plugins')

        Copy-FileIfNewer (Join-Path $Dsh 'storages\workspace.json') (Join-Path $Root 'state\workspace.json')
        Copy-FileIfNewer (Join-Path $Dsh 'workspace-groups.yaml') (Join-Path $Root 'workspace-groups.yaml')
        Copy-FileIfNewer (Join-Path $Dsh 'workspace-groups.tabs.json') (Join-Path $Root 'workspace-groups.tabs.json')
        Copy-FileIfNewer (Join-Path $Dsh 'codex-sync.json') (Join-Path $Root 'codex-sync.json')

        foreach ($name in $ProfileFiles) {
            Copy-FileIfExists (Join-Path $ProfileDir $name) (Join-Path $Root "profiles\$DshProfile\$name")
        }

        New-Item -ItemType Directory -Path (Join-Path $Root 'state') -Force | Out-Null
        @{ machine = $env:COMPUTERNAME; at = (Get-Date).ToString('o'); pid = $PID } |
            ConvertTo-Json | Set-Content -LiteralPath (Join-Path $Root 'state\last-push.json') -Encoding UTF8
        Write-Log 'Push 完成'
    } finally {
        Release-Lock
    }
}

switch ($Action) {
    'Pull' { Pull-State }
    'Push' { Push-State }
    'Heartbeat' { Update-Heartbeat; Write-Log '心跳已更新' }
    'Unlock' {
        if ($Force) {
            Remove-Item -LiteralPath $LockPath -Force -ErrorAction SilentlyContinue
            Write-Log '已强制释放锁（-Force）'
        } else {
            Release-Lock
            Write-Log '已释放本机锁'
        }
    }
    'Status' {
        Write-Host "DshKit $script:Version"
        Write-Host "KitRoot: $Root"
        Write-Host "DshHome: $Dsh"
        $lock = Read-Lock
        if ($lock) {
            $age = Get-LockAge $lock
            Write-Host "锁: $($lock.machine)（心跳 $([math]::Round($age.TotalMinutes,1)) 分钟前）"
        } else { Write-Host '锁: 无' }
        if (Test-Path -LiteralPath (Join-Path $Root 'state\last-push.json')) {
            Get-Content -LiteralPath (Join-Path $Root 'state\last-push.json') -Raw -Encoding UTF8
        }
        $remote = @(Get-ChildItem -LiteralPath (Join-Path $Root 'sessions') -Recurse -File -ErrorAction SilentlyContinue).Count
        $local = @(Get-ChildItem -LiteralPath (Join-Path $Dsh 'sessions') -Recurse -File -ErrorAction SilentlyContinue).Count
        Write-Host "sessions: local=$local remote=$remote"
        Write-Host "DSH 运行中: $(Test-DshRunning)"
    }
    'Version' { Write-Host "DshKit $script:Version" }
}

# robocopy returns 1..7 on success; do not leak that to the caller's exit code.
$global:LASTEXITCODE = 0
