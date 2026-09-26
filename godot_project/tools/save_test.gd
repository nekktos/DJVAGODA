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
	expected_host = 42
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

	_clear_leftovers()

	_test_profile(me)
	await _test_round_trip(me)
	_test_faction_memory(me)
	_test_restore_is_once(me)
	# Стройки — ПОСЛЕДНИМИ, и это не вкусовщина: проверка «второй раз прогресс
	# не накатывается» читает список уже восстановленных профилей, а любая
	# загрузка мира его очищает. Стоя раньше, эта проверка роняла ту.
	await _test_buildings(me)
	await _test_labourers(me)
	await _test_squad(me)

	if not multiplayer.get_peers().is_empty():
		await get_tree().create_timer(6.0).timeout
	finish()


func _save() -> Node:
	return _world.savegame


## Начать с ЧИСТОГО мира — и файла, и того, что уже стоит на карте.
##
## Набор гоняют по многу раз подряд, а стройки и батраки теперь сохраняются.
## Файл проверки живёт между прогонами намеренно: иначе круговорот «сохранили —
## испортили — загрузили» нечего было бы проверять. Но сессия успевает
## ЗАГРУЗИТЬ его раньше, чем начнётся проверка, поэтому стереть один файл мало —
## прошлые дома и работники уже стоят в мире и уедут в новый файл. Прогон за
## прогоном мир пух бы без конца, и однажды набор упал бы не на ошибке, а на
## собственном мусоре, а искали бы её в коде.
func _clear_leftovers() -> void:
	DirAccess.remove_absolute(_save().save_path())
	for node in _buildings():
		if is_instance_valid(node):
			node.free()
	for node in get_tree().get_nodes_in_group("unit"):
		if is_instance_valid(node) and "sync_role" in node:
			node.free()


func _buildings() -> Array:
	return get_tree().get_nodes_in_group("building")


## Кто есть у стороны, по ремёслам, в порядке возрастания. Сравнивать надо
## именно состав: вернуть четверых лесорубов вместо двух лесорубов и двух
## рудокопов значит вернуть не тех батраков, а число сойдётся.
func _roles(side: int) -> Array:
	var roles := []
	for node in _world.labourers_of(side):
		roles.append(int(node.sync_role))
	roles.sort()
	return roles


## Нанятый отряд переживает перезаход, а призванный волк — нет.
##
## Разница не придирка. Мечник куплен за золото и стоит в отряде, пока его не
## убьют; волк призван заклинанием и живёт считанные минуты по своему таймеру.
## Вернуть волка — значит выдумать его заново, и сделать это молча.
##
## Отряд лежит в разделе ПРОФИЛЯ, а не мира: сетевой id при следующем входе
## другой, и владельца бойцам назначают в момент спавна персонажа. Поэтому и
## проверяем через `restore_player`, а не через `load_world`.
func _test_squad(me: Node3D) -> void:
	var peer: int = int(me.peer_id)
	for node in _world.units_of(peer):
		node.free()
	await get_tree().physics_frame

	var at: Vector3 = me.global_position
	_world.spawn_unit(peer, 0, at + Vector3(4.0, 1.0, 0.0), false, false)
	_world.spawn_unit(peer, 1, at + Vector3(-4.0, 1.0, 0.0), false, false)
	_world.spawn_unit(peer, 2, at + Vector3(0.0, 1.0, 4.0), false, true)
	_world.spawn_unit(peer, 3, at + Vector3(0.0, 1.0, -4.0), true, false)
	await get_tree().physics_frame
	check(_world.units_of(peer).size() == 4, "отряд набран, и с ним волк",
		"%d при хозяине" % _world.units_of(peer).size())

	_save().save_world()
	for node in _world.units_of(peer):
		node.free()
	await get_tree().physics_frame
	check(_world.units_of(peer).is_empty(), "перед возвращением отряда нет",
		"%d осталось" % _world.units_of(peer).size())

	# Профиль в этой сессии уже восстановлен, и второй раз накатывать нельзя —
	# это проверено отдельно выше. Здесь воспроизводится НОВЫЙ вход: список
	# восстановленных чистится ровно так же, как его чистит загрузка мира.
	_save()._restored.clear()
	check(_save().restore_player(me), "прогресс накатан как при новом входе", "успех")
	await get_tree().physics_frame

	var back: Array = _world.units_of(peer)
	check(back.size() == 3, "ОТРЯД вернулся, а волк нет", "%d бойцов" % back.size())
	var archers := 0
	for node in back:
		if bool(node.is_archer):
			archers += 1
	check(archers == 1, "и лучник вернулся лучником", "%d из %d" % [archers, back.size()])


## Батраки переживают перезаход: каждый нанят за золото.
func _test_labourers(me: Node3D) -> void:
	var side: int = int(me.faction)
	var base := Vector3(150.0, 0.0, 30.0)
	# Двоих и РАЗНЫХ ремёсел: стартовых батраков сторона проверки не имеет
	# (их получает только злодей), а с одинаковыми проверка состава была бы
	# неотличима от проверки числа.
	_world.spawn_labourer(side, base + Vector3(1.0, 0.5, 0.0), base, 0)
	_world.spawn_labourer(side, base + Vector3(-1.0, 0.5, 0.0), base, 2)
	await get_tree().physics_frame
	var before: Array = _roles(side)
	check(before.size() >= 2, "батраки у стороны есть", "%d штук" % before.size())
	check(before[0] != before[before.size() - 1], "и они разных ремёсел", str(before))

	_save().save_world()
	for node in _world.labourers_of(side):
		node.free()
	await get_tree().physics_frame
	check(_roles(side).is_empty(), "перед загрузкой батраков нет",
		"%d осталось" % _roles(side).size())

	check(_save().load_world(), "мир загружен с батраками", "успех")
	await get_tree().physics_frame
	check(_roles(side).size() == before.size(), "БАТРАКИ вернулись",
		"%d из %d" % [_roles(side).size(), before.size()])
	check(_roles(side) == before, "и вернулись при своих ремёслах",
		"%s вместо %s" % [str(_roles(side)), str(before)])


## Постройки переживают перезаход.
##
## Проверять надо не только «дом вернулся», но и «потолок склада не удвоился».
## Достроенный склад поднимает стороне потолок хранения, а сам потолок лежит в
## сейве отдельно: если восстановленный склад засчитывается как достроенный
## заново, потолок растёт на бонус при каждом заходе в мир. Это тот случай,
## когда починка одной дыры открывает другую, и увидеть её можно только здесь.
func _test_buildings(me: Node3D) -> void:
	var wallet: Node = _world.treasury.of(me.faction)
	var cap_before: int = int(wallet.stored.capacity)
	var spot := Vector3(140.0, 0.0, -60.0)
	_world.spawn_building(RES.Building.STORAGE, spot, 1, int(me.faction), true)
	await get_tree().physics_frame
	var before: int = _buildings().size()
	check(before >= 1, "постройка стоит на карте", "%d штук" % before)

	_save().save_world()
	for node in _buildings():
		node.free()
	await get_tree().physics_frame
	check(_buildings().is_empty(), "перед загрузкой снесли всё",
		"%d осталось" % _buildings().size())

	check(_save().load_world(), "мир загружен со стройками", "успех")
	await get_tree().physics_frame
	check(_buildings().size() == before, "ПОСТРОЙКИ вернулись",
		"%d из %d" % [_buildings().size(), before])
## Место постройки — это X и Z, а не три координаты.
##
## Высоту дом выбирает САМ: он садится полом на самую высокую точку земли под
## собой и встаёт на сваи (см. `building.gd::_apply_footing`). Сравнение в трёх
## измерениях проверяло бы заодно и рельеф под складом, а он к сохранению
## отношения не имеет — обе проверки упали в тот же день, когда появились сваи.
	var found := false
	for node in _buildings():
		var gap := Vector2(node.position.x - spot.x, node.position.z - spot.z)
		if gap.length() < 0.5 and int(node.kind) == RES.Building.STORAGE:
			found = true
	check(found, "склад вернулся на своё место", "(%.0f, %.0f)" % [spot.x, spot.z])

	# Двух кадров хватает: сигнал о достройке идёт из _process, а не из _ready.
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(int(wallet.stored.capacity) == cap_before, "потолок склада не удвоился",
		"было %d, стало %d" % [cap_before, int(wallet.stored.capacity)])


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
	var wallet: Node = _world.treasury.of(me.faction)

	# Ставим заметное состояние.
	objective.palace_owner = FACTIONS.Kind.ELVES
	wallet.carried.amounts = PackedInt32Array([1, 2, 3, 4])
	wallet.stored.capacity = 777
	# Лошади — имущество стороны, и дорогое: до дюжины по 25 золота и 12 железа.
	wallet.horses = 9
	wallet.horses_out = 4
	me.gear_tier = 2
	me.orders_done = 4
	me.harness_size = 5
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
	wallet.carried.amounts = PackedInt32Array([0, 0, 0, 0])
	wallet.stored.capacity = 0
	wallet.horses = 0
	wallet.horses_out = 0
	await get_tree().physics_frame

	check(_save().load_world(), "мир загружен", "успех")
	check(int(objective.palace_owner) == FACTIONS.Kind.ELVES, "владелец дворца вернулся",
		FACTIONS.name_of(int(objective.palace_owner)))
	# Допуск, а не точное равенство: дрейф репутации тикает каждый кадр и
	# успевает сдвинуть значение между загрузкой и проверкой. Это он и должен
	# делать — сравнивать здесь до шестого знака было бы проверкой дрейфа, а не
	# сохранения.
	check(wallet.carried.get_amount(RES.Kind.IRON) == 4, "казна «при себе» вернулась",
		"железа %d" % wallet.carried.get_amount(RES.Kind.IRON))
	check(wallet.stored.capacity == 777, "потолок склада вернулся",
		"%d" % wallet.stored.capacity)
	check(int(wallet.horses) == 9, "ЛОШАДИ вернулись", "%d в конюшне" % int(wallet.horses))
	# Уведённые с обозом возвращаются в конюшню, а не остаются занятыми:
	# обозов после загрузки нет ни одного, и «занятые» лошади висели бы вечно.
	check(int(wallet.horses_out) == 0, "уведённые лошади вернулись в конюшню",
		"занято %d, свободно %d" % [int(wallet.horses_out), wallet.horses_free()])

	# Состояние персонажа накатывается отдельно, при спавне.
	me.gear_tier = 0
	me.orders_done = 0
	me.harness_size = 2
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
	check(int(me.harness_size) == 5, "выбор упряжки вернулся",
		"%d лошадей" % int(me.harness_size))
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
