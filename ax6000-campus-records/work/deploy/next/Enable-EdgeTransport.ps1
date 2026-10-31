$ErrorActionPreference = 'Stop'
$target = 'HKCU:\SOFTWARE\Policies\Microsoft\Edge'
$names = @('QuicAllowed', 'EncryptedClientHelloEnabled')
$evidencePath = Join-Path $PSScriptRoot 'edge-policy-manual-applied.json'
$backupPath = Join-Path $PSScriptRoot 'edge-policy-manual-before.json'
if ((Test-Path -LiteralPath $evidencePath) -or (Test-Path -LiteralPath $backupPath)) { throw 'Existing manual-run evidence prevents duplicate mutation; review or restore it first.' }
$keyExisted = Test-Path -LiteralPath $target
$before = @{}
if ($keyExisted) {
    $key = Get-Item -LiteralPath $target
    foreach ($name in $names) {
        if ($key.GetValueNames() -contains $name) { $before[$name] = @{existed=$true; kind=$key.GetValueKind($name).ToString(); value=$key.GetValue($name)} }
        else { $before[$name] = @{existed=$false} }
    }
} else { foreach ($name in $names) { $before[$name] = @{existed=$false} } }
$backup = @{key=$target; keyExisted=$keyExisted; before=$before; time=(Get-Date -Format o)}
[IO.File]::WriteAllText($backupPath, ($backup | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
$changed = [Collections.Generic.List[string]]::new()
try {
    New-Item -Path $target -Force | Out-Null
    foreach ($name in $names) {
        New-ItemProperty -LiteralPath $target -Name $name -PropertyType DWord -Value 1 -Force | Out-Null
        $changed.Add($name)
    }
    $readback = @{}
    $key = Get-Item -LiteralPath $target
    foreach ($name in $names) {
        $value = Get-ItemPropertyValue -LiteralPath $target -Name $name
        if (($value -ne 1) -or ($key.GetValueKind($name).ToString() -ne 'DWord')) { throw "Policy readback failed: $name" }
        $readback[$name] = $value
    }
    $result = @{key=$target; values=$readback; before=$before; backupFile=[IO.Path]::GetFileName($backupPath); dnsPoliciesChanged=$false; pacChanged=$false; browserForcedRestart=$false; quicPolicyFullRestartRequired=$true; actualConnectionVerified=$false}
    [IO.File]::WriteAllText($evidencePath, ($result | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
    $result | ConvertTo-Json -Depth 6
} catch {
    $initialError = $_.Exception.Message
    $rollbackErrors = [Collections.Generic.List[string]]::new()
    foreach ($name in $changed) {
        try {
            $old = $before[$name]
            if ($old.existed) { New-ItemProperty -LiteralPath $target -Name $name -PropertyType $old.kind -Value $old.value -Force | Out-Null }
            else { Remove-ItemProperty -LiteralPath $target -Name $name -ErrorAction Stop }
        } catch { $rollbackErrors.Add($_.Exception.Message) }
    }
    if (-not $keyExisted -and (Test-Path -LiteralPath $target)) {
        try {
            $key = Get-Item -LiteralPath $target
            if (($key.GetValueNames().Count -eq 0) -and ($key.GetSubKeyNames().Count -eq 0)) { Remove-Item -LiteralPath $target }
        } catch { $rollbackErrors.Add($_.Exception.Message) }
    }
    if ($rollbackErrors.Count -gt 0) { throw "Policy update failed: $initialError. Partial rollback needs review: $($rollbackErrors -join '; ')" }
    throw "Policy update failed; this run's changed values were restored: $initialError"
}
