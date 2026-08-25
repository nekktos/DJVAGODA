# Запуск двух окон «ДжваГода» на одной машине для теста Этапа 0.
#   .\run_two_clients.ps1                 — хост + клиент на 127.0.0.1
#   .\run_two_clients.ps1 -Bot            — оба персонажа ходят по кругу сами
#   .\run_two_clients.ps1 -NetLog         — печатать позиции игроков в консоль
#   .\run_two_clients.ps1 -Godot "путь"   — указать другой godot.exe
param(
    [string]$Godot = "$env:USERPROFILE\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe",
    [switch]$Bot,
    [switch]$NetLog
)

if (-not (Test-Path $Godot)) {
    Write-Error "Не найден Godot: $Godot . Передай путь через -Godot."
    exit 1
}

$project = Join-Path $PSScriptRoot "godot_project"
$extra = @()
if ($Bot)    { $extra += "--bot" }
if ($NetLog) { $extra += "--netlog" }

$common = @("--path", $project, "--resolution", "960x540")

Start-Process -FilePath $Godot -ArgumentList ($common + @("--position","20,40","--","--host") + $extra)
Start-Sleep -Milliseconds 1500
Start-Process -FilePath $Godot -ArgumentList ($common + @("--position","1000,40","--","--join=127.0.0.1") + $extra)

Write-Host "Два окна запущены. Esc — освободить курсор, F10 — выйти в меню."
