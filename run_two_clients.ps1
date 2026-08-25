# Запуск нескольких окон «ДжваГода» на одной машине для теста Этапа 0.
#   .\run_two_clients.ps1              — хост + один клиент
#   .\run_two_clients.ps1 -Count 3     — хост + два клиента (максимум сессии)
#   .\run_two_clients.ps1 -Bot         — персонажи ходят по кругу сами
#   .\run_two_clients.ps1 -NetLog      — печатать позиции игроков в консоль
#   .\run_two_clients.ps1 -Godot "путь" — указать другой godot.exe
param(
    [string]$Godot = "$env:USERPROFILE\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe",
    [ValidateRange(1, 3)]
    [int]$Count = 2,
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

$common = @("--path", $project, "--resolution", "800x480")
$slots = @("20,40", "840,40", "20,580")

Start-Process -FilePath $Godot -ArgumentList ($common + @("--position", $slots[0], "--", "--host") + $extra)

for ($i = 1; $i -lt $Count; $i++) {
    Start-Sleep -Milliseconds 1500
    Start-Process -FilePath $Godot -ArgumentList ($common + @("--position", $slots[$i], "--", "--join=127.0.0.1") + $extra)
}

Write-Host "Запущено окон: $Count. Esc — освободить курсор, F10 — выйти в меню."
