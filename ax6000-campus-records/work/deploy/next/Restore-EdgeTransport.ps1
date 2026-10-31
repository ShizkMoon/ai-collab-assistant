$ErrorActionPreference = 'Stop'
$backupPath = Join-Path $PSScriptRoot 'edge-policy-manual-before.json'
if (-not (Test-Path -LiteralPath $backupPath)) { throw 'No manual-run snapshot exists; current historical policies require no restoration.' }
$saved = Get-Content -LiteralPath $backupPath -Raw | ConvertFrom-Json -AsHashtable
$target = $saved.key
if ($target -ne 'HKCU:\SOFTWARE\Policies\Microsoft\Edge') { throw 'Unexpected policy target in saved snapshot.' }
foreach ($name in @('QuicAllowed', 'EncryptedClientHelloEnabled')) {
    $old = $saved.before[$name]
    if (Test-Path -LiteralPath $target) {
        $key = Get-Item -LiteralPath $target
        if ($key.GetValueNames() -contains $name) {
            if (($key.GetValue($name) -ne 1) -or ($key.GetValueKind($name).ToString() -ne 'DWord')) { throw "Policy changed after the manual run; preserve and review: $name" }
        }
    }
}
foreach ($name in @('QuicAllowed', 'EncryptedClientHelloEnabled')) {
    $old = $saved.before[$name]
    if ($old.existed) {
        if (-not (Test-Path -LiteralPath $target)) { New-Item -Path $target -Force | Out-Null }
        New-ItemProperty -LiteralPath $target -Name $name -PropertyType $old.kind -Value $old.value -Force | Out-Null
    } elseif (Test-Path -LiteralPath $target) {
        $key = Get-Item -LiteralPath $target
        if ($key.GetValueNames() -contains $name) { Remove-ItemProperty -LiteralPath $target -Name $name -ErrorAction Stop }
    }
}
if (-not $saved.keyExisted -and (Test-Path -LiteralPath $target)) {
    $key = Get-Item -LiteralPath $target
    if ($key.GetValueNames().Count -eq 0 -and $key.GetSubKeyNames().Count -eq 0) { Remove-Item -LiteralPath $target }
}
[pscustomobject]@{restored=$true; key=$target; unrelatedValuesPreserved=$true}
