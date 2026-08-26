extends Node
##
## Запас ресурсов игрока. Менять его имеет право ТОЛЬКО хост.
##
## Едет тем же серверным синхронизатором, что здоровье и ранения: клиент
## значения только читает. Иначе любой клиент выписывал бы себе золото.
##
## Пока запас привязан к игроку. Когда появятся фракции, владельцем станет
## фракция, а не отдельный персонаж — менять придётся только владельца.
##

const RES := preload("res://scripts/economy/resources.gd")

signal changed

## Реплицируемое состояние: по одному числу на ресурс.
@export var amounts: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
## Потолок хранения. Растёт от построенных складов.
@export var capacity: int = RES.BASE_CAPACITY

var _seen := PackedInt32Array([0, 0, 0, 0])


func _process(_delta: float) -> void:
	if amounts != _seen:
		_seen = amounts.duplicate()
		changed.emit()


func get_amount(kind: int) -> int:
	if kind < 0 or kind >= amounts.size():
		return 0
	return amounts[kind]


## Хватает ли на покупку. Читать можно где угодно, менять — только на хосте.
func can_afford(cost: Array) -> bool:
	for i in RES.COUNT:
		if get_amount(i) < int(cost[i]):
			return false
	return true


## Списать стоимость. Только на хосте. false, если не хватило.
func spend(cost: Array) -> bool:
	if not multiplayer.is_server() or not can_afford(cost):
		return false
	var copy := amounts.duplicate()
	for i in RES.COUNT:
		copy[i] -= int(cost[i])
	amounts = copy
	changed.emit()
	return true


## Добавить добытое. Только на хосте. Возвращает, сколько влезло.
func add(kind: int, value: int) -> int:
	if not multiplayer.is_server() or kind < 0 or kind >= RES.COUNT or value <= 0:
		return 0
	var copy := amounts.duplicate()
	var room: int = maxi(0, capacity - copy[kind])
	var taken: int = mini(room, value)
	copy[kind] += taken
	amounts = copy
	changed.emit()
	return taken


## Поднять потолок хранения. Только на хосте.
func raise_capacity(bonus: int) -> void:
	if not multiplayer.is_server():
		return
	capacity += bonus
	changed.emit()


func summary() -> String:
	var parts := PackedStringArray()
	for i in RES.COUNT:
		parts.append("%s %d" % [RES.SHORT[i], get_amount(i)])
	return "%s  (потолок %d)" % [" ".join(parts), capacity]


## Снять одно значение одного ресурса. Только на хосте. Возвращает, сколько
## реально сняли. Нужен кошельку (wallet.gd), который тратит из двух запасов
## по очереди и потому не может пользоваться spend() с полной стоимостью.
func take(kind: int, value: int) -> int:
	if not multiplayer.is_server() or kind < 0 or kind >= RES.COUNT or value <= 0:
		return 0
	var copy := amounts.duplicate()
	var taken: int = mini(copy[kind], value)
	copy[kind] -= taken
	amounts = copy
	changed.emit()
	return taken
