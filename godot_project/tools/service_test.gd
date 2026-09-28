extends "res://tools/test_base.gd"
##
## Служба стражи: новые приказы и повышение по цепочке (GDD 9a, доработка
## концепции от 28.09.2026).
##
## Запуск: godot --headless --path godot_project -- --host --faction=2 --servicetest
##
## Решение автора: «страже, чтоб стать руководителем стражи и открыть
## стратегический режим, надо пройти цепочку квестов» и «задачи для стражи:
## сопровождение и защита каравана, защита дворца от нападения, выследить и
## убить тех, кто разграбил караван».
##
## ПРИКАЗЫ ЗАСЧИТЫВАЮТСЯ ДЕЛОМ, а не выставлением счётчика: страж идёт рядом с
## обозом, пока тот не доедет; стоит у шахты; убивает того, кто грабил.
##

const RES := preload("res://scripts/economy/resources.gd")
const FACTIONS := preload("res://scripts/factions.gd")
const ORDERS := preload("res://scripts/orders.gd")

var _world: Node3D
var _commander: Node3D


func start(world: Node3D) -> void:
	tag = "служба"
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
	if me == null or int(me.faction) != FACTIONS.Kind.GUARD:
		fail("набор должен идти за стражу")
		finish()
		return
	_commander = _world.commander

	await _test_promotion_needs_service(me)
	await _test_rotation_skips_impossible(me)
	await _test_defend(me)
	await _test_hunt(me)
	await _test_mine(me)
	await _test_field(me)
	await _test_escort(me)
	finish()


func _give(me: Node3D, kind: int) -> void:
	me.order_kind = kind
	me.order_progress = 0
	me.set_meta("hold_seconds", 0.0)
	me.set_meta("mine_seconds", 0.0)


## Командование — только после службы. Раньше его давали по простому согласию,
## и обучение, обещавшее «пять выполненных — повышение», говорило неправду.
func _test_promotion_needs_service(me: Node3D) -> void:
	me.teleport.rpc(_commander.POSITION + Vector3(0.0, 2.0, 2.0))
	await get_tree().create_timer(0.5).timeout
	me.orders_done = ORDERS.ORDERS_FOR_PROMOTION - 1
	var early: bool = _commander.can_promote(me)
	me.request_promotion()
	await get_tree().physics_frame
	var leader_early: bool = me.is_leader
	me.orders_done = ORDERS.ORDERS_FOR_PROMOTION
	var ready: bool = _commander.can_promote(me)
	check(not early and not leader_early and ready,
		"командование принимают только после %d приказов" % ORDERS.ORDERS_FOR_PROMOTION,
		"за %d — можно %s, стал командиром %s; за %d — можно %s" % [
			ORDERS.ORDERS_FOR_PROMOTION - 1, early, leader_early, ORDERS.ORDERS_FOR_PROMOTION, ready])
	me.orders_done = 0


## Невыполнимое не выдают: без грабителей нет погони, без поля злодея — набега.
func _test_rotation_skips_impossible(me: Node3D) -> void:
	var hunt_at: int = ORDERS.ROTATION.find(ORDERS.Kind.HUNT)
	me.orders_done = hunt_at
	me.final_threshold = 999
	_give(me, -1)
	_commander._issue_next(me)
	var skipped: bool = me.order_kind != ORDERS.Kind.HUNT
	check(skipped and me.order_kind == ORDERS.ROTATION[hunt_at + 1],
		"погоню без грабителей не выдают — следующий приказ круга",
		"выдан «%s»" % ORDERS.name_of(me.order_kind))
	me.orders_done = 0


## Оборона: засчитывается убитый ЧУЖОЙ у дворца, а не где попало.
func _test_defend(me: Node3D) -> void:
	_give(me, ORDERS.Kind.DEFEND)
	var palace: Vector3 = _world.objective.PALACE
	var near := _unit(FACTIONS.Kind.ELVES, palace + Vector3(20.0, 0.0, 0.0))
	var far := _unit(FACTIONS.Kind.ELVES, palace + Vector3(300.0, 0.0, 300.0))
	await get_tree().physics_frame
	_commander.report_victim(int(me.peer_id), far)
	var after_far: int = me.order_progress
	_commander.report_victim(int(me.peer_id), near)
	check(after_far == 0 and me.order_progress == 1,
		"оборона засчитывает убитого у дворца и не засчитывает далёкого",
		"после далёкого %d, после ближнего %d" % [after_far, me.order_progress])
	for node in [near, far]:
		if is_instance_valid(node):
			node.queue_free()


## Погоня: грабителями записываются те, кто был у обоза стражи, и засчитывается
## только их смерть.
func _test_hunt(me: Node3D) -> void:
	var spot: Vector3 = me.global_position + Vector3(200.0, 0.0, 0.0)
	var robber := _unit(FACTIONS.Kind.VILLAIN, spot + Vector3(5.0, 0.0, 0.0))
	var stranger := _unit(FACTIONS.Kind.VILLAIN, spot + Vector3(150.0, 0.0, 0.0))
	await get_tree().physics_frame
	_commander.report_caravan_lost(spot, FACTIONS.Kind.GUARD)
	var possible: bool = _commander._order_possible(ORDERS.Kind.HUNT)
	_give(me, ORDERS.Kind.HUNT)
	_commander.report_victim(int(me.peer_id), stranger)
	var after_stranger: int = me.order_progress
	_commander.report_victim(int(me.peer_id), robber)
	check(possible and after_stranger == 0 and me.order_progress == 1,
		"после грабежа обоза стражи появляется погоня, и засчитывается только грабитель",
		"погоня доступна %s, за постороннего %d, за грабителя %d" % [
			possible, after_stranger, me.order_progress])
	for node in [robber, stranger]:
		if is_instance_valid(node):
			node.queue_free()


## Шахта: секунды идут, пока страж стоит у входа и чужих рядом нет.
func _test_mine(me: Node3D) -> void:
	_give(me, ORDERS.Kind.MINE)
	var mine: Node3D = _world.mine_of(RES.Kind.COAL)
	var dock: Vector3 = _world.mine_dock(mine)
	# Чистим поляну от случайно забредших: проверяем правило, а не удачу.
	for body in _commander._living_hostiles():
		if Vector2(body.global_position.x, body.global_position.z).distance_to(
				Vector2(mine.global_position.x, mine.global_position.z)) < ORDERS.MINE_RADIUS + 20.0:
			if body.is_in_group("unit"):
				body.queue_free()
	me.teleport.rpc(dock + Vector3(0.0, 2.0, 0.0))
	await get_tree().create_timer(3.5).timeout
	var alone: int = me.order_progress
	var intruder := _unit(FACTIONS.Kind.ELVES, dock + Vector3(4.0, 0.0, 0.0))
	await get_tree().create_timer(2.0).timeout
	var with_intruder: int = me.order_progress
	check(alone >= 2 and with_intruder == alone,
		"у шахты время идёт, пока рядом нет чужих, и встаёт, когда пришли",
		"один %d с, с чужим %d с" % [alone, with_intruder])
	if is_instance_valid(intruder):
		intruder.queue_free()


## Набег на поле: снесённое стражем поле злодея засчитано; без полей приказ не
## выдаётся.
func _test_field(me: Node3D) -> void:
	var without: bool = _commander._order_possible(ORDERS.Kind.FIELD)
	var farm: Node3D = _world.spawn_building(RES.Building.FARM,
		me.global_position + Vector3(40.0, 0.0, 40.0), 0, FACTIONS.Kind.VILLAIN, true)
	await get_tree().physics_frame
	var with_farm: bool = _commander._order_possible(ORDERS.Kind.FIELD)
	_give(me, ORDERS.Kind.FIELD)
	farm.take_damage(99999.0, int(me.peer_id), "", farm.global_position, Vector3.FORWARD)
	await get_tree().create_timer(0.3).timeout
	check(not without and with_farm and me.order_progress == ORDERS.target_of(ORDERS.Kind.FIELD),
		"набег на поле: без поля не выдаётся, снесённое стражем — засчитано",
		"без поля %s, с полем %s, прогресс %d" % [without, with_farm, me.order_progress])


## Сопровождение: страж идёт рядом с обозом стражи, пока тот не доедет.
## Встретить обоз у склада в последний миг — не сопровождение.
func _test_escort(me: Node3D) -> void:
	var storage: Node3D = _world.storage_of(FACTIONS.Kind.GUARD)
	if storage == null:
		fail("у стражи нет склада")
		return
	var home: Vector3 = storage.global_position
	var start: Vector3 = home + Vector3(-250.0, 0.0, 0.0)
	var wallet: Node = _world.treasury.of(FACTIONS.Kind.GUARD)
	wallet.horses += 2
	wallet.horses_out += 2

	# Сперва БЕЗ сопровождения: обоз доезжает, приказ не засчитан.
	_give(me, ORDERS.Kind.ESCORT)
	var alone: Node3D = _cart_home(home, start)
	me.teleport.rpc(home + Vector3(60.0, 2.0, 60.0))
	await _wait_home(alone)
	var unescorted: int = me.order_progress

	# Теперь рядом всю дорогу.
	wallet.horses += 2
	wallet.horses_out += 2
	var cart: Node3D = _cart_home(home, start)
	var arrived := false
	for i in 200:
		if not is_instance_valid(cart) or int(cart.state) != int(cart.State.TO_HOME):
			arrived = true
			break
		me.teleport.rpc(cart.global_position + Vector3(8.0, 2.0, 0.0))
		await get_tree().create_timer(0.2).timeout
	await get_tree().create_timer(4.0).timeout
	check(unescorted == 0 and arrived and me.order_progress == ORDERS.target_of(ORDERS.Kind.ESCORT),
		"сопровождение засчитано, когда шёл рядом, и не засчитано без этого",
		"без стража %d, со стражем %d (доехал %s)" % [unescorted, me.order_progress, arrived])


## Обоз стражи, едущий домой издалека: маршрут склад -> точка, едет задом.
func _cart_home(home: Vector3, start: Vector3) -> Node3D:
	var cart: Node3D = _world.spawn_caravan(PackedVector3Array([home, start]), 0,
		FACTIONS.Kind.GUARD, 2)
	cart.position = start
	cart.sync_position = start
	cart.state = cart.State.TO_HOME
	cart._leg = 0
	cart.route = _world._walkable_route(PackedVector3Array([home, start]))
	return cart


func _wait_home(cart: Node3D) -> void:
	for i in 200:
		if not is_instance_valid(cart) or int(cart.state) != int(cart.State.TO_HOME):
			break
		await get_tree().create_timer(0.2).timeout
	await get_tree().create_timer(4.0).timeout


## Боец стороны в точке. Без владельца — как гарнизон.
func _unit(faction: int, at: Vector3) -> Node3D:
	return _world.spawn_garrison_unit(faction, 0, at, at, 5.0)
