# Снимок экрана для работы над интерфейсом.
#
# Интерфейс нельзя переделывать вслепую: headless-прогон покажет, что код
# исполняется, и ничего не скажет о том, читается ли получившееся глазами.
# Скрипт запускает игру в окне, ждёт, снимает экран и закрывает её.
#
#   .\tools\shot.ps1 -Out before.png
#   .\tools\shot.ps1 -Out after.png -Seconds 12 -Args "--host --faction=0"
param(
    [string]$Out = "shot.png",
    [int]$Seconds = 10,
    [string]$GameArgs = "--host --faction=0",
    [string]$Godot = "$env:USERPROFILE\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe",
    [int]$Width = 1600,
    [int]$Height = 900
)

$ErrorActionPreference = "Stop"
$project = Join-Path $PSScriptRoot "..\godot_project"

$list = @("--path", $project, "--resolution", "${Width}x${Height}", "--", "--freshworld")
foreach ($a in $GameArgs.Split(" ")) { if ($a -ne "") { $list += $a } }

Write-Host "Запускаю игру в окне ${Width}x${Height}…"
$proc = Start-Process -FilePath $Godot -ArgumentList $list -PassThru
Start-Sleep -Seconds $Seconds

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bmp = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
$gfx = [System.Drawing.Graphics]::FromImage($bmp)
$gfx.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
$path = if ([System.IO.Path]::IsPathRooted($Out)) { $Out } else { Join-Path (Get-Location) $Out }
$bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
$gfx.Dispose()
$bmp.Dispose()

if (-not $proc.HasExited) { $proc.Kill() }
Write-Host "Снимок: $path"
