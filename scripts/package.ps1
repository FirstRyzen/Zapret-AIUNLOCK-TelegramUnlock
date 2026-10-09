$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$target = Join-Path $root 'dist/Kontur'
if (Test-Path -LiteralPath $target) { throw 'dist/Kontur already exists. Move it aside before packaging again.' }
New-Item -ItemType Directory -Force $target | Out-Null
foreach ($folder in @('profiles','launcher','scripts','licenses')) {
    Copy-Item -LiteralPath (Join-Path $root $folder) -Destination $target -Recurse
}
foreach ($file in @('Kontur.exe','README.md','LICENSE.txt','THIRD_PARTY_NOTICES.md','PRODUCT.md','DESIGN.md','.gitignore','.gitattributes')) {
    Copy-Item -LiteralPath (Join-Path $root $file) -Destination $target
}
foreach ($folder in @('bin','bin/telegram','lists','utils','.github/workflows','docs')) { New-Item -ItemType Directory -Force (Join-Path $target $folder) | Out-Null }
Get-ChildItem -LiteralPath (Join-Path $root 'bin') -File | Where-Object { $_.Extension -in @('.exe','.dll','.sys','.bin') } | Copy-Item -Destination (Join-Path $target 'bin')
foreach ($file in @('TgWsProxy_windows.exe','LICENSE.txt','release.json')) { Copy-Item -LiteralPath (Join-Path $root "bin/telegram/$file") -Destination (Join-Path $target 'bin/telegram') }
foreach ($file in @('list-general.txt','list-google.txt','list-exclude.txt','ipset-all.txt','ipset-exclude.txt','ai-unlock-domains.txt','ai-unlock-hosts.txt','telegram-domains.txt')) { Copy-Item -LiteralPath (Join-Path $root "lists/$file") -Destination (Join-Path $target 'lists') }
foreach ($file in @('list-general-user.txt','list-exclude-user.txt','ipset-exclude-user.txt')) { [IO.File]::WriteAllText((Join-Path $target "lists/$file"),'',[Text.Encoding]::UTF8) }
foreach ($file in @('ai-unlock.ps1','telegram-proxy.ps1','ai-unlock-source-LICENSE.txt')) { Copy-Item -LiteralPath (Join-Path $root "utils/$file") -Destination (Join-Path $target 'utils') }
Copy-Item -LiteralPath (Join-Path $root '.github/workflows/build.yml') -Destination (Join-Path $target '.github/workflows')
Copy-Item -LiteralPath (Join-Path $root 'artifacts/Подключение.png') -Destination (Join-Path $target 'docs/interface.png')
$sums = Get-ChildItem -LiteralPath $target -File -Recurse | Sort-Object FullName | ForEach-Object {
    (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() + '  ' + $_.FullName.Substring($target.Length + 1).Replace('\','/')
}
[IO.File]::WriteAllLines((Join-Path $target 'SHA256SUMS.txt'),$sums,[Text.Encoding]::UTF8)
Compress-Archive -LiteralPath $target -DestinationPath (Join-Path $root 'dist/Kontur-1.0.0-win-x64.zip')
Write-Output "Package ready: $target"
