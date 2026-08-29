extends Node
##
## Отношения между фракциями (Этап 10, шаг 4, GDD раздел 9).
##
## Матрица попарная и симметричная: отношение злодея к эльфам — то же число, что
## отношение эльфов к злодею. Односторонняя вражда («я тебя ненавижу, а ты меня
## нет») в GDD не описана, а пар всего три — городить ради этого матрицу 3x3 с
## двумя половинами незачем.
##
## Шкала -100 (война) .. +100 (союз). ВСЕ пары стартуют враждебно: это мир
## гражданской войны на троих, а не нейтральный мир, где вражду надо заслужить.
## Но не одинаково — у эльфов и стражи нет прямого конфликта интересов, кроме
## дворца, поэтому между ними теплее, чем у любой из них со злодеем.
##
## Считает и хранит ТОЛЬКО хост, значение реплицируется всем.
##

const FACTIONS := preload("res://scripts/factions.gd")

## Пары в порядке индексов: 0 — злодей/эльфы, 1 — злодей/стража, 2 — эльфы/стража.
const PAIRS := 3

const MIN_VALUE := -100.0
const MAX_VALUE := 100.0

## Стартовые значения по парам.
const START := [-70.0, -80.0, -30.0]

## Куда отношения сползают сами по себе. Совпадает со стартовым: мир не
## стремится к миру, он стремится к вражде, если её не гасить (GDD раздел 9.3).
const BASELINE := START

## Скорость дрейфа к базовому значению, единиц в секунду. Медленно намеренно:
## дрейф должен стирать последствия давних событий, а не отменять свежие.
const DRIFT_PER_SECOND := 0.35

## Ниже этого торговля закрыта совсем: лавочник не обслуживает того, с кем его
## сторона в открытой войне.
const TRADE_CLOSED_BELOW := -60.0
## Выше этого начинается скидка.
const FRIENDLY_ABOVE := 20.0

## Насколько дорожает товар в худшем случае и дешевеет в лучшем.
const MAX_MARKUP := 1.0
const MAX_DISCOUNT := 0.25

signal changed

## Реплицируемое состояние: по одному числу на пару.
@export var values: PackedFloat32Array = PackedFloat32Array([-70.0, -80.0, -30.0])

var _seen := PackedFloat32Array([0.0, 0.0, 0.0])


func _ready() -> void:
	reset()


## Вернуть отношения к стартовым. Зовётся и при загрузке сцены, и при начале
## новой партии: иначе новая партия начиналась бы с враждой, нажитой в прошлой.
func reset() -> void:
	# Значения константные и одинаковые на всех пирах, поэтому раскладываем без
	# проверки на хоста: сетевого пира в момент загрузки сцены ещё нет.
	var start := PackedFloat32Array()
	for v in START:
		start.append(float(v))
	values = start
	_seen = values.duplicate()
	_offers.clear()


func _process(delta: float) -> void:
	if values != _seen:
		_seen = values.duplicate()
		changed.emit()
	if Net.hosting():
		_drift(delta)


## Индекс пары. Порядок сторон не важен: отношение симметрично.
static func pair_index(a: int, b: int) -> int:
	var lo: int = mini(a, b)
	var hi: int = maxi(a, b)
	if lo == FACTIONS.Kind.VILLAIN and hi == FACTIONS.Kind.ELVES:
		return 0
	if lo == FACTIONS.Kind.VILLAIN and hi == FACTIONS.Kind.GUARD:
		return 1
	return 2


## Отношение между сторонами. К себе сторона всегда в союзе.
func value_of(a: int, b: int) -> float:
	if a == b:
		return MAX_VALUE
	return values[pair_index(a, b)]


## Сдвинуть отношение. Только на хосте. Положительное — теплеет.
func shift(a: int, b: int, delta: float) -> void:
	if not Net.hosting() or a == b:
		return
	var index := pair_index(a, b)
	var copy := values.duplicate()
	copy[index] = clampf(copy[index] + delta, MIN_VALUE, MAX_VALUE)
	values = copy


## Медленный сполз к базовому. Не «мир восстанавливается», а наоборот: без новых
## событий отношения скатываются обратно к вражде.
func _drift(delta: float) -> void:
	var copy := values.duplicate()
	var moved := false
	for i in PAIRS:
		var target: float = float(BASELINE[i])
		if is_equal_approx(copy[i], target):
			continue
		var step: float = DRIFT_PER_SECOND * delta
		copy[i] = move_toward(copy[i], target, step)
		moved = true
	if moved:
		values = copy


# --- эффекты (GDD раздел 9.2) ----------------------------------------------

## Обслужит ли лавка стороны `owner` покупателя стороны `buyer`.
func trade_allowed(buyer: int, owner: int) -> bool:
	return value_of(buyer, owner) > TRADE_CLOSED_BELOW


## Во сколько раз дороже товар для этого покупателя.
##
## Вражда наказывает сильнее, чем дружба награждает: наценка до двух раз,
## скидка максимум четверть. Иначе выгоднее было бы дружить со всеми, а это мир
## гражданской войны.
func price_scale(buyer: int, owner: int) -> float:
	var rel := value_of(buyer, owner)
	if rel >= 0.0:
		return 1.0 - MAX_DISCOUNT * (rel / MAX_VALUE)
	return 1.0 + MAX_MARKUP * (-rel / MAX_VALUE)


## Цена с учётом отношения. Округляем вверх: скидка не должна давать бесплатно.
func adjust_cost(cost: Array, buyer: int, owner: int) -> Array:
	var scale := price_scale(buyer, owner)
	var result := []
	for value in cost:
		var raw := float(int(value)) * scale
		result.append(int(ceil(raw)) if raw > 0.0 else 0)
	return result


## Человекочитаемое отношение — для панели лавки и HUD.
func label_of(a: int, b: int) -> String:
	var rel := value_of(a, b)
	if rel <= TRADE_CLOSED_BELOW:
		return "война"
	if rel < -20.0:
		return "вражда"
	if rel < FRIENDLY_ABOVE:
		return "холод"
	if rel < 60.0:
		return "терпимость"
	return "союз"


# --- события (GDD раздел 9.3) ----------------------------------------------

## Насколько падает отношение от событий. Убийство персонажа — сильнее всего:
## это самое личное, что стороны могут друг другу сделать.
const HIT_KILL := -14.0
## Убийство вожака — окончательное и потому вдвое тяжелее обычного.
const HIT_LEADER_KILL := -28.0
## Разбитый караван бьёт по кошельку, а не по людям.
const HIT_CARAVAN := -8.0
## Снесённая постройка — тоже по имуществу, но заметнее каравана.
const HIT_BUILDING := -10.0
## Выполненный приказ против стороны: вред нанесён по приказу, а не сгоряча.
const HIT_ORDER := -5.0


## Персонажа убили. Только на хосте.
func on_kill(victim_faction: int, killer_faction: int, victim_was_leader: bool) -> void:
	if killer_faction < 0 or victim_faction == killer_faction:
		return
	shift(victim_faction, killer_faction, HIT_LEADER_KILL if victim_was_leader else HIT_KILL)


## Караван разбит. Только на хосте.
func on_caravan_destroyed(owner_faction: int, killer_faction: int) -> void:
	if killer_faction < 0 or owner_faction == killer_faction:
		return
	shift(owner_faction, killer_faction, HIT_CARAVAN)


## Постройка снесена. Только на хосте.
func on_building_destroyed(owner_faction: int, killer_faction: int) -> void:
	if killer_faction < 0 or owner_faction == killer_faction:
		return
	shift(owner_faction, killer_faction, HIT_BUILDING)


## Приказ стражи выполнен против конкретной стороны. Только на хосте.
func on_order_against(target_faction: int, actor_faction: int) -> void:
	if actor_faction < 0 or target_faction == actor_faction:
		return
	shift(target_faction, actor_faction, HIT_ORDER)


# --- перемирие между игроками (GDD раздел 9.4) -----------------------------

## На сколько поднимается отношение при принятом перемирии и насколько долго
## держится, прежде чем дрейф его съест.
##
## Это намеренно ЖЕСТ, а не переговоры: никаких таблиц условий и торга. Поднять
## отношение можно, удержать — только новыми делами, потому что дрейф тянет
## обратно к вражде.
const TRUCE_BONUS := 45.0
## Как близко надо стоять, чтобы предложить.
const TRUCE_RANGE := 12.0
## Сколько живёт непринятое предложение.
const OFFER_SECONDS := 20.0

## Кто кому предложил: ключ — сторона предложившего, значение — сторона, которой
## предложено, и когда предложение истекает.
var _offers := {}


## Предложить перемирие другой стороне. Только на хосте.
func offer_truce(from_faction: int, to_faction: int) -> String:
	if not Net.hosting() or from_faction == to_faction:
		return ""
	# Встречное предложение той же пары считается согласием: не нужен отдельный
	# «принять» — достаточно, чтобы оба сделали шаг навстречу.
	if _has_offer(to_faction, from_faction):
		_offers.erase(to_faction)
		shift(from_faction, to_faction, TRUCE_BONUS)
		return "Перемирие заключено: %s и %s" % [
			FACTIONS.name_of(from_faction), FACTIONS.name_of(to_faction)
		]
	_offers[from_faction] = {
		"to": to_faction,
		"until": Time.get_ticks_msec() / 1000.0 + OFFER_SECONDS,
	}
	return "%s предлагает перемирие стороне «%s»" % [
		FACTIONS.name_of(from_faction), FACTIONS.name_of(to_faction)
	]


## Есть ли живое предложение от `from` к `to`.
func _has_offer(from_faction: int, to_faction: int) -> bool:
	if not _offers.has(from_faction):
		return false
	var offer: Dictionary = _offers[from_faction]
	if float(offer["until"]) < Time.get_ticks_msec() / 1000.0:
		_offers.erase(from_faction)
		return false
	return int(offer["to"]) == to_faction


## Ждёт ли эта сторона ответа на своё предложение — для подсказки в HUD.
func pending_offer_to(from_faction: int) -> int:
	if not _offers.has(from_faction):
		return -1
	var offer: Dictionary = _offers[from_faction]
	if float(offer["until"]) < Time.get_ticks_msec() / 1000.0:
		_offers.erase(from_faction)
		return -1
	return int(offer["to"])
