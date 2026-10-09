$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$files = @(Get-ChildItem -LiteralPath $root -Filter 'general*.bat' | Sort-Object @{Expression={if ($_.Name -eq 'general.bat') {0} elseif ($_.Name -match '^general \(ALT(\d*)\)') {if ($Matches[1]) {[int]$Matches[1]} else {1}} else {100}}},Name)
$index = @()
if ($files.Count -eq 0) { throw 'No original general*.bat files found. Import is only for the original workspace.' }
foreach ($file in $files) {
    $text = Get-Content -LiteralPath $file.FullName -Raw
    $match = [regex]::Match($text, '(?s)start\s+"[^"]*"\s+/min\s+"%BIN%winws.exe"\s+(.+)')
    if (!$match.Success) { throw "Cannot extract profile: $($file.Name)" }
    $args = ($match.Groups[1].Value -replace '\^\r?\n',' ' -replace '\^!','!').Trim()
    $args = $args.Replace('%BIN%','{BIN}').Replace('%LISTS%','{LISTS}').Replace('%GameFilterTCP%','{GAME_TCP}').Replace('%GameFilterUDP%','{GAME_UDP}').Replace('%GameFilter%','{GAME_TCP}')
    if ($args -match '%|\^|[\r\n]') { throw "Unexpected batch syntax: $($file.Name)" }
    $id = if ($file.BaseName -eq 'general') {'standard'} else {($file.BaseName -replace '^general \(','') -replace '\)$','' -replace ' ','-'}
    $name = if ($id -eq 'standard') {'Основной'} elseif ($id -eq 'ALT') {'ALT1'} else {$id.Replace('-',' ')}
    [IO.File]::WriteAllText((Join-Path $root "profiles/$id.args"), $args, (New-Object Text.UTF8Encoding($false)))
    $index += "$id|$name|$($file.Name)"
}
[IO.File]::WriteAllLines((Join-Path $root 'profiles/catalog.txt'), $index, (New-Object Text.UTF8Encoding($false)))
Write-Output "Imported $($index.Count) profiles."
