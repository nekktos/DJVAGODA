extends "res://tools/test_base.gd"
##
## Автопроверка хозяйства ИИ (Этап 10, шаг 8, ступень «в»). Работает headless.
##
## Запуск: godot --headless --path godot_project -- --host --faction=1 --stewardtest
##
## Хост берёт эльфов, поэтому злодей остаётся свободным — а хозяйство по GDD
## умеет вести только он.
##
## Проверяем РЕШЕНИЯ, а не добычу: что сторона нанимает руки, ставит их по
## нуждам, строит по порядку и набирает войско. Сама добыча — общий код с
## игроком, и она проверяется набором батраков; дублировать её здесь значило бы
## ждать, пока шахтёр сходит за железом на другой конец зоны.
##
## Отдельно проверяем границу: за занятую сторону ИИ хозяйство не ведёт. Сел
## живой игрок — его батраки не должны получать приказы от кого-то ещё.
##

const FACTIONS := preload("res://scripts/factions.gd")
const RES := preload("res://scripts/economy/resources.gd")
const LABOURER := preload("res://scripts/units/labourer.gd")
const STEWARD := preload("res://scripts/ai/steward.gd")

var _world: Node3D


func start(world: Node3D) -> void:
	tag = "хозяйство"
	expected_host = 18
	expected_client = 1
	_world = world
	_run.call_deferred()


func _run() -> void:
	if not session_ready():
		finish()
		return
	await get_tree().create_timer(2.0).timeout

	_test_only_villain()
	await _test_hires_and_builds()
	await _test_roles_follow_need()
	await _test_sends_caravan()
	await _test_trains_and_joins_warband()
	finish()


func _steward() -> Node:
	return _world.steward


func _villain_wallet() -> Node:
	return _world.treasury.of(FACTIONS.Kind.VILLAIN)


## Хозяйство ведёт только злодей и только пока за него никто не сел.
func _test_only_villain() -> void:
	check(_steward()._runs_for(FACTIONS.Kind.VILLAIN), "за свободного злодея хозяйство ведётся",
		"да")
	check(not _steward()._runs_for(FACTIONS.Kind.ELVES), "за занятую сторону — нет",
		"эльфы заняты хостом")
	check(not _steward()._runs_for(FACTIONS.Kind.GUARD),
		"и за ту, что строить не умеет, тоже нет", "стража свободна, но не строит")


## Нанимает руки и ставит склад первым: без склада у стороны нет безопасного
## запаса вовсе.
func _test_hires_and_builds() -> void:
	var crew_before: int = _world.labourers_of(FACTIONS.Kind.VILLAIN).size()
	# С НУЛЯ: батраков на старте нет (GDD 9a), и ИИ их нанимает сам.
	check(crew_before == 0, "партия началась без батраков", "%d" % crew_before)

	# Даём стороне запас: проверяем решения, а не скорость лесоруба.
	_villain_wallet().grant([600, 600, 600, 600])

	var hired := false
	var storage: Node3D = null
	for i in 40:
		await get_tree().create_timer(1.0).timeout
		if _world.labourers_of(FACTIONS.Kind.VILLAIN).size() > crew_before:
			hired = true
		storage = _steward()._ready_building(FACTIONS.Kind.VILLAIN, RES.Building.STORAGE)
		if hired and storage != null:
			break

	check(hired, "ИИ нанял ещё батраков",
		"%d -> %d" % [crew_before, _world.labourers_of(FACTIONS.Kind.VILLAIN).size()])
	check(storage != null, "и построил склад первым", "склад готов")
	check(_villain_wallet().stored.capacity > 0,
		"склад поднял потолок СТОРОНЫ, а не игрока",
		"вместимость %d" % _villain_wallet().stored.capacity)


## Роли следуют за нуждой: пока идёт стройка, часть рук уходит на неё.
func _test_roles_follow_need() -> void:
	var seen_builder := false
	var seen_gatherer := false
	for i in 30:
		await get_tree().create_timer(1.0).timeout
		for worker in _world.labourers_of(FACTIONS.Kind.VILLAIN):
			if int(worker.sync_role) == LABOURER.Role.BUILDER:
				seen_builder = true
			if int(worker.sync_role) == LABOURER.Role.LUMBERJACK \
					or int(worker.sync_role) == LABOURER.Role.MINER:
				seen_gatherer = true
		if seen_builder and seen_gatherer:
			break
	check(seen_builder, "во время стройки часть рук — на стройке", "видели строителя")
	check(seen_gatherer, "но добыча не оголяется полностью", "видели добытчика")


## Возит караваном. Это была последняя незакрытая часть стратегического слоя.
##
## Проверяем не только «караван выехал», но и что он ДОВЁЗ: у каравана ИИ нет
## владельца-персонажа, и разгрузка, искавшая владельца среди игроков, привозила
## груз в никуда — молча, ровно как когда-то склад ИИ и первые батраки.
func _test_sends_caravan() -> void:
	var sent: Node3D = null
	for i in 45:
		await get_tree().create_timer(1.0).timeout
		# Обоз ЗЛОДЕЯ, а не первый попавшийся: с 28.09 (GDD 9a) обозы водит и
		# стража, и первым ИИ-обозом в мире оказывался её.
		for cart in _world.caravans_of(0):
			if int(cart.faction) == FACTIONS.Kind.VILLAIN:
				sent = cart
		if sent != null:
			break
	check(sent != null, "ИИ отправил караван", "караванов %d" % _world.caravans_of(0).size())
	if sent == null:
		return
	check(int(sent.faction) == FACTIONS.Kind.VILLAIN, "караван принадлежит СТОРОНЕ",
		FACTIONS.name_of(int(sent.faction)))
	# И ДОЕДЕТ ДО ШАХТЫ: конец пути у входа, а не где-то по дороге. Обоз
	# грузится только у шахты, и маршрут, оборвавшийся раньше, — это пустая
	# телега. Так и было: склад ИИ стоял на крыше глыбы во дворе форта, путь
	# от него обрывался через три точки, и обозы злодея ездили пустыми.
	var end: Vector3 = sent.route[sent.route.size() - 1]
	var mine: Node3D = _world.mine_near(end)
	var gap: float = Vector2(end.x, end.z).distance_to(
		Vector2(mine.global_position.x, mine.global_position.z))
	check(gap <= sent.LOAD_REACH, "маршрут обоза ИИ кончается у шахты",
		"конец в %.0f м от ближайшей шахты (%s), точек %d" % [gap, mine.title(), sent.route.size()])

	# Разгрузку проверяем НАПРЯМУЮ, а не ждём круга: дорога до шахты и обратно
	# занимает больше минуты, и набор упирался бы в предел по времени. Сломан был
	# именно этот код — разгрузка искала владельца среди игроков и у каравана без
	# владельца привозила груз в никуда.
	var wallet: Node = _villain_wallet()
	var before: int = wallet.get_amount(RES.Kind.IRON)
	sent.cargo = RES.fit([0, 0, 0, 40])
	sent._unload_at_home()
	check(wallet.get_amount(RES.Kind.IRON) > before, "и разгружается в казну СТОРОНЫ",
		"железо %d -> %d" % [before, wallet.get_amount(RES.Kind.IRON)])

	# ПОЛНЫЙ СКЛАД (ответ автора от 29.09): обоз ИИ ждёт у склада — ИИ ставит
	# ещё склад.
	var storages_before := _count_storages()
	wallet.grant(RES.fit([400, 400, 0, 0]))
	sent.waiting = true
	var extra := false
	for i in 12:
		await get_tree().create_timer(1.0).timeout
		if _count_storages() > storages_before:
			extra = true
			break
	sent.waiting = false
	check(extra, "обоз ИИ ждёт у полного склада — ИИ ставит ещё склад",
		"складов %d -> %d" % [storages_before, _count_storages()])


## Набирает войско, и оно попадает в общий отряд ИИ — а батраки в него не
## попадают. Это не мелочь: у батраков тоже нет владельца, и без проверки отряд
## уводил бы в набег лесорубов.
func _test_trains_and_joins_warband() -> void:
	_villain_wallet().grant([600, 600, 600, 600])
	var band_before: int = _world.warband._band(FACTIONS.Kind.VILLAIN).size()

	var trained := false
	for i in 60:
		await get_tree().create_timer(1.0).timeout
		if _steward()._ready_building(FACTIONS.Kind.VILLAIN, RES.Building.SWORD_BARRACKS) == null:
			continue
		if _world.warband._band(FACTIONS.Kind.VILLAIN).size() > band_before:
			trained = true
			break

	check(_steward()._ready_building(FACTIONS.Kind.VILLAIN, RES.Building.SWORD_BARRACKS) != null,
		"после склада ИИ строит казарму", "казарма мечников готова")
	check(trained, "и набирает в неё войско",
		"отряд %d -> %d" % [band_before, _world.warband._band(FACTIONS.Kind.VILLAIN).size()])

	var band: Array = _world.warband._band(FACTIONS.Kind.VILLAIN)
	var labourers_in_band := 0
	for unit in band:
		if "sync_role" in unit and int(unit.sync_role) != LABOURER.Role.MILITIA:
			labourers_in_band += 1
	check(labourers_in_band == 0, "работающих батраков в набег не гонят",
		"батраков в отряде: %d" % labourers_in_band)

	check(_world.warband._band(FACTIONS.Kind.VILLAIN).size() <= STEWARD.SQUAD_WANTED,
		"войско ИИ не растёт бесконечно",
		"%d при потолке %d" % [band.size(), STEWARD.SQUAD_WANTED])


func _count_storages() -> int:
	var count := 0
	for node in get_tree().get_nodes_in_group("building"):
		if int(node.faction) == FACTIONS.Kind.VILLAIN and int(node.kind) == RES.Building.STORAGE:
			count += 1
	return count
