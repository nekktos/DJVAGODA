extends Node
##
## Живой фон: ветер, птицы, насекомые. Автозагрузка `Ambience`.
##
## ЗАЧЕМ ОТДЕЛЬНО ОТ `sfx.gd`. Тот играет СОБЫТИЯ: ударили, выстрелили, достроили.
## Между событиями стояла полная тишина, и живой отчёт назвал это точно — «игра
## ощущается пустынной». Пустынной её делает не отсутствие ударов, а отсутствие
## фона: настоящий лес шумит, даже когда в нём ничего не происходит.
##
## ЗВУК СИНТЕЗИРОВАН, А НЕ ВЗЯТ ФАЙЛАМИ. Та же причина, по которой модели теперь
## свои: чужих ассетов в проекте не держим. И причина частная — ветер, щебет и
## стрекот синтезируются ЛЕГЧЕ удара: это шум под фильтром и пара качающихся
## тонов, а не запись физического события.
##
## КАК УСТРОЕНО. Три слоя, и каждый решает свою задачу:
##
##   ветер     — непрерывная петля, тише всего, слышна всегда. Она и убирает
##               тишину; её не замечают, пока не выключишь.
##   птицы     — редкие щебеты вокруг слушателя, чаще в лесу. Именно они читаются
##               как «здесь кто-то живёт»: постоянный звук ухо перестаёт слышать
##               через минуту, редкий — нет.
##   стрекот   — ровный высокий фон на открытых местах, слабее ветра.
##
## ПОЧЕМУ ПТИЦЫ ВОКРУГ СЛУШАТЕЛЯ, А НЕ В ТОЧКАХ МИРА. Расставить их по карте
## значит либо завести сотни источников, либо слышать птиц только там, где их
## поставили. Щебет рождается рядом с игроком, в случайной точке — и мир звучит
## одинаково живо везде, где он есть.
##

const MIX_RATE := 22050

## Как далеко от слушателя рождается щебет и стрекот.
const NEAR := 26.0
## Промежутки между щебетами, секунды: от и до.
const BIRD_GAP := Vector2(2.6, 9.0)
## В лесу птиц втрое больше — это и отличает лес от поля на слух.
const FOREST_BIRDS := 3.0
## Насколько «лес» считается лесом: расстояние до зоны эльфов.
const FOREST_RANGE := 260.0

var _enabled := true
var _wind: AudioStreamPlayer = null
var _crickets: AudioStreamPlayer = null
var _voices: Array[AudioStreamPlayer3D] = []
var _next := 0
var _birds: Array[AudioStream] = []
var _until_bird := 3.0
var _rng := RandomNumberGenerator.new()
## Где стоит слушатель. Ставит игра; пусто — фон молчит, и это верно: в меню
## птицам петь незачем.
var listener: Node3D = null


func _ready() -> void:
	_enabled = (AudioServer.get_output_device() != "Null"
		and DisplayServer.get_name() != "headless")
	if not _enabled:
		return
	_rng.randomize()

	_wind = AudioStreamPlayer.new()
	_wind.stream = _wind_loop()
	_wind.volume_db = -26.0
	add_child(_wind)

	_crickets = AudioStreamPlayer.new()
	_crickets.stream = _cricket_loop()
	_crickets.volume_db = -34.0
	add_child(_crickets)

	for i in 4:
		var voice := AudioStreamPlayer3D.new()
		voice.max_distance = 60.0
		voice.unit_size = 4.0
		add_child(voice)
		_voices.append(voice)

	for seed_value in 4:
		_birds.append(_bird_call(seed_value))


## Начать и прекратить фон. Зовёт мир: в меню его быть не должно.
func set_running(on: bool) -> void:
	if not _enabled:
		return
	if on:
		if not _wind.playing:
			_wind.play()
		if not _crickets.playing:
			_crickets.play()
	else:
		_wind.stop()
		_crickets.stop()
		listener = null


func _process(delta: float) -> void:
	if not _enabled or listener == null or not is_instance_valid(listener):
		return
	if not _wind.playing:
		return
	_until_bird -= delta * _bird_rate()
	if _until_bird > 0.0:
		return
	_until_bird = _rng.randf_range(BIRD_GAP.x, BIRD_GAP.y)
	_sing()


## Во сколько раз чаще поют птицы здесь. В лесу — чаще, в чистом поле — реже.
func _bird_rate() -> float:
	var here: Vector3 = listener.global_position
	var forest := Vector2(-300.0, -300.0)          # зона эльфов
	var far: float = Vector2(here.x, here.z).distance_to(forest)
	if far >= FOREST_RANGE:
		return 1.0
	return lerpf(FOREST_BIRDS, 1.0, far / FOREST_RANGE)


func _sing() -> void:
	if _voices.is_empty() or _birds.is_empty():
		return
	var voice := _voices[_next]
	_next = (_next + 1) % _voices.size()
	var angle: float = _rng.randf() * TAU
	var away: float = _rng.randf_range(NEAR * 0.4, NEAR)
	# Птицы СВЕРХУ: щебет из-под ног звучит как что-то другое.
	voice.global_position = listener.global_position + Vector3(
		cos(angle) * away, _rng.randf_range(3.0, 9.0), sin(angle) * away)
	voice.stream = _birds[_rng.randi() % _birds.size()]
	voice.pitch_scale = _rng.randf_range(0.88, 1.18)
	voice.volume_db = _rng.randf_range(-22.0, -14.0)
	voice.play()


# --- синтез ----------------------------------------------------------------

## Ветер: шум под фильтром, с медленным качанием силы.
##
## Один низкочастотный фильтр превращает белый шум в шипение, два — в гул. Нам
## нужно среднее: шум листвы, а не морской прибой и не радиопомеха. Поэтому
## фильтр второго порядка, но лёгкий.
##
## Качание обязательно. Ровный шум ухо принимает за неисправность колонок и
## перестаёт слышать через полминуты; порывы делают его ветром.
func _wind_loop() -> AudioStreamWAV:
	var seconds := 9.0
	var count := int(MIX_RATE * seconds)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var low := 0.0
	var lower := 0.0
	for i in count:
		var t: float = float(i) / float(count)
		low = lerpf(low, rng.randf_range(-1.0, 1.0), 0.06)
		lower = lerpf(lower, low, 0.22)
		# Два порыва за петлю, разной силы, плюс лёгкая постоянная основа.
		var gust: float = 0.45 + 0.35 * sin(t * TAU) + 0.20 * sin(t * TAU * 2.7)
		# Стыковка петли: к концу сводим к началу, иначе на шве слышен щелчок.
		var seam: float = minf(1.0, minf(t, 1.0 - t) * 24.0)
		_put(data, i, lower * gust * seam * 1.6)
	return _wav(data, true)


## Стрекот: ровная высокая рябь. Отдельно от ветра, потому что слышна она на
## открытом месте, а в лесу её перебивают птицы.
func _cricket_loop() -> AudioStreamWAV:
	var seconds := 4.0
	var count := int(MIX_RATE * seconds)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 90909
	var phase := 0.0
	for i in count:
		var t: float = float(i) / float(count)
		# Стрекот — не тон, а частые щелчки: тон на 4.2 кГц, рубленный в крошку.
		phase += TAU * 4200.0 / float(MIX_RATE)
		var chop: float = 1.0 if fmod(float(i), 46.0) < 15.0 else 0.0
		var sway: float = 0.6 + 0.4 * sin(t * TAU * 3.0)
		var seam: float = minf(1.0, minf(t, 1.0 - t) * 24.0)
		_put(data, i, sin(phase) * chop * sway * seam * 0.35
			+ rng.randf_range(-0.02, 0.02))
	return _wav(data, true)


## Щебет: две-три короткие ноты подряд, каждая со скольжением вверх.
##
## Именно скольжение делает звук птицей: ровный писк слышится сигналом прибора.
func _bird_call(seed_value: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150 + seed_value * 37
	var notes: int = rng.randi_range(2, 4)
	var seconds: float = 0.10 * float(notes) + 0.06
	var count := int(MIX_RATE * seconds)
	var data := PackedByteArray()
	data.resize(count * 2)
	var phase := 0.0
	for i in count:
		var t: float = float(i) / float(count)
		var slot: int = mini(notes - 1, int(t * float(notes)))
		var inside: float = fmod(t * float(notes), 1.0)
		var base: float = 2100.0 + float(slot) * rng.randf_range(-260.0, 420.0)
		var hz: float = base + inside * 900.0
		phase += TAU * hz / float(MIX_RATE)
		# Каждая нота со своим коротким затуханием: между ними тишина, иначе
		# выходит одна длинная трель, а не щебет.
		var envelope: float = sin(inside * PI)
		_put(data, i, sin(phase) * envelope * 0.5)
	return _wav(data, false)


func _put(data: PackedByteArray, index: int, value: float) -> void:
	var clamped: int = clampi(int(clampf(value, -1.0, 1.0) * 32767.0), -32768, 32767)
	data.encode_s16(index * 2, clamped)


func _wav(data: PackedByteArray, looping: bool) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	if looping:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = data.size() / 2
	return wav
