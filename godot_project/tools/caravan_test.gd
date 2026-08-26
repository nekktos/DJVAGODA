extends "res://tools/test_base.gd"
##
## Автопроверка каравана (Этап 5). Работает headless.
##
## Запуск: godot --headless --path godot_project -- --host --caravantest
##
## Проверяем то, ради чего караван в GDD вообще есть: он везёт ресурсы из
## далёкой шахты на склад, едет по НАРИСОВАННОМУ игроком пути и остаётся
## уязвимой целью — разбитый высыпает груз, который может подобрать любой.
##

const RES := preload("res://scripts/economy/resources.gd")

var _world: Node3D


func start(world: Node3D) -> void:
	tag = "караван-тест"
	expected_host = 9
	expected_client = 1
	_world = world
	_run.call_deferred()

func _caravans(me: Node3D) -> Array:
	return _world.caravans_of(me.peer_id)


func _loot() -> Array:
	return get_tree().get_nodes_in_group("loot")


func _run() -> void:
	await get_tree().create_timer(3.0).timeout
	var me: Node3D = _world.local_player()
	if me == null:
		fail("персонаж не заспавнен")
		finish()
		return

	await _test_needs_storage(me)
	await _build_storage(me)
	await _test_delivery(me)
	await _test_raid(me)

	finish()


func _test_needs_storage(me: Node3D) -> void:
	me.stock.grant([500, 500, 500, 500])
	# Потолок держим выше выданного: иначе карман полон, и проверка «груз с
	# разбитого каравана можно подобрать» падала бы не потому, что подбор сломан,
	# а потому, что подбирать некуда.
	me.stock.set_carried_capacity(2000)
	await get_tree().process_frame
	me.request_send_caravan(PackedVector3Array())
	await get_tree().create_timer(0.5).timeout
	check(_caravans(me).is_empty(), "без достроенного склада караван не отправляется",
		"караванов %d" % _caravans(me).size())


## Ставим склад и ждём, пока он достроится: каравану нужно куда возвращаться.
func _build_storage(me: Node3D) -> void:
	me.request_build(RES.Building.STORAGE, Vector3(-380.0, 0.0, 400.0))
	await get_tree().create_timer(RES.BUILD_TIME[RES.Building.STORAGE] + 1.5).timeout
	check(_world.storage_of(me.peer_id) != null, "склад достроен и найден",
		"склад %s" % ("есть" if _world.storage_of(me.peer_id) != null else "нет"))


func _test_delivery(me: Node3D) -> void:
	# Даём шахте накопить.
	_world.mine.stored = PackedInt32Array([0, 0, 200, 200])
	await get_tree().process_frame

	var iron_before: int = me.stock.get_amount(RES.Kind.IRON)
	# Маршрут из одной промежуточной точки: хост сам добавит склад в начало и
	# шахту в конец.
	me.request_send_caravan(PackedVector3Array([Vector3(-430.0, 0.0, 430.0)]))
	await get_tree().create_timer(0.5).timeout
	var sent: bool = _caravans(me).size() == 1
	check(sent, "караван отправлен по нарисованному маршруту", "караванов %d" % _caravans(me).size())
	if not sent:
		return

	# Ждём полный цикл: туда, погрузка, обратно, разгрузка.
	var caravan: Node3D = _caravans(me)[0]
	var loaded := false
	for i in 120:
		await get_tree().create_timer(0.5).timeout
		if not is_instance_valid(caravan):
			break
		if caravan.state == caravan.State.TO_HOME:
			loaded = true
		if me.stock.get_amount(RES.Kind.IRON) > iron_before:
			break

	check(loaded, "караван погрузился на шахте", "гружёным вышел обратно")
	check(me.stock.get_amount(RES.Kind.IRON) > iron_before,
		"груз доставлен на склад", "железо %d -> %d" % [iron_before, me.stock.get_amount(RES.Kind.IRON)])
	check(_world.mine.stored[RES.Kind.IRON] < 200,
		"шахта отдала накопленное", "осталось железа %d" % _world.mine.stored[RES.Kind.IRON])


func _test_raid(me: Node3D) -> void:
	_world.mine.stored = PackedInt32Array([0, 0, 200, 200])
	me.request_send_caravan(PackedVector3Array([Vector3(-430.0, 0.0, 430.0)]))
	await get_tree().create_timer(0.5).timeout
	if _caravans(me).is_empty():
		check(false, "караван для перехвата отправлен", "не отправился")
		return
	var caravan: Node3D = _caravans(me)[0]

	# Ждём, пока он загрузится и повезёт груз — грабить пустой смысла нет.
	for i in 120:
		await get_tree().create_timer(0.5).timeout
		if not is_instance_valid(caravan):
			break
		if caravan.state == caravan.State.TO_HOME:
			break
	if not is_instance_valid(caravan) or caravan.state != caravan.State.TO_HOME:
		check(false, "караван вышел с грузом", "не дождались")
		return

	var carried := 0
	for value in caravan.cargo:
		carried += value
	check(carried > 0, "караван везёт груз", "единиц %d" % carried)

	var loot_before: int = _loot().size()
	var point: Vector3 = caravan.global_position
	# Разбиваем: караван — уязвимая цель по GDD.
	caravan.take_damage(9999.0, 2, "cargo", point, Vector3.FORWARD)
	await get_tree().create_timer(0.6).timeout
	check(_loot().size() > loot_before, "разбитый караван высыпал груз",
		"куч на земле %d" % _loot().size())

	# Подбирает любой, кто подошёл.
	if _loot().is_empty():
		return
	var pile: Node3D = _loot()[0]
	me.global_position = pile.global_position + Vector3(0.0, 1.0, 1.0)
	me.sync_position = me.global_position
	await get_tree().create_timer(0.3).timeout
	var before: int = me.stock.get_amount(RES.Kind.GOLD)
	me.request_collect_loot()
	await get_tree().create_timer(0.3).timeout
	check(me.stock.get_amount(RES.Kind.GOLD) > before, "груз подобран с земли",
		"золото %d -> %d" % [before, me.stock.get_amount(RES.Kind.GOLD)])
