extends Node
##
## Система ранений и протезов (Этап 3, GDD раздел 4).
##
## Состояние считает ТОЛЬКО хост и реплицирует его отдельным синхронизатором
## с авторитетом хоста — тем же каналом, что и здоровье. Клиенты состояние
## только читают: по нему они прячут оторванные части и рисуют последствия.
##
## Таблица GDD раздела 4 и уточнения из DESIGN_ANSWERS.md (пункты 11-13):
##   рука  — кровотечение, без перевязки смерть; перевязка расходует бинт
##   глаз  — слепота на половину экрана, не смертельно
##   нога  — без одной ползёшь, без двух ползёшь медленнее
##   протезы разного качества, топовые ЛУЧШЕ живых конечностей
##

enum Limb { ARM_L, ARM_R, LEG_L, LEG_R }

const LIMB_KEYS := ["arm_l", "arm_r", "leg_l", "leg_r"]
const LIMB_NAMES := ["левая рука", "правая рука", "левая нога", "правая нога"]

## Сколько урона выдерживает конечность, прежде чем её оторвёт.
const LIMB_DURABILITY := 45.0
## Урона по голове на потерю одного глаза.
const EYE_THRESHOLD := 40.0

## Потеря крови, единиц здоровья в секунду.
const BLEED_PER_SECOND := 3.0
## Сколько секунд занимает перевязка.
const BANDAGE_TIME := 3.0
## Сколько бинтов у игрока в начале. Полноценный инвентарь появится вместе с
## экономикой (Этапы 4-5), пока это просто счётчик.
const START_BANDAGES := 3

## Скорость ползания без одной ноги и без обеих, метры в секунду.
const CRAWL_SPEED_ONE := 1.4
const CRAWL_SPEED_BOTH := 0.8
## Скорость в коляске.
const WHEELCHAIR_SPEED := 4.5

## Качество протезов. Индекс — уровень: 0 это отсутствие протеза.
##   1 деревянный — крафтится сам из древесины, подогнан плохо: чуть быстрее
##     ползания и периодически травмирует
##   2 кованый    — примерно как живая конечность
##   3 мастерский — ЛУЧШЕ живой: выше прыжок, быстрее бег
const TIER_NAMES := ["нет", "деревянный", "кованый", "мастерский"]
const TIER_SPEED := [0.0, 0.30, 1.0, 1.25]
const TIER_JUMP := [0.0, 0.55, 1.0, 1.35]
## Периодический урон от плохо подогнанного протеза: натирает и травмирует.
const TIER_CHAFE_DAMAGE := [0.0, 1.5, 0.0, 0.0]
const CHAFE_INTERVAL := 4.0
## Множитель кулдауна атак: мастерская рука бьёт быстрее.
const TIER_ATTACK_SPEED := [1.0, 1.0, 1.0, 0.75]

## Конечность оторвана (на любом пире, после репликации).
signal limb_severed(limb: int)
## Протез поставлен или снят.
signal prosthetic_changed(limb: int, tier: int)
## Состояние изменилось настолько, что игроку надо пересчитать движение и позу.
signal state_changed

## --- реплицируемое состояние (авторитет — хост) ---
@export var severed_mask: int = 0
@export var prosthetics: PackedByteArray = PackedByteArray([0, 0, 0, 0])
@export var eyes_lost: int = 0
@export var bleeding: bool = false
@export var bandages: int = START_BANDAGES
@export var in_wheelchair: bool = false

## --- только на хосте ---
var _limb_damage := {}
var _head_damage := 0.0
var _chafe_timer := 0.0

var _seen_mask := 0
var _seen_prosthetics := PackedByteArray([0, 0, 0, 0])
var _seen_eyes := 0


func _ready() -> void:
	for key in LIMB_KEYS:
		_limb_damage[key] = 0.0
	_seen_mask = severed_mask
	_seen_prosthetics = prosthetics.duplicate()
	_seen_eyes = eyes_lost


func _process(delta: float) -> void:
	# Клиенты узнают об изменениях только через репликацию, поэтому следим за
	# значениями, а не за вызовами. Так визуал одинаков на хосте и клиентах.
	if severed_mask != _seen_mask:
		var newly := severed_mask & ~_seen_mask
		_seen_mask = severed_mask
		for i in LIMB_KEYS.size():
			if newly & (1 << i):
				limb_severed.emit(i)
		state_changed.emit()

	if prosthetics != _seen_prosthetics:
		for i in LIMB_KEYS.size():
			if i < prosthetics.size() and i < _seen_prosthetics.size():
				if prosthetics[i] != _seen_prosthetics[i]:
					prosthetic_changed.emit(i, prosthetics[i])
		_seen_prosthetics = prosthetics.duplicate()
		state_changed.emit()

	if eyes_lost != _seen_eyes:
		_seen_eyes = eyes_lost
		state_changed.emit()

	if Net.hosting():
		_server_tick(delta)


func is_severed(limb: int) -> bool:
	return (severed_mask & (1 << limb)) != 0


func tier(limb: int) -> int:
	if limb < 0 or limb >= prosthetics.size():
		return 0
	return prosthetics[limb]


## Живая конечность или протез: 1.0 — здоровая, иначе множитель по качеству.
func _limb_factor(limb: int, table: Array) -> float:
	if not is_severed(limb):
		return 1.0
	return table[clampi(tier(limb), 0, table.size() - 1)]


# --- что состояние тела разрешает и запрещает ------------------------------

## Ползёт ли персонаж: нога потеряна и не заменена работающим протезом.
func is_crawling() -> bool:
	if in_wheelchair:
		return false
	return _leg_factor(Limb.LEG_L) <= 0.0 or _leg_factor(Limb.LEG_R) <= 0.0


func _leg_factor(limb: int) -> float:
	return _limb_factor(limb, TIER_SPEED)


## Скорость передвижения. base — обычная скорость здорового персонажа.
func move_speed(base: float) -> float:
	if in_wheelchair:
		return WHEELCHAIR_SPEED
	var left := _leg_factor(Limb.LEG_L)
	var right := _leg_factor(Limb.LEG_R)
	var lost := int(left <= 0.0) + int(right <= 0.0)
	if lost == 2:
		return CRAWL_SPEED_BOTH
	if lost == 1:
		return CRAWL_SPEED_ONE
	return base * (left + right) * 0.5


## Высота прыжка. Ползком и в коляске не прыгают.
func jump_velocity(base: float) -> float:
	if in_wheelchair or is_crawling():
		return 0.0
	var factor := minf(_limb_factor(Limb.LEG_L, TIER_JUMP), _limb_factor(Limb.LEG_R, TIER_JUMP))
	return base * factor


## Есть ли рука, которой вообще можно бить.
func can_attack_melee() -> bool:
	return _arm_usable(Limb.ARM_L, 1) or _arm_usable(Limb.ARM_R, 1)


## Лук и заклинания требуют полноценной руки: деревянный протез не годится.
func can_attack_ranged() -> bool:
	return _arm_usable(Limb.ARM_L, 2) or _arm_usable(Limb.ARM_R, 2)


func _arm_usable(limb: int, min_tier: int) -> bool:
	if not is_severed(limb):
		return true
	return tier(limb) >= min_tier


## Множитель кулдауна атак: мастерская рука бьёт быстрее живой.
func attack_speed_scale() -> float:
	var best := 1.0
	for limb in [Limb.ARM_L, Limb.ARM_R]:
		if is_severed(limb):
			best = minf(best, TIER_ATTACK_SPEED[clampi(tier(limb), 0, 3)])
	return best


## Доля экрана, закрытая слепотой: 0, половина или весь.
func blindness() -> float:
	return clampf(float(eyes_lost) * 0.5, 0.0, 1.0)


## Человекочитаемая сводка для HUD.
func summary() -> String:
	if severed_mask == 0 and eyes_lost == 0 and not in_wheelchair:
		return "цел"
	var parts := PackedStringArray()
	for i in LIMB_KEYS.size():
		if is_severed(i):
			var t := tier(i)
			parts.append("%s: %s" % [LIMB_NAMES[i], TIER_NAMES[t] if t > 0 else "оторвана"])
	if eyes_lost > 0:
		parts.append("глаз потеряно: %d" % eyes_lost)
	if in_wheelchair:
		parts.append("в коляске")
	if bleeding:
		parts.append("КРОВОТЕЧЕНИЕ")
	return ", ".join(parts)


# --- сторона хоста ---------------------------------------------------------

## Учесть попадание в зону. Вызывается ТОЛЬКО на хосте, из player.take_damage.
## Здоровье снимается отдельно: здесь считается только судьба конечности.
func register_hit(zone: String, amount: float) -> void:
	if not Net.hosting() or amount <= 0.0:
		return

	if zone == "head":
		_head_damage += amount
		while _head_damage >= EYE_THRESHOLD and eyes_lost < 2:
			_head_damage -= EYE_THRESHOLD
			eyes_lost += 1
			state_changed.emit()
		return

	var limb := LIMB_KEYS.find(zone)
	if limb < 0 or is_severed(limb):
		return

	_limb_damage[zone] = float(_limb_damage[zone]) + amount
	if float(_limb_damage[zone]) < LIMB_DURABILITY:
		return

	# Конечность отрывает. Протез при этом слетает вместе с ней.
	severed_mask |= (1 << limb)
	_set_tier(limb, 0)
	bleeding = true
	limb_severed.emit(limb)
	state_changed.emit()


func _server_tick(delta: float) -> void:
	var health: Node = get_parent().get_node_or_null("Health")
	if health == null or not health.alive:
		return

	if bleeding:
		# GDD раздел 4: не перевяжут — смерть от кровопотери.
		health.apply_damage(BLEED_PER_SECOND * delta, 0)

	# Плохо подогнанный протез натирает и травмирует.
	var chafe := 0.0
	for limb in LIMB_KEYS.size():
		if is_severed(limb):
			chafe += TIER_CHAFE_DAMAGE[clampi(tier(limb), 0, 3)]
	if chafe <= 0.0:
		_chafe_timer = 0.0
		return
	_chafe_timer += delta
	if _chafe_timer >= CHAFE_INTERVAL:
		_chafe_timer = 0.0
		health.apply_damage(chafe, 0)


## Перевязать. Только на хосте. Возвращает true, если бинт израсходован.
func apply_bandage() -> bool:
	if not Net.hosting():
		return false
	if not bleeding or bandages <= 0:
		return false
	bandages -= 1
	bleeding = false
	state_changed.emit()
	return true


## Поставить протез. Только на хосте.
func grant_prosthetic(limb: int, new_tier: int) -> bool:
	if not Net.hosting():
		return false
	if limb < 0 or limb >= LIMB_KEYS.size() or not is_severed(limb):
		return false
	new_tier = clampi(new_tier, 1, TIER_NAMES.size() - 1)
	if tier(limb) == new_tier:
		return false
	_set_tier(limb, new_tier)
	prosthetic_changed.emit(limb, new_tier)
	state_changed.emit()
	return true


## Пересесть в коляску или встать из неё. Только на хосте.
func set_wheelchair(on: bool) -> bool:
	if not Net.hosting():
		return false
	# В коляску есть смысл садиться только без рабочих ног.
	if on and not is_crawling():
		return false
	if in_wheelchair == on:
		return false
	in_wheelchair = on
	state_changed.emit()
	return true


func _set_tier(limb: int, value: int) -> void:
	var copy := prosthetics.duplicate()
	while copy.size() <= limb:
		copy.append(0)
	copy[limb] = value
	prosthetics = copy


## Полный сброс при респавне. Только на хосте.
func reset() -> void:
	if not Net.hosting():
		return
	severed_mask = 0
	prosthetics = PackedByteArray([0, 0, 0, 0])
	eyes_lost = 0
	bleeding = false
	in_wheelchair = false
	bandages = START_BANDAGES
	_head_damage = 0.0
	_chafe_timer = 0.0
	for key in LIMB_KEYS:
		_limb_damage[key] = 0.0
	state_changed.emit()
