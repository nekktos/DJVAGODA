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
	expected_host = 16
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
	check(crew_before >= 2, "партия началась с двух рук", "%d" % crew_before)

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
		var mine_caravans: Array = _world.caravans_of(0)
		if not mine_caravans.is_empty():
			sent = mine_caravans[0]
			break
	check(sent != null, "ИИ отправил караван", "караванов %d" % _world.caravans_of(0).size())
	if sent == null:
		return
	check(int(sent.faction) == FACTIONS.Kind.VILLAIN, "караван принадлежит СТОРОНЕ",
		FACTIONS.name_of(int(sent.faction)))

	# Разгрузку проверяем НАПРЯМУЮ, а не ждём круга: дорога до шахты и обратно
	# занимает больше минуты, и набор упирался бы в предел по времени. Сломан был
	# именно этот код — разгрузка искала владельца среди игроков и у каравана без
	# владельца привозила груз в никуда.
	var wallet: Node = _villain_wallet()
	var before: int = wallet.get_amount(RES.Kind.IRON)
	sent.cargo = PackedInt32Array([0, 0, 0, 40])
	sent._unload_at_home()
	check(wallet.get_amount(RES.Kind.IRON) > before, "и разгружается в казну СТОРОНЫ",
		"железо %d -> %d" % [before, wallet.get_amount(RES.Kind.IRON)])


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
