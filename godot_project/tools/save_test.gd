extends "res://tools/test_base.gd"
##
## Автопроверка сохранений и профиля игрока (Этап 10, шаг 5, GDD раздел 6).
## Работает headless.
##
## Запуск:
##   godot --headless --path godot_project -- --host --faction=2 --savetest
##   godot --headless --path godot_project -- --join=127.0.0.1 --faction=1 --savetest
##

const FACTIONS := preload("res://scripts/factions.gd")
const RES := preload("res://scripts/economy/resources.gd")

var _world: Node3D


func start(world: Node3D) -> void:
	tag = "сейв"
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

	if not Net.hosting():
		await _run_client(me)
		finish()
		return

	_test_profile(me)
	await _test_round_trip(me)
	_test_faction_memory(me)
	_test_restore_is_once(me)

	if not multiplayer.get_peers().is_empty():
		await get_tree().create_timer(6.0).timeout
	finish()


func _save() -> Node:
	return _world.savegame


## Профиль устойчив и НЕ равен сетевому id: именно в этом весь смысл.
func _test_profile(me: Node3D) -> void:
	check(not Net.profile_id.is_empty(), "профиль заведён", Net.profile_id)
	check(Net.profile_id != str(Net.local_id()), "профиль не равен сетевому id",
		"профиль %s, peer %d" % [Net.profile_id, Net.local_id()])
	check(String(me.profile_id) == Net.profile_id, "профиль доехал до персонажа",
		String(me.profile_id))
	check(not _save().world_id.is_empty(), "у мира есть свой идентификатор",
		_save().world_id)


## Сохранили — испортили всё в памяти — загрузили — вернулось.
func _test_round_trip(me: Node3D) -> void:
	var objective: Node = _world.objective
	var dip: Node = _world.diplomacy
	var wallet: Node = _world.treasury.of(me.faction)

	# Ставим заметное состояние.
	objective.palace_owner = FACTIONS.Kind.ELVES
	dip.values = PackedFloat32Array([11.0, 22.0, 33.0])
	wallet.carried.amounts = PackedInt32Array([1, 2, 3, 4])
	wallet.stored.capacity = 777
	me.gear_tier = 2
	me.orders_done = 4
	me.body.severed_mask = 0b0100
	me.body.bandages = 7
	# Трофеи и вставленный глаз — то, что копится ДОЛЬШЕ одного захода.
	me.trophies = PackedInt32Array([3, 7, 11])
	me.body.eyes_lost = 2
	me.body.eye_implants = 1
	await get_tree().physics_frame

	var path: String = _save().save_world()
	check(not path.is_empty(), "мир сохранён", path)
	check(_save().has_save(), "файл сохранения на месте", "есть")

	# Портим всё.
	objective.palace_owner = FACTIONS.Kind.VILLAIN
	dip.values = PackedFloat32Array([-99.0, -99.0, -99.0])
	wallet.carried.amounts = PackedInt32Array([0, 0, 0, 0])
	wallet.stored.capacity = 0
	await get_tree().physics_frame

	check(_save().load_world(), "мир загружен", "успех")
	check(int(objective.palace_owner) == FACTIONS.Kind.ELVES, "владелец дворца вернулся",
		FACTIONS.name_of(int(objective.palace_owner)))
	# Допуск, а не точное равенство: дрейф репутации тикает каждый кадр и
	# успевает сдвинуть значение между загрузкой и проверкой. Это он и должен
	# делать — сравнивать здесь до шестого знака было бы проверкой дрейфа, а не
	# сохранения.
	check(absf(dip.values[0] - 11.0) < 1.0, "отношения фракций вернулись",
		"%.2f вместо -99" % dip.values[0])
	check(wallet.carried.get_amount(RES.Kind.IRON) == 4, "казна «при себе» вернулась",
		"железа %d" % wallet.carried.get_amount(RES.Kind.IRON))
	check(wallet.stored.capacity == 777, "потолок склада вернулся",
		"%d" % wallet.stored.capacity)

	# Состояние персонажа накатывается отдельно, при спавне.
	me.gear_tier = 0
	me.orders_done = 0
	me.body.severed_mask = 0
	me.body.bandages = 0
	me.trophies = PackedInt32Array([0, 0, 0])
	me.body.eyes_lost = 0
	me.body.eye_implants = 0
	check(_save().restore_player(me), "прогресс персонажа накатан", "успех")
	check(int(me.gear_tier) == 2, "снаряжение вернулось", "уровень %d" % int(me.gear_tier))
	check(int(me.orders_done) == 4, "служба вернулась", "%d приказов" % int(me.orders_done))
	check(int(me.body.severed_mask) == 0b0100, "РАНЕНИЯ вернулись",
		"маска %d" % int(me.body.severed_mask))
	check(int(me.body.bandages) == 7, "бинты вернулись", "%d" % int(me.body.bandages))
	# Некротический протез стоит десять чужих конечностей одного вида, и набрать
	# столько за один заход почти нельзя. Не переживи счёт выход — самый дорогой
	# протез в игре стал бы недостижимым для всех, кто хоть раз вышел.
	check(me.trophies[0] == 3 and me.trophies[1] == 7 and me.trophies[2] == 11,
		"ТРОФЕИ вернулись", "рук %d, ног %d, глаз %d" % [
			me.trophies[0], me.trophies[1], me.trophies[2]
		])
	# Выбитые глаза сохранялись и раньше, вставленные — нет: вернувшийся
	# оказывался слепым на глаз, за который уже заплатил.
	check(int(me.body.eye_implants) == 1 and int(me.body.eyes_lost) == 2,
		"вставленный глаз вернулся вместе с выбитыми",
		"выбито %d, вставлено %d" % [int(me.body.eyes_lost), int(me.body.eye_implants)])


## Прогресс привязан к фракции: вернувшийся садится за свою прежнюю сторону.
func _test_faction_memory(me: Node3D) -> void:
	var remembered: int = _save().saved_faction(String(me.profile_id))
	check(remembered == int(me.faction), "сторона профиля запомнена",
		FACTIONS.name_of(remembered))
	check(_save().saved_faction("незнакомый-профиль") < 0, "чужой профиль не узнан", "-1")
	check(_save().saved_faction("") < 0, "пустой профиль не узнан", "-1")


## Дважды за сессию прогресс не накатывается: иначе повторный спавн затирал бы
## то, что игрок успел нажить после возвращения.
func _test_restore_is_once(me: Node3D) -> void:
	me.gear_tier = 0
	check(not _save().restore_player(me), "второй раз прогресс не накатывается", "отказ")
	check(int(me.gear_tier) == 0, "нажитое после возврата не затирается",
		"уровень %d" % int(me.gear_tier))


## Клиент: у него свой профиль, и сохраняет мир не он.
func _run_client(me: Node3D) -> void:
	check(not Net.profile_id.is_empty(), "у клиента свой профиль", Net.profile_id)
	var host_player: Node3D = _world.get_node_or_null("Players/1")
	check(host_player != null and String(host_player.profile_id) != Net.profile_id,
		"профили хоста и клиента различаются",
		"клиент %s" % Net.profile_id)
	check(String(me.profile_id) == Net.profile_id, "профиль клиента доехал до его персонажа",
		String(me.profile_id))
	check(_world.savegame.save_world().is_empty(), "клиент мир не сохраняет",
		"отказано")
	await get_tree().create_timer(1.0).timeout
