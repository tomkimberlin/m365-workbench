[CmdletBinding()]
param(
    [string]$OutputPath = (Join-Path $PSScriptRoot 'M365Workbench.ico'),
    [string]$PreviewPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing

function New-RoundedRectanglePath {
    param(
        [Parameter(Mandatory)][System.Drawing.RectangleF]$Rectangle,
        [Parameter(Mandatory)][single]$Radius
    )

    $diameter = [single]($Radius * 2)
    $path = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $path.AddArc($Rectangle.X, $Rectangle.Y, $diameter, $diameter, 180, 90)
    $path.AddArc($Rectangle.Right - $diameter, $Rectangle.Y, $diameter, $diameter, 270, 90)
    $path.AddArc($Rectangle.Right - $diameter, $Rectangle.Bottom - $diameter, $diameter, $diameter, 0, 90)
    $path.AddArc($Rectangle.X, $Rectangle.Bottom - $diameter, $diameter, $diameter, 90, 90)
    $path.CloseFigure()
    return $path
}

function New-LogoBitmap {
    param([Parameter(Mandatory)][int]$Size)

    $scale = [single]($Size / 64.0)
    $bitmap = [System.Drawing.Bitmap]::new($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)

    try {
        $graphics.Clear([System.Drawing.Color]::Transparent)
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality

        $logoRectangle = [System.Drawing.RectangleF]::new(4 * $scale, 4 * $scale, 56 * $scale, 56 * $scale)
        $logoPath = New-RoundedRectanglePath -Rectangle $logoRectangle -Radius (16 * $scale)
        $background = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
            $logoRectangle,
            [System.Drawing.ColorTranslator]::FromHtml('#2563EB'),
            [System.Drawing.ColorTranslator]::FromHtml('#4338CA'),
            48.0
        )

        try {
            $graphics.FillPath($background, $logoPath)
        }
        finally {
            $background.Dispose()
            $logoPath.Dispose()
        }

        # One active module sits on a work surface supported by the product's W-shaped brace.
        $bracePoints = [System.Drawing.PointF[]]@(
            [System.Drawing.PointF]::new(19 * $scale, 28 * $scale),
            [System.Drawing.PointF]::new(23 * $scale, 45 * $scale),
            [System.Drawing.PointF]::new(32 * $scale, 35 * $scale),
            [System.Drawing.PointF]::new(41 * $scale, 45 * $scale),
            [System.Drawing.PointF]::new(45 * $scale, 28 * $scale)
        )
        $markPen = [System.Drawing.Pen]::new([System.Drawing.Color]::White, [single](5 * $scale))
        try {
            $markPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
            $markPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
            $markPen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
            $graphics.DrawLines($markPen, $bracePoints)
        }
        finally {
            $markPen.Dispose()
        }

        $surfaceRectangle = [System.Drawing.RectangleF]::new(14 * $scale, 24 * $scale, 36 * $scale, 6 * $scale)
        $surfacePath = New-RoundedRectanglePath -Rectangle $surfaceRectangle -Radius (3 * $scale)
        $surface = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::White)
        try {
            $graphics.FillPath($surface, $surfacePath)
        }
        finally {
            $surface.Dispose()
            $surfacePath.Dispose()
        }

        $moduleRectangle = [System.Drawing.RectangleF]::new(36 * $scale, 16 * $scale, 10 * $scale, 9 * $scale)
        $modulePath = New-RoundedRectanglePath -Rectangle $moduleRectangle -Radius (2.25 * $scale)
        $accent = [System.Drawing.SolidBrush]::new([System.Drawing.ColorTranslator]::FromHtml('#7DD3FC'))
        try {
            $graphics.FillPath($accent, $modulePath)
        }
        finally {
            $accent.Dispose()
            $modulePath.Dispose()
        }
    }
    finally {
        $graphics.Dispose()
    }

    return $bitmap
}

$outputDirectory = Split-Path -Parent $OutputPath
if ($outputDirectory -and -not (Test-Path -LiteralPath $outputDirectory)) {
    $null = New-Item -ItemType Directory -Path $outputDirectory
}

$images = [System.Collections.Generic.List[object]]::new()
foreach ($size in @(16, 20, 24, 32, 40, 48, 64, 128, 256)) {
    $bitmap = New-LogoBitmap -Size $size
    $stream = [System.IO.MemoryStream]::new()
    try {
        $bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
        $images.Add([pscustomobject]@{ Size = $size; Bytes = $stream.ToArray() })
    }
    finally {
        $stream.Dispose()
        $bitmap.Dispose()
    }
}

$fileStream = [System.IO.File]::Open($OutputPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
$writer = [System.IO.BinaryWriter]::new($fileStream)
try {
    $writer.Write([uint16]0)
    $writer.Write([uint16]1)
    $writer.Write([uint16]$images.Count)

    $imageOffset = 6 + (16 * $images.Count)
    foreach ($image in $images) {
        $dimension = if ($image.Size -eq 256) { [byte]0 } else { [byte]$image.Size }
        $writer.Write($dimension)
        $writer.Write($dimension)
        $writer.Write([byte]0)
        $writer.Write([byte]0)
        $writer.Write([uint16]1)
        $writer.Write([uint16]32)
        $writer.Write([uint32]$image.Bytes.Length)
        $writer.Write([uint32]$imageOffset)
        $imageOffset += $image.Bytes.Length
    }

    foreach ($image in $images) {
        $writer.Write([byte[]]$image.Bytes)
    }
}
finally {
    $writer.Dispose()
    $fileStream.Dispose()
}

if ($PreviewPath) {
    $previewDirectory = Split-Path -Parent $PreviewPath
    if ($previewDirectory -and -not (Test-Path -LiteralPath $previewDirectory)) {
        $null = New-Item -ItemType Directory -Path $previewDirectory
    }
    $preview = New-LogoBitmap -Size 512
    try {
        $preview.Save($PreviewPath, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $preview.Dispose()
    }
}

Write-Output $OutputPath
