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
Assert-True (($versionOut -join "`n") -match 'DshKit 1\.0\.5') 'version output is 1.0.5'

$temp = Join-Path $env:TEMP ('dshkit-test-' + [guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path (Join-Path $temp 'sessions') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $temp 'storages') -Force | Out-Null
    $statusOut = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $sync -Action Status -KitRoot $temp -DshHome $temp 2>&1
    Assert-True ($LASTEXITCODE -eq 0) "Status exits 0 (exit $LASTEXITCODE)"
    Assert-True (($statusOut -join "`n") -match 'DshKit 1\.0\.5') 'Status prints version'
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

$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (Test-Path -LiteralPath $csc) {
    $root3 = Join-Path $env:TEMP ('dshkit-launcher-' + [guid]::NewGuid().ToString('N'))
    $kit3 = Join-Path $root3 'kit'
    $dsh3 = Join-Path $root3 'dsh'
    $fake = Join-Path $root3 'FakeDsh.exe'
    try {
        New-Item -ItemType Directory -Path $kit3 -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $dsh3 'profiles\desktop\node_modules') -Force | Out-Null
        Copy-Item -Path (Join-Path $repo 'src\*') -Destination $kit3 -Force
        @{ version = '1.0.5'; kitRoot = $kit3; dshHome = $dsh3; dshExe = $fake; profile = 'desktop'; processName = 'FakeDsh' } |
            ConvertTo-Json | Set-Content -LiteralPath (Join-Path $kit3 'config.json') -Encoding UTF8
        $cs = Join-Path $root3 'fake.cs'
        'public class FakeDsh { public static void Main() { System.Threading.Thread.Sleep(3000); } }' | Set-Content -LiteralPath $cs -Encoding ASCII
        & $csc /nologo /target:exe /out:$fake $cs | Out-Null
        Assert-True (Test-Path -LiteralPath $fake) 'launcher test fake executable compiled'
        $launcherOut = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $kit3 'Start-DshSynced.ps1') 2>&1
        Assert-True ($LASTEXITCODE -eq 0) "launcher exits 0 (exit $LASTEXITCODE)"
        Assert-True (Test-Path -LiteralPath (Join-Path $kit3 'state\last-push.json')) 'launcher pushes after fake DSH exits'
        Assert-True (($launcherOut -join "`n") -match 'Push after exit') 'launcher reaches Push stage'
    } finally {
        Remove-Item -LiteralPath $root3 -Recurse -Force -ErrorAction SilentlyContinue
    }
} else {
    Write-Host 'skip launcher test: csc.exe not found'
}

if ($failures -gt 0) {
    Write-Host "$failures failure(s)"
    exit 1
}
Write-Host 'all tests passed'
exit 0
