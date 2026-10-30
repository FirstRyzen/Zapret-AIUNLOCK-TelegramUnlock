param([string]$OutputName = 'Kontur.exe')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$output = Join-Path $root 'dist'
$stage = Join-Path $output ('payload-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $stage | Out-Null
foreach ($folder in @('bin','bin/telegram','profiles','lists','utils','licenses','launcher')) { New-Item -ItemType Directory -Force (Join-Path $stage $folder) | Out-Null }
Get-ChildItem -LiteralPath (Join-Path $root 'bin') -File | Where-Object { $_.Extension -in @('.exe','.dll','.sys','.bin') } | Copy-Item -Destination (Join-Path $stage 'bin')
foreach ($file in @('TgWsProxy_windows.exe','LICENSE.txt','release.json')) { Copy-Item -LiteralPath (Join-Path $root "bin/telegram/$file") -Destination (Join-Path $stage 'bin/telegram') }
Get-ChildItem -LiteralPath (Join-Path $root 'profiles') -File | Where-Object { $_.Extension -in @('.args','.txt') } | Copy-Item -Destination (Join-Path $stage 'profiles')
foreach ($file in @('list-general.txt','list-google.txt','list-exclude.txt','ipset-all.txt','ipset-exclude.txt','ai-unlock-domains.txt','ai-unlock-hosts.txt','telegram-domains.txt')) { Copy-Item -LiteralPath (Join-Path $root "lists/$file") -Destination (Join-Path $stage 'lists') }
foreach ($file in @('list-general-user.txt','list-exclude-user.txt','ipset-exclude-user.txt')) { [IO.File]::WriteAllText((Join-Path $stage "lists/$file"),'',[Text.Encoding]::ASCII) }
foreach ($file in @('ai-unlock.ps1','telegram-proxy.ps1')) { Copy-Item -LiteralPath (Join-Path $root "utils/$file") -Destination (Join-Path $stage 'utils') }
Get-ChildItem -LiteralPath (Join-Path $root 'licenses') -File | Copy-Item -Destination (Join-Path $stage 'licenses')
foreach ($file in @('LICENSE.txt','THIRD_PARTY_NOTICES.md','README.md')) { Copy-Item -LiteralPath (Join-Path $root $file) -Destination $stage }
Copy-Item -LiteralPath (Join-Path $root 'launcher/kontur.ico') -Destination (Join-Path $stage 'launcher')
$integrity = Join-Path $output 'payload-integrity.txt'
$checksums = Get-ChildItem -LiteralPath $stage -File -Recurse | Where-Object {
    $_.Extension -in @('.exe','.dll','.sys','.ps1','.args') -or $_.Name -eq 'catalog.txt'
} | Sort-Object FullName | ForEach-Object {
    (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() + '  ' + $_.FullName.Substring($stage.Length + 1).Replace('\','/')
}
[IO.File]::WriteAllLines($integrity,$checksums,[Text.Encoding]::UTF8)
Add-Type -AssemblyName System.IO.Compression.FileSystem
$payload = Join-Path $output ('payload-' + [Guid]::NewGuid().ToString('N') + '.zip')
[IO.Compression.ZipFile]::CreateFromDirectory($stage,$payload,[IO.Compression.CompressionLevel]::Optimal,$false)
$compiler = Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
$relativePayload = 'dist\' + [IO.Path]::GetFileName($payload)
$arguments = @('/nologo','/target:winexe','/optimize+','/platform:x64','/main:Kontur.Bootstrap',('/out:dist\' + $OutputName),'/reference:System.Windows.Forms.dll','/reference:System.Drawing.dll','/reference:System.IO.Compression.dll','/reference:System.IO.Compression.FileSystem.dll','/win32manifest:launcher\app.manifest','/win32icon:launcher\kontur.ico',('/resource:' + $relativePayload + ',Kontur.Payload'),'/resource:dist\payload-integrity.txt,Kontur.Integrity','launcher\MainForm.cs','launcher\Bootstrap.cs')
$response = Join-Path $output 'single.rsp'
[IO.File]::WriteAllLines($response,$arguments,[Text.Encoding]::UTF8)
Push-Location $root
try { & $compiler '@dist\single.rsp'; if ($LASTEXITCODE -ne 0) { throw 'Single EXE compilation failed.' } } finally { Pop-Location }
$exePath=Join-Path $output $OutputName
$hash=(Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText(($exePath+'.sha256'),($hash+'  '+$OutputName+[Environment]::NewLine),[Text.Encoding]::ASCII)
Write-Output ('Built standalone EXE: '+$exePath+' ('+(Get-Item -LiteralPath $exePath).Length+' bytes)')
