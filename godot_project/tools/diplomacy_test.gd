extends "res://tools/test_base.gd"
##
## Автопроверка репутации и дипломатии (Этап 10, шаг 4, GDD раздел 9).
## Работает headless.
##
## Запуск:
##   godot --headless --path godot_project -- --host --faction=1 --diptest
##   godot --headless --path godot_project -- --join=127.0.0.1 --faction=2 --diptest
##
## Хост берёт эльфов (хозяев лавки), клиент — стражу: так проверяется и цена для
## своих, и цена для чужих, и жест перемирия между двумя живыми игроками.
##

const FACTIONS := preload("res://scripts/factions.gd")
const RES := preload("res://scripts/economy/resources.gd")
const DIPLOMACY := preload("res://scripts/diplomacy.gd")

var _world: Node3D


func start(world: Node3D) -> void:
	tag = "репутация"
	expected_host = 23
	expected_client = 4
	_world = world
	_run.call_deferred()


func _run() -> void:
	await get_tree().create_timer(3.0).timeout
	var me: Node3D = _world.local_player()
	if me == null:
		fail("персонаж не заспавнен")
		finish()
		return

	if not multiplayer.is_server():
		await _run_client(me)
		finish()
		return

	_test_model()
	_test_prices(me)
	await _test_events(me)
	await _test_drift()
	_test_truce()

	if not multiplayer.get_peers().is_empty():
		await get_tree().create_timer(8.0).timeout
	finish()


func _dip() -> Node:
	return _world.diplomacy


## 9.1: матрица попарная, симметричная, все пары стартуют враждебно, но не
## одинаково — со злодеем хуже, чем между эльфами и стражей.
func _test_model() -> void:
	var dip: Node = _dip()
	var ve: float = dip.value_of(FACTIONS.Kind.VILLAIN, FACTIONS.Kind.ELVES)
	var vg: float = dip.value_of(FACTIONS.Kind.VILLAIN, FACTIONS.Kind.GUARD)
	var eg: float = dip.value_of(FACTIONS.Kind.ELVES, FACTIONS.Kind.GUARD)

	check(ve < 0.0 and vg < 0.0 and eg < 0.0, "все пары стартуют враждебно",
		"злодей/эльфы %.0f, злодей/стража %.0f, эльфы/стража %.0f" % [ve, vg, eg])
	check(eg > ve and eg > vg, "эльфы и стража враждуют слабее, чем со злодеем",
		"%.0f против %.0f и %.0f" % [eg, ve, vg])
	check(is_equal_approx(ve, dip.value_of(FACTIONS.Kind.ELVES, FACTIONS.Kind.VILLAIN)),
		"отношение симметрично", "порядок сторон не важен")
	check(dip.value_of(FACTIONS.Kind.ELVES, FACTIONS.Kind.ELVES) > 0.0,
		"к себе сторона в союзе", "%.0f" % dip.value_of(FACTIONS.Kind.ELVES, FACTIONS.Kind.ELVES))


## 9.2: цена — функция отношения, ниже порога вражды лавка закрыта.
func _test_prices(me: Node3D) -> void:
	var dip: Node = _dip()
	var base: Array = RES.BANDAGE_COST

	# Эльф покупает у эльфов: своим скидка.
	check(int(me.faction) == FACTIONS.Kind.ELVES, "тест идёт за эльфов",
		FACTIONS.name_of(me.faction))
	var own: Array = dip.adjust_cost(base, FACTIONS.Kind.ELVES, FACTIONS.Kind.ELVES)
	check(int(own[RES.Kind.GOLD]) < int(base[RES.Kind.GOLD]), "своим лавка даёт скидку",
		"%d вместо %d" % [int(own[RES.Kind.GOLD]), int(base[RES.Kind.GOLD])])

	# Страже дороже, потому что отношение холодное.
	var guard_price: Array = dip.adjust_cost(base, FACTIONS.Kind.GUARD, FACTIONS.Kind.ELVES)
	check(int(guard_price[RES.Kind.GOLD]) > int(own[RES.Kind.GOLD]),
		"чужим дороже, чем своим",
		"страже %d, эльфам %d" % [int(guard_price[RES.Kind.GOLD]), int(own[RES.Kind.GOLD])])

	# Злодею лавка эльфов не откроется вовсе: они в открытой войне.
	check(not dip.trade_allowed(FACTIONS.Kind.VILLAIN, FACTIONS.Kind.ELVES),
		"при войне лавка не обслуживает",
		"отношение %.0f" % dip.value_of(FACTIONS.Kind.VILLAIN, FACTIONS.Kind.ELVES))
	check(dip.trade_allowed(FACTIONS.Kind.GUARD, FACTIONS.Kind.ELVES),
		"при холоде лавка обслуживает",
		"отношение %.0f" % dip.value_of(FACTIONS.Kind.GUARD, FACTIONS.Kind.ELVES))
	check(me.trade_allowed(), "хозяин лавки обслуживается всегда", "да")


## 9.3: события портят отношения, и убийство — сильнее прочего.
func _test_events(me: Node3D) -> void:
	var dip: Node = _dip()

	# Ставим тёплое отношение, чтобы было куда падать и не упереться в предел.
	dip.values = PackedFloat32Array([0.0, 0.0, 0.0])
	await get_tree().physics_frame

	var before: float = dip.value_of(FACTIONS.Kind.VILLAIN, FACTIONS.Kind.ELVES)
	dip.on_caravan_destroyed(FACTIONS.Kind.VILLAIN, FACTIONS.Kind.ELVES)
	var after_caravan: float = dip.value_of(FACTIONS.Kind.VILLAIN, FACTIONS.Kind.ELVES)
	check(after_caravan < before, "грабёж каравана портит отношения",
		"%.0f -> %.0f" % [before, after_caravan])

	dip.values = PackedFloat32Array([0.0, 0.0, 0.0])
	dip.on_kill(FACTIONS.Kind.VILLAIN, FACTIONS.Kind.ELVES, false)
	var after_kill: float = dip.value_of(FACTIONS.Kind.VILLAIN, FACTIONS.Kind.ELVES)
	check(after_kill < after_caravan, "убийство бьёт сильнее грабежа",
		"убийство %.0f, караван %.0f" % [after_kill, after_caravan])

	dip.values = PackedFloat32Array([0.0, 0.0, 0.0])
	dip.on_kill(FACTIONS.Kind.VILLAIN, FACTIONS.Kind.ELVES, true)
	var after_leader: float = dip.value_of(FACTIONS.Kind.VILLAIN, FACTIONS.Kind.ELVES)
	check(after_leader < after_kill, "убийство вожака бьёт сильнее всего",
		"вожак %.0f, рядовой %.0f" % [after_leader, after_kill])

	# Свои своих не портят.
	dip.values = PackedFloat32Array([0.0, 0.0, 0.0])
	dip.on_kill(FACTIONS.Kind.ELVES, FACTIONS.Kind.ELVES, false)
	check(is_equal_approx(dip.value_of(FACTIONS.Kind.VILLAIN, FACTIONS.Kind.ELVES), 0.0),
		"убийство своего чужих отношений не трогает", "не изменилось")

	# Реальное убийство через мир должно давать тот же эффект.
	dip.values = PackedFloat32Array([0.0, 0.0, 0.0])
	var villain := _player_of(FACTIONS.Kind.VILLAIN)
	if villain == null:
		note("злодея в сессии нет — проверка убийства через мир пропущена")
	else:
		villain.take_damage(999.0, int(me.peer_id), "torso", villain.global_position, Vector3.FORWARD)
		await get_tree().create_timer(1.0).timeout
		check(dip.value_of(FACTIONS.Kind.VILLAIN, FACTIONS.Kind.ELVES) < 0.0,
			"убийство в бою доходит до репутации",
			"%.0f" % dip.value_of(FACTIONS.Kind.VILLAIN, FACTIONS.Kind.ELVES))


## 9.3: дрейф тянет обратно к вражде, а не к миру.
func _test_drift() -> void:
	var dip: Node = _dip()
	dip.values = PackedFloat32Array([50.0, 50.0, 50.0])
	var before: float = dip.value_of(FACTIONS.Kind.VILLAIN, FACTIONS.Kind.ELVES)
	await get_tree().create_timer(2.0).timeout
	var after: float = dip.value_of(FACTIONS.Kind.VILLAIN, FACTIONS.Kind.ELVES)
	check(after < before, "без событий отношения сползают к вражде",
		"%.1f -> %.1f" % [before, after])
	check(after > DIPLOMACY.START[0], "дрейф медленный, а не мгновенный",
		"за 2 с прошло %.1f единиц" % (before - after))


func _player_of(faction: int) -> Node3D:
	for child in _world.get_node("Players").get_children():
		if "faction" in child and int(child.faction) == faction:
			return child
	return null


## 9.4: жест перемирия. Клиент предлагает первым, хост отвечает встречным —
## встречное предложение и есть согласие.
func _run_client(me: Node3D) -> void:
	var dip: Node = _world.diplomacy
	check(int(me.faction) == FACTIONS.Kind.GUARD, "клиент играет за стражу",
		FACTIONS.name_of(me.faction))
	check(dip.values.size() == DIPLOMACY.PAIRS, "матрица доехала до клиента",
		"%d пар" % dip.values.size())

	# Издалека предлагать некому.
	me.teleport.rpc(Vector3(400.0, 8.0, 400.0))
	await get_tree().create_timer(0.5).timeout
	check(me.truce_target() == null, "издалека перемирие предложить некому", "цели нет")

	await get_tree().create_timer(6.0).timeout
	check(dip.value_of(FACTIONS.Kind.VILLAIN, FACTIONS.Kind.ELVES)
			!= DIPLOMACY.START[0],
		"изменения репутации доехали до клиента",
		"%.1f" % dip.value_of(FACTIONS.Kind.VILLAIN, FACTIONS.Kind.ELVES))


## 9.4: перемирие — это ЖЕСТ, а не переговоры. Отдельного «принять» нет:
## встречное предложение той же пары и есть согласие.
##
## Механику проверяем напрямую на хосте: свести двух живых игроков вплотную и
## заставить обоих нажать клавишу автотест не может, это дело playtest.
func _test_truce() -> void:
	var dip: Node = _dip()
	dip.values = PackedFloat32Array([0.0, 0.0, 0.0])

	# Одностороннее предложение отношений ещё не меняет.
	var before: float = dip.value_of(FACTIONS.Kind.ELVES, FACTIONS.Kind.GUARD)
	var text: String = dip.offer_truce(FACTIONS.Kind.ELVES, FACTIONS.Kind.GUARD)
	check(not text.is_empty(), "предложение принято к рассмотрению", text)
	check(is_equal_approx(dip.value_of(FACTIONS.Kind.ELVES, FACTIONS.Kind.GUARD), before),
		"одностороннее предложение ничего не меняет",
		"%.0f" % dip.value_of(FACTIONS.Kind.ELVES, FACTIONS.Kind.GUARD))
	check(dip.pending_offer_to(FACTIONS.Kind.ELVES) == FACTIONS.Kind.GUARD,
		"предложение висит и ждёт ответа", "ждём стражу")

	# Встречное предложение = согласие.
	var accepted: String = dip.offer_truce(FACTIONS.Kind.GUARD, FACTIONS.Kind.ELVES)
	check(accepted.contains("заключено"), "встречное предложение заключает перемирие", accepted)
	check(dip.value_of(FACTIONS.Kind.ELVES, FACTIONS.Kind.GUARD) > before,
		"перемирие поднимает отношение",
		"%.0f -> %.0f" % [before, dip.value_of(FACTIONS.Kind.ELVES, FACTIONS.Kind.GUARD)])
	check(dip.pending_offer_to(FACTIONS.Kind.ELVES) < 0, "предложение снято после согласия",
		"висящих нет")

	# Сама с собой сторона не мирится.
	var self_text: String = dip.offer_truce(FACTIONS.Kind.ELVES, FACTIONS.Kind.ELVES)
	check(self_text.is_empty(), "предложить перемирие себе нельзя", "отказ")
