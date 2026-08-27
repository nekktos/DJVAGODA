extends "res://scripts/units/unit.gd"
##
## Батрак злодея (Этап 10). Рабочие руки: рубит лес, бьёт камень, работает в
## шахте, строит — или берёт оружие и идёт в ополчение.
##
## ЗАЧЕМ ОТДЕЛЬНЫЙ ВИД, А НЕ РОЛЬ У МЕЧНИКА. Мечник умеет ровно одно: держать
## строй и бить. Батрак умеет четыре разных дела, и все они про работу с местом
## на карте, а не про бой. Смешав их в одном скрипте, я получил бы `_physics_
## process` с четырьмя ветками, из которых боевая нужна одной роли из четырёх.
##
## ЧТО ОН НАСЛЕДУЕТ. Всё, что умеет боец: движение с навигацией, здоровье, зоны
## попадания, кровь, смерть, расталкивание. Своё у него только одно — куда идти,
## когда драться не с кем (`_idle_destination`). Это ровно та развилка, ради
## которой она в `unit.gd` и выделена.
##
## РОЛЬ МЕНЯЕТСЯ НА ХОДУ. По замыслу батрак — не специалист, а пара рук: сегодня
## он на лесе, завтра в ополчении. Поэтому роль это поле, а не отдельный вид
## юнита, и смена роли ничего не пересоздаёт.
##
## Считает ТОЛЬКО хост. Клиент получает позицию, здоровье и роль.
##

const RES2 := preload("res://scripts/economy/resources.gd")

enum Role { LUMBERJACK, MINER, MILITIA, BUILDER }

const ROLE_COUNT := 4
const ROLE_NAMES := ["лесоруб", "шахтёр", "ополченец", "строитель"]

## Что ищет каждая роль. Шахтёр берёт и шахту, и камень на поверхности: это одно
## занятие с двумя видами месторождения, а не две роли.
const ROLE_RESOURCES := {
	Role.LUMBERJACK: [RES2.Kind.WOOD],
	Role.MINER: [RES2.Kind.STONE, RES2.Kind.IRON],
}

## Сколько единиц батрак уносит за раз. Больше носильщика-игрока не делаем:
## батрак должен быть выгоднее числом, а не грузоподъёмностью.
const LOAD_LIMIT := 30

## Пауза между ударами по источнику.
const WORK_INTERVAL := 1.2

## Ближе этого можно работать. Чуть больше игроцкой HARVEST_RANGE: батрак
## подходит сам и не должен тыкаться носом в текстуру.
const WORK_RANGE := 4.5

## Как часто перевыбирать, где работать. Каждый кадр искать ближайшее дерево
## среди сотен источников — впустую жечь время хоста.
const RETARGET_INTERVAL := 2.0

## Насколько быстрее идёт стройка с каждым строителем — см. `building.gd`.
## Здесь только для документации: само число применяет постройка.

## Реплицируемая роль: клиент подписывает батрака в HUD.
@export var sync_role: int = Role.LUMBERJACK

## Что несёт с собой. Отдаётся стороне, когда батрак доносит груз до склада.
var load := PackedInt32Array([0, 0, 0, 0])

var _work_t := 0.0
var _retarget_t := 0.0
## Текущее место работы: источник, стройка или шахта.
var _site: Node3D = null
## Куда нести груз. Пересчитывается, когда груз набран.
var _drop := Vector3.INF


func setup(data: Dictionary) -> void:
	super(data)
	sync_role = int(data.get("role", Role.LUMBERJACK))


## Ополченец дерётся, остальные — нет. Батрак с топором в руках, бросающийся на
## мечника, — это не храбрость, а потерянные руки.
func _wants_fight() -> bool:
	return sync_role == Role.MILITIA


func role_name() -> String:
	return ROLE_NAMES[clampi(sync_role, 0, ROLE_COUNT - 1)]


func carrying() -> int:
	var total := 0
	for value in load:
		total += value
	return total


## Сменить занятие. Прежнее место работы забываем: с новой ролью оно негодно.
func set_role(role: int) -> void:
	if not Net.hosting():
		return
	sync_role = clampi(role, 0, ROLE_COUNT - 1)
	_site = null
	_retarget_t = RETARGET_INTERVAL


func _idle_destination(delta: float) -> Vector3:
	if sync_role == Role.MILITIA:
		# Ополченец ведёт себя как обычный боец: строй, поводок, пост.
		return super(delta)

	# Набрал груз — несём на склад. Работа подождёт: батрак, продолжающий рубить
	# с полными руками, просто теряет время.
	if carrying() >= LOAD_LIMIT:
		return _deliver(delta)

	_retarget_t -= delta
	if _site == null or not is_instance_valid(_site) or _retarget_t <= 0.0:
		_retarget_t = RETARGET_INTERVAL
		_site = _find_site()
	if _site == null:
		# Работы нет — стоим у дома, а не бродим по карте.
		return home if home != Vector3.ZERO else global_position

	var spot: Vector3 = _site.global_position
	if global_position.distance_to(spot) > WORK_RANGE:
		return spot

	_work_t -= delta
	if _work_t <= 0.0:
		_work_t = WORK_INTERVAL
		_work_on(_site)
	# Стоим вплотную и работаем.
	return global_position


## Донести груз до места сдачи и высыпать.
func _deliver(delta: float) -> Vector3:
	if not _drop.is_finite():
		_drop = _drop_point()
	if global_position.distance_to(_drop) > WORK_RANGE:
		return _drop

	var world := get_parent().get_parent()
	if world != null and "treasury" in world:
		var wallet: Node = world.treasury.of(faction)
		if wallet != null:
			for kind in RES2.COUNT:
				if load[kind] <= 0:
					continue
				# Сначала в склад: сложенное там не теряется со смертью. Пока
				# склада нет, у стороны нет и вместимости склада вовсе — тогда
				# кладём при себе, ровно туда же, куда кладёт добычу игрок без
				# склада. Иначе первые батраки сдавали бы груз в никуда: молча,
				# без отказа и без прибытка.
				var left: int = load[kind] - wallet.add_stored(kind, load[kind])
				if left > 0:
					wallet.add(kind, left)
	load = PackedInt32Array([0, 0, 0, 0])
	_drop = Vector3.INF
	_work_t = 0.0
	return global_position


## Куда нести добытое: ближайший достроенный склад своей стороны, иначе домой.
##
## Дом — это точка базы. Без склада батрак всё равно должен куда-то носить,
## иначе первые руки бесполезны до первой постройки, а строить не на что.
func _drop_point() -> Vector3:
	var best: Vector3 = home if home != Vector3.ZERO else global_position
	var best_distance := INF
	for node in get_tree().get_nodes_in_group("building"):
		var building := node as Node3D
		if building == null or not ("faction" in building):
			continue
		if int(building.faction) != faction or float(building.progress) < 1.0:
			continue
		if int(building.kind) != RES2.Building.STORAGE:
			continue
		var d: float = global_position.distance_to(building.global_position)
		if d < best_distance:
			best_distance = d
			best = building.global_position
	return best


## Сделать один заход работы на месте.
func _work_on(site: Node3D) -> void:
	if sync_role == Role.BUILDER:
		# Стройку двигает сама постройка, считая приставленных строителей
		# (`building.gd`). Батраку остаётся стоять рядом — и он уже стоит.
		return
	if site.has_method("take"):
		# Шахта: берём накопленное, сколько влезет в руки.
		var taken: PackedInt32Array = site.take(LOAD_LIMIT - carrying())
		var copy := load.duplicate()
		for kind in RES2.COUNT:
			copy[kind] += taken[kind]
		load = copy
		return

	var kind: int = int(site.get_meta("resource", RES2.Kind.WOOD))
	var copy := load.duplicate()
	copy[kind] += RES2.YIELD_PER_HIT
	load = copy

	var tree: int = int(site.get_meta("tree", -1))
	var world := get_parent().get_parent()
	if tree >= 0 and world != null:
		if world.forest.hit_tree(tree) <= 0:
			world.forest.fell_tree.rpc(tree)
			_site = null
		return

	var left: int = int(site.get_meta("hits_left", 1)) - 1
	site.set_meta("hits_left", left)
	if left <= 0:
		site.queue_free()
		_site = null


## Где работать. Ближайшее подходящее место для своей роли.
func _find_site() -> Node3D:
	if sync_role == Role.BUILDER:
		return _nearest_site_building()
	var wanted: Array = ROLE_RESOURCES.get(sync_role, [])
	var best: Node3D = null
	var best_distance := INF

	# Шахта для шахтёра — тоже месторождение, и обычно самое богатое.
	if sync_role == Role.MINER:
		var world := get_parent().get_parent()
		if world != null and "mine" in world and world.mine != null:
			best = world.mine
			best_distance = global_position.distance_to(world.mine.global_position)

	for node in get_tree().get_nodes_in_group("harvestable"):
		var source := node as Node3D
		if source == null:
			continue
		if not wanted.has(int(source.get_meta("resource", -1))):
			continue
		var d: float = global_position.distance_to(source.global_position)
		if d < best_distance:
			best_distance = d
			best = source
	return best


## Ближайшая недостроенная постройка своей стороны.
func _nearest_site_building() -> Node3D:
	var best: Node3D = null
	var best_distance := INF
	for node in get_tree().get_nodes_in_group("building"):
		var building := node as Node3D
		if building == null or not ("faction" in building):
			continue
		if int(building.faction) != faction or float(building.progress) >= 1.0:
			continue
		var d: float = global_position.distance_to(building.global_position)
		if d < best_distance:
			best_distance = d
			best = building
	return best


## Стоит ли этот батрак у стройки и помогает ли ей. Спрашивает сама постройка.
func builds(building: Node3D) -> bool:
	return sync_role == Role.BUILDER and _site == building \
		and global_position.distance_to(building.global_position) <= WORK_RANGE
