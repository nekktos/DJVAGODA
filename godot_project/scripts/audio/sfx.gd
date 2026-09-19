extends Node
##
## Звук (Этап 10, шаг 9). Автозагрузка `Sfx`.
##
## ЗВУКИ — ФАЙЛЫ, А СИНТЕЗ ОСТАЛСЯ ЗАПАСНЫМ ПУТЁМ.
##
## Сначала здесь был только синтез: игра должна была зазвучать сразу, не
## дожидаясь ни художника, ни разбора библиотек. Это сработало, и обещание из
## того комментария — «заменить файлами потом, работа на полдня, точки вызова
## уже расставлены» — сдержано буквально: точки вызова не изменились ни одна,
## изменился только источник звука.
##
## Файлы взяты из наборов Kenney (RPG Audio и Impact Sounds), лицензия CC0 —
## см. LICENSE.txt рядом с ними. Из полутора сотен взято по одному на звук:
## класть в репозиторий оба набора целиком ради дюжины файлов значит навсегда
## засорить поиск по проекту.
##
## Синтез НЕ выброшен и остаётся запасным: если файл не нашёлся (не доехал в
## сборку, повреждён, переименован), звук всё равно будет — шумовой, но будет.
## Молчащая игра хуже некрасиво звучащей, и отлаживать молчание втрое дороже.
##
## ГДЕ ЗВУК БЕРЁТСЯ. Не заводим ни одной новой точки синхронизации. Все события,
## которые слышно, уже вызываются на КАЖДОМ пире: попадание, щепки, взрыв и
## магия идут через `effects.gd`, который дёргают `call_local`-RPC хоста. Звук
## встаёт рядом с ними и наследует правильное поведение по сети даром.
##
## HEADLESS. В прогонах без окна аудиодрайвер — пустышка, и создавать
## проигрыватели незачем: молча ничего не делаем.
##

## Виды звуков. Держим списком, а не отдельными полями: так их видно все разом.
enum Kind {
	HIT_FLESH,      ## удар по живому
	HIT_WOOD,       ## топор по дереву, щепки
	HIT_STONE,      ## кирка по камню
	BOW,            ## тетива
	SPELL,          ## бросок огненного шара
	EXPLOSION,      ## его разрыв
	DEATH,          ## смерть
	BUILD_DONE,     ## постройка достроена
	MAGIC,          ## магия поддержки эльфов
	NOTICE,         ## объявление в интерфейсе
	STEP,           ## шаг
	HOOF,           ## копыто
	CART,           ## скрип и грохот обоза, петля
}

const MIX_RATE := 22050

## Какой файл на какой звук. Пусто — синтезируем, как раньше.
const FILES := {
	Kind.HIT_FLESH: "res://assets/audio/knifeSlice.ogg",
	Kind.HIT_WOOD: "res://assets/audio/impactPlank_medium_000.ogg",
	Kind.HIT_STONE: "res://assets/audio/impactMining_000.ogg",
	Kind.BOW: "res://assets/audio/impactGeneric_light_000.ogg",
	Kind.SPELL: "res://assets/audio/impactBell_heavy_000.ogg",
	Kind.EXPLOSION: "res://assets/audio/impactPlate_heavy_000.ogg",
	Kind.DEATH: "res://assets/audio/dropLeather.ogg",
	Kind.BUILD_DONE: "res://assets/audio/metalLatch.ogg",
	Kind.MAGIC: "res://assets/audio/handleCoins.ogg",
	Kind.NOTICE: "res://assets/audio/metalClick.ogg",
	Kind.STEP: "res://assets/audio/footstep_grass_000.ogg",
	# Копыта и обоз — СИНТЕЗ, файла нет намеренно: чужих ассетов в проекте
	# больше не держим, а стук и скрип синтезируются легче удара.
}

## Шаги берём по кругу из нескольких файлов: один и тот же шаг подряд слышен как
## заедающая пластинка, и это замечают все.
const STEP_FILES := [
	"res://assets/audio/footstep_grass_000.ogg",
	"res://assets/audio/footstep_grass_001.ogg",
	"res://assets/audio/footstep_grass_002.ogg",
	"res://assets/audio/footstep_grass_003.ogg",
]

## Сколько звуков может звучать одновременно. Больше не нужно: в бою и так каша,
## а каждый лишний проигрыватель — это узел в дереве.
const VOICES := 12

## Дальше этого источник не слышно вовсе.
const HEAR_DISTANCE := 90.0

var _samples := {}
var _voices: Array[AudioStreamPlayer3D] = []
var _flat: AudioStreamPlayer = null
var _next := 0
## Звуки шагов по кругу.
var _steps: Array[AudioStream] = []
var _next_step := 0
var _enabled := true


func _ready() -> void:
	# Пустой аудиодрайвер бывает не только в headless: его можно задать ключом
	# запуска. Спрашиваем сам драйвер, а не режим отображения.
	_enabled = AudioServer.get_output_device() != "Null" and DisplayServer.get_name() != "headless"
	if not _enabled:
		return
	_build_samples()
	for i in VOICES:
		var voice := AudioStreamPlayer3D.new()
		voice.max_distance = HEAR_DISTANCE
		voice.unit_size = 6.0
		add_child(voice)
		_voices.append(voice)
	_flat = AudioStreamPlayer.new()
	add_child(_flat)


## Сыграть звук в точке мира. Если звука нет или он выключен — тишина, без
## жалоб: звук никогда не должен ломать игру.
func at(kind: int, point: Vector3, volume_db: float = 0.0) -> void:
	if not _enabled or _voices.is_empty():
		return
	var stream: AudioStream = _samples.get(kind, null)
	if stream == null:
		return
	var voice := _voices[_next]
	_next = (_next + 1) % _voices.size()
	voice.stream = stream
	voice.global_position = point
	voice.volume_db = volume_db
	voice.play()


## Шаг в точке мира. Отдельно от `at()`: шагов много, они тише всего прочего и
## идут по кругу, чтобы не звучать заезженной пластинкой.
func step(point: Vector3) -> void:
	if not _enabled or _voices.is_empty() or _steps.is_empty():
		return
	var voice := _voices[_next]
	_next = (_next + 1) % _voices.size()
	voice.stream = _steps[_next_step]
	_next_step = (_next_step + 1) % _steps.size()
	voice.global_position = point
	voice.volume_db = -12.0
	voice.play()


## Сыграть звук интерфейса — без позиции в мире.
func flat(kind: int, volume_db: float = -6.0) -> void:
	if not _enabled or _flat == null:
		return
	var stream: AudioStream = _samples.get(kind, null)
	if stream == null:
		return
	_flat.stream = stream
	_flat.volume_db = volume_db
	_flat.play()


## Копыто в точке мира. Отдельно от шага: у лошади удар ниже, глуше и тяжелее,
## и слышен дальше человеческого.
func hoof(point: Vector3) -> void:
	at(Kind.HOOF, point, -14.0)


## Поток для непрерывного звука — его вешают на саму повозку и крутят, пока
## она едет. Возвращаем сам поток, а не проигрыватель: где ему звучать, решает
## тот, кто едет.
func stream_of(kind: int) -> AudioStream:
	return _samples.get(kind, null)


# --- синтез ----------------------------------------------------------------

## Собрать звуки: сперва файлы, синтез — только там, где файла нет.
func _build_samples() -> void:
	for kind in FILES:
		var path: String = FILES[kind]
		if ResourceLoader.exists(path):
			var stream: AudioStream = load(path)
			if stream != null:
				_samples[kind] = stream
	for path in STEP_FILES:
		if ResourceLoader.exists(path):
			var step: AudioStream = load(path)
			if step != null:
				_steps.append(step)
	_build_synth_only()
	_build_fallback()


## Синтез. Остаётся запасным путём и заполняет только то, чего не нашлось
## файлом: молчащая игра хуже некрасиво звучащей.
func _build_synth_only() -> void:
	_samples[Kind.HOOF] = _hoof_sample()
	_samples[Kind.CART] = _cart_loop()


func _build_fallback() -> void:
	# Удар по живому: короткий шумовой всплеск с быстрым спадом. Мясисто и
	# коротко — в бою таких звуков десятки в секунду.
	if not _samples.has(Kind.HIT_FLESH):
		_samples[Kind.HIT_FLESH] = _noise(0.14, 0.9, 0.35)
	# Дерево: тот же шум, но выше и суше.
	if not _samples.has(Kind.HIT_WOOD):
		_samples[Kind.HIT_WOOD] = _noise(0.09, 0.55, 0.9)
	# Камень: ещё короче и звонче.
	if not _samples.has(Kind.HIT_STONE):
		_samples[Kind.HIT_STONE] = _noise(0.07, 0.4, 1.6)
	# Тетива: щелчок с призвуком.
	if not _samples.has(Kind.BOW):
		_samples[Kind.BOW] = _tone(0.12, 880.0, 220.0, 0.35)
	# Бросок шара: восходящий гул.
	if not _samples.has(Kind.SPELL):
		_samples[Kind.SPELL] = _tone(0.30, 180.0, 420.0, 0.6)
	# Разрыв: низкий рокот подлиннее.
	if not _samples.has(Kind.EXPLOSION):
		_samples[Kind.EXPLOSION] = _noise(0.55, 1.0, 0.12)
	# Смерть: нисходящий тон.
	if not _samples.has(Kind.DEATH):
		_samples[Kind.DEATH] = _tone(0.55, 320.0, 90.0, 0.55)
	# Стройка готова: две ноты вверх.
	if not _samples.has(Kind.BUILD_DONE):
		_samples[Kind.BUILD_DONE] = _chord(0.45, [440.0, 660.0])
	# Магия: чистая высокая нота.
	if not _samples.has(Kind.MAGIC):
		_samples[Kind.MAGIC] = _tone(0.40, 620.0, 900.0, 0.4)
	# Объявление: две ноты, тише и мягче.
	if not _samples.has(Kind.NOTICE):
		_samples[Kind.NOTICE] = _chord(0.35, [520.0, 780.0])


## Шумовой всплеск. `bright` поднимает высоту: 1.0 — белый шум, меньше — глуше.
## Копыто: глухой низкий удар с коротким цоканьем сверху.
##
## Один шум звучит шлепком, один тон — деревяшкой. Копыто это и то и другое:
## удар копыта о землю и щелчок ободка, и слышны они как один звук только
## вместе.
func _hoof_sample() -> AudioStreamWAV:
	var seconds := 0.20
	var count := int(MIX_RATE * seconds)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 6161
	var phase := 0.0
	for i in count:
		var t: float = float(i) / float(count)
		var thump: float = exp(-t * 26.0)
		phase += TAU * lerpf(150.0, 60.0, t) / float(MIX_RATE)
		var click: float = rng.randf_range(-1.0, 1.0) * exp(-t * 120.0)
		_put(data, i, sin(phase) * thump * 0.7 + click * 0.35)
	return _wav(data)


## Обоз: непрерывный низкий грохот колёс со скрипом оси поверх.
##
## Петля намеренно НЕ круглая по длине скрипа: если скрип попадает в такт петле,
## слышно, что это петля. Берём период скрипа, не укладывающийся в неё нацело.
func _cart_loop() -> AudioStreamWAV:
	var seconds := 3.0
	var count := int(MIX_RATE * seconds)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 313131
	var low := 0.0
	var phase := 0.0
	for i in count:
		var t: float = float(i) / float(count)
		# Колёса: низкий шум, качающийся от неровностей.
		low = lerpf(low, rng.randf_range(-1.0, 1.0), 0.09)
		var roll: float = low * (0.55 + 0.45 * sin(t * TAU * 3.0))
		# Ось: скрип на 430 Гц, гуляющий по высоте, с периодом 0.7 от петли.
		var creak_hz: float = 430.0 + 90.0 * sin(t * TAU * 1.43)
		phase += TAU * creak_hz / float(MIX_RATE)
		var creak: float = sin(phase) * maxf(0.0, sin(t * TAU * 1.43)) * 0.18
		var seam: float = minf(1.0, minf(t, 1.0 - t) * 30.0)
		_put(data, i, (roll * 0.5 + creak) * seam)
	return _wav(data, true)


func _noise(seconds: float, level: float, bright: float) -> AudioStreamWAV:
	var count := int(MIX_RATE * seconds)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(seconds * 100000.0) + int(bright * 977.0)
	var data := PackedByteArray()
	data.resize(count * 2)
	# Однополюсный фильтр: чем меньше bright, тем сильнее сглаживание.
	var smooth := clampf(bright, 0.05, 1.0)
	var last := 0.0
	for i in count:
		var t := float(i) / float(count)
		var envelope: float = pow(1.0 - t, 3.0)
		last = last + (rng.randf_range(-1.0, 1.0) - last) * smooth
		_put(data, i, last * envelope * level)
	return _wav(data)


## Тон, скользящий от одной частоты к другой.
func _tone(seconds: float, from_hz: float, to_hz: float, level: float) -> AudioStreamWAV:
	var count := int(MIX_RATE * seconds)
	var data := PackedByteArray()
	data.resize(count * 2)
	var phase := 0.0
	for i in count:
		var t := float(i) / float(count)
		var hz: float = lerpf(from_hz, to_hz, t)
		phase += TAU * hz / float(MIX_RATE)
		var envelope: float = pow(1.0 - t, 2.0)
		_put(data, i, sin(phase) * envelope * level)
	return _wav(data)


## Несколько нот подряд — короткая фраза для интерфейса.
func _chord(seconds: float, notes: Array) -> AudioStreamWAV:
	var count := int(MIX_RATE * seconds)
	var data := PackedByteArray()
	data.resize(count * 2)
	var per: int = maxi(1, count / notes.size())
	for i in count:
		var index: int = mini(i / per, notes.size() - 1)
		var local := float(i % per) / float(per)
		var phase := TAU * float(notes[index]) * float(i % per) / float(MIX_RATE)
		var envelope: float = pow(1.0 - local, 2.0)
		_put(data, i, sin(phase) * envelope * 0.4)
	return _wav(data)


## Записать один отсчёт как 16-битный PCM с обрезкой по краям.
func _put(data: PackedByteArray, index: int, value: float) -> void:
	var sample := int(clampf(value, -1.0, 1.0) * 32000.0)
	data.encode_s16(index * 2, sample)


func _wav(data: PackedByteArray, looping: bool = false) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	# Петля нужна непрерывным звукам — обозу. Без неё скрип играет три секунды
	# и замолкает, а повозка едет дальше.
	if looping:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = data.size() / 2
	return wav


## Есть ли звук вообще. Для автопроверок и для того, чтобы вызывающий мог
## отличить «выключено» от «сломано».
func enabled() -> bool:
	return _enabled


## Сколько звуков собрано. Тоже для автопроверок: пустой набор означает, что
## синтез отвалился, а игра при этом продолжает молча работать.
func sample_count() -> int:
	return _samples.size()
