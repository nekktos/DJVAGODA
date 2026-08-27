extends Node
##
## Звук (Этап 10, шаг 9). Автозагрузка `Sfx`.
##
## ПОЧЕМУ ЗВУКИ СИНТЕЗИРОВАННЫЕ, А НЕ ФАЙЛЫ. Ровно по той же причине, по которой
## карта — процедурный grey-box из коробок: чтобы игра зазвучала СЕЙЧАС, не
## дожидаясь ни художника, ни разбора бесплатных библиотек. Это заглушки того же
## сорта, и заменить их файлами потом — работа на полдня: точки вызова уже
## расставлены и не изменятся.
##
## Звучат они соответственно: удар — шум с резкой атакой, тетива — короткий
## щелчок, взрыв — низкий рокот. Никакого «настоящего» звука тут нет и не
## задумано.
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
}

const MIX_RATE := 22050

## Сколько звуков может звучать одновременно. Больше не нужно: в бою и так каша,
## а каждый лишний проигрыватель — это узел в дереве.
const VOICES := 12

## Дальше этого источник не слышно вовсе.
const HEAR_DISTANCE := 90.0

var _samples := {}
var _voices: Array[AudioStreamPlayer3D] = []
var _flat: AudioStreamPlayer = null
var _next := 0
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


# --- синтез ----------------------------------------------------------------

func _build_samples() -> void:
	# Удар по живому: короткий шумовой всплеск с быстрым спадом. Мясисто и
	# коротко — в бою таких звуков десятки в секунду.
	_samples[Kind.HIT_FLESH] = _noise(0.14, 0.9, 0.35)
	# Дерево: тот же шум, но выше и суше.
	_samples[Kind.HIT_WOOD] = _noise(0.09, 0.55, 0.9)
	# Камень: ещё короче и звонче.
	_samples[Kind.HIT_STONE] = _noise(0.07, 0.4, 1.6)
	# Тетива: щелчок с призвуком.
	_samples[Kind.BOW] = _tone(0.12, 880.0, 220.0, 0.35)
	# Бросок шара: восходящий гул.
	_samples[Kind.SPELL] = _tone(0.30, 180.0, 420.0, 0.6)
	# Разрыв: низкий рокот подлиннее.
	_samples[Kind.EXPLOSION] = _noise(0.55, 1.0, 0.12)
	# Смерть: нисходящий тон.
	_samples[Kind.DEATH] = _tone(0.55, 320.0, 90.0, 0.55)
	# Стройка готова: две ноты вверх.
	_samples[Kind.BUILD_DONE] = _chord(0.45, [440.0, 660.0])
	# Магия: чистая высокая нота.
	_samples[Kind.MAGIC] = _tone(0.40, 620.0, 900.0, 0.4)
	# Объявление: две ноты, тише и мягче.
	_samples[Kind.NOTICE] = _chord(0.35, [520.0, 780.0])


## Шумовой всплеск. `bright` поднимает высоту: 1.0 — белый шум, меньше — глуше.
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


func _wav(data: PackedByteArray) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	return wav


## Есть ли звук вообще. Для автопроверок и для того, чтобы вызывающий мог
## отличить «выключено» от «сломано».
func enabled() -> bool:
	return _enabled


## Сколько звуков собрано. Тоже для автопроверок: пустой набор означает, что
## синтез отвалился, а игра при этом продолжает молча работать.
func sample_count() -> int:
	return _samples.size()
