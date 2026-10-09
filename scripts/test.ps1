param([string]$Root = (Split-Path $PSScriptRoot -Parent))
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
[void][Reflection.Assembly]::LoadFrom((Join-Path $Root 'Kontur.exe'))
function Assert($condition,$message) { if (!$condition) { throw $message } }
$profiles = [Kontur.Engine]::Load($Root)
Assert ($profiles.Count -eq 22) 'Expected 22 profiles.'
$settings = New-Object Kontur.Settings
foreach ($mode in @('Выключен','TCP','UDP','TCP и UDP')) {
    $settings.GameMode = $mode
    foreach ($profile in $profiles) {
        $arguments = [Kontur.Engine]::Arguments($Root,$profile,$settings)
        Assert ($arguments.StartsWith('--wf-tcp=')) "Invalid profile $($profile.Name)"
        Assert (!$arguments.Contains('{') -and !$arguments.Contains('%')) "Unresolved variables: $($profile.Name)"
        Assert (!$arguments.Contains('^')) "Batch escaping survived: $($profile.Name)"
        Assert ($arguments.Length -lt 32767) "Windows process command length: $($profile.Name)"
        if ($mode -eq 'Выключен') { Assert (!$arguments.Contains('1024-65535')) 'Game mode disabled incorrectly.' }
        if ($mode -eq 'TCP и UDP') { Assert ($arguments.Contains('--filter-tcp=1024-65535') -and $arguments.Contains('--filter-udp=1024-65535')) 'Game mode enabled incorrectly.' }
    }
}
foreach ($value in @('1','65535','27015,27036-27037','1024-65535')) { Assert ([Kontur.Engine]::Ports($value)) "Rejected ports: $value" }
foreach ($value in @('0','65536','100-99','80,','-1','1;exit','abc','01','')) { Assert (![Kontur.Engine]::Ports($value)) "Accepted invalid ports: $value" }
New-Item -ItemType Directory -Force (Join-Path $Root 'artifacts') | Out-Null
$form = New-Object Kontur.MainForm($Root,$true)
try {
    $form.Show()
    [System.Windows.Forms.Application]::DoEvents()
    foreach ($page in @('Подключение','Настройки','Домены','Инструменты','Журнал','О программе')) {
        $form.CapturePage($page,(Join-Path $Root ('artifacts/' + $page + '.png')))
    }
} finally { $form.Dispose() }
Write-Output 'PASS: 88 profile configurations, port validation, six native UI pages rendered. No network engine or hosts changes performed.'
