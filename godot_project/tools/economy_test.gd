extends Node
##
## Автопроверка экономики (Этап 4): добыча ресурсов и стройка. Работает headless.
##
## Запуск: godot --headless --path godot_project -- --host --econtest
##

const RES := preload("res://scripts/economy/resources.gd")

var _world: Node3D
var _failures := 0


func start(world: Node3D) -> void:
	_world = world
	_run.call_deferred()


func _check(ok: bool, label: String, detail: String) -> void:
	if not ok:
		_failures += 1
	print("[эконом] %s | %s: %s" % ["OK  " if ok else "ПРОВАЛ", label, detail])


func _run() -> void:
	await get_tree().create_timer(3.0).timeout
	var me: Node3D = _world.local_player()
	if me == null:
		print("[эконом] ПРОВАЛ: персонаж не заспавнен")
		get_tree().quit(1)
		return

	if not multiplayer.is_server():
		await _run_client(me)
		get_tree().quit(1 if _failures > 0 else 0)
		return

	await _test_harvest(me, RES.Kind.WOOD, "рубка дерева")
	await _test_harvest(me, RES.Kind.STONE, "добыча камня")
	await _test_capacity(me)
	await _test_build(me)
	await _test_prosthetic_cost(me)

	if _failures == 0:
		print("[эконом] все проверки пройдены")
	else:
		print("[эконом] провалено проверок: %d" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


## Найти ближайший к точке источник нужного ресурса.
func _nearest_source(kind: int, from: Vector3) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for node in get_tree().get_nodes_in_group("harvestable"):
		var body := node as Node3D
		if body == null or int(body.get_meta("resource", -1)) != kind:
			continue
		var d: float = body.global_position.distance_to(from)
		if d < best_d:
			best_d = d
			best = body
	return best


func _test_harvest(me: Node3D, kind: int, label: String) -> void:
	var source := _nearest_source(kind, me.global_position)
	if source == null:
		_check(false, label, "источник не найден на карте")
		return

	# Встаём вплотную и поворачиваемся к источнику.
	var to_source := source.global_position - me.global_position
	to_source.y = 0.0
	var dir := to_source.normalized()
	me.global_position = source.global_position - dir * 2.0
	me.global_position.y = 2.0
	me.sync_position = me.global_position
	me.rotation.y = atan2(-dir.x, -dir.z)
	me.velocity = Vector3.ZERO
	await get_tree().create_timer(0.5).timeout

	var before: int = me.stock.get_amount(kind)
	me.sync_weapon = 0                      # меч
	me.scripted_input = {"move": Vector2.ZERO, "jump": false, "attack": true}
	await get_tree().create_timer(3.0).timeout
	me.scripted_input = {}
	var after: int = me.stock.get_amount(kind)

	_check(after > before, label, "%s: %d -> %d" % [RES.NAMES[kind], before, after])


func _test_capacity(me: Node3D) -> void:
	var before: int = me.stock.capacity
	me.stock.raise_capacity(RES.STORAGE_BONUS)
	_check(me.stock.capacity == before + RES.STORAGE_BONUS,
		"склад поднимает потолок хранения", "%d -> %d" % [before, me.stock.capacity])

	# Сверх потолка не влезает.
	me.stock.capacity = 10
	me.stock.amounts = PackedInt32Array([10, 0, 0, 0])
	var taken: int = me.stock.add(RES.Kind.WOOD, 50)
	_check(taken == 0 and me.stock.get_amount(RES.Kind.WOOD) == 10,
		"сверх потолка не принимается", "влезло %d" % taken)


func _give(me: Node3D, wood: int, stone: int, gold: int, iron: int) -> void:
	me.stock.capacity = 9999
	me.stock.amounts = PackedInt32Array([wood, stone, gold, iron])
	await get_tree().process_frame


func _buildings() -> Array:
	return get_tree().get_nodes_in_group("building")


func _test_build(me: Node3D) -> void:
	# Ровная площадка в стороне от перекрёстка и стартовых ресурсов.
	var spot := Vector3(60.0, 0.0, 60.0)

	# Без ресурсов строить нельзя.
	await _give(me, 0, 0, 0, 0)
	var before: int = _buildings().size()
	me.request_build(RES.Building.STORAGE, spot)
	await get_tree().create_timer(0.4).timeout
	_check(_buildings().size() == before, "без ресурсов склад не ставится", "построек %d" % _buildings().size())

	# С ресурсами — ставится, и стоимость списывается.
	await _give(me, 200, 200, 200, 200)
	var wood_before: int = me.stock.get_amount(RES.Kind.WOOD)
	me.request_build(RES.Building.STORAGE, spot)
	await get_tree().create_timer(0.4).timeout
	var placed: bool = _buildings().size() == before + 1
	_check(placed, "склад поставлен", "построек %d" % _buildings().size())
	_check(me.stock.get_amount(RES.Kind.WOOD) < wood_before,
		"стоимость списана", "дерево %d -> %d" % [wood_before, me.stock.get_amount(RES.Kind.WOOD)])

	# Второй склад вплотную к первому не влезает.
	var packed: int = _buildings().size()
	me.request_build(RES.Building.STORAGE, spot + Vector3(2.0, 0.0, 2.0))
	await get_tree().create_timer(0.4).timeout
	_check(_buildings().size() == packed, "вплотную к соседнему зданию не ставится",
		"построек %d" % _buildings().size())

	# На перепаде высот нельзя. Берём край плато императора: он ровно на
	# границе, половина основания на высоте 6 м, половина на нуле. Горы у
	# злодея расставлены случайным сидом, на них полагаться нельзя.
	var slope := Vector3(480.0, 0.0, -300.0)
	var on_slope: int = _buildings().size()
	me.request_build(RES.Building.BARRACKS, slope)
	await get_tree().create_timer(0.4).timeout
	_check(_buildings().size() == on_slope, "на неровном месте не ставится",
		"построек %d" % _buildings().size())

	# Достроенный склад поднимает потолок.
	var cap_before: int = me.stock.capacity
	await get_tree().create_timer(RES.BUILD_TIME[RES.Building.STORAGE] + 1.5).timeout
	_check(me.stock.capacity > cap_before, "достроенный склад поднял потолок",
		"%d -> %d" % [cap_before, me.stock.capacity])


func _test_prosthetic_cost(me: Node3D) -> void:
	# Отрываем руку и встаём к верстаку.
	me.body.reset()
	me.health.revive()
	for i in 6:
		me.body.register_hit("arm_r", 12.0)
		me.health.revive()
	me.body.bleeding = false
	me.global_position = _world.workbench_position() + Vector3(0.0, 2.0, 2.0)
	me.sync_position = me.global_position
	await get_tree().create_timer(0.4).timeout

	await _give(me, 0, 0, 0, 0)
	me.request_prosthetic(1)
	await get_tree().process_frame
	_check(me.body.tier(0 if me.body.is_severed(0) else 1) == 0,
		"без ресурсов протез не выдают", "уровень протеза 0")

	await _give(me, 200, 200, 200, 200)
	var wood_before: int = me.stock.get_amount(RES.Kind.WOOD)
	me.request_prosthetic(1)
	await get_tree().process_frame
	var limb := 0 if me.body.is_severed(0) else 1
	_check(me.body.tier(limb) == 1 and me.stock.get_amount(RES.Kind.WOOD) < wood_before,
		"деревянный протез крафтится за древесину",
		"уровень %d, дерево %d -> %d" % [me.body.tier(limb), wood_before, me.stock.get_amount(RES.Kind.WOOD)])


# --- клиент: пробует строить за чужой счёт --------------------------------

func _run_client(me: Node3D) -> void:
	await get_tree().create_timer(2.0).timeout
	var host_player: Node3D = _world.get_node("Players").get_node_or_null("1")
	if host_player == null:
		print("[эконом] клиент: персонаж хоста не найден")
		return

	# Атака 1: приказать ЧУЖОМУ персонажу построить здание. Хост обязан
	# отклонить — заявку прислал не владелец.
	var before: int = _buildings().size()
	host_player.request_build.rpc_id(1, RES.Building.STORAGE, Vector3(90.0, 0.0, 90.0))
	await get_tree().create_timer(1.5).timeout
	_check(_buildings().size() == before,
		"клиент не может строить чужим персонажем", "построек %d" % _buildings().size())

	# Атака 2: выписать себе ресурсы локально. Репликация обязана затереть.
	me.stock.amounts = PackedInt32Array([9999, 9999, 9999, 9999])
	await get_tree().create_timer(1.5).timeout
	var wood: int = me.stock.get_amount(RES.Kind.WOOD)
	_check(wood < 9999, "подделка ресурсов затёрта хостом", "дерева стало %d" % wood)
