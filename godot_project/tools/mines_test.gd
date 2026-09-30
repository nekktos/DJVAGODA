extends "res://tools/test_base.gd"
##
## Шахты на земле эльфов (GDD 9a, доработка концепции от 28.09.2026).
##
## Запуск: godot --headless --path godot_project -- --host --faction=0 --minestest
##
## ЗАЧЕМ. Решение автора игры: «главная точка интереса и соприкосновения — это
## шахты (разные шахты для железа, камня и угля), шахты находятся на территории
## эльфов; ресурсы, добытые на шахте, можно использовать только после того, как
## караван дойдёт с шахты до склада».
##
## Проверяем три вещи. РАСКЛАДКУ: шахт четыре, все в лесу эльфов, и к каждой можно
## подойти. ДОБЫЧУ: каждая копит свою породу, и руками её не взять — ни молотом по
## скале, ни батраком-шахтёром. И ОБОЗ: едет к той шахте, у которой поставлена
## последняя точка, и грузится только у шахты.
##

const RES := preload("res://scripts/economy/resources.gd")
const FACTIONS := preload("res://scripts/factions.gd")
const WORLD_BUILDER := preload("res://scripts/world_builder.gd")
const LABOURER := preload("res://scripts/units/labourer.gd")

## Насколько близко к входу путь обязан подойти, чтобы считаться дошедшим.
const REACH := 12.0
## Ближе этого к входу не должно быть ни одного дерева: там разворачивается обоз.
const DOOR_CLEAR := 15.0

var _world: Node3D


func start(world: Node3D) -> void:
	tag = "шахты"
	expected_host = 12
	expected_client = 1
	_world = world
	_run.call_deferred()


func _run() -> void:
	if not session_ready():
		finish()
		return
	await get_tree().create_timer(2.0).timeout
	var me: Node3D = _world.local_player()
	if me == null:
		fail("персонаж не заспавнен")
		finish()
		return

	_test_one_per_kind()
	_test_on_elf_land()
	_test_iron_is_contested()
	_test_near_mines()
	_test_reachable()
	_test_no_trees_at_door()
	_test_rock_not_harvestable()
	await _test_each_mines_its_own()
	_test_miner_skips_mines()
	await _test_miner_digs_for_caravan()
	await _test_caravan_goes_to_last_point(me)
	finish()


func _flat(at: Vector3) -> Vector2:
	return Vector2(at.x, at.z)


func _at(kind: int) -> Vector3:
	return WORLD_BUILDER.mine_info(kind).get("at", Vector3.INF)


func _test_one_per_kind() -> void:
	var kinds := []
	for each in _world.mines:
		kinds.append(int(each.kind))
	kinds.sort()
	var want := [RES.Kind.IRON, RES.Kind.COAL, RES.Kind.STONE, RES.Kind.GOLD]
	want.sort()
	check(kinds == want, "шахт четыре, по одной на породу: железо, камень, уголь, золото",
		"породы шахт: %s" % str(kinds))


## Эльфам до любой шахты ближе, чем злодею и страже. Это и есть «на их земле».
func _test_on_elf_land() -> void:
	var elves := _flat(FACTIONS.SPAWN[FACTIONS.Kind.ELVES])
	var villain := _flat(FACTIONS.SPAWN[FACTIONS.Kind.VILLAIN])
	var guard := _flat(FACTIONS.SPAWN[FACTIONS.Kind.GUARD])
	var stray := PackedStringArray()
	for each in _world.mines:
		var at := _flat(each.global_position)
		var to_elves: float = at.distance_to(elves)
		if to_elves >= at.distance_to(villain) or to_elves >= at.distance_to(guard):
			stray.append(each.title())
		# И внутри их леса, а не на опушке за его краем.
		if to_elves > WORLD_BUILDER.ZONE_HALF - 30.0:
			stray.append("%s за краем леса" % each.title())
	check(stray.is_empty(), "все шахты на земле эльфов, в их лесу",
		", ".join(stray))


## Железо и золото — самые нужные породы, и за них обязаны драться на равных.
func _test_iron_is_contested() -> void:
	var parts := PackedStringArray()
	var fair := true
	for kind in [RES.Kind.IRON, RES.Kind.GOLD]:
		var at := _flat(_at(kind))
		var to_villain: float = at.distance_to(_flat(FACTIONS.SPAWN[FACTIONS.Kind.VILLAIN]))
		var to_guard: float = at.distance_to(_flat(FACTIONS.SPAWN[FACTIONS.Kind.GUARD]))
		if absf(to_villain - to_guard) >= 1.5:
			fair = false
		parts.append("%s: злодею %.0f м, страже %.0f м" % [RES.NAMES[kind], to_villain, to_guard])
	check(fair, "железо и золото ровно посередине между злодеем и стражей",
		"; ".join(parts))


## У каждой стороны своя шахта поближе: камень у злодея, уголь у стражи.
func _test_near_mines() -> void:
	var villain := _flat(FACTIONS.SPAWN[FACTIONS.Kind.VILLAIN])
	var guard := _flat(FACTIONS.SPAWN[FACTIONS.Kind.GUARD])
	var stone := _flat(_at(RES.Kind.STONE))
	var coal := _flat(_at(RES.Kind.COAL))
	check(stone.distance_to(villain) < stone.distance_to(guard)
			and coal.distance_to(guard) < coal.distance_to(villain),
		"каменоломня ближе к злодею, угольная шахта — к страже",
		"камень: злодею %.0f, страже %.0f; уголь: злодею %.0f, страже %.0f" % [
			stone.distance_to(villain), stone.distance_to(guard),
			coal.distance_to(villain), coal.distance_to(guard)])


## До входа каждой шахты можно дойти от злодея и от стражи. Шахта посреди леса,
## до которой сетка не довела бы, — это декорация, а не точка соприкосновения.
func _test_reachable() -> void:
	var bad := PackedStringArray()
	for each in _world.mines:
		var door: Vector3 = _world.mine_dock(each)
		for side in [FACTIONS.Kind.VILLAIN, FACTIONS.Kind.GUARD]:
			var path: PackedVector3Array = _world.navigation.path_between(
				FACTIONS.SPAWN[side], door)
			var gap := INF
			if not path.is_empty():
				gap = _flat(path[path.size() - 1]).distance_to(_flat(door))
			if gap > REACH:
				bad.append("%s от %s: не дошёл %.0f м" % [
					each.title(), FACTIONS.name_of(side), gap])
	check(bad.is_empty(), "к входу каждой шахты можно дойти и от злодея, и от стражи",
		"; ".join(bad))


func _test_no_trees_at_door() -> void:
	var crowded := PackedStringArray()
	for each in _world.mines:
		var door := _flat(_world.mine_dock(each))
		var count := 0
		for tree in _world.forest._pos:
			if _flat(tree).distance_to(door) < DOOR_CLEAR:
				count += 1
		if count > 0:
			crowded.append("%s: деревьев у входа %d" % [each.title(), count])
	check(crowded.is_empty(), "у входов шахт лес расчищен — обозу есть где встать",
		", ".join(crowded))


## Скалу шахты нельзя набить молотом и унести в руках: старая была залежью
## железа на сорок ударов, и это был путь к железу мимо обоза.
func _test_rock_not_harvestable() -> void:
	var found := 0
	for node in get_tree().get_nodes_in_group("harvestable"):
		var deposit := node as Node3D
		if deposit == null:
			continue
		for each in _world.mines:
			if _flat(deposit.global_position).distance_to(_flat(each.global_position)) \
					< WORLD_BUILDER.MINE_ROCK:
				found += 1
	check(found == 0, "скалу шахты руками не добыть", "залежей у шахт: %d" % found)


func _test_each_mines_its_own() -> void:
	for each in _world.mines:
		each.stored = RES.empty()
	# Копают на всех — без рабочих шахта даёт малую долю, и золота за четыре
	# секунды не набралось бы и единицы.
	var digger := Node.new()
	add_child(digger)
	for i in 8:
		for each in _world.mines:
			each.dig(digger)
		await get_tree().create_timer(0.5).timeout
	digger.queue_free()
	var wrong := PackedStringArray()
	for each in _world.mines:
		var own: int = int(each.kind)
		if RES.at(each.stored, own) <= 0:
			wrong.append("%s не копит своё" % each.title())
		for other in [RES.Kind.IRON, RES.Kind.STONE, RES.Kind.COAL, RES.Kind.GOLD,
				RES.Kind.WOOD, RES.Kind.FOOD]:
			if other != own and RES.at(each.stored, other) > 0:
				wrong.append("%s копит %s" % [each.title(), RES.NAMES[other]])
	check(wrong.is_empty(), "каждая шахта копит свою породу, и только её",
		", ".join(wrong))


## Шахтёр НЕ носит руду из шахты в руках: её довозит только обоз. Но копает
## на шахте — туда, куда едет обоз его стороны (ответ автора от 30.09: «на
## шахтах тоже физически должны работать, но не обязательно таскать руками,
## приоритетнее загрузить обоз»). Без такого обоза на шахту не идёт.
func _test_miner_skips_mines() -> void:
	var door: Vector3 = _world.mine_dock(_world.mine)
	var worker: Node = _world.spawn_labourer(FACTIONS.Kind.VILLAIN, door, door,
		LABOURER.Role.MINER)
	if worker == null:
		fail("батрака для проверки не заспавнили")
		return
	var site: Node3D = worker._find_site()
	var is_mine: bool = site != null and _world.mines.has(site)
	check(not is_mine, "без обоза шахтёр на шахту не идёт",
		"место работы: %s" % (site.name if site != null else "нет"))
	worker.free()


## С обозом у шахты шахтёр копает у её входа: шахта копит быстрее, а в руках —
## пусто.
func _test_miner_digs_for_caravan() -> void:
	var iron: Node3D = _world.mine_of(RES.Kind.IRON)
	var door: Vector3 = _world.mine_dock(iron)
	var cart: Node = _world.spawn_caravan(PackedVector3Array([
		door + Vector3(0.0, 0.0, 60.0), door]), 0, FACTIONS.Kind.VILLAIN, 2)
	var worker: Node = _world.spawn_labourer(FACTIONS.Kind.VILLAIN, door, door,
		LABOURER.Role.MINER)
	if cart == null or worker == null:
		fail("обоза или батрака для проверки нет")
		return
	iron.stored = RES.empty()
	var digging := false
	for i in 12:
		await get_tree().create_timer(0.5).timeout
		if int(iron.diggers()) > 0:
			digging = true
	check(digging and int(worker.carrying()) == 0 and iron.share() > iron.PASSIVE_SHARE,
		"с обозом у шахты шахтёр копает у входа, а руду в руках не носит",
		"копают %d, в руках %d, скорость шахты x%.1f" % [int(iron.diggers()),
			int(worker.carrying()), float(iron.share())])
	worker.queue_free()
	cart.queue_free()


## Обоз едет к шахте, у которой стоит последняя точка, и грузится ТОЛЬКО у шахты.
func _test_caravan_goes_to_last_point(me: Node3D) -> void:
	var side := int(me.faction)
	var wallet: Node = _world.treasury.of(side)
	wallet.horses = 2
	var storage_at := Vector3(-380.0, 0.0, 400.0)
	_world.spawn_building(RES.Building.STORAGE, storage_at, 0, side, true)
	await get_tree().create_timer(0.5).timeout
	var coal: Node3D = _world.mine_of(RES.Kind.COAL)
	var near_coal: Vector3 = _world.mine_dock(coal) + Vector3(6.0, 0.0, 0.0)
	me.request_send_caravan(PackedVector3Array([near_coal]))
	await get_tree().create_timer(0.5).timeout
	var list: Array = _world.caravans_of(me.peer_id)
	if list.is_empty():
		fail("обоз не отправлен")
		return
	var cart: Node3D = list[0]
	var end: Vector3 = cart.route[cart.route.size() - 1]
	var gap: float = _flat(end).distance_to(_flat(_world.mine_dock(coal)))
	check(gap < REACH, "обоз едет к шахте у последней точки маршрута",
		"конец маршрута в %.0f м от входа угольной шахты" % gap)

	# Погрузку зовём напрямую, передвигая телегу: ехать по-настоящему минуты, а
	# проверяется правило, а не дорога.
	coal.stored = RES.fit([0, 0, 0, 0, 0, 100])
	cart.position = storage_at
	cart._load_at_mine()
	var empty_total := 0
	for value in cart.cargo:
		empty_total += int(value)
	cart.position = _world.mine_dock(coal)
	cart._load_at_mine()
	check(empty_total == 0 and RES.at(cart.cargo, RES.Kind.COAL) > 0,
		"грузится только у шахты: вдали пусто, у входа — уголь",
		"вдали %d, у входа угля %d" % [empty_total, RES.at(cart.cargo, RES.Kind.COAL)])
	cart.free()
	wallet.horses_out = 0
