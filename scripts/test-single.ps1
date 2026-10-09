$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Add-Type -AssemblyName System.Windows.Forms,System.Drawing,System.IO.Compression,System.IO.Compression.FileSystem
[void][Reflection.Assembly]::LoadFrom((Join-Path $root 'dist/Kontur.exe'))
$sandbox = Join-Path $root ('artifacts/single-exe-' + [Guid]::NewGuid().ToString('N'))
$runtime = [Kontur.Bootstrap]::PrepareRuntime($sandbox)
if(!(Test-Path -LiteralPath (Join-Path $runtime 'bin/winws.exe'))) {throw 'Embedded engine missing.'}
if([Kontur.Engine]::Load($runtime).Count -ne 22) {throw 'Embedded profiles missing.'}
if(Test-Path -LiteralPath (Join-Path $runtime 'bin/telegram/TgWsProxy_data/config.json')) {throw 'Local Telegram secret packaged.'}
$settings = New-Object Kontur.Settings
foreach ($profile in [Kontur.Engine]::Load($runtime)) { [void][Kontur.Engine]::Arguments($runtime,$profile,$settings) }
$customList=Join-Path $runtime 'lists/list-general-user.txt'
[IO.File]::WriteAllText($customList,'custom.example',[Text.Encoding]::UTF8)
$again=[Kontur.Bootstrap]::PrepareRuntime($sandbox)
if($again -ne $runtime -or [IO.File]::ReadAllText($customList) -ne 'custom.example') {throw 'Repeat launch lost user state.'}
$form = New-Object Kontur.MainForm($runtime,$true)
try { $form.Show(); [System.Windows.Forms.Application]::DoEvents(); $form.CapturePage('Подключение',(Join-Path $sandbox 'single-exe.png')) } finally {$form.Dispose()}
$critical=Join-Path $runtime 'profiles/standard.args'
[IO.File]::AppendAllText($critical,' tampered')
$rejected=$false
try {[void][Kontur.Bootstrap]::PrepareRuntime($sandbox)} catch {$rejected=$true}
if(!$rejected) {throw 'Modified embedded strategy was not detected.'}
Write-Output 'PASS: isolated EXE extraction, bundled dependencies and 22 profiles, repeat launch, user list persistence, UI render and integrity validation. No engine started or hosts changed.'
