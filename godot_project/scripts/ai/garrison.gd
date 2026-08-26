extends Node
##
## Гарнизоны свободных сторон (Этап 10, шаг 8, ступень «а»).
##
## ЧТО ЭТО И ЧТО ЭТО НЕ. Это первая, самая дешёвая ступень ИИ: болванчики,
## которые стоят в своей зоне и дерутся с теми, кто в неё зашёл. Они НЕ строят,
## НЕ ведут экономику, НЕ водят караваны и НЕ ходят в чужие зоны. Всё это —
## ступени «б» и «в», и браться за них одним куском нельзя.
##
## Задача ступени ровно одна: мир не должен пустовать. До неё сторона, за
## которую никто не сел, физически отсутствовала на карте — двое играли, а
## третья зона была голой, и это первое, что замечал любой тестер.
##
## Гарнизон появляется ТОЛЬКО у стороны, за которую никто не играет, и
## распускается, как только игрок этой стороны подключился: живой человек не
## должен обнаружить, что его базу занял кто-то другой.
##
## Считает и спавнит ТОЛЬКО хост.
##

const FACTIONS := preload("res://scripts/factions.gd")

## Сколько бойцов держит свободная сторона. Немного намеренно: это «мир не
## пустой», а не полноценный противник. Настоящая угроза — ступень «б».
const SIZE := 4

## Радиус обороны вокруг точки базы. Дальше него гарнизон за целью не идёт.
const LEASH := 90.0

## Как часто проверять, не изменился ли состав сторон.
const CHECK_INTERVAL := 3.0

var _check_t := 0.0
## Сторона -> массив её бойцов-гарнизона.
var _garrisons := {}


func _process(delta: float) -> void:
	if not Net.hosting():
		return
	_check_t += delta
	if _check_t < CHECK_INTERVAL:
		return
	_check_t = 0.0
	_sync_garrisons()


## Привести гарнизоны в соответствие с тем, кто сейчас играет.
func _sync_garrisons() -> void:
	var world := get_parent()
	for faction in FACTIONS.COUNT:
		var occupied: bool = not world.players_of(faction).is_empty()
		if occupied:
			_disband(faction)
		else:
			_reinforce(faction)


## Распустить гарнизон: за сторону сел человек.
func _disband(faction: int) -> void:
	if not _garrisons.has(faction):
		return
	var alive_count := 0
	for unit in _garrisons[faction]:
		if is_instance_valid(unit):
			alive_count += 1
			unit.queue_free()
	_garrisons.erase(faction)
	if alive_count > 0:
		print("[гарнизон] %s: распущен, за сторону сел игрок" % FACTIONS.name_of(faction))


## Дополнить гарнизон до штата. Павших восполняем: иначе первый же набег
## оставлял бы зону пустой до конца партии, и смысл ступени пропадал бы.
func _reinforce(faction: int) -> void:
	var list: Array = _garrisons.get(faction, [])
	var kept := []
	for unit in list:
		if is_instance_valid(unit):
			kept.append(unit)

	var world := get_parent()
	var base: Vector3 = FACTIONS.SPAWN[clampi(faction, 0, FACTIONS.COUNT - 1)]
	while kept.size() < SIZE:
		var index := kept.size()
		# Разводим по кольцу: спавн в одну точку заклинивает капсулы друг в друге.
		var angle := TAU * float(index) / float(SIZE)
		var spot := base + Vector3(cos(angle) * 6.0, 0.5, sin(angle) * 6.0)
		var unit: Node3D = world.spawn_garrison_unit(faction, index, spot, base, LEASH)
		if unit == null:
			break
		kept.append(unit)

	if kept.size() != list.size():
		print("[гарнизон] %s: в строю %d" % [FACTIONS.name_of(faction), kept.size()])
	_garrisons[faction] = kept


## Сколько бойцов сейчас стоит за эту сторону. Для автопроверок и HUD.
func size_of(faction: int) -> int:
	var count := 0
	for unit in _garrisons.get(faction, []):
		if is_instance_valid(unit):
			count += 1
	return count
