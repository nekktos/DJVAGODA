# Сборка playtest-версий «ДжваГоды» под Windows и macOS.
#
#   .\build_playtest.ps1                 — собрать обе платформы
#   .\build_playtest.ps1 -Release        — релизная сборка (без консоли и читов)
#   .\build_playtest.ps1 -Godot "путь"   — указать другой godot.exe
#
# Что нужно заранее: установленные шаблоны экспорта Godot той же версии, что и
# редактор. Проверить: %APPDATA%\Godot\export_templates\<версия>\ — если папки
# нет, скрипт скажет об этом и остановится.
#
# Сборка НЕ ПОДПИСАНА ни на одной платформе. На macOS это значит, что Gatekeeper
# заблокирует запуск, и тестеру придётся снять карантин вручную — как написано в
# инструкции, которая кладётся внутрь архива.
param(
    [string]$Godot = "$env:USERPROFILE\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe",
    [switch]$Release
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $Godot)) {
    Write-Error "Не найден Godot: $Godot . Передай путь через -Godot."
    exit 1
}

$root = $PSScriptRoot
$project = Join-Path $root "godot_project"
$build = Join-Path $root "build"
$readme = Join-Path $root "PLAYTEST_TESTERS.md"
# Анкета едет РЯДОМ с инструкцией: без неё отчёты приходят в свободной форме и
# не сравниваются между собой.
$form = Join-Path $root "PLAYTEST_FORM.md"

# Версия берётся из project.godot, чтобы имя архива и то, что видно в игре,
# не могли разойтись.
$version = (Select-String -Path (Join-Path $project "project.godot") -Pattern 'config/version="([^"]+)"').Matches[0].Groups[1].Value
Write-Host "Версия сборки: $version"

$mode = if ($Release) { "--export-release" } else { "--export-debug" }
Write-Host ("Режим: " + $(if ($Release) { "релиз (без консоли)" } else { "отладка (консоль на тильду доступна)" }))

# Пересобираем импорт: без него экспорт может взять устаревшие ресурсы.
& $Godot --headless --path $project --import | Out-Null

Remove-Item -Recurse -Force $build -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force (Join-Path $build "windows") | Out-Null
New-Item -ItemType Directory -Force (Join-Path $build "macos") | Out-Null

Write-Host "`n=== Windows ==="
& $Godot --headless --path $project $mode "Windows" (Join-Path $build "windows\DzhvaGoda.exe")
if ($LASTEXITCODE -ne 0) { Write-Error "Экспорт под Windows не удался"; exit 1 }
Copy-Item $readme (Join-Path $build "windows\README-PLAYTEST.md") -Force
Copy-Item $form (Join-Path $build "windows\АНКЕТА.md") -Force

Write-Host "`n=== macOS ==="
& $Godot --headless --path $project $mode "macOS" (Join-Path $build "macos\DzhvaGoda.zip")
if ($LASTEXITCODE -ne 0) { Write-Error "Экспорт под macOS не удался"; exit 1 }

# Архив, который выдал Godot, НЕ ТРОГАЕМ. Внутри него у DzhvaGoda.app/Contents/
# MacOS/DzhvaGoda стоит бит запуска (-rwxr-xr-x, хост unx). Любая перезапись
# через System.IO.Compression сбрасывает права в -rw---- и меняет хост на fat:
# .NET Framework игнорирует ExternalAttributes при записи, проверено. Тестер
# после такого получает .app, который не запускается вовсе.
#
# Поэтому инструкцию кладём не внутрь, а РЯДОМ, и заворачиваем оба файла во
# внешний архив: внутренний .zip для него просто байты, права переживают.
# Цена — тестер распаковывает дважды; это написано первой строкой инструкции.
Copy-Item $readme (Join-Path $build "macos\README-PLAYTEST.md") -Force
Copy-Item $form (Join-Path $build "macos\АНКЕТА.md") -Force

# Итоговые архивы для раздачи.
$winZip = Join-Path $build "DzhvaGoda-$version-windows.zip"
Compress-Archive -Path (Join-Path $build "windows\*") -DestinationPath $winZip -Force
$macOut = Join-Path $build "DzhvaGoda-$version-macos.zip"
Compress-Archive -Path (Join-Path $build "macos\*") -DestinationPath $macOut -Force

Write-Host "`n=== Готово ==="
Get-ChildItem $build -Filter "*.zip" | ForEach-Object {
    "{0,-42} {1,7:N1} МБ" -f $_.Name, ($_.Length / 1MB)
}
Write-Host "`nПапка: $build"
Write-Host "macOS подписана СОБСТВЕННОЙ подписью (codesign/codesign=1 в пресете)."
Write-Host "Без неё маки на Apple Silicon не запускают программу вовсе — объявляют повреждённой."
Write-Host "Заверения у Apple нет, поэтому первый запуск тестер подтверждает вручную: см. README."
Write-Host "В архиве macOS лежат README и вложенный DzhvaGoda.zip — распаковывать дважды."
