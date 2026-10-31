#Requires -Version 7.0
<#
.SYNOPSIS
默认只读，按当前驱动公开值执行 SMPS 单项试验、独立还原或明确保留。
.NOTES
不请求 UAC，不改执行策略、任务计划、服务、驱动、其他高级属性或直接写注册表。
Trial / Rollback / Accept / 内部 Watchdog 必须已经在管理员 PowerShell 7 中运行。
#>
[CmdletBinding()]
param(
    [ValidateSet('DryRun', 'Trial', 'Rollback', 'Accept', 'Watchdog')]
    [string]$Action = 'DryRun',

    [ValidateNotNullOrEmpty()]
    [string]$AdapterName = 'WLAN',

    [string]$StatePath = (Join-Path $PSScriptRoot 'smps-trial-state.json'),

    [ValidateRange(60, 3600)]
    [int]$RollbackAfterSeconds = 300,

    [switch]$ConfirmAccept,

    # 仅由 Trial 启动的独立进程使用；不是提权或认证凭据。
    [string]$WatchdogToken
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:SmpsError = '未完成 SMPS 操作。'
$script:StateSchema = 1

function Stop-SmpsOperation {
    param([string]$Message)
    $script:SmpsError = $Message
    throw [System.InvalidOperationException]::new($Message)
}

function Test-SameValues {
    param([object[]]$Left, [object[]]$Right)
    if (@($Left).Count -ne @($Right).Count) { return $false }
    for ($valueIndex = 0; $valueIndex -lt @($Left).Count; $valueIndex++) {
        if ([string]$Left[$valueIndex] -cne [string]$Right[$valueIndex]) { return $false }
    }
    return $true
}

function Assert-ExactAdapterName {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name) -or $Name -match '[*?\[\]\r\n]') {
        Stop-SmpsOperation '必须使用单个准确的网卡名称，不能使用通配符。'
    }
}

function Assert-Administrator {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    try {
        $principal = [System.Security.Principal.WindowsPrincipal]::new($identity)
        if (-not $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
            Stop-SmpsOperation '此操作需要已经获授权的管理员 PowerShell 7。脚本没有更改设备，也不会自行触发 UAC。'
        }
    }
    finally { $identity.Dispose() }
}

function Convert-SmpsProperty {
    param([object]$Property)
    # 显式白名单；不保存整个 CIM 对象、设备实例路径、SSID、MAC 或 InterfaceGuid。
    return [pscustomobject][ordered]@{
        Name = [string]$Property.Name
        InterfaceDescription = [string]$Property.InterfaceDescription
        DisplayName = [string]$Property.DisplayName
        DisplayValue = [string]$Property.DisplayValue
        RegistryKeyword = [string]$Property.RegistryKeyword
        RegistryValue = @($Property.RegistryValue | ForEach-Object { [string]$_ })
        ValidDisplayValues = @($Property.ValidDisplayValues | ForEach-Object { [string]$_ })
        ValidRegistryValues = @($Property.ValidRegistryValues | ForEach-Object { [string]$_ })
    }
}

function Test-NoSmpsDisplayValue {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    # 只承认明确的英文 / 本机简体中文显示语义；仍返回驱动原字符串用于实际设置。
    $choiceText = $Value.Trim()
    return ($choiceText.Equals('No SMPS', [System.StringComparison]::OrdinalIgnoreCase) -or
        $choiceText.Equals('无SMPS', [System.StringComparison]::Ordinal))
}

function Get-SmpsPlan {
    param([object[]]$Properties, [string]$Name)
    Assert-ExactAdapterName $Name
    $candidates = @($Properties | Where-Object {
        [string]$_.Name -ceq $Name -and
        ([string]$_.DisplayName -match '(?i)SMPS|MIMO.*(power|save|节能|省电)' -or
         [string]$_.RegistryKeyword -match '(?i)SMPS|MIMO.*(power|save)') -and
        @($_.ValidDisplayValues | Where-Object { Test-NoSmpsDisplayValue ([string]$_) }).Count -eq 1
    })
    if ($candidates.Count -ne 1) {
        Stop-SmpsOperation '当前驱动没有公开唯一的 SMPS 属性与 No SMPS 可选值；停止，不能猜名称、数值或注册表。'
    }
    $original = Convert-SmpsProperty $candidates[0]
    $sameDisplayNames = @($Properties | Where-Object {
        [string]$_.Name -ceq $Name -and [string]$_.DisplayName -ceq $original.DisplayName
    })
    $sameKeywords = @($Properties | Where-Object {
        [string]$_.Name -ceq $Name -and [string]$_.RegistryKeyword -ceq $original.RegistryKeyword
    })
    if ($sameDisplayNames.Count -ne 1 -or $sameKeywords.Count -ne 1) {
        Stop-SmpsOperation 'SMPS 的显示名称或 RegistryKeyword 不是唯一属性；停止，避免修改多个属性。'
    }
    if ([string]::IsNullOrWhiteSpace($original.DisplayName) -or
        [string]::IsNullOrWhiteSpace($original.RegistryKeyword) -or
        [string]::IsNullOrWhiteSpace($original.InterfaceDescription) -or
        $original.RegistryValue.Count -ne 1 -or
        $original.ValidDisplayValues.Count -eq 0 -or
        $original.ValidDisplayValues.Count -ne $original.ValidRegistryValues.Count) {
        Stop-SmpsOperation '驱动没有提供完整的属性原值与可选值对应关系；停止。'
    }
    $targetIndexes = @(for ($choiceIndex = 0; $choiceIndex -lt $original.ValidDisplayValues.Count; $choiceIndex++) {
        if (Test-NoSmpsDisplayValue $original.ValidDisplayValues[$choiceIndex]) { $choiceIndex }
    })
    $originalIndexes = @(for ($choiceIndex = 0; $choiceIndex -lt $original.ValidDisplayValues.Count; $choiceIndex++) {
        if ($original.ValidDisplayValues[$choiceIndex] -ceq $original.DisplayValue -and
            $original.ValidRegistryValues[$choiceIndex] -ceq $original.RegistryValue[0]) { $choiceIndex }
    })
    if ($targetIndexes.Count -ne 1 -or $originalIndexes.Count -ne 1) {
        Stop-SmpsOperation '原值或 No SMPS 与驱动公开的可选值不一致；停止。'
    }
    $targetIndex = $targetIndexes[0]
    return [pscustomobject]@{
        Original = $original
        Target = [pscustomobject]@{
            DisplayValue = $original.ValidDisplayValues[$targetIndex]
            RegistryValue = @($original.ValidRegistryValues[$targetIndex])
        }
    }
}

function Read-SmpsPlan {
    param([string]$Name)
    try { $properties = @(Get-NetAdapterAdvancedProperty -Name $Name -AllProperties -ErrorAction Stop) }
    catch { Stop-SmpsOperation '读取高级属性失败；未输出原始 CIM 信息。请确认网卡存在并使用 PowerShell 7。' }
    return Get-SmpsPlan -Properties $properties -Name $Name
}

function Resolve-SmpsStatePath {
    param([string]$Path)
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    if ($fullPath.StartsWith('\\') -or $fullPath.Contains('"') -or
        -not $fullPath.EndsWith('.json', [System.StringComparison]::OrdinalIgnoreCase) -or
        -not (Test-Path -LiteralPath ([System.IO.Path]::GetDirectoryName($fullPath)) -PathType Container)) {
        Stop-SmpsOperation 'StatePath 必须是已有本地目录中的 .json 文件；不要使用网络路径或引号。'
    }
    return $fullPath
}

function Write-SmpsState {
    param([object]$State, [string]$Path, [switch]$Create)
    $stateJson = $State | ConvertTo-Json -Depth 12
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    if ($Create) {
        $stateStream = [System.IO.File]::Open($Path, [System.IO.FileMode]::CreateNew,
            [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
        try {
            $stateBytes = $utf8.GetBytes($stateJson)
            $stateStream.Write($stateBytes, 0, $stateBytes.Length)
            $stateStream.Flush($true)
        }
        finally { $stateStream.Dispose() }
        return
    }
    $replacementPath = $Path + '.' + [System.IO.Path]::GetRandomFileName() + '.tmp'
    try {
        [System.IO.File]::WriteAllText($replacementPath, $stateJson, $utf8)
        [System.IO.File]::Replace($replacementPath, $Path, $null)
    }
    finally {
        if (Test-Path -LiteralPath $replacementPath) { Remove-Item -LiteralPath $replacementPath }
    }
}

function Read-SmpsState {
    param([string]$Path)
    try { $state = Get-Content -LiteralPath $Path -Raw -Encoding utf8 | ConvertFrom-Json -Depth 12 }
    catch { Stop-SmpsOperation '无法读取试验快照；停止，不使用默认值替代原值。' }
    if ($state.Schema -ne $script:StateSchema -or [string]::IsNullOrWhiteSpace($state.Token) -or
        [string]::IsNullOrWhiteSpace($state.AdapterName) -or
        @($state.Original.RegistryValue).Count -ne 1 -or
        @($state.Target.RegistryValue).Count -ne 1) {
        Stop-SmpsOperation '试验快照格式无效；停止。'
    }
    Assert-ExactAdapterName $state.AdapterName
    return $state
}

function Enter-SmpsLock {
    param([string]$Name)
    # 同一登录会话中的同名网卡串行处理，避免不同快照并行改同一 SMPS。
    $hashBytes = [System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($Name))
    $lockName = 'Local\WirelessSmpsTrial_' + [Convert]::ToHexString($hashBytes)
    $mutex = [System.Threading.Mutex]::new($false, $lockName)
    $acquired = $false
    try {
        try { $acquired = $mutex.WaitOne(15000) }
        catch [System.Threading.AbandonedMutexException] { $acquired = $true }
        if (-not $acquired) { Stop-SmpsOperation '同一网卡有另一个 SMPS 操作尚未结束；停止，勿并行操作。' }
        return $mutex
    }
    catch { $mutex.Dispose(); throw }
}

function Assert-SmpsSnapshotMatches {
    param([object]$State, [object]$Plan)
    if ($Plan.Original.Name -cne $State.Original.Name -or
        $Plan.Original.InterfaceDescription -cne $State.Original.InterfaceDescription -or
        $Plan.Original.DisplayName -cne $State.Original.DisplayName -or
        $Plan.Original.RegistryKeyword -cne $State.Original.RegistryKeyword -or
        -not (Test-SameValues $Plan.Original.ValidDisplayValues $State.Original.ValidDisplayValues) -or
        -not (Test-SameValues $Plan.Original.ValidRegistryValues $State.Original.ValidRegistryValues) -or
        $Plan.Target.DisplayValue -cne $State.Target.DisplayValue -or
        -not (Test-SameValues $Plan.Target.RegistryValue $State.Target.RegistryValue)) {
        Stop-SmpsOperation '网卡、属性或驱动可选值已变化；停止，不把旧快照套到新对象。'
    }
    $savedOriginalMatches = @(for ($savedIndex = 0; $savedIndex -lt $Plan.Original.ValidDisplayValues.Count; $savedIndex++) {
        if ($Plan.Original.ValidDisplayValues[$savedIndex] -ceq $State.Original.DisplayValue -and
            $Plan.Original.ValidRegistryValues[$savedIndex] -ceq $State.Original.RegistryValue[0]) { $savedIndex }
    })
    if ($savedOriginalMatches.Count -ne 1) {
        Stop-SmpsOperation '快照原值不再与当前驱动公开映射一致；停止，不能猜恢复值。'
    }
}

function Test-SmpsCurrentValue {
    param([object]$Plan, [object]$Expected)
    return ($Plan.Original.DisplayValue -ceq $Expected.DisplayValue -and
        (Test-SameValues $Plan.Original.RegistryValue $Expected.RegistryValue))
}

function Wait-SmpsReadback {
    param([object]$State, [object]$Expected)
    # 仅等待高级属性读回；不认定 WLAN 已重新关联或网络业务已恢复。
    for ($readAttempt = 0; $readAttempt -lt 15; $readAttempt++) {
        try {
            $plan = Read-SmpsPlan $State.AdapterName
            Assert-SmpsSnapshotMatches -State $State -Plan $plan
            if (Test-SmpsCurrentValue $plan $Expected) { return $plan }
        }
        catch { }
        Start-Sleep -Seconds 2
    }
    Stop-SmpsOperation '设置后 30 秒内未读回预期原值 / 目标值；不能认定操作成功。'
}

function Set-SmpsTarget {
    param([object]$State)
    try {
        # 使用当前驱动真实显示名称和值，省略 NoRestart，让正规 cmdlet 完成必要重启。
        Set-NetAdapterAdvancedProperty -Name $State.AdapterName -DisplayName $State.Original.DisplayName `
            -DisplayValue $State.Target.DisplayValue -Confirm:$false -ErrorAction Stop
    }
    catch { Stop-SmpsOperation '正规高级属性设置失败；试验仍需恢复原值。' }
    return Wait-SmpsReadback -State $State -Expected $State.Target
}

function Restore-SmpsOriginal {
    param([object]$State, [string]$Path)
    $plan = Read-SmpsPlan $State.AdapterName
    Assert-SmpsSnapshotMatches -State $State -Plan $plan
    if (-not (Test-SmpsCurrentValue $plan $State.Original)) {
        if (-not (Test-SmpsCurrentValue $plan $State.Target)) {
            Stop-SmpsOperation 'SMPS 已是第三个值；停止，避免覆盖另一位操作者的设置。原快照仍保留。'
        }
        try {
            # 精确恢复本次保存的完整 RegistryValue 数组；没有猜数值，也不直接操作注册表。
            Set-NetAdapterAdvancedProperty -Name $State.AdapterName -RegistryKeyword $State.Original.RegistryKeyword `
                -RegistryValue ([string[]]$State.Original.RegistryValue) -Confirm:$false -ErrorAction Stop
        }
        catch { Stop-SmpsOperation '原值恢复命令失败；请在已获授权的管理员窗口再次执行 Rollback。' }
        $plan = Wait-SmpsReadback -State $State -Expected $State.Original
    }
    $State.Status = 'Restored'
    $State.UpdatedUtc = [DateTimeOffset]::UtcNow.ToString('o')
    $State.LastReadback = $plan.Original
    $State.Error = $null
    Write-SmpsState -State $State -Path $Path
    return $plan
}

function Write-SmpsResult {
    param([string]$Status, [object]$Plan, [string]$Path, [object]$State)
    [pscustomobject][ordered]@{
        Action = $Action
        Status = $Status
        AdapterName = $Plan.Original.Name
        Property = $Plan.Original.DisplayName
        CurrentDisplayValue = $Plan.Original.DisplayValue
        CurrentRegistryValue = @($Plan.Original.RegistryValue)
        TargetDisplayValue = $Plan.Target.DisplayValue
        StatePath = $Path
        RollbackDeadlineUtc = $(if ($null -ne $State) { $State.DeadlineUtc } else { $null })
        WatchdogPid = $(if ($null -ne $State) { $State.WatchdogPid } else { $null })
        NetworkAcceptance = 'NotChecked'
    } | ConvertTo-Json -Depth 5
}

try {
    if (-not $IsWindows) { Stop-SmpsOperation '此脚本仅适用于 Windows PowerShell 7。' }
    Assert-ExactAdapterName $AdapterName
    if ($Action -eq 'DryRun') {
        $plan = Read-SmpsPlan $AdapterName
        Write-SmpsResult -Status 'DryRunNoChanges' -Plan $plan -Path $StatePath -State $null
        return
    }

    Assert-Administrator
    $stateFile = Resolve-SmpsStatePath $StatePath
    if ($Action -ne 'Trial') {
        $state = Read-SmpsState $stateFile
        if ($PSBoundParameters.ContainsKey('AdapterName') -and $AdapterName -cne $state.AdapterName) {
            Stop-SmpsOperation 'AdapterName 与快照不一致；停止。Rollback / Accept 应直接使用保存的 StatePath。'
        }
        $AdapterName = $state.AdapterName
    }

    if ($Action -eq 'Watchdog') {
        if ($WatchdogToken -cne $state.Token) { Stop-SmpsOperation '回滚进程与试验快照不匹配；停止。' }
        [System.IO.File]::WriteAllText($stateFile + '.watchdog-ready', $WatchdogToken,
            [System.Text.UTF8Encoding]::new($false))
        while ($true) {
            $state = Read-SmpsState $stateFile
            if ($WatchdogToken -cne $state.Token) { Stop-SmpsOperation '回滚进程的快照已被替换；停止。' }
            if ($state.Status -in @('Accepted', 'Restored', 'RollbackFailed')) { return }
            if ([DateTimeOffset]::UtcNow -ge [DateTimeOffset]::Parse($state.DeadlineUtc)) { break }
            Start-Sleep -Seconds 1
        }
    }

    $operationLock = Enter-SmpsLock $AdapterName
    try {
        if ($Action -eq 'Trial') {
            $plan = Read-SmpsPlan $AdapterName
            if (Test-SmpsCurrentValue $plan $plan.Target) {
                Write-SmpsResult -Status 'AlreadyNoSmpsNoChanges' -Plan $plan -Path $stateFile -State $null
                return
            }
            foreach ($reservedPath in @($stateFile, ($stateFile + '.watchdog-ready'),
                ($stateFile + '.watchdog.stdout.log'), ($stateFile + '.watchdog.stderr.log'))) {
                if (Test-Path -LiteralPath $reservedPath) {
                    Stop-SmpsOperation '试验快照或日志已存在；停止。先完成旧试验，并为新试验选择新的 StatePath。'
                }
            }
            $state = [pscustomobject][ordered]@{
                Schema = $script:StateSchema
                AdapterName = $AdapterName
                Original = $plan.Original
                Target = $plan.Target
                Token = [System.IO.Path]::GetRandomFileName() + [System.IO.Path]::GetRandomFileName()
                Status = 'Prepared'
                CreatedUtc = [DateTimeOffset]::UtcNow.ToString('o')
                UpdatedUtc = [DateTimeOffset]::UtcNow.ToString('o')
                DeadlineUtc = [DateTimeOffset]::UtcNow.AddSeconds($RollbackAfterSeconds).ToString('o')
                WatchdogPid = $null
                LastReadback = $plan.Original
                Error = $null
            }
            Write-SmpsState -State $state -Path $stateFile -Create
            try {
                $pwshPath = Join-Path $PSHOME 'pwsh.exe'
                $watchdogArguments = @('-NoLogo', '-NoProfile', '-NonInteractive', '-File',
                    ('"' + $PSCommandPath + '"'), '-Action', 'Watchdog', '-StatePath',
                    ('"' + $stateFile + '"'), '-WatchdogToken', $state.Token)
                $guardProcess = Start-Process -FilePath $pwshPath -ArgumentList $watchdogArguments `
                    -WindowStyle Hidden -PassThru -RedirectStandardOutput ($stateFile + '.watchdog.stdout.log') `
                    -RedirectStandardError ($stateFile + '.watchdog.stderr.log') -ErrorAction Stop
                $state.WatchdogPid = $guardProcess.Id
                $state.Status = 'Armed'
                Write-SmpsState -State $state -Path $stateFile
                $watchdogReady = $false
                for ($readyAttempt = 0; $readyAttempt -lt 50; $readyAttempt++) {
                    if (Test-Path -LiteralPath ($stateFile + '.watchdog-ready')) {
                        $readyToken = [REDACTED] -LiteralPath ($stateFile + '.watchdog-ready') -Raw
                        if ($readyToken -ceq $state.Token) { $watchdogReady = $true; break }
                    }
                    if ($guardProcess.HasExited) { break }
                    Start-Sleep -Milliseconds 200
                }
                if (-not $watchdogReady -or $guardProcess.HasExited) {
                    Stop-SmpsOperation '独立回滚进程没有就绪；停止，尚未允许修改 SMPS。'
                }
                # 写前再读一次，避免把等待回滚进程期间的外部改动当作旧原值。
                $freshPlan = Read-SmpsPlan $AdapterName
                Assert-SmpsSnapshotMatches -State $state -Plan $freshPlan
                if (-not (Test-SmpsCurrentValue $freshPlan $state.Original)) {
                    Stop-SmpsOperation '准备期间原值已变化；停止修改。'
                }
                $state.Status = 'Applying'
                Write-SmpsState -State $state -Path $stateFile
                $plan = Set-SmpsTarget $state
                $state.Status = 'Trial'
                $state.UpdatedUtc = [DateTimeOffset]::UtcNow.ToString('o')
                $state.LastReadback = $plan.Original
                Write-SmpsState -State $state -Path $stateFile
                Write-SmpsResult -Status 'TrialReadbackPassedRollbackArmed' -Plan $plan -Path $stateFile -State $state
            }
            catch {
                $trialFailure = $script:SmpsError
                try { $null = Restore-SmpsOriginal -State $state -Path $stateFile }
                catch {
                    $state.Status = 'RollbackFailed'
                    $state.Error = $script:SmpsError
                    Write-SmpsState -State $state -Path $stateFile
                    Stop-SmpsOperation ('试验未完成，且未确认恢复原值。请从快照执行 Rollback。原因：' + $state.Error)
                }
                Stop-SmpsOperation ('试验未完成，已读回原值。原因：' + $trialFailure)
            }
        }
        elseif ($Action -in @('Rollback', 'Watchdog')) {
            $state = Read-SmpsState $stateFile
            if ($Action -eq 'Watchdog' -and $state.Status -in @('Accepted', 'Restored', 'RollbackFailed')) { return }
            try {
                $plan = Restore-SmpsOriginal -State $state -Path $stateFile
                Write-SmpsResult -Status 'OriginalReadbackPassed' -Plan $plan -Path $stateFile -State $state
            }
            catch {
                $state.Status = 'RollbackFailed'
                $state.Error = $script:SmpsError
                Write-SmpsState -State $state -Path $stateFile
                throw
            }
        }
        elseif ($Action -eq 'Accept') {
            if (-not $ConfirmAccept) { Stop-SmpsOperation 'Accept 必须显式带 -ConfirmAccept；没有更改设备或取消回滚。' }
            $state = Read-SmpsState $stateFile
            if ($state.Status -notin @('Trial', 'Restored', 'Accepted')) {
                Stop-SmpsOperation '当前试验未完成或回滚失败；不能 Accept。'
            }
            $plan = Read-SmpsPlan $AdapterName
            Assert-SmpsSnapshotMatches -State $state -Plan $plan
            if (-not (Test-SmpsCurrentValue $plan $state.Target)) {
                if (-not (Test-SmpsCurrentValue $plan $state.Original)) {
                    Stop-SmpsOperation '当前 SMPS 已是第三个值；不能 Accept。'
                }
                try { $plan = Set-SmpsTarget $state }
                catch {
                    $acceptFailure = $script:SmpsError
                    try { $null = Restore-SmpsOriginal -State $state -Path $stateFile }
                    catch {
                        $state.Status = 'RollbackFailed'
                        $state.Error = $script:SmpsError
                        Write-SmpsState -State $state -Path $stateFile
                        Stop-SmpsOperation 'Accept 失败且未确认原值恢复；必须从快照执行 Rollback。'
                    }
                    Stop-SmpsOperation ('Accept 失败，已读回原值。原因：' + $acceptFailure)
                }
            }
            $state.Status = 'Accepted'
            $state.UpdatedUtc = [DateTimeOffset]::UtcNow.ToString('o')
            $state.LastReadback = $plan.Original
            $state.Error = $null
            Write-SmpsState -State $state -Path $stateFile
            Write-SmpsResult -Status 'AcceptedNoSmpsReadbackPassed' -Plan $plan -Path $stateFile -State $state
        }
    }
    finally {
        $operationLock.ReleaseMutex()
        $operationLock.Dispose()
    }
}
catch {
    # 不回显 NetAdapter 原始异常、CIM 对象或潜在设备标识。
    Write-Error -Message $script:SmpsError -ErrorAction Continue
    exit 1
}
