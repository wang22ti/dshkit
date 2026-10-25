# 安装/修复两个固定命名的开始菜单入口；重复运行不会新增第三个入口。
$ErrorActionPreference = 'Stop'
$Root = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$Wrapper = Join-Path $Root 'Start-DshSynced.vbs'

$Config = @{}
$ConfigPath = Join-Path $Root 'config.json'
if (Test-Path -LiteralPath $ConfigPath) {
    try {
        $loaded = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($property in $loaded.PSObject.Properties) { $Config[$property.Name] = $property.Value }
    } catch { }
}
$Exe = if ($Config.ContainsKey('dshExe') -and $Config['dshExe']) { $Config['dshExe'] } else { Join-Path $env:LOCALAPPDATA 'Programs\DeepSeek Harness\DeepSeek Harness.exe' }
$ScriptHost = Join-Path $env:WINDIR 'System32\wscript.exe'

foreach ($required in @($Wrapper, $Exe, $ScriptHost)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "找不到 $required" }
}

$startDir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
New-Item -ItemType Directory -Path $startDir -Force | Out-Null
$ws = New-Object -ComObject WScript.Shell

# 默认的「DeepSeek Harness」指向同步启动器；原生入口单独放在「(原生启动)」。
$synced = $ws.CreateShortcut((Join-Path $startDir 'DeepSeek Harness.lnk'))
$synced.TargetPath = $ScriptHost
$synced.Arguments = '"' + $Wrapper + '"'
$synced.WorkingDirectory = $Root
$synced.WindowStyle = 1
$synced.IconLocation = "$Exe,0"
$synced.Description = 'DSH 同步启动：启动前 Pull，退出后 Push'
$synced.Save()

$native = $ws.CreateShortcut((Join-Path $startDir 'DeepSeek Harness (原生启动).lnk'))
$native.TargetPath = $Exe
$native.Arguments = ''
$native.WorkingDirectory = Split-Path -Parent $Exe
$native.WindowStyle = 1
$native.IconLocation = "$Exe,0"
$native.Description = '原生 DeepSeek Harness，不执行 DshKit 同步'
$native.Save()

# 旧入口移入机器本地备份，不再出现在开始菜单或桌面。
$legacy = @(
    (Join-Path $startDir 'DSH - DshKit.lnk'),
    (Join-Path $startDir 'DeepSeek Harness (直接启动).lnk')
)
$desktop = [Environment]::GetFolderPath('Desktop')
if ($desktop) {
    $legacy += (Join-Path $desktop 'DSH 同步启动.lnk')
    $legacy += (Join-Path $desktop 'DSH 同步上传.lnk')
}
foreach ($path in $legacy) {
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $backupDir = Join-Path $env:LOCALAPPDATA 'DshKit\shortcut-backups'
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        $backupName = [IO.Path]::GetFileNameWithoutExtension($path) + '-' + [guid]::NewGuid().ToString('N') + '.lnk'
        Move-Item -LiteralPath $path -Destination (Join-Path $backupDir $backupName)
    }
}

Write-Host '开始菜单已保留两个入口：'
Write-Host '  DeepSeek Harness             -> 同步启动，自动 Pull/Push'
Write-Host '  DeepSeek Harness (原生启动)  -> 原生启动，不同步'
Write-Host '日常请用「DeepSeek Harness」；需要绕过同步时才用「(原生启动)」。'
