extends "res://tools/test_base.gd"
##
## Автопроверка батраков (Этап 10). Работает headless.
##
## Запуск: godot --headless --path godot_project -- --host --faction=0 --labtest
##
## Проверяем не «батрак заспавнился», а всю петлю, ради которой он есть: он
## САМ находит работу, САМ до неё идёт, добывает, доносит груз до дома и
## пополняет казну СТОРОНЫ. И меняет занятие по приказу.
##
## Отдельно проверяем то, что легко сломать незаметно: роль «ополченец» должна
## возвращать батрака к обычному поведению бойца, а прочие роли — наоборот,
## удерживать его от драки. Батрак с лопатой, кидающийся на мечника, — это не
## храбрость, а потерянные руки.
##

const FACTIONS := preload("res://scripts/factions.gd")
const RES := preload("res://scripts/economy/resources.gd")
const LABOURER := preload("res://scripts/units/labourer.gd")
const MINE := preload("res://scripts/economy/mine.gd")

## В пределах какого расстояния от базы лес считается «своим».
const GROVE_RADIUS := 160.0

var _world: Node3D


func start(world: Node3D) -> void:
	tag = "батраки"
	expected_host = 18
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

	_test_start_with_two(me)
	await _test_hire(me)
	_test_mine_composition()
	await _test_gathers_and_delivers(me)
	await _test_roles(me)
	await _test_builders(me)
	finish()


func _crew(me: Node3D) -> Array:
	return _world.labourers_of(int(me.faction))


## Партия начинается с двух рук. Без них петля не запускается: батрак стоит
## золота, а золото добывают батраки.
func _test_start_with_two(me: Node3D) -> void:
	check(int(me.faction) == FACTIONS.Kind.VILLAIN, "проверяем за злодея",
		FACTIONS.name_of(int(me.faction)))
	check(_crew(me).size() == 2, "на старте два батрака", "%d" % _crew(me).size())


## Наём: за деньги, с потолком, и только той стороне, у которой они есть.
func _test_hire(me: Node3D) -> void:
	me.stock.grant([0, 0, 500, 0])
	var before: int = _crew(me).size()
	me.ask_hire_labourer()
	await get_tree().create_timer(0.4).timeout
	check(_crew(me).size() == before + 1, "батрак нанят за золото",
		"%d -> %d" % [before, _crew(me).size()])

	# Потолок. Добираем до него и убеждаемся, что дальше отказ.
	for i in RES.LABOURER_LIMIT + 2:
		me.ask_hire_labourer()
		await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout
	check(_crew(me).size() == RES.LABOURER_LIMIT, "больше потолка не нанять",
		"%d при потолке %d" % [_crew(me).size(), RES.LABOURER_LIMIT])


## Состав добычи шахты: камень основной, железа заметно больше золота.
func _test_mine_composition() -> void:
	var stone: float = MINE.RATE[RES.Kind.STONE]
	var iron: float = MINE.RATE[RES.Kind.IRON]
	var gold: float = MINE.RATE[RES.Kind.GOLD]
	var total := stone + iron + gold
	check(stone / total > 0.5, "камень — основная добыча шахты",
		"%.0f%% от всего" % (stone / total * 100.0))
	check(iron > gold * 2.0, "железа заметно больше золота",
		"%.1f против %.1f в секунду" % [iron, gold])


## Главное: батрак сам находит работу, добывает и доносит груз до дома.
func _test_gathers_and_delivers(me: Node3D) -> void:
	var crew := _crew(me)
	if crew.is_empty():
		fail("батраков нет")
		return

	# Рубят НАСТОЯЩУЮ рощу за воротами форта, а не подставленное для проверки
	# дерево. Раньше своего леса у злодея не было вовсе, и проверке приходилось
	# сажать источник самой — то есть проверять петлю в условиях, которых в игре
	# не существует. Роща посажена, и заодно проверяем, что она на месте: без неё
	# батраки снова уйдут за брёвнами через полкарты.
	var base: Vector3 = FACTIONS.SPAWN[int(me.faction)]
	var near_wood := 0
	var nearest := INF
	for node in get_tree().get_nodes_in_group("harvestable"):
		var source := node as Node3D
		if source == null or int(source.get_meta("resource", -1)) != RES.Kind.WOOD:
			continue
		var d: float = base.distance_to(source.global_position)
		nearest = minf(nearest, d)
		if d < GROVE_RADIUS:
			near_wood += 1
	check(near_wood >= 10, "у злодея своя роща под боком",
		"деревьев ближе %d м: %d, ближайшее в %.0f м" % [int(GROVE_RADIUS), near_wood, nearest])

	# Смотрим на казну СТОРОНЫ, а не на карман персонажа: батраки принадлежат
	# стороне и носят в общий склад.
	var wallet: Node = _world.treasury.of(int(me.faction))
	var before: int = wallet.get_amount(RES.Kind.WOOD)

	var working := 0
	for worker in crew:
		if int(worker.sync_role) == LABOURER.Role.LUMBERJACK:
			working += 1
	check(working > 0, "кто-то поставлен на лес", "%d лесорубов" % working)

	# Ждём полный круг: дойти, нарубить полные руки, донести, высыпать.
	var delivered := false
	var seen_load := false
	# Круг до рощи и обратно занимает под минуту: ждём с запасом.
	for i in 90:
		await get_tree().create_timer(1.0).timeout
		for worker in _crew(me):
			if int(worker.carrying()) > 0:
				seen_load = true
		if wallet.get_amount(RES.Kind.WOOD) > before:
			delivered = true
			break

	check(seen_load, "батрак набирает груз", "видели гружёного: %s" % seen_load)
	check(delivered, "груз донесён в казну стороны",
		"дерево %d -> %d" % [before, wallet.get_amount(RES.Kind.WOOD)])


## Смена занятия и то, что из неё следует.
func _test_roles(me: Node3D) -> void:
	var before := _count_by_role(me)
	me.ask_set_labourer_role(LABOURER.Role.MINER)
	await get_tree().create_timer(0.3).timeout
	var after := _count_by_role(me)
	check(after[LABOURER.Role.MINER] == before[LABOURER.Role.MINER] + 1,
		"батрак переведён в шахтёры",
		"%d -> %d" % [before[LABOURER.Role.MINER], after[LABOURER.Role.MINER]])

	me.ask_set_labourer_role(LABOURER.Role.BUILDER)
	await get_tree().create_timer(0.3).timeout
	check(_count_by_role(me)[LABOURER.Role.BUILDER] > 0, "и в строители",
		"%d строителей" % _count_by_role(me)[LABOURER.Role.BUILDER])

	# Роль решает, дерётся ли батрак. Это не мелочь: рабочие руки, бросающиеся
	# на мечника, — потерянные руки.
	var worker: Node3D = null
	for candidate in _crew(me):
		worker = candidate
		break
	if worker == null:
		fail("батраков нет")
		return
	worker.set_role(LABOURER.Role.MINER)
	check(not worker._wants_fight(), "шахтёр в драку не лезет",
		"хочет драться: %s" % worker._wants_fight())
	worker.set_role(LABOURER.Role.MILITIA)
	check(worker._wants_fight(), "ополченец дерётся",
		"хочет драться: %s" % worker._wants_fight())
	check(worker.role_name() == "ополченец", "роль подписана по-человечески",
		worker.role_name())


## Строители ускоряют стройку. Это и есть их смысл: «от количества строителей
## зависит скорость постройки».
##
## Проверяем не время до готовности, а множитель скорости: время зависит ещё и
## от того, успели ли строители дойти, и такая проверка мигала бы через раз.
func _test_builders(me: Node3D) -> void:
	var base: Vector3 = FACTIONS.SPAWN[int(me.faction)]
	var site: Node3D = _world.spawn_building(RES.Building.STORAGE,
		base + Vector3(0.0, 0.0, 16.0), int(me.peer_id), int(me.faction), false)
	await get_tree().physics_frame
	if site == null:
		fail("стройку поставить не удалось")
		return
	check(site.progress < 1.0, "стройка начата", "готовность %.0f%%" % (site.progress * 100.0))
	check(is_equal_approx(site._build_rate(), 1.0), "без строителей скорость обычная",
		"множитель %.1f" % site._build_rate())

	# Переводим всех в строители и ждём, пока подойдут.
	for worker in _crew(me):
		worker.set_role(LABOURER.Role.BUILDER)
	var rate := 1.0
	for i in 30:
		await get_tree().create_timer(1.0).timeout
		rate = site._build_rate()
		if rate > 1.0:
			break
	check(rate > 1.0, "строители у стройки ускоряют её",
		"множитель %.1f" % rate)


func _count_by_role(me: Node3D) -> PackedInt32Array:
	var counts := PackedInt32Array()
	counts.resize(LABOURER.ROLE_COUNT)
	for worker in _crew(me):
		counts[int(worker.sync_role)] += 1
	return counts
