# 等 DSH 完全退出后补一次 Push。
# 正常从「DSH 同步启动」进入时不需要它；这里用于当前这次“改快捷方式之前就已打开”的 DSH。
$Root = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$Sync = Join-Path $Root 'Sync-DshKit.ps1'
$StateDir = Join-Path $env:LOCALAPPDATA 'DshKit'
New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
$Log = Join-Path $StateDir 'exit-push.log'

$ProcessName = 'DeepSeek Harness'
$ConfigPath = Join-Path $Root 'config.json'
if (Test-Path -LiteralPath $ConfigPath) {
    try {
        $cfg = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($cfg.processName) { $ProcessName = $cfg.processName }
    } catch { }
}

function Test-DshRunning {
    return @(Get-Process -Name $ProcessName -ErrorAction SilentlyContinue).Count -gt 0
}

while (Test-DshRunning) { Start-Sleep -Seconds 5 }
Start-Sleep -Seconds 5
try {
    & $Sync -Action Push *>> $Log
} catch {
    "Push failed: $($_.Exception.Message)" | Add-Content -LiteralPath $Log -Encoding UTF8
}
