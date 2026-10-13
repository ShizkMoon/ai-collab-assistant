[CmdletBinding()]
param([ValidateSet('Apply','Restore')][string]$Action = 'Apply')

$ErrorActionPreference = 'Stop'
$backupPath = Join-Path $PSScriptRoot 'private-configuration\ethernet-before-router-optimization.json'
$resultPath = Join-Path $PSScriptRoot 'ethernet-last-action.json'
$targetGuid = [guid]'1F42C76B-E849-453F-8608-CAA586E00A17'
$result = [ordered]@{ Action = $Action; Time = [DateTimeOffset]::Now.ToString('o'); Passed = $false }

try {
    $principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
        throw '本操作需要 Windows 管理员权限。'
    }
    $adapter = @(Get-NetAdapter -Physical | Where-Object { [guid]$_.InterfaceGuid -eq $targetGuid })
    if ($adapter.Count -ne 1 -or $adapter[0].Status -ne 'Disconnected') {
        throw '目标以太网卡不是唯一且断开的适配器，已停止。'
    }
    $adapterIndex = $adapter[0].ifIndex
    $beforeInterface = Get-NetIPInterface -InterfaceIndex $adapterIndex -AddressFamily IPv4
    $beforeAddresses = @(Get-NetIPAddress -InterfaceIndex $adapterIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue)
    $beforeDns = Get-DnsClientServerAddress -InterfaceIndex $adapterIndex -AddressFamily IPv4
    $wifiBefore = @(Get-NetIPInterface -AddressFamily IPv4 | Where-Object { $_.ConnectionState -eq 'Connected' } | Select-Object InterfaceIndex,InterfaceAlias,Dhcp,NlMtu)
    if ($Action -eq 'Apply') {
        $manual = @($beforeAddresses | Where-Object { $_.PrefixOrigin -eq 'Manual' })
        $expected = @('192.168.31.176','192.168.1.2')
        if (@($manual | Where-Object { $_.IPAddress -notin $expected }).Count -gt 0) {
            throw '发现本轮未记录的手动 IPv4 地址，已停止。'
        }
        if (-not (Test-Path -LiteralPath $backupPath)) {
            [ordered]@{
                InterfaceGuid = $targetGuid.ToString(); InterfaceAlias = $adapter[0].Name
                Dhcp = [string]$beforeInterface.Dhcp
                Addresses = @($manual | Select-Object IPAddress,PrefixLength)
                DnsServers = @($beforeDns.ServerAddresses)
            } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $backupPath -Encoding utf8NoBOM
        }
        foreach ($entry in $manual) {
            Remove-NetIPAddress -InterfaceIndex $adapterIndex -IPAddress $entry.IPAddress -Confirm:$false
        }
        Set-NetIPInterface -InterfaceIndex $adapterIndex -AddressFamily IPv4 -Dhcp Enabled
        Set-DnsClientServerAddress -InterfaceIndex $adapterIndex -ResetServerAddresses
    }
    else {
        $saved = Get-Content -LiteralPath $backupPath -Raw | ConvertFrom-Json
        if ([guid]$saved.InterfaceGuid -ne $targetGuid) { throw '恢复记录与目标网卡不一致。' }
        Set-NetIPInterface -InterfaceIndex $adapterIndex -AddressFamily IPv4 -Dhcp Disabled
        foreach ($entry in @($saved.Addresses)) {
            if (-not (Get-NetIPAddress -InterfaceIndex $adapterIndex -IPAddress $entry.IPAddress -ErrorAction SilentlyContinue)) {
                New-NetIPAddress -InterfaceIndex $adapterIndex -IPAddress $entry.IPAddress -PrefixLength $entry.PrefixLength | Out-Null
            }
        }
        if (@($saved.DnsServers).Count) {
            Set-DnsClientServerAddress -InterfaceIndex $adapterIndex -ServerAddresses $saved.DnsServers
        }
        else { Set-DnsClientServerAddress -InterfaceIndex $adapterIndex -ResetServerAddresses }
    }
    $after = Get-NetIPInterface -InterfaceIndex $adapterIndex -AddressFamily IPv4
    $manualAfter = @(Get-NetIPAddress -InterfaceIndex $adapterIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.PrefixOrigin -eq 'Manual' })
    $wifiAfter = @(Get-NetIPInterface -AddressFamily IPv4 | Where-Object { $_.ConnectionState -eq 'Connected' } | Select-Object InterfaceIndex,InterfaceAlias,Dhcp,NlMtu)
    $result.Dhcp = [string]$after.Dhcp
    $result.ManualAddressCount = $manualAfter.Count
    $result.WifiConfigurationUnchanged = ($wifiBefore | ConvertTo-Json -Compress) -eq ($wifiAfter | ConvertTo-Json -Compress)
    $result.LinkConnected = $false
    $result.Passed = if ($Action -eq 'Apply') { $after.Dhcp -eq 'Enabled' -and $manualAfter.Count -eq 0 -and $result.WifiConfigurationUnchanged } else { $true }
    $result.Note = '仅完成断开以太网卡的配置读回；尚未接线取得租约或验证有线流量。'
}
catch { $result.Error = $_.Exception.Message }
finally { $result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $resultPath -Encoding utf8NoBOM }
if (-not $result.Passed) { exit 1 }
