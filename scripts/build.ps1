$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$compiler = Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
if (!(Test-Path -LiteralPath $compiler)) { throw 'Install .NET Framework 4.8 developer tools or enable .NET Framework.' }
$arguments = @('/nologo','/target:winexe','/optimize+','/platform:x64','/out:Kontur.exe','/reference:System.Windows.Forms.dll','/reference:System.Drawing.dll','/win32manifest:launcher\app.manifest')
if (Test-Path -LiteralPath "$root/launcher\kontur.ico") { $arguments += '/win32icon:launcher\kontur.ico' }
$arguments += 'launcher\MainForm.cs'
$response = Join-Path $PSScriptRoot 'build.rsp'
[IO.File]::WriteAllLines($response, $arguments, [Text.Encoding]::UTF8)
Push-Location $root
try { & $compiler '@scripts/build.rsp' } finally { Pop-Location; Remove-Item -LiteralPath $response -ErrorAction SilentlyContinue }
if ($LASTEXITCODE -ne 0) { throw 'Compilation failed.' }
Write-Output 'Built Kontur.exe'



