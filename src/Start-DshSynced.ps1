param([switch]$NoPush)

$ErrorActionPreference = 'Stop'
$Root = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$Sync = Join-Path $Root 'Sync-DshKit.ps1'

$Config = @{}
$ConfigPath = Join-Path $Root 'config.json'
if (Test-Path -LiteralPath $ConfigPath) {
    try {
        $loaded = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($property in $loaded.PSObject.Properties) { $Config[$property.Name] = $property.Value }
    } catch { }
}

$DshHome = if ($Config.ContainsKey('dshHome') -and $Config['dshHome']) { $Config['dshHome'] } else { Join-Path $env:USERPROFILE '.dsh' }
$DshProfile = if ($Config.ContainsKey('profile') -and $Config['profile']) { $Config['profile'] } else { 'desktop' }
$DshProcessName = if ($Config.ContainsKey('processName') -and $Config['processName']) { $Config['processName'] } else { 'DeepSeek Harness' }
$Exe = if ($Config.ContainsKey('dshExe') -and $Config['dshExe']) { $Config['dshExe'] } else { Join-Path $env:LOCALAPPDATA 'Programs\DeepSeek Harness\DeepSeek Harness.exe' }
$Cli = Join-Path (Split-Path -Parent $Exe) 'resources\runtime\cli\bin\dsh.cmd'
$ProfileDir = Join-Path $DshHome "profiles\$DshProfile"

function Test-DshRunning {
    return @(Get-Process -Name $DshProcessName -ErrorAction SilentlyContinue).Count -gt 0
}

function Invoke-Sync([string]$SyncAction) {
    $syncArgs = @('-Action', $SyncAction, '-KitRoot', $Root)
    if ($DshHome) { $syncArgs += @('-DshHome', $DshHome) }
    if ($DshProfile) { $syncArgs += @('-Profile', $DshProfile) }
    & $Sync @syncArgs
}

if (-not (Test-Path -LiteralPath $Exe)) {
    Write-Host "DSH executable not found: $Exe" -ForegroundColor Red
    exit 1
}

# Already running: focus it; do not Pull, wait, or Push.
if (Test-DshRunning) {
    Write-Host 'DSH already running; skip Pull/Push.'
    Start-Process -FilePath $Exe -WorkingDirectory $env:USERPROFILE
    exit 0
}

Write-Host '=== Pull before launch ==='
try {
    Invoke-Sync Pull
} catch {
    Write-Host "Pull failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host '=== Launch DSH ==='
$PackageJson = Join-Path $ProfileDir 'package.json'
$InstallMarker = Join-Path $ProfileDir '.dshkit-installed.json'
$needInstall = -not (Test-Path -LiteralPath (Join-Path $ProfileDir 'node_modules'))
if (-not $needInstall -and (Test-Path -LiteralPath $PackageJson)) {
    $hash = (Get-FileHash -LiteralPath $PackageJson -Algorithm SHA256).Hash
    $installed = $null
    if (Test-Path -LiteralPath $InstallMarker) {
        try { $installed = (Get-Content -LiteralPath $InstallMarker -Raw | ConvertFrom-Json).packageHash } catch { }
    }
    if ($installed -ne $hash) { $needInstall = $true }
}
if ($needInstall) {
    if (-not (Test-Path -LiteralPath $Cli)) {
        Write-Host "DSH CLI not found: $Cli" -ForegroundColor Red
        Invoke-Sync Unlock
        exit 1
    }
    Write-Host 'Plugin manifest changed or first run: installing DSH plugin dependencies...'
    $installLog = (& $Cli plugin --profile $DshProfile install 2>&1 | Out-String)
    Write-Host $installLog
    # dsh.cmd's Electron launcher can exit 1 on crashpad noise even when pnpm succeeds.
    if ($installLog -notmatch 'Done in|Already up to date') {
        Write-Host 'Plugin dependency install failed; check the network and retry.' -ForegroundColor Red
        Invoke-Sync Unlock
        exit 1
    }
    if (Test-Path -LiteralPath $PackageJson) {
        @{ packageHash = (Get-FileHash -LiteralPath $PackageJson -Algorithm SHA256).Hash; at = (Get-Date).ToString('o') } |
            ConvertTo-Json | Set-Content -LiteralPath $InstallMarker -Encoding UTF8
    }
}
Start-Process -FilePath $Exe -WorkingDirectory $env:USERPROFILE
$started = $false
for ($i = 0; $i -lt 15; $i++) {
    Start-Sleep -Seconds 1
    if (Test-DshRunning) { $started = $true; break }
}
if (-not $started) {
    Write-Host 'DSH did not start; skip Push to avoid saving a half-started state.' -ForegroundColor Red
    Invoke-Sync Unlock
    exit 1
}

Write-Host '=== Wait for DSH to exit (auto Push afterwards) ==='
Invoke-Sync Heartbeat
$ticks = 0
while (Test-DshRunning) {
    Start-Sleep -Seconds 5
    $ticks++
    if ($ticks % 60 -eq 0) { Invoke-Sync Heartbeat }
}
Start-Sleep -Seconds 3

if ($NoPush) {
    Write-Host '-NoPush given; skip Push.'
    exit 0
}

Write-Host '=== Push after exit ==='
try {
    Invoke-Sync Push
} catch {
    Write-Host "Push failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
Write-Host 'Done.'
