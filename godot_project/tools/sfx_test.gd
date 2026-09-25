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
const AMBIENCE := preload("res://scripts/audio/ambience.gd")

## Выше этого фон считается режущим. Обоснование числа — у проверки.
const HARSH := 1.0

## Реже какого промежутка обязаны звучать слои с узнаваемым рисунком, секунды.
## Числа не с потолка: живой игрок попросил «хотя бы раз в 30 секунд» про
## стрекот, и это нижняя граница, а не пожелание.
const MIN_CRICKET_GAP := 20.0
const MIN_BIRD_GAP := 8.0

var _world: Node3D


func start(world: Node3D) -> void:
	tag = "звук"
	expected_host = 16
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
	_test_living_world()
	_test_background_is_not_harsh()
	_test_background_does_not_nag()

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
## Фон не режет ухо.
##
## СТОРОЖ ЗА ЖИВОЙ ЖАЛОБОЙ «противный звук бьёт по ушам». Виновата была не
## громкость, а форма: стрекот рубил тон прямоугольной крошкой, и у краёв
## оказались гармоники по всему диапазону — 40% энергии в полосе 5-8 кГц и
## заворот частот выше потолка. Убавленная громкость такое не лечит, только
## отодвигает.
##
## КАК МЕРЯЕМ БЕЗ СПЕКТРА. Полное преобразование в GDScript стоило бы секунд
## прогона, а нам нужен один вопрос: далеко ли энергия ушла вверх. На это
## честно отвечает отношение энергии РАЗНОСТЕЙ соседних отсчётов к энергии
## самого сигнала: у низкого звука соседние отсчёты почти равны и разности
## малы, у резкого — велики. Предел величины 4.0 (отсчёты через один).
##
## Замеры, по которым выбран порог:
##
##   ветер                       0.015
##   стрекот ПОСЛЕ починки       0.804
##   ПОРОГ                       1.000
##   стрекот ДО починки          1.318   <- так звучать не должно
func _test_background_is_not_harsh() -> void:
	var box := AMBIENCE.new()
	var loops := {
		"ветер": box._wind_loop(),
		"стрекот": box._cricket_trill(),
		"щебет": box._bird_call(0),
	}
	var bad := PackedStringArray()
	for label in loops:
		var sharp: float = _sharpness(loops[label])
		note("%s: резкость %.3f" % [label, sharp])
		if sharp >= HARSH:
			bad.append("%s: %.3f" % [label, sharp])
	check(bad.is_empty(), "фон не режет ухо: энергия не ушла в верх диапазона",
		"порог %.2f, превысили: %s" % [HARSH, ", ".join(bad)])


## Фон не навязчив: непрерывен только бесформенный слой.
##
## СТОРОЖ ЗА ВТОРОЙ ЖИВОЙ ЖАЛОБОЙ — «очень очень надоедает жутко». Стрекот
## крутился непрерывной петлёй: три трели на четыре секунды, то есть примерно
## раз в секунду. Ухо запоминает МОТИВ за полминуты и дальше слышит каждый
## повтор как навязчивость, сколько громкость ни убавляй. Щебет страдал тем же
## помягче: от 2.6 секунды, а в лесу втрое чаще.
##
## Правило, которое проверка и стережёт: непрерывным может быть только
## БЕСФОРМЕННЫЙ слой — шум ветра. Всё, у чего есть узнаваемый рисунок, звучит
## редко и через неровные промежутки.
func _test_background_does_not_nag() -> void:
	var box := AMBIENCE.new()
	var bad := PackedStringArray()

	var wind: AudioStreamWAV = box._wind_loop()
	if wind.loop_mode != AudioStreamWAV.LOOP_FORWARD:
		bad.append("ветер не зациклен, а должен: он и убирает тишину")
	var trill: AudioStreamWAV = box._cricket_trill()
	if trill.loop_mode != AudioStreamWAV.LOOP_DISABLED:
		bad.append("стрекот зациклен — он обязан быть разовым")
	var call: AudioStreamWAV = box._bird_call(0)
	if call.loop_mode != AudioStreamWAV.LOOP_DISABLED:
		bad.append("щебет зациклен")

	if AMBIENCE.CRICKET_GAP.x < MIN_CRICKET_GAP:
		bad.append("стрекот чаще раза в %d с" % int(MIN_CRICKET_GAP))
	if AMBIENCE.BIRD_GAP.x < MIN_BIRD_GAP:
		bad.append("щебет чаще раза в %d с" % int(MIN_BIRD_GAP))
	# Промежуток обязан ГУЛЯТЬ: ровно раз в тридцать секунд — тот же мотив,
	# только медленнее, и ухо его так же выучит.
	if AMBIENCE.CRICKET_GAP.y - AMBIENCE.CRICKET_GAP.x < 5.0:
		bad.append("промежуток стрекота не гуляет")

	note("стрекот раз в %d-%d с, щебет раз в %d-%d с" % [
		int(AMBIENCE.CRICKET_GAP.x), int(AMBIENCE.CRICKET_GAP.y),
		int(AMBIENCE.BIRD_GAP.x), int(AMBIENCE.BIRD_GAP.y)])
	check(bad.is_empty(), "фон не навязчив: непрерывен только шум ветра",
		", ".join(bad))


## Насколько звук «острый»: энергия разностей к энергии сигнала.
func _sharpness(wav: AudioStreamWAV) -> float:
	var data := wav.data
	var count: int = data.size() / 2
	if count < 2:
		return 0.0
	var diff := 0.0
	var power := 0.0
	var previous: float = float(data.decode_s16(0)) / 32768.0
	for i in range(1, count):
		var value: float = float(data.decode_s16(i * 2)) / 32768.0
		diff += (value - previous) * (value - previous)
		power += value * value
		previous = value
	if power <= 0.0:
		return 0.0
	return diff / power


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


## Живой фон: ветер, птицы, обоз, копыта.
##
## Живой отчёт: «игра ощущается пустынной». Пустынной её делало не отсутствие
## ударов, а отсутствие фона — между событиями стояла полная тишина.
##
## Проверяем ДАННЫЕ, как и весь этот набор: headless звука не слышит. Но данные
## тут говорят о многом — синтез легко вырождается в тишину или в постоянный
## отсчёт, и тогда «звук есть» означает ровный писк или ничего.
func _test_living_world() -> void:
	# Берём ОТДЕЛЬНЫЙ экземпляр и строим сэмплы руками: у автозагрузки в
	# прогоне без окна звук выключен целиком и сэмплов нет вовсе — спрашивать
	# у неё значит проверять, что звук выключен.
	var box := SFX.new()
	box._build_samples()
	var cart: AudioStream = box._samples.get(SFX.Kind.CART, null)
	var hoof: AudioStream = box._samples.get(SFX.Kind.HOOF, null)
	check(cart != null and hoof != null, "обоз и копыта синтезированы",
		"обоз %s, копыто %s" % [cart != null, hoof != null])

	# Обоз ЕДЕТ долго, а сэмпл короткий: без петли он смолкнет на полдороге.
	var looping: bool = (cart is AudioStreamWAV
		and (cart as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD)
	check(looping, "скрип обоза зациклен", "петля: %s" % looping)

	# Ветер — то, что убирает тишину. Он обязан быть длинным и зациклённым:
	# короткая петля слышна как повторяющийся шорох и раздражает сильнее тишины.
	var air := AMBIENCE.new()
	var wind: AudioStreamWAV = air._wind_loop()
	var seconds: float = float(wind.data.size() / 2) / float(air.MIX_RATE)
	check(wind.loop_mode == AudioStreamWAV.LOOP_FORWARD and seconds > 5.0,
		"ветер длинный и зациклен", "%.1f с, петля %s" % [
			seconds, wind.loop_mode == AudioStreamWAV.LOOP_FORWARD])

	# И он не должен быть тишиной. Синтез, ушедший в ноль, — самая обидная
	# поломка звука: всё «есть», а не слышно ничего.
	var bird: AudioStreamWAV = air._bird_call(1)
	check(_loudest(wind) > 0.05 and _loudest(bird) > 0.1,
		"ветер и щебет звучат, а не молчат",
		"ветер %.2f, щебет %.2f" % [_loudest(wind), _loudest(bird)])
	air.free()
	box.free()


## Самый громкий отсчёт в сэмпле, от 0 до 1.
func _loudest(wav: AudioStreamWAV) -> float:
	var top := 0
	var count: int = wav.data.size() / 2
	var step: int = maxi(1, count / 2000)
	for i in range(0, count, step):
		top = maxi(top, absi(wav.data.decode_s16(i * 2)))
	return float(top) / 32767.0
