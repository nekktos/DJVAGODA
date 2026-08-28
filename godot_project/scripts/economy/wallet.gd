extends Node
##
## Кошелёк фракции: два запаса вместо одного (Этап 10, шаг 1, GDD раздел 4.1).
##
## ПРИ СЕБЕ (Carried) — то, что персонаж носит на себе. Смерть роняет это всё
## трупом на землю, поднять может любой, включая убийцу.
##
## В СКЛАДЕ (Stored) — то, что сложено в постройку. Смертью не теряется. Склад
## существует ровно для этого: чтобы поход в поле был рискованным, а база — нет.
##
## Асимметрия сторон здесь не побочная, а задуманная: склад умеет строить только
## злодей, поэтому у эльфов и стражи безопасного запаса нет вовсе, и всё, что у
## них есть, всегда под ударом. Взамен у них ниже входной порог.
##
## Наружу кошелёк выглядит как один запас: add/spend/can_afford/get_amount
## работают как раньше, поэтому весь код Этапов 4-9 не переписывался.
## Разница только в том, КУДА кладётся и ОТКУДА тратится.
##

const RES := preload("res://scripts/economy/resources.gd")

signal changed

@onready var carried: Node = $Carried
@onready var stored: Node = $Stored


func _ready() -> void:
	carried.changed.connect(func() -> void: changed.emit())
	stored.changed.connect(func() -> void: changed.emit())


## Положить добытое. Всегда ложится ПРИ СЕБЕ: чтобы попало в склад, надо дойти
## до склада (deposit). Возвращает, сколько влезло.
func add(kind: int, value: int) -> int:
	return carried.add(kind, value)


## Положить сразу в склад, минуя руки. Так приезжает караван: он и так везёт
## груз именно на склад, а не в карман игроку.
func add_stored(kind: int, value: int) -> int:
	return stored.add(kind, value)


## Лошади стороны: сколько всего куплено и сколько сейчас в упряжках.
##
## Держим у СТОРОНЫ, а не у персонажа. Конюшня, обозы и всадники — общее
## хозяйство, и искать лошадей по владельцу-персонажу значит наступить на те же
## грабли, что с казной, батраками, гарнизоном, постройками и караванами. Это
## было пять раз, и каждый раз молча.
##
## Ушедшие с обозом считаются отдельно: увёл караван шестёрку — на вторую
## упряжку осталось шесть, и это видно сразу, без пересчёта повозок по карте.
@export var horses := 0
@export var horses_out := 0


## Сколько лошадей свободно прямо сейчас: не в упряжке и не под седлом.
func horses_free() -> int:
	return maxi(0, horses - horses_out)


## Сколько всего есть — при себе плюс в складе.
func get_amount(kind: int) -> int:
	return carried.get_amount(kind) + stored.get_amount(kind)


func can_afford(cost: Array) -> bool:
	for i in RES.COUNT:
		if get_amount(i) < int(cost[i]):
			return false
	return true


## Списать. Сначала тратим то, что при себе: этот запас всё равно под риском,
## глупо беречь его и тратить защищённый.
func spend(cost: Array) -> bool:
	if not Net.hosting() or not can_afford(cost):
		return false
	for i in RES.COUNT:
		var left := int(cost[i])
		if left <= 0:
			continue
		var from_hand: int = mini(left, carried.get_amount(i))
		if from_hand > 0:
			carried.take(i, from_hand)
			left -= from_hand
		if left > 0:
			stored.take(i, left)
	changed.emit()
	return true


## Переложить всё, что при себе, в склад. Только на хосте.
## Возвращает, сколько единиц удалось сложить (в склад может не влезть).
func deposit() -> int:
	if not Net.hosting():
		return 0
	var moved := 0
	for i in RES.COUNT:
		var have: int = carried.get_amount(i)
		if have <= 0:
			continue
		var placed: int = stored.add(i, have)
		if placed > 0:
			carried.take(i, placed)
			moved += placed
	return moved


## Смерть: всё, что при себе, уходит из кошелька. Возвращает выпавшее, чтобы
## мир высыпал это трупом на землю. Только на хосте.
func drop_carried() -> PackedInt32Array:
	if not Net.hosting():
		return PackedInt32Array([0, 0, 0, 0])
	var lost: PackedInt32Array = carried.amounts.duplicate()
	carried.amounts = PackedInt32Array([0, 0, 0, 0])
	changed.emit()
	return lost


## Потолок склада растёт от построенных складов. Потолок «при себе» не растёт
## никогда: нельзя носить на себе бесконечно много.
func raise_capacity(bonus: int) -> void:
	stored.raise_capacity(bonus)


func carried_total() -> int:
	var sum := 0
	for i in RES.COUNT:
		sum += carried.get_amount(i)
	return sum


## Потолок в проекте считается НА КАЖДЫЙ РЕСУРС, а не на суммарный вес, —
## поэтому в скобках показываем именно его, а не «сколько всего влезет».
func summary() -> String:
	var parts := PackedStringArray()
	for i in RES.COUNT:
		parts.append("%s %d/%d" % [RES.SHORT[i], carried.get_amount(i), stored.get_amount(i)])
	return "%s  (при себе/в складе, потолок на ресурс %d/%d)" % [
		" ".join(parts), carried.capacity, stored.capacity
	]


func _stored_total() -> int:
	var sum := 0
	for i in RES.COUNT:
		sum += stored.get_amount(i)
	return sum


## Суммарный потолок: сколько сторона вообще способна хранить.
## Только для чтения — поднимать надо raise_capacity(), он знает, какому из
## двух запасов прибавлять.
var capacity: int:
	get:
		return carried.capacity + stored.capacity


## Выдать запас разом, минуя добычу. Нужен автопроверкам, консоли и съёмке
## ракурсов: там важно проверить траты, а не путь накопления.
##
## Кладёт ПРИ СЕБЕ и поднимает потолок так, чтобы влезло целиком — иначе выдача
## молча срезалась бы по потолку, и тест падал бы не там, где сломано.
func grant(values: Array) -> void:
	var biggest := 0
	for i in RES.COUNT:
		biggest = maxi(biggest, int(values[i]))
	# Потолок на ресурс, поэтому равняемся на самый крупный, а не на сумму.
	carried.capacity = maxi(carried.capacity, biggest)
	var copy := PackedInt32Array([0, 0, 0, 0])
	for i in RES.COUNT:
		copy[i] = int(values[i])
	carried.amounts = copy
	changed.emit()


## Ограничить то, что помещается при себе. Тоже для автопроверок: проверить
## работу потолка иначе нечем.
func set_carried_capacity(value: int) -> void:
	carried.capacity = value
	changed.emit()
