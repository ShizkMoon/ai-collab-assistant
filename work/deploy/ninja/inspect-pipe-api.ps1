$ErrorActionPreference = 'Stop'
$taskInput = [Console]::In.ReadToEnd() | ConvertFrom-Json
$taskResult = @{}
foreach ($taskEndpoint in @('/version', '/proxies', '/connections')) {
    $taskPipe = [System.IO.Pipes.NamedPipeClientStream]::new('.', $taskInput.pipe, [System.IO.Pipes.PipeDirection]::InOut, [System.IO.Pipes.PipeOptions]::Asynchronous)
    try {
        $taskPipe.Connect(3000)
        $taskRequest = "GET $taskEndpoint HTTP/1.0`r`nHost: localhost`r`nConnection: close`r`n"
        if ($taskInput.secret) { $taskRequest += "Authorization: Bearer $($taskInput.secret)`r`n" }
        $taskRequest += "`r`n"
        $taskBytes = [Text.Encoding]::UTF8.GetBytes($taskRequest)
        $taskPipe.Write($taskBytes, 0, $taskBytes.Length)
        $taskPipe.Flush()
        $taskReader = [IO.StreamReader]::new($taskPipe, [Text.Encoding]::UTF8)
        $taskRead = $taskReader.ReadToEndAsync()
        if (-not $taskRead.Wait(5000)) { throw 'pipe_read_timeout' }
        $taskRaw = $taskRead.Result
        $taskParts = $taskRaw -split "`r`n`r`n", 2
        $taskData = $taskParts[1] | ConvertFrom-Json
        if ($taskEndpoint -eq '/version') {
            $taskResult.version = @{ version = $taskData.version; meta = $taskData.meta }
        } elseif ($taskEndpoint -eq '/proxies') {
            $taskResult.groups = @{}
            foreach ($taskGroup in $taskInput.groups) {
                $taskProxy = $taskData.proxies.$taskGroup
                if ($taskProxy) { $taskResult.groups[$taskGroup] = @{ type = $taskProxy.type; now = $taskProxy.now } }
            }
        } else {
            $taskResult.target_connections = @($taskData.connections | Where-Object { $_.metadata.host -match '(^|\.)(microsoft\.com|windowsupdate\.com|steamcontent\.com)$' } | ForEach-Object {
                @{ host = $_.metadata.host; network = $_.metadata.network; rule = $_.rule; rulePayload = $_.rulePayload; chains = $_.chains; download = $_.download; upload = $_.upload }
            })
            $taskResult.connection_count = @($taskData.connections).Count
        }
    } catch {
        $taskResult[$taskEndpoint] = @{ error = $_.Exception.GetType().Name }
    } finally {
        $taskPipe.Dispose()
    }
}
$taskResult | ConvertTo-Json -Depth 12
