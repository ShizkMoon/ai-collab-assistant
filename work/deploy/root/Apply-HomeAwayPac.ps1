$ErrorActionPreference = 'Stop'
$taskGui = Get-Process -Name 'clash-verge' -ErrorAction Stop
$taskExe = $taskGui[0].Path
if ($taskExe -ne 'C:\Program Files\Clash Verge Ninja\clash-verge.exe') { throw 'Unexpected GUI executable' }
$taskGui | Stop-Process
$taskGui | Wait-Process -Timeout 10 -ErrorAction SilentlyContinue
try {
    & uv run --no-project --with PyYAML python -X utf8 (Join-Path $PSScriptRoot 'apply_home_pac.py')
    if ($LASTEXITCODE -ne 0) { throw 'PAC update failed' }
} finally {
    Start-Process -FilePath $taskExe -WindowStyle Hidden
}
