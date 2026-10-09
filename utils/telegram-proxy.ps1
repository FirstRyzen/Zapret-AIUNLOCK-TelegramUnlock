[CmdletBinding()]
param(
    [ValidateSet('Start', 'Stop', 'Connect', 'Toggle', 'InstallService', 'RemoveService', 'Status')]
    [string]$Mode = 'Status',
    [switch]$RequireService,
    [switch]$LibraryOnly
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$ExePath = Join-Path $ProjectRoot 'bin\telegram\TgWsProxy_windows.exe'
$DataDir = Join-Path (Split-Path -Parent $ExePath) 'TgWsProxy_data'
$ConfigPath = Join-Path $DataDir 'config.json'
$DisabledPath = Join-Path $PSScriptRoot 'telegram-proxy.disabled'
$RunKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$RunName = 'ZapretTelegramProxy'
$ControllerPath = $PSCommandPath

function Get-ManagedTelegramProxy {
    @(Get-Process -Name 'TgWsProxy_windows' -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -and $_.Path.Equals($ExePath, [StringComparison]::OrdinalIgnoreCase) })
}

function Initialize-TelegramConfig {
    [void][IO.Directory]::CreateDirectory($DataDir)
    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        $secretBytes = New-Object byte[] 16
        $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
        try { $rng.GetBytes($secretBytes) } finally { $rng.Dispose() }
        $config = [ordered]@{
            host = '127.0.0.1'; port = 1443
            secret = ([BitConverter]::ToString($secretBytes)).Replace('-', '').ToLowerInvariant()
            dc_ip = @('4:149.154.167.220')
            verbose = $false; check_updates = $false; autostart = $false
            log_max_mb = 5; buf_kb = 256; pool_size = 4
            cfproxy = $true; h2 = $true; no_secure = $false
            cfproxy_user_domain_enabled = $false; cfproxy_user_domain = @()
            cfproxy_worker_enabled = $false; cfproxy_worker_domain = @()
            force_test_dc = $false; appearance = 'auto'; language = 'ru'
        }
        [IO.File]::WriteAllText($ConfigPath, ($config | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
    }
}

function Get-TelegramConfig {
    $config = [IO.File]::ReadAllText($ConfigPath) | ConvertFrom-Json
    if ($config.host -ne '127.0.0.1' -or $config.port -lt 1 -or $config.port -gt 65535 -or
        $config.secret -notmatch '^[a-fA-F0-9]{32}$') {
        throw 'Invalid Telegram proxy configuration; only loopback binding is supported.'
    }
    return $config
}

function Test-LocalTelegramPort([int]$Port) {
    $client = New-Object Net.Sockets.TcpClient
    try {
        $task = $client.ConnectAsync('127.0.0.1', $Port)
        return ($task.Wait(500) -and $client.Connected)
    } catch { return $false } finally { $client.Dispose() }
}

function Start-TelegramProxy {
    if (Test-Path -LiteralPath $DisabledPath) { Write-Host 'Telegram proxy: automatic start disabled.'; return $false }
    if ($RequireService) {
        $running = $false
        for ($i = 0; $i -lt 15; $i++) {
            $service = Get-Service -Name zapret -ErrorAction SilentlyContinue
            if (-not $service) { return $false }
            if ($service.Status -eq 'Running') { $running = $true; break }
            Start-Sleep -Seconds 2
        }
        if (-not $running) { return $false }
    }
    if (-not (Test-Path -LiteralPath $ExePath)) { throw 'Telegram proxy executable is missing.' }
    Initialize-TelegramConfig
    $config = Get-TelegramConfig
    $existing = @(Get-ManagedTelegramProxy)
    if ($existing.Count -gt 0 -and (Test-LocalTelegramPort $config.port)) {
        Write-Host "Telegram proxy: already running on 127.0.0.1:$($config.port)."
        return $true
    }
    if ($existing.Count -eq 0) {
        if (Test-LocalTelegramPort $config.port) { throw "Port $($config.port) is occupied by another application." }
        if (@(Get-Process -Name 'TgWsProxy_windows*' -ErrorAction SilentlyContinue).Count -gt 0) {
            throw 'Another TG WS Proxy instance is running; stop it or use its Telegram settings.'
        }
        $process = Start-Process -FilePath $ExePath -ArgumentList '--portable' -WorkingDirectory (Split-Path -Parent $ExePath) -WindowStyle Hidden -PassThru
    }
    for ($i = 0; $i -lt 20; $i++) {
        if ((Test-LocalTelegramPort $config.port) -and @(Get-ManagedTelegramProxy).Count -gt 0) {
            Write-Host "Telegram proxy: running on 127.0.0.1:$($config.port)."
            return $true
        }
        Start-Sleep -Milliseconds 500
    }
    throw 'Telegram proxy did not start; check bin\telegram\TgWsProxy_data\proxy.log.'
}

function Stop-TelegramProxy {
    foreach ($process in @(Get-ManagedTelegramProxy)) { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue }
    Write-Host 'Telegram proxy: stopped.'
}

function Get-TelegramLink {
    $config = Get-TelegramConfig
    return "tg://proxy?server=127.0.0.1&port=$($config.port)&secret=dd$($config.secret)"
}

function Register-TelegramAutoStart {
    $command = '"' + (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') +
        '" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $ControllerPath + '" -Mode Start -RequireService'
    if (-not (Test-Path -LiteralPath $RunKey)) { [void](New-Item -Path $RunKey -Force) }
    $previous = (Get-ItemProperty -LiteralPath $RunKey -Name $RunName -ErrorAction SilentlyContinue).$RunName
    if ($previous -and $previous -ne $command) { throw 'Telegram startup entry already belongs to another zapret folder.' }
    [void](New-ItemProperty -LiteralPath $RunKey -Name $RunName -Value $command -PropertyType String -Force)
}

function Unregister-TelegramAutoStart {
    $previous = (Get-ItemProperty -LiteralPath $RunKey -Name $RunName -ErrorAction SilentlyContinue).$RunName
    if ($previous -and $previous.Contains('"' + $ControllerPath + '"')) {
        Remove-ItemProperty -LiteralPath $RunKey -Name $RunName
    }
}

if ($LibraryOnly) { return }
try {
    switch ($Mode) {
        'Start' { [void](Start-TelegramProxy) }
        'Stop' { Stop-TelegramProxy }
        'Status' {
            if (Test-Path -LiteralPath $DisabledPath) { Write-Host 'OFF' }
            elseif (@(Get-ManagedTelegramProxy).Count -gt 0) { Write-Host 'RUNNING' }
            else { Write-Host 'AUTO' }
        }
        'Connect' {
            if (Start-TelegramProxy) { Start-Process -FilePath (Get-TelegramLink) }
        }
        'Toggle' {
            if (Test-Path -LiteralPath $DisabledPath) {
                Remove-Item -LiteralPath $DisabledPath
                [void](Start-TelegramProxy)
            } else {
                [IO.File]::WriteAllText($DisabledPath, 'Automatic Telegram proxy disabled.')
                Stop-TelegramProxy
            }
        }
        'InstallService' { Register-TelegramAutoStart; [void](Start-TelegramProxy) }
        'RemoveService' { Unregister-TelegramAutoStart; Stop-TelegramProxy }
    }
} catch {
    Write-Host "Telegram proxy ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
