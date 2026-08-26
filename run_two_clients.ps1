# Запуск нескольких окон «ДжваГода» на одной машине для playtest.
#
#   .\run_two_clients.ps1                  — хост + один клиент
#   .\run_two_clients.ps1 -Count 3         — хост + два клиента
#   .\run_two_clients.ps1 -Factions 0,1,2  — кто за кого (0 злодей, 1 эльфы, 2 стража)
#   .\run_two_clients.ps1 -Fresh           — начать с чистого мира, не подхватывая сохранение
#   .\run_two_clients.ps1 -Bot             — персонажи ходят по кругу сами
#   .\run_two_clients.ps1 -NetLog          — печатать позиции игроков в консоль
#   .\run_two_clients.ps1 -Godot "путь"    — указать другой godot.exe
#
# ВАЖНО про профили. Все окна на одной машине делят папку user://, а значит и
# файл профиля игрока. Без разных профилей игра считала бы всех ОДНИМ человеком:
# второй игрок садился бы за сторону первого и тянул его сохранённый прогресс.
# Поэтому каждому окну здесь выдаётся свой профиль (--profile).
param(
    [string]$Godot = "$env:USERPROFILE\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe",
    [ValidateRange(1, 3)]
    [int]$Count = 2,
    [int[]]$Factions = @(),
    [switch]$Fresh,
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
if ($Fresh)  { $extra += "--freshworld" }

$common = @("--path", $project, "--resolution", "800x480")
$slots = @("20,40", "840,40", "20,580")
# Профили постоянные, а не случайные: прогресс должен находиться при следующем
# запуске, иначе сохранения проверить нечем.
$profiles = @("local-1", "local-2", "local-3")

function Get-FactionArg([int]$index) {
    if ($index -lt $Factions.Count) { return @("--faction=$($Factions[$index])") }
    return @()
}

$args0 = $common + @("--position", $slots[0], "--", "--host", "--profile=$($profiles[0])") `
    + (Get-FactionArg 0) + $extra
Start-Process -FilePath $Godot -ArgumentList $args0

for ($i = 1; $i -lt $Count; $i++) {
    Start-Sleep -Milliseconds 1500
    $argsN = $common + @("--position", $slots[$i], "--", "--join=127.0.0.1", "--profile=$($profiles[$i])") `
        + (Get-FactionArg $i) + $extra
    Start-Process -FilePath $Godot -ArgumentList $argsN
}

Write-Host "Запущено окон: $Count. Профили: $($profiles[0..($Count-1)] -join ', ')."
Write-Host "Esc — освободить курсор, F10 — выйти в меню, тильда — консоль."
if ($Fresh) { Write-Host "Мир чистый: сохранение не подхватывается и не пишется." }
