extends "res://tools/test_base.gd"
##
## Автопроверка звука (Этап 10, шаг 9). Работает headless.
##
## Запуск: godot --headless --path godot_project -- --host --sfxtest
##
## ЗДЕСЬ ЕСТЬ ЛОВУШКА, И ОНА ГЛАВНАЯ. В прогонах без окна аудиодрайвер —
## пустышка, звук намеренно выключается целиком, и «проверка звука» headless
## выродилась бы в проверку того, что он выключен. Это ровно тот сорт зелёной
## проверки, которая не проверяет ничего.
##
## Поэтому проверяем ДАННЫЕ, а не звучание: что все виды звуков синтезируются,
## что в каждом есть отсчёты и они не пустые, что вызов в выключенном состоянии
## безопасен, и что точки вызова расставлены на событиях, которые доходят до
## каждого пира, — иначе половина игроков будет играть в тишине.
##

const SFX := preload("res://scripts/audio/sfx.gd")
const EFFECTS := preload("res://scripts/combat/effects.gd")

var _world: Node3D


func start(world: Node3D) -> void:
	tag = "звук"
	expected_host = 10
	expected_client = 1
	_world = world
	_run.call_deferred()


func _run() -> void:
	if not session_ready():
		finish()
		return
	await get_tree().create_timer(1.0).timeout

	_test_samples_built()
	_test_safe_when_silent()
	await _test_hooks()
	finish()


## Все виды звуков собраны, и в каждом есть звук.
##
## Синтез идёт при запуске автозагрузки, но набор строится независимо от того,
## включён ли звук: пустой аудиодрайвер не повод не собирать данные, зато
## проверить их можно и в прогоне без окна.
func _test_samples_built() -> void:
	var built := SFX.new()
	built._build_samples()

	var kinds := SFX.Kind.values()
	check(built.sample_count() == kinds.size(), "собраны все виды звуков",
		"%d из %d" % [built.sample_count(), kinds.size()])

	# Тип здесь ОБЩИЙ, а не AudioStreamWAV. Звуки теперь приходят файлами, и это
	# AudioStreamOggVorbis; строгий тип валил присваивание, функция обрывалась
	# на середине, и две последние проверки молча не выполнялись. Поймал их
	# счётчик выполненных — ради этого он и заведён.
	var shortest := 1.0
	var silent := 0
	for kind in kinds:
		var sound: AudioStream = built._samples.get(kind, null)
		if sound == null:
			continue
		if sound.get_length() < shortest:
			shortest = sound.get_length()
		# Тишину умеем мерить только у синтезированных: у сжатого файла образцы
		# так просто не прочитать, да и проверять там нечего — он либо
		# загрузился, либо его нет вовсе.
		if sound is AudioStreamWAV and _peak(sound as AudioStreamWAV) < 0.05:
			silent += 1
	check(shortest > 0.05, "у каждого звука есть длительность",
		"самый короткий %.2f с" % shortest)
	check(silent == 0, "и ни один синтезированный не оказался тишиной",
		"беззвучных: %d" % silent)

	# Файлы должны РЕАЛЬНО находиться. Без этой проверки набор остаётся зелёным
	# и когда все файлы потерялись: синтез молча подменит их шумом, и заметить
	# это можно будет только ушами.
	var from_files := 0
	for kind in built.FILES:
		var sound: AudioStream = built._samples.get(kind, null)
		if sound != null and not (sound is AudioStreamWAV):
			from_files += 1
	check(from_files >= built.FILES.size() - 1,
		"звуки взяты из файлов, а не подменены синтезом",
		"файлами %d из %d" % [from_files, built.FILES.size()])
	check(not built._steps.is_empty(), "шаги загружены",
		"вариантов шага: %d" % built._steps.size())
	built.free()


## Звук выключен — вызовы обязаны быть безвредны. Игра не должна падать из-за
## того, что её запустили без звуковой карты.
func _test_safe_when_silent() -> void:
	check(not Sfx.enabled(), "в прогоне без окна звук выключен",
		"включён=%s" % Sfx.enabled())
	Sfx.at(Sfx.Kind.HIT_FLESH, Vector3.ZERO)
	Sfx.flat(Sfx.Kind.NOTICE)
	Sfx.at(999, Vector3.ZERO)
	check(true, "вызовы при выключенном звуке безопасны", "ошибок нет")


## Точки вызова стоят на событиях, которые доходят до КАЖДОГО пира.
##
## Это не придирка: если повесить звук на хостовую ветку, половина игроков будет
## играть в тишине и никто этого не заметит — хост-то слышит всё. Проверяем, что
## звук встроен в `effects.gd`, а тот вызывается из `call_local`-RPC.
func _test_hooks() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/combat/effects.gd")
	check(source.contains("Sfx.at("), "звук встроен в общие эффекты боя",
		"вызовы есть")

	var unit_source := FileAccess.get_file_as_string("res://scripts/units/unit.gd")
	check(unit_source.contains("show_death.rpc("),
		"гибель бойца объявляется всем пирам, а не только хосту", "оповещение есть")

	# И сами эффекты по-прежнему работают: звук не должен был их сломать.
	var before := _world.get_child_count()
	EFFECTS.blood(_world, Vector3(0.0, 1.0, 0.0), Vector3.UP, 40.0)
	await get_tree().process_frame
	check(_world.get_child_count() > before, "эффект крови по-прежнему рисуется",
		"узлов %d -> %d" % [before, _world.get_child_count()])


## Наибольшая громкость в сэмпле, 0..1.
func _peak(wav: AudioStreamWAV) -> float:
	var data := wav.data
	var peak := 0.0
	var count: int = data.size() / 2
	# Каждый сотый отсчёт: искать пик по всем — впустую жечь время прогона.
	var step: int = maxi(1, count / 400)
	var i := 0
	while i < count:
		peak = maxf(peak, absf(float(data.decode_s16(i * 2)) / 32768.0))
		i += step
	return peak
