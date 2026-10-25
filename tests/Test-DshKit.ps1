$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$failures = 0

function Assert-True([bool]$Condition, [string]$Message) {
    if ($Condition) {
        Write-Host "ok   $Message"
    } else {
        Write-Host "FAIL $Message"
        $script:failures++
    }
}

function Test-TextFile([string]$Path, [bool]$RequireBom) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    $text = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
    $bom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $lf = ([regex]::Matches($text, "`n")).Count
    $crlf = ([regex]::Matches($text, "`r`n")).Count
    Assert-True ($bom -eq $RequireBom) "$Path BOM expected=$RequireBom"
    Assert-True ($lf -eq $crlf) "$Path has CRLF line endings"
}

$ps1 = Get-ChildItem -LiteralPath $repo -Recurse -File -Filter '*.ps1'
$cmd = Get-ChildItem -LiteralPath $repo -Recurse -File -Filter '*.cmd'
$vbs = Get-ChildItem -LiteralPath $repo -Recurse -File -Filter '*.vbs'

foreach ($file in $ps1) {
    Test-TextFile $file.FullName $true
    try {
        [void][scriptblock]::Create([IO.File]::ReadAllText($file.FullName, [Text.Encoding]::UTF8))
        Assert-True $true "$($file.Name) parses"
    } catch {
        Assert-True $false "$($file.Name) parses: $($_.Exception.Message)"
    }
}
foreach ($file in $cmd + $vbs) {
    Test-TextFile $file.FullName $false
    $bytes = [IO.File]::ReadAllBytes($file.FullName)
    Assert-True (@($bytes | Where-Object { $_ -gt 127 }).Count -eq 0) "$($file.Name) is ASCII"
}

$sync = Join-Path $repo 'src\Sync-DshKit.ps1'
$versionOut = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $sync -Action Version 2>&1
Assert-True ($LASTEXITCODE -eq 0) "Windows PowerShell 5.1 runs Sync-DshKit.ps1 (exit $LASTEXITCODE)"
Assert-True (($versionOut -join "`n") -match 'DshKit 1\.0\.3') 'version output is 1.0.3'

$temp = Join-Path $env:TEMP ('dshkit-test-' + [guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path (Join-Path $temp 'sessions') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $temp 'storages') -Force | Out-Null
    $statusOut = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $sync -Action Status -KitRoot $temp -DshHome $temp 2>&1
    Assert-True ($LASTEXITCODE -eq 0) "Status exits 0 (exit $LASTEXITCODE)"
    Assert-True (($statusOut -join "`n") -match 'DshKit 1\.0\.3') 'Status prints version'
} finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}

$root2 = Join-Path $env:TEMP ('dshkit-push-' + [guid]::NewGuid().ToString('N'))
$dsh2 = Join-Path $root2 'dsh'
$kit2 = Join-Path $root2 'kit'
$rel = '--test--\s\session.v4.jsonl.zstd'
$srcFile = Join-Path $dsh2 "sessions\$rel"
$dstFile = Join-Path $kit2 "sessions\$rel"
try {
    New-Item -ItemType Directory -Path (Split-Path -Parent $srcFile) -Force | Out-Null
    New-Item -ItemType Directory -Path (Split-Path -Parent $dstFile) -Force | Out-Null
    @{ processName = 'DshKitTestNoSuchProcess' } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $kit2 'config.json') -Encoding UTF8
    'NEW' | Set-Content -LiteralPath $srcFile -Encoding ASCII
    'OLD' | Set-Content -LiteralPath $dstFile -Encoding ASCII
    (Get-Item $srcFile).LastWriteTime = (Get-Date).AddHours(-1)
    (Get-Item $dstFile).LastWriteTime = (Get-Date).AddHours(1)
    & $sync -Action Push -KitRoot $kit2 -DshHome $dsh2 -Force | Out-Null
    Assert-True ((Get-Content -LiteralPath $dstFile -Raw).Trim() -eq 'OLD') 'Push does not overwrite a newer target'

    $rel2 = '--test-copy--\s\session.v4.jsonl.zstd'
    $srcFile2 = Join-Path $dsh2 "sessions\$rel2"
    $dstFile2 = Join-Path $kit2 "sessions\$rel2"
    New-Item -ItemType Directory -Path (Split-Path -Parent $srcFile2) -Force | Out-Null
    'COPY' | Set-Content -LiteralPath $srcFile2 -Encoding ASCII
    & $sync -Action Push -KitRoot $kit2 -DshHome $dsh2 -Force | Out-Null
    Assert-True ((Get-Content -LiteralPath $dstFile2 -Raw).Trim() -eq 'COPY') 'Push copies a new session file'
} finally {
    Remove-Item -LiteralPath $root2 -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures -gt 0) {
    Write-Host "$failures failure(s)"
    exit 1
}
Write-Host 'all tests passed'
exit 0
