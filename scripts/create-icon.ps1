$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$root = Split-Path $PSScriptRoot -Parent
$bitmap = New-Object Drawing.Bitmap(64,64)
$graphics = [Drawing.Graphics]::FromImage($bitmap)
try {
    $graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.Clear([Drawing.Color]::FromArgb(32,43,40))
    $pen = New-Object Drawing.Pen([Drawing.Color]::FromArgb(190,230,204),5)
    try {
        $graphics.DrawEllipse($pen,13,13,38,38)
        $graphics.DrawArc($pen,23,23,18,18,35,285)
        $graphics.DrawLine($pen,42,21,53,10)
    } finally { $pen.Dispose() }
    $png = New-Object IO.MemoryStream
    $bitmap.Save($png,[Drawing.Imaging.ImageFormat]::Png)
    $bytes = $png.ToArray()
    $stream = [IO.File]::Create((Join-Path $root 'launcher/kontur.ico'))
    $writer = New-Object IO.BinaryWriter($stream)
    try {
        $writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]1)
        $writer.Write([byte]64); $writer.Write([byte]64); $writer.Write([byte]0); $writer.Write([byte]0)
        $writer.Write([uint16]1); $writer.Write([uint16]32); $writer.Write([uint32]$bytes.Length); $writer.Write([uint32]22); $writer.Write($bytes)
    } finally { $writer.Dispose(); $png.Dispose() }
} finally { $graphics.Dispose(); $bitmap.Dispose() }
