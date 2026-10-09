[CmdletBinding()]
param(
    [ValidateSet('Enable', 'Disable', 'Toggle', 'Update', 'Status')]
    [string]$Mode = 'Status',
    [switch]$LibraryOnly
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$CachePath = Join-Path $ProjectRoot 'lists\ai-unlock-hosts.txt'
$DomainsPath = Join-Path $ProjectRoot 'lists\ai-unlock-domains.txt'
$DisabledPath = Join-Path $PSScriptRoot 'ai-unlock.disabled'
$SystemHostsPath = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
$SourceUrl = 'https://raw.githubusercontent.com/ImMALWARE/dns.malw.link/master/hosts'
$BeginMarker = '# BEGIN ZAPRET AI UNLOCK'
$EndMarker = '# END ZAPRET AI UNLOCK'
# Latin-1 is used as a reversible byte-to-character mapping, not a text conversion.
$ByteEncoding = [Text.Encoding]::GetEncoding(28591)

function Get-AiDomains {
    @(Get-Content -LiteralPath $DomainsPath | ForEach-Object { $_.Trim().ToLowerInvariant() } |
        Where-Object { $_ -and -not $_.StartsWith('#') })
}

function Test-AiDomain([string]$Domain, [string[]]$Roots) {
    foreach ($root in $Roots) {
        if ($Domain -eq $root -or $Domain.EndsWith('.' + $root)) { return $true }
    }
    return $false
}

function ConvertTo-AiEntries([string]$Content, [switch]$Strict) {
    $roots = Get-AiDomains
    $entries = [ordered]@{}
    foreach ($line in ($Content -split '\r?\n')) {
        $line = ($line -split '#', 2)[0].Trim()
        if (-not $line) { continue }
        $parts = $line -split '\s+'
        if ($parts.Count -ne 2) {
            if ($Strict) { throw 'Malformed AI hosts entry.' }
            continue
        }
        $domain = $parts[1].ToLowerInvariant()
        if (-not (Test-AiDomain $domain $roots)) {
            if ($Strict) { throw "Unexpected domain in AI hosts: $domain" }
            continue
        }
        $address = $null
        if ($domain -notmatch '^(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z0-9-]+$' -or
            -not [Net.IPAddress]::TryParse($parts[0], [ref]$address) -or
            $address.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) {
            throw "Invalid AI hosts entry: $line"
        }
        $octets = $address.GetAddressBytes()
        if ($octets[0] -in @(0, 10, 127) -or $octets[0] -ge 224 -or
            ($octets[0] -eq 169 -and $octets[1] -eq 254) -or
            ($octets[0] -eq 172 -and $octets[1] -ge 16 -and $octets[1] -le 31) -or
            ($octets[0] -eq 192 -and $octets[1] -eq 168) -or
            ($octets[0] -eq 100 -and $octets[1] -ge 64 -and $octets[1] -le 127)) {
            throw "Non-public AI proxy address: $line"
        }
        if ($entries.Contains($domain) -and $entries[$domain] -ne $address.ToString()) {
            throw "Conflicting AI proxy addresses: $domain"
        }
        $entries[$domain] = $address.ToString()
    }
    foreach ($required in @('chatgpt.com', 'claude.ai', 'gemini.google.com')) {
        if (-not $entries.Contains($required)) { throw "AI hosts is incomplete: missing $required" }
    }
    @($entries.GetEnumerator() | ForEach-Object { '{0} {1}' -f $_.Value, $_.Key })
}

function Update-AiCache {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $response = Invoke-WebRequest -Uri $SourceUrl -UseBasicParsing -TimeoutSec 12
    if ($response.Content.Length -gt 2097152) { throw 'AI hosts download is unexpectedly large.' }
    $entries = @(ConvertTo-AiEntries $response.Content)
    $content = "# Source: $SourceUrl`r`n# Updated UTC: $([DateTime]::UtcNow.ToString('s'))`r`n" +
        ($entries -join "`r`n") + "`r`n"
    $tempPath = $CachePath + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [IO.File]::WriteAllText($tempPath, $content, [Text.Encoding]::ASCII)
        Move-Item -LiteralPath $tempPath -Destination $CachePath -Force
    } finally {
        if (Test-Path -LiteralPath $tempPath) { Remove-Item -LiteralPath $tempPath }
    }
    Write-Host "AI Unlock: updated $($entries.Count) AI domains."
}

function Remove-AiBlock([string]$Content) {
    if ($Content.Contains([char]0)) { throw 'UTF-16 hosts files are not supported. No changes made.' }
    $beginCount = [regex]::Matches($Content, '(?m)^' + [regex]::Escape($BeginMarker) + '\r?$').Count
    $endCount = [regex]::Matches($Content, '(?m)^' + [regex]::Escape($EndMarker) + '\r?$').Count
    if ($beginCount -ne $endCount -or $beginCount -gt 1) { throw 'Damaged AI Unlock markers. No changes made.' }
    if ($beginCount -eq 0) { return $Content }
    $pattern = '(?ms)(?:\r?\n)?^' + [regex]::Escape($BeginMarker) + '\r?\n.*?^' +
        [regex]::Escape($EndMarker) + '(?:\r?\n|$)'
    $result = [regex]::Replace($Content, $pattern, '')
    if ($result.Contains($BeginMarker) -or $result.Contains($EndMarker)) {
        throw 'Damaged AI Unlock block. No changes made.'
    }
    return $result
}

function Add-AiBlock([string]$Content, [string[]]$Entries) {
    $base = Remove-AiBlock $Content
    $domains = @{}
    foreach ($entry in $Entries) { $domains[($entry -split '\s+')[1]] = $true }
    foreach ($line in ($base -split '\r?\n')) {
        $parts = (($line -split '#', 2)[0].Trim() -split '\s+')
        for ($i = 1; $i -lt $parts.Count; $i++) {
            if ($domains.ContainsKey($parts[$i].ToLowerInvariant())) {
                throw "Existing hosts entry for $($parts[$i]); resolve it before enabling AI Unlock."
            }
        }
    }
    return $base + "`r`n$BeginMarker`r`n" + ($Entries -join "`r`n") + "`r`n$EndMarker`r`n"
}

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run the zapret BAT file as administrator to change hosts for AI Unlock.'
    }
}

function Set-AiHosts([bool]$Enable) {
    Assert-Administrator
    $bytes = [IO.File]::ReadAllBytes($SystemHostsPath)
    $original = $ByteEncoding.GetString($bytes)
    if ($Enable) {
        if (-not (Test-Path -LiteralPath $CachePath)) { Update-AiCache }
        $entries = @(ConvertTo-AiEntries ([IO.File]::ReadAllText($CachePath)) -Strict)
        $next = Add-AiBlock $original $entries
    } else { $next = Remove-AiBlock $original }
    if ($next -cne $original) {
        $backupDir = Join-Path $PSScriptRoot 'ai-unlock-backups'
        [void][IO.Directory]::CreateDirectory($backupDir)
        $backupPath = Join-Path $backupDir ('hosts-' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fffffff') + '.bak')
        [IO.File]::WriteAllBytes($backupPath, $bytes)
        [IO.File]::WriteAllBytes($SystemHostsPath, $ByteEncoding.GetBytes($next))
        & "$env:SystemRoot\System32\ipconfig.exe" /flushdns | Out-Null
    }
    if ($Enable) { Write-Host 'AI Unlock: hosts enabled (dns.malw.link).' }
    else { Write-Host 'AI Unlock: hosts removed; other entries preserved.' }
}

function Get-AiStatus {
    if (Test-Path -LiteralPath $DisabledPath) { return 'OFF (automatic start disabled)' }
    if ([IO.File]::ReadAllText($SystemHostsPath).Contains($BeginMarker)) { return 'ON (hosts applied)' }
    return 'AUTO (enabled on next zapret start)'
}

if ($LibraryOnly) { return }

$mutex = New-Object Threading.Mutex($false, 'Global\ZapretAiUnlockHosts')
$locked = $false
try {
    try { $locked = $mutex.WaitOne(20000) } catch [Threading.AbandonedMutexException] { $locked = $true }
    if (-not $locked) { throw 'Another AI Unlock operation is still running.' }
    switch ($Mode) {
        'Status' { Write-Host (Get-AiStatus) }
        'Enable' {
            if (Test-Path -LiteralPath $DisabledPath) { Write-Host 'AI Unlock: automatic start disabled.'; break }
            if (Test-Path -LiteralPath $CachePath) {
                if ((Get-Item -LiteralPath $CachePath).LastWriteTimeUtc -lt [DateTime]::UtcNow.AddDays(-7)) {
                    try { Update-AiCache } catch { Write-Warning "Using cached AI addresses: $($_.Exception.Message)" }
                }
            }
            Set-AiHosts $true
        }
        'Disable' { Set-AiHosts $false }
        'Toggle' {
            Assert-Administrator
            if (Test-Path -LiteralPath $DisabledPath) {
                Set-AiHosts $true
                Remove-Item -LiteralPath $DisabledPath
            } else {
                Set-AiHosts $false
                [IO.File]::WriteAllText($DisabledPath, 'Automatic AI Unlock disabled.')
            }
        }
        'Update' {
            Assert-Administrator
            Update-AiCache
            if ([IO.File]::ReadAllText($SystemHostsPath).Contains($BeginMarker)) { Set-AiHosts $true }
        }
    }
} catch {
    Write-Host "AI Unlock ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
} finally {
    if ($locked) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
