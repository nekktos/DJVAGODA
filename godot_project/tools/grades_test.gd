extends "res://tools/test_base.gd"
##
## Ступени материала построек (ответ автора от 29.09): «у построек тоже грейд
## должен быть: дерево, дерево-камень, камень, камень+железо (самое крепкое)».
##
## Запуск: хост — злодей (`run_tests.sh grades`).
##
## Проверяем результат на каждом шаге: прочность выросла, цена списана, облик
## пересобран, выше предела не пускают, без денег не пускают; и что стража
## ломает постройки злодея снаряжением, а не числом.
##

const RES := preload("res://scripts/economy/resources.gd")
const FACTIONS := preload("res://scripts/factions.gd")
const BUILD_CONTROLLER := preload("res://scripts/economy/build_controller.gd")

## Сколько держала постройка до ступеней.
const OLD_HEALTH := 600.0

var _world: Node3D


func start(world: Node3D) -> void:
	tag = "ступени построек"
	expected_host = 8
	expected_client = 1
	_world = world
	_run.call_deferred()


func _run() -> void:
	if not session_ready():
		finish()
		return
	await get_tree().create_timer(3.0).timeout
	var me: Node3D = _world.local_player()
	if me == null:
		fail("персонаж не заспавнен")
		finish()
		return
	var side: int = int(me.faction)
	var spot := _free_spot(FACTIONS.SPAWN[side], RES.Building.STORAGE)
	var storage: Node3D = _world.spawn_building(RES.Building.STORAGE, spot, int(me.peer_id), side, true)
	await get_tree().physics_frame
	check(int(storage.grade) == RES.Grade.WOOD and float(storage.health) >= OLD_HEALTH * 2.0,
		"новая постройка деревянная и вдвое крепче прежнего",
		"%s, прочность %.0f" % [RES.GRADE_NAMES[int(storage.grade)], float(storage.health)])

	# Без денег не укрепляют.
	me.stock.carried.amounts = RES.empty()
	me.stock.stored.amounts = RES.empty()
	me.teleport.rpc(spot + Vector3(0.0, 1.0, 9.0))
	await get_tree().create_timer(0.5).timeout
	me.request_upgrade_building()
	check(int(storage.grade) == RES.Grade.WOOD, "без камня не укрепить", "ступень %d" % int(storage.grade))

	# Укрепляем до предела — ступень за ступенью.
	me.stock.grant(RES.fit([500, 500, 0, 500]))
	var healths := [float(storage.health)]
	var paid := true
	for step in 3:
		var cost: Array = storage.upgrade_cost()
		var stone_before: int = me.stock.get_amount(RES.Kind.STONE)
		me.request_upgrade_building()
		paid = paid and me.stock.get_amount(RES.Kind.STONE) == stone_before - RES.at(cost, RES.Kind.STONE)
		healths.append(float(storage.health))
	check(int(storage.grade) == RES.Grade.STONE_IRON, "три укрепления — камень и железо",
		RES.GRADE_NAMES[int(storage.grade)])
	check(healths[0] < healths[1] and healths[1] < healths[2] and healths[2] < healths[3],
		"прочность растёт с каждой ступенью", str(healths))
	check(paid, "цена списывается", "камень списан по цене каждой ступени")
	me.request_upgrade_building()
	check(int(storage.grade) == RES.Grade.STONE_IRON and storage.upgrade_cost().is_empty(),
		"крепче камня с железом не бывает", "ступень %d" % int(storage.grade))

	await get_tree().process_frame
	check(int(storage._look_grade) == int(storage.grade), "облик пересобран под ступень",
		"облик %d, ступень %d" % [int(storage._look_grade), int(storage.grade)])

	# Стража ломает постройки злодея снаряжением, а не числом.
	var pawn: Node3D = null
	for unit in get_tree().get_nodes_in_group("unit"):
		if is_instance_valid(unit) and int(unit.faction) == FACTIONS.Kind.GUARD:
			pawn = unit
			break
	var before: float = float(storage.health)
	if pawn != null:
		storage.take_damage(100.0, 0, "building", storage.global_position, Vector3.FORWARD,
			false, -1, pawn)
	var lost: float = before - float(storage.health)
	check(pawn != null and lost > 0.0 and lost <= 25.0,
		"пешка стражи ломает постройку злодея в малую долю силы", "удар 100 снял %.1f" % lost)
	finish()


func _free_spot(around: Vector3, kind: int) -> Vector3:
	for radius in [30.0, 44.0, 58.0, 72.0]:
		for i in 12:
			var angle := TAU * float(i) / 12.0
			var at := around + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
			at.y = 0.0
			if BUILD_CONTROLLER.is_spot_buildable(_world, at, kind):
				return at
	return around
