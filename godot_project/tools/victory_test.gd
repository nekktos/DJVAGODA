extends "res://tools/test_base.gd"
##
## Автопроверка условий победы, слотов сторон и окончательной смерти вожаков
## (Этап 10, шаг 2, GDD раздел 7). Работает headless.
##
## Запуск:
##   godot --headless --path godot_project -- --host --faction=2 --victorytest
##   godot --headless --path godot_project -- --join=127.0.0.1 --faction=0 --victorytest
##
## Хост берёт стражу, клиент — злодея: так проверяется и повышение до командира,
## и окончательная смерть злодея, и победа стражи по факту его гибели.
##

const FACTIONS := preload("res://scripts/factions.gd")

var _world: Node3D
var _heard: Array[String] = []


func start(world: Node3D) -> void:
	tag = "победа"
	expected_host = 24
	expected_client = 3
	_world = world
	_world.objective.announced.connect(func(text: String) -> void: _heard.append(text))
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

	_test_slots()
	await _test_promotion(me)
	await _test_guard_barracks()
	await _test_villain_death_is_final(me)
	await _test_guard_broken_needs_both(me)

	if not multiplayer.get_peers().is_empty():
		await get_tree().create_timer(6.0).timeout
	finish()


## Слоты сторон: злодей один, у эльфов и стражи по нескольку.
func _test_slots() -> void:
	check(FACTIONS.slots(FACTIONS.Kind.VILLAIN) == 1, "злодей в сессии один",
		"слотов %d" % FACTIONS.slots(FACTIONS.Kind.VILLAIN))
	check(FACTIONS.slots(FACTIONS.Kind.ELVES) > 1, "у эльфов несколько слотов",
		"слотов %d" % FACTIONS.slots(FACTIONS.Kind.ELVES))
	check(FACTIONS.slots(FACTIONS.Kind.GUARD) > 1, "у стражи несколько слотов",
		"слотов %d" % FACTIONS.slots(FACTIONS.Kind.GUARD))
	check(Net.max_clients() == FACTIONS.total_slots() - 1,
		"вместимость сессии считается по слотам",
		"клиентов %d при %d слотах" % [Net.max_clients(), FACTIONS.total_slots()])


## Повышение до командира: только страж, только когда живого командира нет,
## и вместе с ним приходит стратегический режим.
func _test_promotion(me: Node3D) -> void:
	var commander: Node3D = _world.commander
	check(int(me.faction) == FACTIONS.Kind.GUARD, "тест идёт за стражу",
		FACTIONS.name_of(me.faction))
	check(not me.is_leader, "рядовой страж не вожак", "is_leader=false")
	check(not me.has_strategy(), "у рядового стража нет стратегии", "нет")

	# Издалека командование не принять.
	me.teleport.rpc(Vector3(0.0, 2.0, 0.0))
	await get_tree().physics_frame
	me.request_promotion()
	await get_tree().physics_frame
	check(not me.is_leader, "издалека командование не принять", "is_leader=false")

	me.teleport.rpc(commander.POSITION + Vector3(0.0, 2.0, 2.0))
	await get_tree().physics_frame
	me.request_promotion()
	await get_tree().physics_frame
	check(me.is_leader, "у NPC командование принимается", "is_leader=true")
	check(me.has_strategy() and me.can_build(),
		"вместе с командованием приходит стратегия и стройка", "да")

	# Второй раз занять место нельзя, пока командир жив.
	check(not commander.can_promote(me), "занятое командование не передаётся",
		"can_promote=false")


## Смерть злодея окончательна и означает победу стражи.
func _test_villain_death_is_final(me: Node3D) -> void:
	var villain := _villain()
	if villain == null:
		note("злодея в сессии нет — проверка его гибели пропущена")
		return

	check(villain.is_leader, "злодей — вожак по рождению", "is_leader=true")
	check(not _world.objective.leader_is_down(FACTIONS.Kind.VILLAIN),
		"до смерти вожак злодея цел", "leader_down=false")

	villain.take_damage(999.0, int(me.peer_id), "torso", villain.global_position, Vector3.FORWARD)
	await get_tree().create_timer(1.0).timeout
	check(_world.objective.leader_is_down(FACTIONS.Kind.VILLAIN), "гибель вожака засчитана",
		"leader_down=true")
	check(_heard.any(func(t: String) -> bool: return t.contains("ПОБЕДА") and t.contains("Охрана")),
		"объявлена победа стражи", "объявлений: %d" % _heard.size())

	# Ждём дольше обычного респавна: злодей возвращаться не должен.
	await get_tree().create_timer(8.0).timeout
	check(not villain.health.alive, "злодей не вернулся в мир", "мёртв")


## Партия не обрывается победой: сессия продолжает жить как песочница.
func _villain() -> Node3D:
	for child in _world.get_node("Players").get_children():
		if "faction" in child and int(child.faction) == FACTIONS.Kind.VILLAIN:
			return child
	return null


## Клиент за злодея: он вожак, командование ему не положено, и после гибели он
## остаётся мёртвым.
func _run_client(me: Node3D) -> void:
	check(int(me.faction) == FACTIONS.Kind.VILLAIN, "клиент играет за злодея",
		FACTIONS.name_of(me.faction))
	check(me.is_leader, "злодей — вожак", "is_leader=true")

	# Хост убьёт его по ходу своей половины; ждём и смотрим, что он не воскрес.
	await get_tree().create_timer(14.0).timeout
	check(not me.health.alive, "клиент видит, что злодей не вернулся", "мёртв")


## У стражи есть казарма во дворце с начала партии, и она разрушаема.
## Без неё условие «казарма снесена» было бы неопределимым.
func _test_guard_barracks() -> void:
	var barracks := _guard_barracks()
	check(barracks != null, "казарма стражи стоит с начала партии",
		"найдена" if barracks != null else "нет")
	if barracks == null:
		check(false, "казарма достроена", "казармы нет")
		check(false, "казарма принимает урон", "казармы нет")
		return
	check(float(barracks.progress) >= 1.0, "казарма достроена",
		"прогресс %.0f%%" % (float(barracks.progress) * 100.0))

	var before: float = barracks.health
	barracks.take_damage(50.0, 1, "building", barracks.global_position, Vector3.FORWARD)
	await get_tree().physics_frame
	check(barracks.health < before, "казарма принимает урон",
		"%.0f -> %.0f" % [before, barracks.health])


## Стража сломлена только когда пали ОБА: командир и казарма.
## Убить одного человека проще, чем выбить гарнизон, и этого не должно хватать.
func _test_guard_broken_needs_both(me: Node3D) -> void:
	var objective: Node3D = _world.objective
	check(not objective.faction_is_broken(FACTIONS.Kind.GUARD),
		"живая стража не сломлена", "казарма цела, командир жив")

	# Валим командира — казарма ещё стоит, значит сторона держится.
	me.take_damage(999.0, 1, "torso", me.global_position, Vector3.FORWARD)
	await get_tree().create_timer(1.0).timeout
	check(objective.leader_is_down(FACTIONS.Kind.GUARD), "гибель командира засчитана",
		"leader_down=true")
	check(not objective.faction_is_broken(FACTIONS.Kind.GUARD),
		"одной гибели командира мало", "казарма ещё стоит")

	# Теперь сносим казарму — вот теперь сломлена.
	var barracks := _guard_barracks()
	if barracks == null:
		check(false, "казарма нашлась для сноса", "нет")
		check(false, "стража сломлена после сноса казармы", "нет")
		return
	barracks.take_damage(99999.0, 1, "building", barracks.global_position, Vector3.FORWARD)
	await get_tree().create_timer(0.5).timeout
	check(_guard_barracks() == null, "казарма нашлась для сноса", "снесена")
	check(objective.faction_is_broken(FACTIONS.Kind.GUARD),
		"стража сломлена после сноса казармы", "оба условия выполнены")


func _guard_barracks() -> Node3D:
	for node in get_tree().get_nodes_in_group("building"):
		if not ("faction" in node) or not ("kind" in node):
			continue
		if int(node.faction) == FACTIONS.Kind.GUARD and int(node.kind) == 1:
			return node
	return null
