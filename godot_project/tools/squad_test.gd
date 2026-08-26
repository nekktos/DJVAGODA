extends "res://tools/test_base.gd"
##
## Автопроверка отряда и построений (Этап 6). Работает headless.
##
## Запуск: godot --headless --path godot_project -- --host --squadtest
##
## Проверяем то, ради чего отряд в GDD есть: наём из казармы за ресурсы, четыре
## построения из раздела 8.3 с разной геометрией, их боевые модификаторы и
## приказы — следовать за командиром либо идти в назначенную точку.
##

const RES := preload("res://scripts/economy/resources.gd")
const FORMATIONS := preload("res://scripts/units/formations.gd")

var _world: Node3D


func start(world: Node3D) -> void:
	tag = "отряд-тест"
	expected_host = 19
	expected_client = 1
	_world = world
	_run.call_deferred()

func _units(me: Node3D) -> Array:
	return _world.units_of(me.peer_id)


func _run() -> void:
	await get_tree().create_timer(3.0).timeout
	var me: Node3D = _world.local_player()
	if me == null:
		fail("персонаж не заспавнен")
		finish()
		return

	await _test_hiring(me)
	await _test_formations(me)
	await _test_orders(me)
	_test_modifiers()
	await _test_spacing_and_animation(me)

	finish()


func _test_hiring(me: Node3D) -> void:
	me.stock.capacity = 99999
	me.stock.amounts = PackedInt32Array([999, 999, 999, 999])
	await get_tree().process_frame

	# Без казармы нанимать негде.
	me.request_train_unit()
	await get_tree().create_timer(0.4).timeout
	check(_units(me).is_empty(), "без достроенной казармы наём невозможен",
		"бойцов %d" % _units(me).size())

	me.request_build(RES.Building.BARRACKS, Vector3(-60.0, 0.0, 90.0))
	await get_tree().create_timer(RES.BUILD_TIME[RES.Building.BARRACKS] + 1.5).timeout
	check(_world.barracks_of(me.peer_id) != null, "казарма достроена", "казарма есть")

	var gold_before: int = me.stock.get_amount(RES.Kind.GOLD)
	for i in 8:
		me.request_train_unit()
		await get_tree().create_timer(0.15).timeout
	check(_units(me).size() == 8, "нанято 8 мечников", "бойцов %d" % _units(me).size())
	check(me.stock.get_amount(RES.Kind.GOLD) < gold_before, "наём списывает ресурсы",
		"золото %d -> %d" % [gold_before, me.stock.get_amount(RES.Kind.GOLD)])

	# Потолок отряда.
	me.stock.amounts = PackedInt32Array([999, 999, 999, 999])
	for i in RES.SQUAD_LIMIT + 4:
		me.request_train_unit()
		await get_tree().create_timer(0.1).timeout
	check(_units(me).size() <= RES.SQUAD_LIMIT, "потолок отряда соблюдён",
		"бойцов %d при потолке %d" % [_units(me).size(), RES.SQUAD_LIMIT])


## Ширина и глубина строя по фактическим позициям слотов.
func _shape(kind: int, count: int) -> Vector2:
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for i in count:
		var offset: Vector3 = FORMATIONS.slot_offset(kind, i, count)
		min_x = minf(min_x, offset.x)
		max_x = maxf(max_x, offset.x)
		min_z = minf(min_z, offset.z)
		max_z = maxf(max_z, offset.z)
	return Vector2(max_x - min_x, max_z - min_z)


func _test_formations(me: Node3D) -> void:
	var count := 8
	var line := _shape(FORMATIONS.Kind.LINE, count)
	var wall := _shape(FORMATIONS.Kind.SHIELD_WALL, count)
	var column := _shape(FORMATIONS.Kind.COLUMN, count)
	var loose := _shape(FORMATIONS.Kind.LOOSE, count)

	check(line.x > line.y, "шеренга шире, чем глубже",
		"фронт %.1f м, глубина %.1f м" % [line.x, line.y])
	check(wall.x < line.x, "стена щитов плотнее шеренги",
		"фронт стены %.1f м против %.1f м" % [wall.x, line.x])
	check(column.y > column.x, "колонна глубже, чем шире",
		"фронт %.1f м, глубина %.1f м" % [column.x, column.y])
	check(loose.x > line.x and loose.y > line.y, "рассыпной строй занимает больше места",
		"%.1f x %.1f м против %.1f x %.1f м" % [loose.x, loose.y, line.x, line.y])

	# Бойцы действительно расходятся по слотам при смене строя.
	var squad: Array = _units(me)
	if squad.size() < 4:
		check(false, "бойцы встают в строй", "отряд слишком мал")
		return
	# Командира ставим рядом с отрядом: иначе бойцы меряются на марше к нему,
	# так и не успев построиться, и проверка прошла бы при сломанных слотах.
	var barracks: Node3D = _world.barracks_of(me.peer_id)
	me.global_position = barracks.global_position + Vector3(0.0, 2.0, 20.0)
	me.sync_position = me.global_position
	me.rotation.y = 0.0

	me.request_formation(FORMATIONS.Kind.LINE)
	me.request_squad_follow()
	await get_tree().create_timer(12.0).timeout
	var spread_line := _squad_width(squad)

	me.request_formation(FORMATIONS.Kind.COLUMN)
	await get_tree().create_timer(12.0).timeout
	var spread_column := _squad_width(squad)

	# Шеренга из 8 в ряд шире 12 м, колонна по 2 в ряд — уже 4 м. Проверяем
	# по абсолютным числам, а не только «меньше»: относительная проверка
	# прошла бы и на полурассыпанном отряде.
	check(spread_line > 12.0 and spread_column < 5.0,
		"смена строя реально перестраивает бойцов на земле",
		"ширина шеренгой %.1f м, колонной %.1f м" % [spread_line, spread_column])


## Фактическая ширина отряда на земле.
func _squad_width(squad: Array) -> float:
	var min_x := INF
	var max_x := -INF
	for unit in squad:
		if not is_instance_valid(unit):
			continue
		min_x = minf(min_x, unit.global_position.x)
		max_x = maxf(max_x, unit.global_position.x)
	return max_x - min_x if max_x > min_x else 0.0


func _test_orders(me: Node3D) -> void:
	var squad: Array = _units(me)
	if squad.is_empty():
		check(false, "приказ идти в точку", "отряд пуст")
		return

	var point := Vector3(-120.0, 0.0, 120.0)
	me.request_squad_move(point)
	check(me.squad_hold, "приказ переводит отряд в режим удержания точки",
		"squad_hold=%s" % me.squad_hold)

	await get_tree().create_timer(18.0).timeout
	var arrived := 0
	for unit in squad:
		if is_instance_valid(unit) and unit.global_position.distance_to(point) < 18.0:
			arrived += 1
	if arrived < squad.size() / 2:
		for unit in squad:
			if is_instance_valid(unit):
				print("[отряд-тест] боец: %s, до точки %.1f м" % [
					unit.global_position, unit.global_position.distance_to(point)
				])
	check(arrived >= squad.size() / 2, "отряд дошёл до назначенной точки",
		"дошло %d из %d" % [arrived, squad.size()])

	me.request_squad_follow()
	check(not me.squad_hold, "приказ следовать возвращает отряд к командиру",
		"squad_hold=%s" % me.squad_hold)


## Модификаторы построений (DESIGN_ANSWERS.md, пункт 16).
func _test_modifiers() -> void:
	var wall: float = FORMATIONS.damage_scale(FORMATIONS.Kind.SHIELD_WALL, false)
	var line: float = FORMATIONS.damage_scale(FORMATIONS.Kind.LINE, false)
	check(wall < line, "стена щитов режет входящий урон",
		"x%.2f против x%.2f" % [wall, line])

	var wall_speed: float = FORMATIONS.speed_scale(FORMATIONS.Kind.SHIELD_WALL)
	var column_speed: float = FORMATIONS.speed_scale(FORMATIONS.Kind.COLUMN)
	check(wall_speed < 1.0 and column_speed > 1.0,
		"стена медленнее, колонна быстрее", "стена x%.2f, колонна x%.2f" % [wall_speed, column_speed])

	var loose_aoe: float = FORMATIONS.damage_scale(FORMATIONS.Kind.LOOSE, true)
	var column_aoe: float = FORMATIONS.damage_scale(FORMATIONS.Kind.COLUMN, true)
	check(loose_aoe < column_aoe * 0.5, "рассыпной строй гасит урон по площади",
		"рассыпной x%.2f, колонна x%.2f" % [loose_aoe, column_aoe])


## Бойцы не должны стоять внахлёст, а ходьба — не должна замирать после
## одного проигрыша. Оба пункта нашлись на живом playtest, глазами.
func _test_spacing_and_animation(me: Node3D) -> void:
	var squad: Array = _units(me)
	if squad.size() < 4:
		check(false, "расстояние между бойцами", "отряд слишком мал")
		return

	# Ставим командира рядом и даём построиться в самый плотный строй.
	var barracks: Node3D = _world.barracks_of(me.peer_id)
	if barracks != null:
		me.teleport.rpc(barracks.global_position + Vector3(0.0, 2.0, 24.0))
	me.request_squad_follow()
	me.request_formation(FORMATIONS.Kind.SHIELD_WALL)
	await get_tree().create_timer(12.0).timeout

	var closest := INF
	for i in squad.size():
		for j in range(i + 1, squad.size()):
			if not is_instance_valid(squad[i]) or not is_instance_valid(squad[j]):
				continue
			var a: Vector3 = squad[i].global_position
			var b: Vector3 = squad[j].global_position
			closest = minf(closest, Vector2(a.x - b.x, a.z - b.z).length())
	check(closest > 0.7, "бойцы не проникают друг в друга даже в стене щитов",
		"ближайшая пара: %.2f м" % closest)

	# Отправляем в поход и смотрим, играет ли ходьба и зациклена ли она.
	me.request_squad_move(me.global_position + Vector3(70.0, 0.0, 70.0))
	await get_tree().create_timer(3.0).timeout
	var walking := 0
	var looping := 0
	for unit in squad:
		if not is_instance_valid(unit):
			continue
		var state: Dictionary = unit.animation_state()
		if state.get("playing", false) and String(state.get("name", "")) == "walk":
			walking += 1
		if state.get("looping", false):
			looping += 1
	check(walking > 0, "на марше играет анимация ходьбы", "идут с анимацией: %d" % walking)
	check(looping == squad.size(), "анимация ходьбы зациклена",
		"зациклено у %d из %d" % [looping, squad.size()])
