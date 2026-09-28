extends "res://tools/test_base.gd"
##
## С чего начинают стороны (GDD 9a, доработка концепции от 28.09.2026).
##
## Запуск: godot --headless --path godot_project -- --host --faction=0 --starttest
##
## ЗАЧЕМ. Решение автора игры: «Злодей начинает игру в разрушенном старом форте с
## 0 построек и ресурсов, должен сам добыть первые ресурсы (микро шахта с
## конечным числом ресурсов, чтоб хватило только на базовые постройки, без
## развития)… У людей со старта есть все постройки, фермы, поля с пшеницей,
## ангары».
##
## Главная проверка — про микро-шахту, и она ДВУСТОРОННЯЯ: запаса обязано
## хватать на базу и обязано НЕ хватать на развитие. Шахта, которой хватает на
## всё, отменяет причину идти к шахтам эльфов, а это главная точка
## соприкосновения сторон.
##
## ЗАПАС СЧИТАЕМ ПО МИРУ, а не по константам: складываем то, что реально лежит у
## форта. Проверка, которая перемножает константы, соглашается сама с собой.
##

const RES := preload("res://scripts/economy/resources.gd")
const FACTIONS := preload("res://scripts/factions.gd")
const WEAPONS := preload("res://scripts/combat/weapons.gd")
const WORLD_BUILDER := preload("res://scripts/world_builder.gd")

## Насколько далеко от центра микро-шахты ещё считается её залежью.
const MICRO_RADIUS := 20.0
## Насколько далеко от центра зоны злодея камня быть не должно — кроме
## микро-шахты. С запасом накрывает и форт, и гряду.
const VILLAIN_REACH := 260.0

var _world: Node3D


func start(world: Node3D) -> void:
	tag = "старт"
	expected_host = 7
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

	_test_villain_starts_empty()
	_test_guard_starts_with_everything()
	var micro := _micro_yield()
	_test_micro_mine_amounts(micro)
	_test_micro_mine_is_enough_for_basics(micro)
	_test_micro_mine_is_not_enough_for_growth(micro)
	_test_micro_mine_reachable()
	_test_ridge_is_not_a_quarry()
	finish()


func _test_villain_starts_empty() -> void:
	var side := FACTIONS.Kind.VILLAIN
	var wallet: Node = _world.treasury.of(side)
	var total := 0
	for kind in RES.COUNT:
		total += int(wallet.get_amount(kind))
	check(total == 0 and _world.labourers_of(side).is_empty()
			and int(wallet.horses) == 0,
		"злодей начинает с нуля: ни ресурсов, ни батраков, ни лошадей",
		"ресурсов %d, батраков %d, лошадей %d"
			% [total, _world.labourers_of(side).size(), int(wallet.horses)])


func _test_guard_starts_with_everything() -> void:
	var have := {}
	for node in get_tree().get_nodes_in_group("building"):
		if not ("faction" in node) or int(node.faction) != FACTIONS.Kind.GUARD:
			continue
		if float(node.progress) < 1.0:
			continue
		have[int(node.kind)] = int(have.get(int(node.kind), 0)) + 1
	var missing := PackedStringArray()
	for kind in [RES.Building.STORAGE, RES.Building.HOUSE, RES.Building.STABLE,
			RES.Building.SWORD_BARRACKS]:
		if int(have.get(kind, 0)) < 1:
			missing.append(RES.BUILDING_NAMES[kind])
	if int(have.get(RES.Building.FARM, 0)) < 2:
		missing.append("два поля")
	check(missing.is_empty(), "у стражи со старта всё хозяйство достроено",
		"не хватает: %s" % ", ".join(missing))


## Сколько даёт микро-шахта — по тому, что реально лежит у форта. Молотом:
## им злодей вооружён с первой минуты, и молот бьёт камень вдвое.
func _micro_yield() -> PackedInt32Array:
	var got := RES.empty()
	for node in get_tree().get_nodes_in_group("harvestable"):
		var deposit := node as Node3D
		if deposit == null:
			continue
		var flat: float = Vector2(deposit.global_position.x, deposit.global_position.z) \
			.distance_to(Vector2(WORLD_BUILDER.MICRO_MINE_POS.x, WORLD_BUILDER.MICRO_MINE_POS.z))
		if flat > MICRO_RADIUS:
			continue
		var kind: int = int(deposit.get_meta("resource", -1))
		if kind < 0:
			continue
		var per_hit: int = int(round(RES.YIELD_PER_HIT
			* WEAPONS.harvest_bonus(WEAPONS.Kind.HAMMER, kind)))
		got[kind] += int(deposit.get_meta("hits_left", 0)) * per_hit
	return got


func _test_micro_mine_amounts(micro: PackedInt32Array) -> void:
	note("микро-шахта даёт: камня %d, золота %d, железа %d" % [
		micro[RES.Kind.STONE], micro[RES.Kind.GOLD], micro[RES.Kind.IRON]])
	check(micro[RES.Kind.STONE] > 0 and micro[RES.Kind.GOLD] > 0
			and micro[RES.Kind.IRON] == 0,
		"в микро-шахте есть камень и золото и нет железа",
		"камня %d, золота %d, железа %d" % [
			micro[RES.Kind.STONE], micro[RES.Kind.GOLD], micro[RES.Kind.IRON]])


## ХВАТАЕТ НА БАЗУ — то есть на путь к ПЕРВОМУ ОБОЗУ: склад, поле, конюшня, два
## батрака и лошадь. Без обоза нет ни железа, ни нового камня, и база, которая
## не доводит до обоза, — это тупик, а не база.
func _test_micro_mine_is_enough_for_basics(micro: PackedInt32Array) -> void:
	var need := RES.empty()
	for kind in [RES.Building.STORAGE, RES.Building.FARM, RES.Building.STABLE]:
		for i in RES.COUNT:
			need[i] += RES.at(RES.BUILDING_COST[kind], i)
	for i in 2:
		for r in RES.COUNT:
			need[r] += RES.at(RES.LABOURER_COST, r)
	for r in RES.COUNT:
		need[r] += RES.at(RES.HORSE_COST, r)
	# Дерево в счёт не идёт: его злодей рубит в роще у форта, и оно не кончается.
	var short := PackedStringArray()
	for kind in [RES.Kind.STONE, RES.Kind.GOLD, RES.Kind.IRON]:
		if micro[kind] < need[kind]:
			short.append("%s: есть %d, нужно %d" % [RES.NAMES[kind], micro[kind], need[kind]])
	check(short.is_empty(),
		"микро-шахты хватает до первого обоза: склад, поле, конюшня, два батрака, лошадь",
		", ".join(short))


## И НЕ ХВАТАЕТ НА РАЗВИТИЕ: ни на казарму (там железо), ни на дом дружины. Это и
## есть «без развития» из решения автора — за развитием идут к шахтам эльфов.
func _test_micro_mine_is_not_enough_for_growth(micro: PackedInt32Array) -> void:
	var spent := RES.empty()
	for kind in [RES.Building.STORAGE, RES.Building.FARM, RES.Building.STABLE]:
		for i in RES.COUNT:
			spent[i] += RES.at(RES.BUILDING_COST[kind], i)
	var affordable := PackedStringArray()
	for kind in [RES.Building.SWORD_BARRACKS, RES.Building.HOUSE]:
		var can: bool = true
		for i in RES.COUNT:
			if i == RES.Kind.WOOD:
				continue
			if micro[i] - spent[i] < RES.at(RES.BUILDING_COST[kind], i):
				can = false
		if can:
			affordable.append(RES.BUILDING_NAMES[kind])
	check(affordable.is_empty(),
		"после базы на развитие микро-шахты НЕ хватает — ни на казарму, ни на дом",
		"хватает ещё и на: %s" % ", ".join(affordable))


func _test_micro_mine_reachable() -> void:
	var from: Vector3 = FACTIONS.SPAWN[FACTIONS.Kind.VILLAIN]
	var to: Vector3 = WORLD_BUILDER.MICRO_MINE_POS
	var path: PackedVector3Array = _world.navigation.path_between(from, to)
	var gap := INF
	if not path.is_empty():
		var last: Vector3 = path[path.size() - 1]
		gap = Vector2(last.x, last.z).distance_to(Vector2(to.x, to.z))
	check(gap < MICRO_RADIUS, "до микро-шахты можно дойти от форта",
		"путь не дошёл %.1f м" % gap)


## Гряда у форта — не каменоломня. Иначе предел микро-шахты не ограничивал бы
## ничего: раньше там лежало больше тысячи камня.
func _test_ridge_is_not_a_quarry() -> void:
	var centre: Vector2 = WORLD_BUILDER.ZONE_CENTERS[WORLD_BUILDER.Zone.VILLAIN]
	var stray := 0
	for node in get_tree().get_nodes_in_group("harvestable"):
		var deposit := node as Node3D
		if deposit == null or int(deposit.get_meta("resource", -1)) != RES.Kind.STONE:
			continue
		var at := Vector2(deposit.global_position.x, deposit.global_position.z)
		if at.distance_to(centre) > VILLAIN_REACH:
			continue
		if at.distance_to(Vector2(WORLD_BUILDER.MICRO_MINE_POS.x,
				WORLD_BUILDER.MICRO_MINE_POS.z)) <= MICRO_RADIUS:
			continue
		stray += 1
	check(stray == 0, "у форта нет камня, кроме микро-шахты",
		"посторонних залежей камня: %d" % stray)
