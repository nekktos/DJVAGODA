extends "res://tools/test_base.gd"
##
## Дома эльфов (GDD 9a, ответы автора от 28.09.2026).
##
## Запуск: godot --headless --path godot_project -- --host --faction=1 --elvestest
##
## Решение автора: «вырезать эльфов — разрушить все их здания и не дать
## отстроить новые»; «при разрушении последней постройки эльфы проигрывают,
## только если в живых нет никого: им негде возрождаться»; «на постройку их
## домов обязательно нужны ресурсы (дерево, камень; от материала зависит
## прочность), нужно время, количество ограничено и зависит от числа игроков
## за эльфов — например, пять на игрока».
##

const RES := preload("res://scripts/economy/resources.gd")
const FACTIONS := preload("res://scripts/factions.gd")
const BUILD_CONTROLLER := preload("res://scripts/economy/build_controller.gd")

var _world: Node3D


func start(world: Node3D) -> void:
	tag = "эльфы"
	expected_host = 9
	expected_client = 1
	_world = world
	_run.call_deferred()


func _run() -> void:
	if not session_ready():
		finish()
		return
	await get_tree().create_timer(2.0).timeout
	var me: Node3D = _world.local_player()
	if me == null or int(me.faction) != FACTIONS.Kind.ELVES:
		fail("набор должен идти за эльфов")
		finish()
		return

	var start_houses: Array = _world.elf_houses(true)
	check(start_houses.size() == 3, "на старте у эльфов три готовых дома",
		"домов %d" % start_houses.size())

	await _test_build(me)
	await _test_limit(me)
	_test_durability()
	await _test_respawn_at_house(me)
	await _test_no_house_no_respawn(me)
	finish()


func _test_build(me: Node3D) -> void:
	# Железо тоже: иначе казарма получала бы отказ по цене, а не по правилу
	# стороны, и проверка правила молчала бы.
	me.stock.grant(RES.fit([500, 500, 0, 50]))
	await get_tree().physics_frame
	var here: Vector3 = me.global_position
	var before: int = _world.elf_houses().size()
	me.request_build(RES.Building.ELF_HOUSE, here + Vector3(0.0, 0.0, 22.0))
	await get_tree().create_timer(0.3).timeout
	var built: bool = _world.elf_houses().size() == before + 1
	me.request_build(RES.Building.ELF_HOUSE, here + Vector3(150.0, 0.0, 0.0))
	await get_tree().create_timer(0.3).timeout
	var far_refused: bool = _world.elf_houses().size() == before + 1
	check(built and far_refused, "эльф строит дом рядом с собой, а за полкарты — нет",
		"рядом %s, далеко отказано %s" % [built, far_refused])

	# Место ищем такое, где казарма ФИЗИЧЕСКИ встаёт: иначе отказ пришёл бы
	# по месту, а не по правилу стороны, и проверка молчала бы о правиле.
	var spot := Vector3.INF
	for offset in [Vector3(-26.0, 0.0, 0.0), Vector3(0.0, 0.0, -30.0), Vector3(30.0, 0.0, 0.0),
			Vector3(-30.0, 0.0, -30.0), Vector3(30.0, 0.0, -30.0)]:
		if BUILD_CONTROLLER.is_spot_buildable(_world, here + offset, RES.Building.SWORD_BARRACKS):
			spot = here + offset
			break
	var buildings_before: int = get_tree().get_nodes_in_group("building").size()
	if spot != Vector3.INF:
		me.request_build(RES.Building.SWORD_BARRACKS, spot)
		await get_tree().create_timer(0.3).timeout
	check(spot != Vector3.INF and get_tree().get_nodes_in_group("building").size() == buildings_before,
		"казарму эльфу не построить: его стройка — только дома",
		"место нашлось %s, построек %d -> %d" % [spot != Vector3.INF, buildings_before,
			get_tree().get_nodes_in_group("building").size()])


## Пять домов на игрока — и не больше.
func _test_limit(me: Node3D) -> void:
	var here: Vector3 = me.global_position
	var spots := [Vector3(-22.0, 0.0, 22.0), Vector3(22.0, 0.0, 22.0), Vector3(0.0, 0.0, -24.0)]
	for spot in spots:
		me.request_build(RES.Building.ELF_HOUSE, here + spot)
		await get_tree().create_timer(0.3).timeout
	var count: int = _world.elf_houses().size()
	check(count == _world.elf_house_limit() and _world.elf_house_limit() == RES.ELF_HOUSES_PER_PLAYER,
		"домов не больше пяти на одного игрока за эльфов",
		"домов %d при пределе %d" % [count, _world.elf_house_limit()])


func _test_durability() -> void:
	check(RES.building_health(RES.Building.ELF_STONE_HOUSE) > RES.building_health(RES.Building.ELF_HOUSE)
			and RES.at(RES.BUILDING_COST[RES.Building.ELF_STONE_HOUSE], RES.Kind.STONE) > 0,
		"каменный дом крепче деревянного и требует камня",
		"дерево %.0f, камень %.0f" % [RES.building_health(RES.Building.ELF_HOUSE),
			RES.building_health(RES.Building.ELF_STONE_HOUSE)])


## Павший эльф встаёт у своего дома, а не в точке появления стороны.
func _test_respawn_at_house(me: Node3D) -> void:
	var far: Vector3 = Vector3(-150.0, 2.0, -150.0)
	me.teleport.rpc(far)
	await get_tree().physics_frame
	me.take_damage(9999.0, 0, "torso", me.global_position, Vector3.FORWARD)
	await get_tree().create_timer(_world.RESPAWN_DELAY + 1.5).timeout
	var nearest := INF
	for house in _world.elf_houses(true):
		nearest = minf(nearest, _flat(me.global_position).distance_to(_flat(house.global_position)))
	check(me.health.alive and nearest < 15.0, "павший эльф встаёт у своего дома",
		"жив %s, до ближайшего дома %.0f м" % [me.health.alive, nearest])


## Без домов павшему негде встать — он ждёт, пока живые отстроят дом. А когда
## нет ни домов, ни живых эльфов, сторона выбывает.
func _test_no_house_no_respawn(me: Node3D) -> void:
	for house in _world.elf_houses():
		house.take_damage(99999.0, 0, "", house.global_position, Vector3.FORWARD)
	await get_tree().create_timer(0.5).timeout
	var no_houses: bool = _world.elf_houses().is_empty()
	# Живой эльф где-то в лесу: сторона не выбыла, есть кому отстроиться.
	var survivor: Node3D = _world.spawn_garrison_unit(FACTIONS.Kind.ELVES, 0,
		Vector3(-250.0, 1.0, -250.0), Vector3(-250.0, 1.0, -250.0), 5.0)
	me.take_damage(9999.0, 0, "torso", me.global_position, Vector3.FORWARD)
	await get_tree().create_timer(_world.RESPAWN_DELAY + 3.0).timeout
	var still_dead: bool = not me.health.alive
	check(no_houses and still_dead and int(_world.objective.out[FACTIONS.Kind.ELVES]) == 0,
		"без домов павший эльф не встаёт, но сторона жива, пока жив хоть один эльф",
		"домов нет %s, мёртв %s, выбыли %s" % [no_houses, still_dead, _world.objective.out])

	var new_home: Vector3 = Vector3(-300.0, 0.0, -330.0)
	_world.spawn_building(RES.Building.ELF_HOUSE, new_home, 0, FACTIONS.Kind.ELVES, true)
	await get_tree().create_timer(3.0).timeout
	var near: float = _flat(me.global_position).distance_to(_flat(new_home))
	check(me.health.alive and near < 15.0, "отстроили дом — павший встал у него",
		"жив %s, до дома %.0f м" % [me.health.alive, near])

	# Теперь до конца: дом снесён, выживший убит, сам эльф пал.
	for house in _world.elf_houses():
		house.take_damage(99999.0, 0, "", house.global_position, Vector3.FORWARD)
	if is_instance_valid(survivor):
		survivor.take_damage(99999.0, 0, "torso", survivor.global_position, Vector3.FORWARD)
	me.take_damage(9999.0, 0, "torso", me.global_position, Vector3.FORWARD)
	await get_tree().create_timer(3.0).timeout
	check(int(_world.objective.out[FACTIONS.Kind.ELVES]) == 1,
		"домов нет и в живых никого — эльфы выбывают",
		"выбыли %s, живых эльфов %d" % [_world.objective.out, _world.living_elves()])


func _flat(at: Vector3) -> Vector2:
	return Vector2(at.x, at.z)
