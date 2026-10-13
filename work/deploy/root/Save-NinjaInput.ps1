$ErrorActionPreference = 'Stop'
$workspacePath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path
$privatePath = Join-Path $workspacePath 'work/deploy/private'
if (-not (Test-Path -LiteralPath $privatePath)) { New-Item -ItemType Directory -Path $privatePath | Out-Null }
$currentAcl = Get-Acl -LiteralPath $privatePath
if (-not $currentAcl.AreAccessRulesProtected) {
    $sourceAcl = Get-Acl -LiteralPath (Join-Path $workspacePath 'work/ax6000/private')
    Set-Acl -LiteralPath $privatePath -AclObject $sourceAcl
}
$sessionPath = 'C:\Users\Shizuku\.codex\sessions\2026\10\12\rollout-2026-10-12T11-16-07-01a12e1c-47ab-7eb1-a047-a1f2110d9045.jsonl'
$subscriptionValue = $null
$sessionStream = [System.IO.FileStream]::new($sessionPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
$sessionReader = [System.IO.StreamReader]::new($sessionStream)
try {
while ($null -ne ($sessionLine = $sessionReader.ReadLine())) {
    $entry = $sessionLine | ConvertFrom-Json
    if ($entry.type -eq 'response_item' -and $entry.payload.type -eq 'message' -and $entry.payload.role -eq 'user') {
        foreach ($part in $entry.payload.content) {
            if ($part.type -eq 'input_text' -and $part.text -match '可以开始执行') {
                $matchValue = [regex]::Match($part.text, 'https://45\.137\.181\.152/api/getData/Authorize\?token=[REDACTED]')
                if ($matchValue.Success) { $subscriptionValue = $matchValue.Value }
            }
        }
    }
}
} finally { $sessionReader.Dispose(); $sessionStream.Dispose() }
if (-not $subscriptionValue) { throw 'No task-authorized subscription was found; no values printed.' }
$secureValue = ConvertTo-SecureString -String $subscriptionValue -AsPlainText -Force
$encryptedValue = ConvertFrom-SecureString -SecureString $secureValue
$targetPath = Join-Path $privatePath 'ninja-subscription-url.dpapi'
[System.IO.File]::WriteAllText($targetPath, $encryptedValue, [System.Text.UTF8Encoding]::new($false))
$roundTrip = ConvertTo-SecureString -String ([System.IO.File]::ReadAllText($targetPath))
$plainRoundTrip = [System.Net.NetworkCredential]::new('', $roundTrip).Password
if ($plainRoundTrip -cne $subscriptionValue) { throw 'Private subscription round trip failed.' }
Write-Output 'Private subscription saved with current-user encryption and restricted directory access; value not printed.'
