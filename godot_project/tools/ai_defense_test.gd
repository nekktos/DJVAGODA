extends "res://tools/test_base.gd"
##
## ИИ держит своё хозяйство: то, что нашла «долгая партия».
##
## Запуск: хост — эльф, злодей под ИИ (`run_tests.sh aidefense`).
##
## 1. Отряд ИИ идёт отбивать своё хозяйство. Четверо стражников две с
##    половиной минуты рубили конюшню злодея в сорока метрах от его гарнизона,
##    а тот ждал врага у своей точки сбора. Угрозой здесь служит сам хост-эльф:
##    он встаёт у склада злодея вдали от гарнизона.
## 2. Обоз проезжает поле насквозь. Пашня проходима, путь по сетке идёт через
##    неё, а объезд построек отталкивал обоз от поля — гружёный обоз двадцать
##    минут дёргался у его угла.
## 3. С кузней распорядитель возит уголь: без него закалка ИИ недоступна.
##

const RES := preload("res://scripts/economy/resources.gd")
const FACTIONS := preload("res://scripts/factions.gd")
const BUILD_CONTROLLER := preload("res://scripts/economy/build_controller.gd")

const VILLAIN := FACTIONS.Kind.VILLAIN

var _world: Node3D


func start(world: Node3D) -> void:
	tag = "ИИ держит хозяйство"
	expected_host = 3
	expected_client = 1
	_world = world
	_run.call_deferred()


func _run() -> void:
	if not session_ready():
		finish()
		return
	await get_tree().create_timer(3.0).timeout
	var me: Node3D = _world.local_player()
	if me == null:
		fail("персонаж не заспавнен")
		finish()
		return
	await _test_defends(me)
	await _test_cart_crosses_field()
	_test_hauls_coal()
	finish()


func _test_defends(me: Node3D) -> void:
	var base: Vector3 = FACTIONS.SPAWN[VILLAIN]
	var spot := _free_spot(base, RES.Building.STORAGE, [70.0, 90.0, 110.0])
	var storage: Node3D = _world.spawn_building(RES.Building.STORAGE, spot, 0, VILLAIN, true)
	await get_tree().create_timer(1.0).timeout
	var band: Array = _world.warband._band(VILLAIN)
	var before: float = _nearest(band, spot)
	# Встаём у склада и не бьём: угроза — само присутствие. Урон по хосту
	# гасим, чтобы он дожил до конца проверки.
	me.control_enabled = false
	me.teleport.rpc(spot + Vector3(0.0, 1.0, 9.0))
	var defending := false
	for i in 20:
		await get_tree().create_timer(1.0).timeout
		me.health.current = me.health.maximum()
		if _world.warband.state_name(VILLAIN) == "защищает хозяйство":
			defending = true
		if defending and _nearest(_world.warband._band(VILLAIN), spot) < 25.0:
			break
	var after: float = _nearest(_world.warband._band(VILLAIN), spot)
	check(defending and after < before - 20.0,
		"отряд ИИ идёт отбивать своё хозяйство",
		"обороняет: %s, ближайший боец был в %.0f м, стал в %.0f" % [defending, before, after])
	me.teleport.rpc(FACTIONS.SPAWN[int(me.faction)] + Vector3(0.0, 1.0, 0.0))
	me.control_enabled = true
	if is_instance_valid(storage):
		storage.queue_free()


func _test_cart_crosses_field() -> void:
	# Чистое поле посреди карты: путь с севера на юг прямо через пашню.
	var field: Node3D = _world.spawn_building(RES.Building.FARM, Vector3(0.0, 0.0, 100.0),
		0, VILLAIN, true)
	var route := PackedVector3Array([Vector3(0.0, 0.0, 70.0), Vector3(0.0, 0.0, 135.0)])
	var cart: Node3D = _world.spawn_caravan(route, 0, VILLAIN, 2)
	var passed := false
	for i in 30:
		await get_tree().create_timer(1.0).timeout
		if not is_instance_valid(cart):
			break
		if cart.global_position.z > 125.0 or int(cart.state) != 0:
			passed = true
			break
	check(passed, "обоз проезжает поле насквозь, не шарахаясь от пашни",
		"обоз в %s" % [cart.global_position.round() if is_instance_valid(cart) else "нет"])
	if is_instance_valid(cart):
		cart.queue_free()
	if is_instance_valid(field):
		field.queue_free()


func _test_hauls_coal() -> void:
	var base: Vector3 = FACTIONS.SPAWN[VILLAIN]
	var spot := _free_spot(base, RES.Building.FORGE, [40.0, 55.0, 70.0])
	_world.spawn_building(RES.Building.FORGE, spot, 0, VILLAIN, true)
	var wallet: Node = _world.treasury.of(VILLAIN)
	wallet.grant(RES.fit([300, 300, 300, 300, 0, 0]))
	var target: Node3D = _world.steward._pick_mine(VILLAIN)
	check(target != null and target == _world.mine_of(RES.Kind.COAL),
		"с кузней распорядитель шлёт обоз за углём, когда угля меньше всего",
		target.title() if target != null else "шахты нет")


func _nearest(band: Array, point: Vector3) -> float:
	var best := INF
	for unit in band:
		if is_instance_valid(unit):
			best = minf(best, Vector2(unit.global_position.x, unit.global_position.z).distance_to(
				Vector2(point.x, point.z)))
	return best


func _free_spot(around: Vector3, kind: int, radii: Array) -> Vector3:
	for radius in radii:
		for i in 12:
			var angle := TAU * float(i) / 12.0
			var at := around + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
			at.y = 0.0
			if BUILD_CONTROLLER.is_spot_buildable(_world, at, kind):
				return at
	return around + Vector3(radii[0], 0.0, 0.0)
