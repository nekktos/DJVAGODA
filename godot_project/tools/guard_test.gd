extends Node
##
## Автопроверка кампании охраны дворца (Этап 9, GDD раздел 2.2). Работает headless.
##
## Запуск:
##   godot --headless --path godot_project -- --host --faction=2 --guardtest
##   godot --headless --path godot_project -- --join=127.0.0.1 --faction=0 --guardtest
##

const ORDERS := preload("res://scripts/orders.gd")
const FACTIONS := preload("res://scripts/factions.gd")
const RES := preload("res://scripts/economy/resources.gd")

var _world: Node3D
var _failures := 0
## Счётчик выполненных проверок — см. forest_test: без него тест зеленеет, когда
## проверяемый скрипт вообще не загрузился.
var _ran := 0
const EXPECTED_CHECKS := 21


func start(world: Node3D) -> void:
	_world = world
	_run.call_deferred()


func _check(ok: bool, label: String, detail: String) -> void:
	_ran += 1
	if not ok:
		_failures += 1
	print("[стража] %s | %s: %s" % ["OK  " if ok else "ПРОВАЛ", label, detail])


func _run() -> void:
	await get_tree().create_timer(3.0).timeout
	var me: Node3D = _world.local_player()
	if me == null:
		print("[стража] ПРОВАЛ: персонаж не заспавнен")
		get_tree().quit(1)
		return

	if not multiplayer.is_server():
		await _run_client()
		get_tree().quit(1 if _failures > 0 else 0)
		return

	await _test_issue(me)
	await _test_hold(me)
	await _test_slay(me)
	await _test_raid(me)
	await _test_faction_guard(me)

	if _ran < EXPECTED_CHECKS:
		print("[стража] ПРОВАЛ: выполнилось проверок %d из %d — часть кода не отработала" % [_ran, EXPECTED_CHECKS])
		_failures += 1
	if _failures == 0:
		print("[стража] все проверки пройдены (%d)" % _ran)
	else:
		print("[стража] провалено проверок: %d из %d" % [_failures, _ran])
	if not multiplayer.get_peers().is_empty():
		await get_tree().create_timer(10.0).timeout
	get_tree().quit(1 if _failures > 0 else 0)


func _commander() -> Node3D:
	return _world.get_node("Commander")


## Приказ выдаётся только у командира и только по докладу.
func _test_issue(me: Node3D) -> void:
	_check(int(me.faction) == FACTIONS.Kind.GUARD, "тест идёт за стражу",
		FACTIONS.name_of(me.faction))
	_check(me.order_kind < 0, "в начале приказа нет", "order_kind=%d" % me.order_kind)

	# Издалека командир не слышит.
	me.teleport.rpc(Vector3(0.0, 2.0, 0.0))
	await get_tree().physics_frame
	_check(not me.at_commander(), "издалека командир недоступен", "at_commander=false")
	me.request_report()
	await get_tree().physics_frame
	_check(me.order_kind < 0, "издалека приказ не выдаётся", "order_kind=%d" % me.order_kind)

	await _go_to_commander(me)
	_check(me.at_commander(), "у командира можно докладывать", "at_commander=true")
	me.request_report()
	await get_tree().physics_frame
	_check(me.order_kind == ORDERS.Kind.HOLD, "выдан первый приказ",
		ORDERS.name_of(me.order_kind))


## Держать дворец: секунды капают, пока страж стоит в точке и дворец наш.
func _test_hold(me: Node3D) -> void:
	var objective: Node3D = _world.objective
	objective.palace_owner = FACTIONS.Kind.GUARD

	# Вне точки прогресс стоять не должен.
	me.teleport.rpc(Vector3(0.0, 2.0, 0.0))
	await get_tree().create_timer(0.6).timeout
	_check(me.order_progress == 0, "вне точки удержание не идёт",
		"прогресс %d" % me.order_progress)

	me.teleport.rpc(objective.PALACE + Vector3(0.0, 26.0, 0.0))
	await get_tree().create_timer(1.6).timeout
	_check(me.order_progress > 0, "в точке удержание идёт", "прогресс %d" % me.order_progress)

	# Доклад до срока не должен ни платить, ни менять приказ.
	var gold_before: int = me.stock.get_amount(RES.Kind.GOLD)
	me.order_progress = 1
	await _go_to_commander(me)
	me.request_report()
	await get_tree().physics_frame
	_check(me.order_kind == ORDERS.Kind.HOLD, "недовыполненный приказ не сдаётся",
		ORDERS.name_of(me.order_kind))
	_check(me.stock.get_amount(RES.Kind.GOLD) == gold_before, "за недоделанное не платят",
		"золота %d" % me.stock.get_amount(RES.Kind.GOLD))

	# А выполненный — сдаётся и оплачивается.
	me.order_progress = ORDERS.target_of(ORDERS.Kind.HOLD)
	me.request_report()
	await get_tree().physics_frame
	_check(me.stock.get_amount(RES.Kind.GOLD) > gold_before, "за выполненный заплатили",
		"%d -> %d" % [gold_before, me.stock.get_amount(RES.Kind.GOLD)])
	_check(me.orders_done == 1, "счётчик выполненных вырос", "%d" % me.orders_done)
	_check(me.order_kind == ORDERS.Kind.SLAY, "сразу выдан следующий приказ",
		ORDERS.name_of(me.order_kind))


## Проредить войско: засчитываются убитые бойцы злодея, но не свои.
func _test_slay(me: Node3D) -> void:
	var before: int = me.order_progress

	# Убитый на стороне злодея засчитывается.
	_commander().report_kill(int(me.peer_id), FACTIONS.Kind.VILLAIN)
	await get_tree().physics_frame
	_check(me.order_progress == before + 1, "убитый на стороне злодея засчитан",
		"прогресс %d" % me.order_progress)

	# Свои — нет: иначе приказ выполнялся бы самоубийством собственного отряда.
	_commander().report_kill(int(me.peer_id), FACTIONS.Kind.GUARD)
	await get_tree().physics_frame
	_check(me.order_progress == before + 1, "свои не засчитываются",
		"прогресс %d" % me.order_progress)

	# Чужая заслуга тоже не идёт в зачёт стражу.
	_commander().report_kill(999, FACTIONS.Kind.VILLAIN)
	await get_tree().physics_frame
	_check(me.order_progress == before + 1, "чужие убийства не засчитываются",
		"прогресс %d" % me.order_progress)

	# Путь от бойца до командира: мир должен перевести владельца бойца в сторону.
	# В соло-прогоне злодея-игрока нет, тогда эту связку проверить нечем.
	var villain_id := _villain_peer()
	if villain_id > 0:
		_world.report_unit_kill(int(me.peer_id), villain_id)
		await get_tree().physics_frame
		_check(me.order_progress == before + 2, "убитый боец злодея засчитан",
			"прогресс %d" % me.order_progress)

	me.order_progress = ORDERS.target_of(ORDERS.Kind.SLAY)
	await _go_to_commander(me)
	me.request_report()
	await get_tree().physics_frame
	_check(me.order_kind == ORDERS.Kind.RAID, "после боя выдан набег",
		ORDERS.name_of(me.order_kind))


## Набег: сначала дойти до форта злодея, потом вернуться. Порядок обязателен.
func _test_raid(me: Node3D) -> void:
	_check(me.order_progress == 0, "набег начинается с нуля", "прогресс %d" % me.order_progress)

	# Вернуться, не дойдя, нельзя: командир не засчитает.
	await _go_to_commander(me)
	await get_tree().physics_frame
	_check(me.order_progress == 0, "возврат без набега не засчитан",
		"прогресс %d" % me.order_progress)

	me.teleport.rpc(ORDERS.RAID_POINT + Vector3(0.0, 3.0, 0.0))
	await get_tree().create_timer(0.5).timeout
	_check(me.order_progress == 1, "форт злодея засчитан", "прогресс %d" % me.order_progress)

	await _go_to_commander(me)
	await get_tree().create_timer(0.5).timeout
	_check(me.order_progress == 2, "возврат засчитан", "прогресс %d" % me.order_progress)


## Приказы получает только стража: у злодея и эльфов свои кампании.
func _test_faction_guard(me: Node3D) -> void:
	me.faction = FACTIONS.Kind.VILLAIN
	var before: int = me.order_kind
	me.request_report()
	await get_tree().physics_frame
	_check(me.order_kind == before, "не страже приказ не выдают",
		"order_kind=%d" % me.order_kind)
	me.faction = FACTIONS.Kind.GUARD


func _go_to_commander(me: Node3D) -> void:
	me.teleport.rpc(_commander().POSITION + Vector3(0.0, 2.0, 2.0))
	await get_tree().physics_frame
	await get_tree().physics_frame


## Peer id злодея, если он в сессии. Иначе годится любой чужой id — командир
## смотрит на сторону владельца, а не на самого убитого.
func _villain_peer() -> int:
	for child in _world.get_node("Players").get_children():
		if "faction" in child and int(child.faction) == FACTIONS.Kind.VILLAIN:
			return int(child.peer_id)
	return -1


## Клиент: приказ хоста доезжает по сети, а подделать свой нельзя.
func _run_client() -> void:
	await get_tree().create_timer(6.0).timeout
	var host_player: Node3D = _world.get_node_or_null("Players/1")
	if host_player == null:
		_check(false, "персонаж хоста виден клиенту", "не найден")
		return
	_check(true, "персонаж хоста виден клиенту", "найден")
	_check(host_player.orders_done > 0, "выполненные приказы хоста доехали",
		"%d" % host_player.orders_done)

	var me: Node3D = _world.local_player()
	if me == null:
		return
	me.orders_done = 99
	await get_tree().create_timer(2.0).timeout
	_check(me.orders_done != 99, "подделка счётчика приказов затёрта хостом",
		"выставил 99, стало %d" % me.orders_done)
