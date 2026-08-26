extends "res://tools/test_base.gd"
##
## Автопроверка смерти, респавна и мародёрства (Этап 10, шаг 1, GDD раздел 4.1).
## Работает headless.
##
## Запуск:
##   godot --headless --path godot_project -- --host --faction=0 --deathtest
##   godot --headless --path godot_project -- --join=127.0.0.1 --faction=1 --deathtest
##

const RES := preload("res://scripts/economy/resources.gd")
const FACTIONS := preload("res://scripts/factions.gd")

var _world: Node3D


func start(world: Node3D) -> void:
	tag = "смерть"
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

	if not multiplayer.is_server():
		await _run_client()
		finish()
		return

	await _test_wallet_split(me)
	await _test_death_drops(me)
	await _test_wounds_survive_respawn(me)
	await _test_storage_is_insurance(me)

	if not multiplayer.get_peers().is_empty():
		await get_tree().create_timer(8.0).timeout
	finish()


## Кошелёк разделён на «при себе» и «в складе», и по умолчанию всё при себе.
func _test_wallet_split(me: Node3D) -> void:
	var wallet: Node = me.stock
	check(wallet.carried != null and wallet.stored != null, "кошелёк разделён на два запаса",
		"при себе и в складе")
	check(wallet.stored.capacity == 0, "без склада безопасного запаса нет",
		"потолок склада %d" % wallet.stored.capacity)

	wallet.carried.amounts = PackedInt32Array([10, 0, 50, 0])
	wallet.stored.amounts = PackedInt32Array([0, 0, 0, 0])
	await get_tree().physics_frame
	check(wallet.get_amount(RES.Kind.GOLD) == 50, "видно суммарно", "золота 50")
	check(wallet.carried_total() == 60, "при себе учитывается отдельно",
		"при себе %d" % wallet.carried_total())


## Смерть роняет всё при себе и купленное снаряжение; поднять может любой.
func _test_death_drops(me: Node3D) -> void:
	me.gear_tier = 2
	me.stock.carried.amounts = PackedInt32Array([0, 0, 90, 20])
	me.teleport.rpc(Vector3(20.0, 2.0, 20.0))
	await get_tree().physics_frame
	var where: Vector3 = me.global_position

	me.take_damage(999.0, 1, "torso", where, Vector3.FORWARD)
	await get_tree().create_timer(1.0).timeout

	check(me.stock.carried_total() == 0, "смерть обнулила то, что при себе",
		"при себе %d" % me.stock.carried_total())
	check(int(me.gear_tier) == 0, "купленное снаряжение потеряно",
		"уровень %d" % int(me.gear_tier))

	var pile := _nearest_loot(where)
	check(pile != null, "на месте смерти лежит куча", "найдена" if pile != null else "нет")
	if pile == null:
		return
	check(int(pile.gear) == 2, "снаряжение выпало в кучу", "уровень %d" % int(pile.gear))

	# Ждём респавна и идём подбирать своё же добро.
	await get_tree().create_timer(6.0).timeout
	check(me.health.alive, "персонаж вернулся в мир", "жив")
	var base: Vector3 = FACTIONS.SPAWN[int(me.faction)]
	check(me.global_position.distance_to(base) < 12.0, "респавн на базе своей стороны",
		"в %.0f м от точки базы" % me.global_position.distance_to(base))

	me.teleport.rpc(pile.global_position + Vector3.UP)
	await get_tree().physics_frame
	pile.collect(me)
	await get_tree().physics_frame
	check(me.stock.get_amount(RES.Kind.GOLD) >= 90, "выпавшее можно подобрать",
		"золота %d" % me.stock.get_amount(RES.Kind.GOLD))
	check(int(me.gear_tier) == 2, "снаряжение возвращается с кучей",
		"уровень %d" % int(me.gear_tier))


## Ранения переживают смерть. Это главное в шаге: раньше здесь стоял body.reset(),
## и умереть было дешевле, чем идти за протезом.
func _test_wounds_survive_respawn(me: Node3D) -> void:
	me.body.severed_mask = 0
	me.body.register_hit("leg_l", 999.0)
	await get_tree().physics_frame
	var lost_before: int = me.body.severed_mask
	check(lost_before != 0, "конечность оторвана до смерти", "маска %d" % lost_before)

	me.take_damage(999.0, 1, "torso", me.global_position, Vector3.FORWARD)
	await get_tree().create_timer(6.5).timeout

	check(me.health.alive, "после ранения персонаж всё равно вернулся", "жив")
	check(me.body.severed_mask == lost_before, "ранения пережили респавн",
		"маска %d" % me.body.severed_mask)


## Склад — страховка: то, что сложено в постройку, смертью не теряется.
## У эльфов и стражи склада нет, поэтому у них страховки нет вовсе.
func _test_storage_is_insurance(me: Node3D) -> void:
	me.stock.stored.capacity = 500
	me.stock.stored.amounts = PackedInt32Array([0, 0, 200, 0])
	me.stock.carried.amounts = PackedInt32Array([0, 0, 40, 0])
	await get_tree().physics_frame

	me.take_damage(999.0, 1, "torso", me.global_position, Vector3.FORWARD)
	await get_tree().create_timer(1.0).timeout

	check(me.stock.stored.get_amount(RES.Kind.GOLD) == 200, "склад смертью не тронут",
		"в складе %d" % me.stock.stored.get_amount(RES.Kind.GOLD))
	check(me.stock.carried.get_amount(RES.Kind.GOLD) == 0, "при себе всё равно потеряно",
		"при себе %d" % me.stock.carried.get_amount(RES.Kind.GOLD))
	await get_tree().create_timer(6.0).timeout


func _nearest_loot(point: Vector3) -> Node3D:
	var best: Node3D = null
	var best_d := 12.0
	for node in get_tree().get_nodes_in_group("loot"):
		var pile := node as Node3D
		if pile == null:
			continue
		var d: float = pile.global_position.distance_to(point)
		if d < best_d:
			best_d = d
			best = pile
	return best


## Клиент: у каждой стороны свой кошелёк, и чужой склад ему не принадлежит.
func _run_client() -> void:
	var me: Node3D = _world.local_player()
	if me == null:
		fail("персонаж клиента не заспавнен")
		return
	var mine: Node = me.stock
	var host_wallet: Node = _world.treasury.of(FACTIONS.Kind.VILLAIN)
	check(mine != null and mine != host_wallet, "у клиента свой кошелёк стороны",
		FACTIONS.name_of(me.faction))

	# У эльфов и стражи склада нет и не появится: строить умеет только злодей.
	await get_tree().create_timer(6.0).timeout
	check(mine.stored.capacity == 0, "у стороны без стройки склада нет",
		"потолок склада %d" % mine.stored.capacity)
