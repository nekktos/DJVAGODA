extends Node3D
##
## Цель вертикального среза (Этап 7): дворец императора.
##
## GDD описывает срез как «форт → отряд → построение → марш → бой → ранения →
## результат», но не говорит, что такое результат. Решение из DESIGN_ANSWERS.md,
## пункт 17: злодей захватывает дворец, стража убивает злодея, эльфам дворец
## тоже интересен. Захват НЕ обрывает партию — он меняет её состояние, и злодей
## может продолжать борьбу.
##
## Всё считает ТОЛЬКО хост. Клиенты получают владельца и прогресс захвата и
## просто рисуют.
##

const FACTIONS := preload("res://scripts/factions.gd")

## Где стоит дворец и какого радиуса точка захвата.
const PALACE := Vector3(300.0, 6.0, -300.0)
const RADIUS := 34.0
## Сколько секунд надо удерживать точку без помех.
const CAPTURE_SECONDS := 20.0
## Насколько быстро прогресс откатывается, когда точку бросили.
const DECAY_PER_SECOND := 0.06

signal announced(text: String)

## Реплицируемое состояние.
@export var palace_owner: int = FACTIONS.Kind.GUARD
@export var capture_progress: float = 0.0
@export var contested: bool = false
## Кто сейчас захватывает. -1 — никто.
@export var claimant: int = -1

var _seen_owner := FACTIONS.Kind.GUARD


func _ready() -> void:
	position = PALACE
	_seen_owner = palace_owner


func _process(delta: float) -> void:
	# Объявление идёт ТОЛЬКО по RPC. Раньше здесь дублировалась ещё и реакция на
	# смену реплицированного владельца, и клиенты получали баннер дважды.
	_seen_owner = palace_owner
	if not multiplayer.is_server():
		return
	_server_tick(delta)


func _server_tick(delta: float) -> void:
	var present := _factions_inside()
	contested = present.size() > 1

	if present.is_empty() or contested:
		# Бросили или оспаривают — прогресс откатывается, но не мгновенно.
		claimant = -1
		capture_progress = maxf(0.0, capture_progress - DECAY_PER_SECOND * delta)
		return

	var who: int = present[0]
	if who == palace_owner:
		# Хозяин стоит у себя — просто откатываем чужой прогресс.
		claimant = -1
		capture_progress = maxf(0.0, capture_progress - DECAY_PER_SECOND * delta * 4.0)
		return

	if claimant != who:
		claimant = who
		capture_progress = 0.0
	capture_progress = minf(1.0, capture_progress + delta / CAPTURE_SECONDS)
	if capture_progress >= 1.0:
		_capture(who)


func _capture(faction: int) -> void:
	palace_owner = faction
	capture_progress = 0.0
	claimant = -1
	_seen_owner = faction
	var text := "Дворец захвачен: %s" % FACTIONS.name_of(faction)
	print("[цель] %s" % text)
	announce.rpc(text)


## Какие стороны сейчас стоят в точке. Считает хост.
func _factions_inside() -> Array:
	var found := []
	var players := get_parent().get_node_or_null("Players")
	if players == null:
		return found
	for child in players.get_children():
		if not ("faction" in child) or not child.has_method("take_damage"):
			continue
		if not child.health.alive:
			continue
		var flat := Vector3(child.global_position.x, PALACE.y, child.global_position.z)
		if flat.distance_to(PALACE) > RADIUS:
			continue
		var faction: int = int(child.faction)
		if not found.has(faction):
			found.append(faction)
	return found


## Объявить результат всем. Прислать может только хост.
@rpc("any_peer", "call_local", "reliable")
func announce(text: String) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	announced.emit(text)


## Кого-то убили. Хост решает, значит ли это результат партии.
func report_death(victim_faction: int, killer_faction: int) -> void:
	if not multiplayer.is_server():
		return
	if victim_faction == FACTIONS.Kind.VILLAIN and killer_faction == FACTIONS.Kind.GUARD:
		announce.rpc("Стража убила злодея")
	elif victim_faction == FACTIONS.Kind.VILLAIN:
		announce.rpc("Злодей пал от рук: %s" % FACTIONS.name_of(killer_faction))


func status_text() -> String:
	var line := "дворец: %s" % FACTIONS.name_of(palace_owner)
	if contested:
		return line + "   ТОЧКА ОСПАРИВАЕТСЯ"
	if claimant >= 0 and capture_progress > 0.0:
		return line + "   захват (%s): %d%%" % [FACTIONS.name_of(claimant), int(capture_progress * 100.0)]
	return line
