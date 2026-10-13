@{
    HTTP_PROXY = [bool][Environment]::GetEnvironmentVariable('HTTP_PROXY','Process')
    HTTPS_PROXY = [bool][Environment]::GetEnvironmentVariable('HTTPS_PROXY','Process')
    ALL_PROXY = [bool][Environment]::GetEnvironmentVariable('ALL_PROXY','Process')
} | ConvertTo-Json -Compress
