# DshKit installer for Windows PowerShell 5.1+
param(
    [string]$KitRoot,
    [string]$DshHome,
    [string]$DshExe,
    [switch]$InitialPush,
    [switch]$InitialPull,
    [switch]$NoShortcuts,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$RepoRoot = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$Source = Join-Path $RepoRoot 'src'
if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
    throw "找不到 src 目录：$Source。请从完整仓库或 release zip 运行安装脚本。"
}

if (-not $KitRoot) {
    $oneDrive = $env:OneDrive
    if (-not $oneDrive) { $oneDrive = Join-Path $env:USERPROFILE 'OneDrive' }
    $KitRoot = Join-Path $oneDrive 'DshKit'
}
if (-not $DshHome) { $DshHome = Join-Path $env:USERPROFILE '.dsh' }
if (-not $DshExe) { $DshExe = Join-Path $env:LOCALAPPDATA 'Programs\DeepSeek Harness\DeepSeek Harness.exe' }

if (-not (Test-Path -LiteralPath $DshExe -PathType Leaf)) {
    throw "找不到 DSH：$DshExe。请先安装 DeepSeek Harness，或用 -DshExe 指定路径。"
}
if (($InitialPush -or $InitialPull) -and (Get-Process -Name 'DeepSeek Harness' -ErrorAction SilentlyContinue)) {
    throw 'DSH 正在运行。首次 Push/Pull 前请先完全退出 DSH。'
}

Write-Host "DshKit 安装到: $KitRoot"
New-Item -ItemType Directory -Path $KitRoot -Force | Out-Null
New-Item -ItemType Directory -Path $DshHome -Force | Out-Null

foreach ($dir in @('sessions', 'attachments', 'plugins', 'profiles', 'storages\session_projcache', 'state', 'skills')) {
    New-Item -ItemType Directory -Path (Join-Path $KitRoot $dir) -Force | Out-Null
}

# 只覆盖程序文件，不碰会话、workspace 和锁。
Get-ChildItem -LiteralPath $Source -File | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $KitRoot $_.Name) -Force
}

$ConfigPath = Join-Path $KitRoot 'config.json'
if (-not (Test-Path -LiteralPath $ConfigPath) -or $Force) {
    [ordered]@{
        version     = '1.0.3'
        kitRoot     = $KitRoot
        dshHome     = $DshHome
        dshExe      = $DshExe
        profile     = 'desktop'
        processName = 'DeepSeek Harness'
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $ConfigPath -Encoding UTF8
    Write-Host "已写入配置: $ConfigPath"
} else {
    Write-Host "保留已有配置: $ConfigPath"
}

# DSH 的技能目录指向 DshKit\skills；已存在时绝不覆盖。
$skillsTarget = Join-Path $KitRoot 'skills'
$skillsLink = Join-Path $DshHome 'skills'
if (-not (Test-Path -LiteralPath $skillsLink)) {
    New-Item -ItemType Junction -Path $skillsLink -Target $skillsTarget | Out-Null
    Write-Host "已建立技能目录 Junction: $skillsLink -> $skillsTarget"
} else {
    $item = Get-Item -LiteralPath $skillsLink -Force
    if ($item.LinkType -eq 'Junction') {
        Write-Host "技能目录已存在: $skillsLink -> $($item.Target)"
    } else {
        Write-Warning "技能目录已存在且不是 Junction，未改动: $skillsLink"
    }
}

if (-not $NoShortcuts) {
    & (Join-Path $KitRoot 'Install-DshKitShortcuts.ps1')
}

$sync = Join-Path $KitRoot 'Sync-DshKit.ps1'
if ($InitialPush -and $InitialPull) {
    throw '不能同时使用 -InitialPush 和 -InitialPull。'
}
if ($InitialPush) {
    Write-Host '=== 首次上传本机 DSH 状态 ==='
    & $sync -Action Push -KitRoot $KitRoot -DshHome $DshHome -Force
}
if ($InitialPull) {
    Write-Host '=== 首次从 DshKit 下载状态 ==='
    & $sync -Action Pull -KitRoot $KitRoot -DshHome $DshHome -Force
}

Write-Host ''
Write-Host '安装完成。'
Write-Host '开始菜单入口：'
Write-Host '  DeepSeek Harness             同步启动（启动前 Pull，退出后 Push）'
Write-Host '  DeepSeek Harness (原生启动)  原生启动，不执行同步'
Write-Host ''
Write-Host '第一台机器（已有 DSH 数据）建议：'
Write-Host "  .\install.ps1 -InitialPush"
Write-Host '第二台机器（从 DshKit 取数据）建议：'
Write-Host "  .\install.ps1 -InitialPull"
Write-Host '之后统一使用「DSH - DshKit」入口。'
