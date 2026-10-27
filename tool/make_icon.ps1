# Genera los PNG del icono de Nido (huevo frito sobre el verde de la marca).
#   assets/icon/nido_icon.png        icono completo, esquinas redondeadas (Windows, web, Android antiguo)
#   assets/icon/nido_foreground.png  solo el huevo, fondo transparente (icono adaptativo de Android)
# Uso: powershell -ExecutionPolicy Bypass -File tool\make_icon.ps1   (desde la carpeta nido)

Add-Type -AssemblyName System.Drawing

$size = 1024
$outDir = Join-Path $PSScriptRoot '..\assets\icon'
New-Item -ItemType Directory -Force $outDir | Out-Null

$green = [System.Drawing.ColorTranslator]::FromHtml('#2F6B4F')
$white = [System.Drawing.ColorTranslator]::FromHtml('#FBFAF5')
$yolk = [System.Drawing.ColorTranslator]::FromHtml('#F2B33D')
$yolkShade = [System.Drawing.ColorTranslator]::FromHtml('#E39A1E')
$shine = [System.Drawing.Color]::FromArgb(150, 255, 255, 255)

function New-Canvas {
  $bmp = New-Object System.Drawing.Bitmap $size, $size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = 'AntiAlias'
  $g.InterpolationMode = 'HighQualityBicubic'
  $g.Clear([System.Drawing.Color]::Transparent)
  return $bmp, $g
}

function Draw-Egg($g, [double]$scale) {
  $c = $size / 2
  # Clara: curva cerrada con radios irregulares para que parezca un huevo frito.
  $n = 36
  $pts = for ($i = 0; $i -lt $n; $i++) {
    $a = 2 * [Math]::PI * $i / $n - [Math]::PI / 2
    $wobble = 0.018 * [Math]::Sin(3 * $a + 0.6) + 0.012 * [Math]::Cos(5 * $a) + 0.006 * [Math]::Sin(7 * $a + 1.3)
    $r = (0.35 + $wobble) * $size * $scale
    New-Object System.Drawing.PointF ([float]($c + $r * [Math]::Cos($a))), ([float]($c + $r * [Math]::Sin($a)))
  }
  $g.FillClosedCurve((New-Object System.Drawing.SolidBrush $white), [System.Drawing.PointF[]]$pts, 'Alternate', 0.5)

  # Yema con un poco de sombra y un brillo.
  $yr = 0.145 * $size * $scale
  $yx = $c + 0.02 * $size * $scale
  $yy = $c - 0.01 * $size * $scale
  $g.FillEllipse((New-Object System.Drawing.SolidBrush $yolkShade), [float]($yx - $yr), [float]($yy - $yr + $yr * 0.08), [float](2 * $yr), [float](2 * $yr))
  $g.FillEllipse((New-Object System.Drawing.SolidBrush $yolk), [float]($yx - $yr), [float]($yy - $yr), [float](2 * $yr), [float](2 * $yr))
  $sr = $yr * 0.28
  $g.FillEllipse((New-Object System.Drawing.SolidBrush $shine), [float]($yx - $yr * 0.45 - $sr), [float]($yy - $yr * 0.45 - $sr), [float](2 * $sr), [float](2 * $sr))
}

# Icono completo con esquinas redondeadas.
$bmp, $g = New-Canvas
$radius = [int]($size * 0.22)
$path = New-Object System.Drawing.Drawing2D.GraphicsPath
$d = 2 * $radius
$path.AddArc(0, 0, $d, $d, 180, 90)
$path.AddArc($size - $d, 0, $d, $d, 270, 90)
$path.AddArc($size - $d, $size - $d, $d, $d, 0, 90)
$path.AddArc(0, $size - $d, $d, $d, 90, 90)
$path.CloseFigure()
$g.FillPath((New-Object System.Drawing.SolidBrush $green), $path)
Draw-Egg $g 1.0
$bmp.Save((Join-Path $outDir 'nido_icon.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()

# Primer plano para el icono adaptativo: el huevo más pequeño, dentro de la zona segura.
$bmp, $g = New-Canvas
Draw-Egg $g 0.68
$bmp.Save((Join-Path $outDir 'nido_foreground.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()

# .ico de Windows con varios tamaños (barra de tareas, Alt+Tab, escritorio).
# Se escribe después de `dart run flutter_launcher_icons`, que solo genera 256 px.
$icoPath = Join-Path $PSScriptRoot '..\windows\runner\resources\app_icon.ico'
$src = [System.Drawing.Image]::FromFile((Join-Path $outDir 'nido_icon.png'))
$sizes = 16, 20, 24, 32, 40, 48, 64, 128, 256
$images = foreach ($s in $sizes) {
  $bmp = New-Object System.Drawing.Bitmap $s, $s, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.InterpolationMode = 'HighQualityBicubic'
  $g.SmoothingMode = 'AntiAlias'
  $g.PixelOffsetMode = 'HighQuality'
  $g.DrawImage($src, 0, 0, $s, $s)
  $ms = New-Object System.IO.MemoryStream
  $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
  $g.Dispose(); $bmp.Dispose()
  , $ms.ToArray()
}
$src.Dispose()
$fs = [System.IO.File]::Create($icoPath)
$w = New-Object System.IO.BinaryWriter $fs
$w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
  $s = $sizes[$i]; $len = $images[$i].Length
  $w.Write([byte]($s % 256)); $w.Write([byte]($s % 256)); $w.Write([byte]0); $w.Write([byte]0)
  $w.Write([uint16]1); $w.Write([uint16]32); $w.Write([uint32]$len); $w.Write([uint32]$offset)
  $offset += $len
}
foreach ($img in $images) { $w.Write($img) }
$w.Close()

Write-Output "Iconos generados en $((Resolve-Path $outDir).Path) y $((Resolve-Path $icoPath).Path)"
