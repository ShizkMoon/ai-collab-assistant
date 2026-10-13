param(
    [Parameter(Mandatory)] [ValidateSet('Home','Away')] [string] $Mode,
    [Parameter(Mandatory)] [string] $FilePath,
    [string[]] $ArgumentList = @()
)
# 仅改变这次调用及其子进程的代理环境，不写注册表、不改用户级环境。
$ErrorActionPreference = 'Stop'
$taskNames = @('HTTP_PROXY','HTTPS_PROXY','ALL_PROXY')
$taskOriginal = @{}
foreach ($taskName in $taskNames) {
    $taskOriginal[$taskName] = [Environment]::GetEnvironmentVariable($taskName, 'Process')
}
try {
    foreach ($taskName in $taskNames) {
        $taskValue = if ($Mode -eq 'Home') { $null } else { [Environment]::GetEnvironmentVariable($taskName, 'User') }
        if ($null -eq $taskValue) {
            Remove-Item -LiteralPath "Env:$taskName" -ErrorAction SilentlyContinue
        } else {
            [Environment]::SetEnvironmentVariable($taskName, $taskValue, 'Process')
        }
    }
    & $FilePath @ArgumentList
    $taskExitCode = $LASTEXITCODE
} finally {
    foreach ($taskName in $taskNames) {
        if ($null -eq $taskOriginal[$taskName]) {
            Remove-Item -LiteralPath "Env:$taskName" -ErrorAction SilentlyContinue
        } else {
            [Environment]::SetEnvironmentVariable($taskName, $taskOriginal[$taskName], 'Process')
        }
    }
}
if ($null -ne $taskExitCode -and $taskExitCode -ne 0) { exit $taskExitCode }
