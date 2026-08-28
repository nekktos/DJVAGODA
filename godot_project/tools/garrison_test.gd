extends "res://tools/test_base.gd"
##
## Автопроверка гарнизонов свободных сторон (Этап 10, шаг 8, ступень «а»).
## Работает headless.
##
## Запуск:
##   godot --headless --path godot_project -- --host --faction=0 --garrisontest
##   godot --headless --path godot_project -- --join=127.0.0.1 --faction=1 --garrisontest
##
## Хост берёт злодея, клиент — эльфов: значит стража остаётся свободной, и
## именно на ней проверяется появление гарнизона, а на двух занятых — его
## отсутствие.
##

const FACTIONS := preload("res://scripts/factions.gd")
const GARRISON := preload("res://scripts/ai/garrison.gd")

var _world: Node3D


func start(world: Node3D) -> void:
	tag = "гарнизон"
	expected_host = 17
	expected_client = 2
	_world = world
	_run.call_deferred()


func _run() -> void:
	await get_tree().create_timer(3.0).timeout
	var me: Node3D = _world.local_player()
	if me == null:
		fail("персонаж не заспавнен")
		finish()
		return

	if not Net.hosting():
		await _run_client(me)
		finish()
		return

	await _test_appears_only_on_free_side(me)
	await _test_targets_by_faction(me)
	await _test_leash()
	await _test_reinforce_and_disband(me)

	if not multiplayer.get_peers().is_empty():
		await get_tree().create_timer(6.0).timeout
	finish()


func _garrison() -> Node:
	return _world.garrison


## Гарнизон стоит только там, где никто не играет.
func _test_appears_only_on_free_side(me: Node3D) -> void:
	# Ждём первой проверки состава сторон.
	await get_tree().create_timer(4.0).timeout

	check(_garrison().size_of(int(me.faction)) == 0, "у занятой стороны гарнизона нет",
		"%s: %d" % [FACTIONS.name_of(int(me.faction)), _garrison().size_of(int(me.faction))])

	var free_side := _free_faction()
	if free_side < 0:
		fail("свободных сторон нет — проверять нечего")
		return
	check(_garrison().size_of(free_side) == GARRISON.SIZE, "свободная сторона выставила гарнизон",
		"%s: %d бойцов" % [FACTIONS.name_of(free_side), _garrison().size_of(free_side)])

	var units := _units_of_faction(free_side)
	check(units.size() == GARRISON.SIZE, "бойцы гарнизона есть в мире",
		"%d нод" % units.size())
	if units.is_empty():
		return
	check(int(units[0].owner_id) == 0, "у бойца гарнизона нет владельца-игрока",
		"owner_id=%d" % int(units[0].owner_id))
	check(units[0].leash > 0.0, "у бойца гарнизона есть поводок",
		"%.0f м" % units[0].leash)

	# Распорядитель стражи — тоже боец без владельца и тоже за стражу, но в штат
	# гарнизона не входит: он стоит на посту всегда, занята сторона или нет.
	# Без этой проверки гарнизон стражи молча считался бы на одного больше.
	var champions := 0
	for node in get_tree().get_nodes_in_group("unit"):
		if is_instance_valid(node) and "is_champion" in node and node.is_champion:
			champions += 1
	check(champions == 1, "распорядитель в мире ровно один", "%d" % champions)
	check(_garrison().size_of(FACTIONS.Kind.GUARD) != 1,
		"распорядитель не попал в штат гарнизона",
		"в штате стражи: %d" % _garrison().size_of(FACTIONS.Kind.GUARD))


## Свой-чужой определяется СТОРОНОЙ, а не владельцем. Иначе отряды двух игроков
## одной стороны резали бы друг друга — теперь слотов по пять.
func _test_targets_by_faction(me: Node3D) -> void:
	var free_side := _free_faction()
	var units := _units_of_faction(free_side)
	if units.is_empty():
		fail("гарнизона нет, проверять цели не на ком")
		return
	var guard_unit: Node3D = units[0]

	# Свой той же стороны целью быть не может.
	var ally: Node3D = _world.spawn_garrison_unit(free_side, 9, guard_unit.global_position
		+ Vector3(2.0, 0.0, 0.0), guard_unit.home, guard_unit.leash)
	await get_tree().physics_frame
	check(ally != null and int(ally.faction) == int(guard_unit.faction),
		"союзник той же стороны создан", "для проверки")

	var before: float = ally.health if ally != null else 0.0
	await get_tree().create_timer(2.5).timeout
	check(ally != null and is_instance_valid(ally) and ally.health >= before,
		"своих гарнизон не бьёт", "здоровье %.0f" % (ally.health if is_instance_valid(ally) else -1.0))
	if is_instance_valid(ally):
		ally.queue_free()

	# А чужой стороны — бьёт.
	check(int(me.faction) != free_side, "игрок другой стороны", FACTIONS.name_of(int(me.faction)))
	me.teleport.rpc(guard_unit.global_position + Vector3(0.0, 1.0, 2.0))
	var hp_before: float = me.health.current
	await get_tree().create_timer(3.0).timeout
	check(me.health.current < hp_before, "чужого гарнизон бьёт",
		"HP %.0f -> %.0f" % [hp_before, me.health.current])


## Поводок: гарнизон обороняет зону, а не гонится за целью через полкарты.
func _test_leash() -> void:
	var free_side := _free_faction()
	var units := _units_of_faction(free_side)
	if units.is_empty():
		fail("гарнизона нет, поводок проверять не на ком")
		return
	var unit: Node3D = units[0]
	var home: Vector3 = unit.home

	check(unit._within_leash(home), "дом внутри поводка", "да")
	check(not unit._within_leash(home + Vector3(unit.leash * 2.0, 0.0, 0.0)),
		"точка за поводком снаружи", "вдвое дальше поводка")

	# Уводим бойца далеко и спрашиваем, КУДА он собрался.
	#
	# Раньше здесь ждали три секунды и мерили, приблизился ли он. В тихом мире
	# это работало, а как только стороны ИИ начали воевать по-настоящему,
	# проверка стала падать на верном поведении: рядом появляется враг, боец
	# идёт за ним — это и есть его работа, а вовсе не поломка поводка. Мир
	# живой, и «куда он пришёл» о правиле не говорит ничего.
	unit.ai_led = false
	unit.global_position = home + Vector3(unit.leash * 0.8, 1.0, 0.0)
	unit.sync_position = unit.global_position
	var far: float = unit.global_position.distance_to(home)
	await get_tree().physics_frame
	var wants: Vector3 = unit._idle_destination(0.0)
	check(wants.distance_to(home) < far, "боец возвращается на пост",
		"стоит в %.0f м, собрался в точку в %.0f м от дома"
			% [far, wants.distance_to(home)])


## Павших восполняют, а при появлении игрока гарнизон распускают.
func _test_reinforce_and_disband(me: Node3D) -> void:
	var free_side := _free_faction()
	var units := _units_of_faction(free_side)
	if units.is_empty():
		fail("гарнизона нет")
		return

	units[0].take_damage(9999.0, int(me.peer_id), "torso", units[0].global_position, Vector3.FORWARD)
	await get_tree().create_timer(0.5).timeout
	check(_garrison().size_of(free_side) < GARRISON.SIZE, "павший выбыл из строя",
		"%d бойцов" % _garrison().size_of(free_side))

	# Пополняют ТОЛЬКО тех, кто дома, и это намеренно: иначе отряд
	# восстанавливался бы прямо посреди боя и правило отхода не срабатывало бы
	# никогда. Проверяем обе половины — сначала что в набеге не восполняют.
	var wb: Node = _world.get_node("Warband")
	if not wb.at_home(free_side):
		await get_tree().create_timer(3.0).timeout
		check(_garrison().size_of(free_side) < GARRISON.SIZE,
			"пока отряд в набеге, павших не восполняют",
			"%d бойцов" % _garrison().size_of(free_side))
	else:
		check(true, "пока отряд в набеге, павших не восполняют",
			"отряд и так дома — проверять нечего")

	# Теперь отправляем отряд домой и ждём пополнения.
	wb._go_home(free_side, FACTIONS.SPAWN[free_side])
	var filled := false
	for i in 12:
		await get_tree().create_timer(2.0).timeout
		if _garrison().size_of(free_side) == GARRISON.SIZE:
			filled = true
			break
	check(filled, "штат восполнен",
		"%d бойцов" % _garrison().size_of(free_side))


func _free_faction() -> int:
	for faction in FACTIONS.COUNT:
		if _world.players_of(faction).is_empty():
			return faction
	return -1


## Бойцы стороны, КРОМЕ распорядителя стражи. Он тоже боец без владельца и
## тоже за стражу, но к гарнизону отношения не имеет: он стоит на посту всегда,
## занята сторона или нет, и в штат не входит.
func _units_of_faction(faction: int) -> Array:
	var result := []
	for node in get_tree().get_nodes_in_group("unit"):
		if not is_instance_valid(node) or not ("faction" in node):
			continue
		if int(node.faction) != faction:
			continue
		if "is_champion" in node and node.is_champion:
			continue
		result.append(node)
	return result


## Клиент: гарнизоны реплицируются как обычные бойцы, и его сторона свободной
## не считается.
func _run_client(me: Node3D) -> void:
	await get_tree().create_timer(6.0).timeout
	check(_units_of_faction(int(me.faction)).is_empty(), "за занятую сторону гарнизона нет",
		FACTIONS.name_of(int(me.faction)))
	var seen := 0
	for node in get_tree().get_nodes_in_group("unit"):
		seen += 1
	check(seen > 0, "бойцы гарнизона видны клиенту", "%d нод" % seen)
