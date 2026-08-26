extends Node
##
## Автопроверка торговли эльфов (Этап 8, GDD раздел 2.1). Работает headless.
##
## Запуск:
##   godot --headless --path godot_project -- --host --faction=1 --tradetest
##   godot --headless --path godot_project -- --join=127.0.0.1 --faction=0 --tradetest
##

const RES := preload("res://scripts/economy/resources.gd")
const WEAPONS := preload("res://scripts/combat/weapons.gd")

var _world: Node3D
var _failures := 0
## Счётчик выполненных проверок — см. forest_test: без него тест зеленеет, когда
## проверяемый скрипт вообще не загрузился.
var _ran := 0
const EXPECTED_CHECKS := 15


func start(world: Node3D) -> void:
	_world = world
	_run.call_deferred()


func _check(ok: bool, label: String, detail: String) -> void:
	_ran += 1
	if not ok:
		_failures += 1
	print("[торг] %s | %s: %s" % ["OK  " if ok else "ПРОВАЛ", label, detail])


func _run() -> void:
	await get_tree().create_timer(3.0).timeout
	var me: Node3D = _world.local_player()
	if me == null:
		print("[торг] ПРОВАЛ: персонаж не заспавнен")
		get_tree().quit(1)
		return

	if not multiplayer.is_server():
		await _run_client()
		get_tree().quit(1 if _failures > 0 else 0)
		return

	await _test_range(me)
	await _test_bandages(me)
	await _test_gear(me)
	await _test_gear_affects_damage(me)

	if _ran < EXPECTED_CHECKS:
		print("[торг] ПРОВАЛ: выполнилось проверок %d из %d — часть кода не отработала" % [_ran, EXPECTED_CHECKS])
		_failures += 1
	if _failures == 0:
		print("[торг] все проверки пройдены (%d)" % _ran)
	else:
		print("[торг] провалено проверок: %d из %d" % [_failures, _ran])
	if not multiplayer.get_peers().is_empty():
		# Клиенту нужно время на проверку репликации, а закрывшийся хост обрывает
		# ему сессию и валит его половину теста.
		await get_tree().create_timer(10.0).timeout
	get_tree().quit(1 if _failures > 0 else 0)


## Купить можно только стоя у лавки. Иначе это покупка с другого конца карты.
func _test_range(me: Node3D) -> void:
	_grant(me, [0, 0, 500, 500])
	me.teleport.rpc(Vector3(0.0, 2.0, 0.0))
	await get_tree().physics_frame

	_check(not me.at_trader(), "вдали от лавки торговля закрыта", "at_trader=false")
	var before: int = me.body.bandages
	me.request_trade(RES.Trade.BANDAGES)
	await get_tree().physics_frame
	_check(me.body.bandages == before, "издалека купить нельзя", "бинтов %d" % me.body.bandages)

	me.teleport.rpc(_world.trader_position() + Vector3(0.0, 2.0, 2.0))
	await get_tree().physics_frame
	_check(me.at_trader(), "у лавки торговля открыта", "at_trader=true")


func _test_bandages(me: Node3D) -> void:
	me.body.bandages = 0
	var gold_before: int = me.stock.get_amount(RES.Kind.GOLD)

	me.request_trade(RES.Trade.BANDAGES)
	await get_tree().physics_frame
	_check(me.body.bandages == RES.BANDAGE_PACK, "бинты куплены",
		"стало %d" % me.body.bandages)
	_check(me.stock.get_amount(RES.Kind.GOLD) < gold_before, "золото списано",
		"%d -> %d" % [gold_before, me.stock.get_amount(RES.Kind.GOLD)])

	# Потолок сумки: бесконечно закупаться нельзя.
	for i in 6:
		me.request_trade(RES.Trade.BANDAGES)
		await get_tree().physics_frame
	_check(me.body.bandages == RES.BANDAGE_LIMIT, "потолок сумки соблюдён",
		"бинтов %d" % me.body.bandages)

	# Без денег не продают.
	me.body.bandages = 0
	_set_stock(me, [0, 0, 0, 0])
	me.request_trade(RES.Trade.BANDAGES)
	await get_tree().physics_frame
	_check(me.body.bandages == 0, "без золота не продают", "бинтов %d" % me.body.bandages)


func _test_gear(me: Node3D) -> void:
	_set_stock(me, [0, 0, 500, 500])
	_check(me.gear_tier == 0, "снаряжение стартовое", WEAPONS.gear_name(me.gear_tier))

	me.request_trade(RES.Trade.GEAR)
	await get_tree().physics_frame
	_check(me.gear_tier == 1, "первый апгрейд куплен", WEAPONS.gear_name(me.gear_tier))

	me.request_trade(RES.Trade.GEAR)
	await get_tree().physics_frame
	_check(me.gear_tier == 2, "второй апгрейд куплен", WEAPONS.gear_name(me.gear_tier))

	# Выше последнего уровня подниматься некуда, и деньги за это брать нельзя.
	var gold_before: int = me.stock.get_amount(RES.Kind.GOLD)
	me.request_trade(RES.Trade.GEAR)
	await get_tree().physics_frame
	_check(me.gear_tier == 2, "выше потолка снаряжения не растёт", WEAPONS.gear_name(me.gear_tier))
	_check(me.stock.get_amount(RES.Kind.GOLD) == gold_before, "за несуществующий уровень не списали",
		"золота %d" % me.stock.get_amount(RES.Kind.GOLD))
	_check(me.next_gear_cost().is_empty(), "цена следующего уровня пуста", "нечего покупать")


## Снаряжение должно реально влиять на бой, иначе покупать его незачем.
func _test_gear_affects_damage(me: Node3D) -> void:
	_check(WEAPONS.gear_damage(2) > WEAPONS.gear_damage(0), "снаряжение усиливает урон",
		"%.2f против %.2f" % [WEAPONS.gear_damage(2), WEAPONS.gear_damage(0)])
	_check(WEAPONS.gear_cooldown(2) < WEAPONS.gear_cooldown(0), "снаряжение сокращает откат",
		"%.2f против %.2f" % [WEAPONS.gear_cooldown(2), WEAPONS.gear_cooldown(0)])
	await get_tree().physics_frame


func _grant(me: Node3D, amounts: Array) -> void:
	_set_stock(me, amounts)


func _set_stock(me: Node3D, amounts: Array) -> void:
	var copy := PackedInt32Array([0, 0, 0, 0])
	for i in RES.COUNT:
		copy[i] = int(amounts[i])
	me.stock.capacity = 1000
	me.stock.amounts = copy


## Клиент: уровень снаряжения хоста доезжает по сети, и подделать свой нельзя —
## хост перезапишет.
func _run_client() -> void:
	await get_tree().create_timer(5.0).timeout
	var host_player: Node3D = _world.get_node_or_null("Players/1")
	if host_player == null:
		_check(false, "персонаж хоста виден клиенту", "не найден")
		return
	_check(true, "персонаж хоста виден клиенту", "найден")
	_check(host_player.gear_tier > 0, "уровень снаряжения хоста доехал",
		"%s" % WEAPONS.gear_name(host_player.gear_tier))

	var me: Node3D = _world.local_player()
	if me == null:
		return
	me.gear_tier = 2
	await get_tree().create_timer(2.0).timeout
	_check(me.gear_tier == 0, "подделка снаряжения затёрта хостом",
		"выставил 2, стало %d" % me.gear_tier)
