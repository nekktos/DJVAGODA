extends Node3D
##
## Мир: grey-box карта из 4 зон, спавн игроков и переключение камеры.
##
## Геометрия карты строится процедурно (world_builder.gd) с фиксированным сидом,
## одинаково на всех пирах, поэтому по сети она НЕ реплицируется — только
## персонажи, через MultiplayerSpawner.
##
## Порядок спавна намеренно построен так, чтобы World уже был в дереве у обоих
## пиров ДО установления соединения (World — часть главной сцены, а не
## подгружается после коннекта). Иначе MultiplayerSpawner на клиенте не успевает
## появиться к моменту, когда хост присылает команду спавна.
##

const PLAYER_SCENE := preload("res://scenes/Player.tscn")
## Скрипт нужен отдельно, чтобы читать SPAWN_POINTS без зависимости от кэша
## глобальных классов (он строится только редактором).
const PLAYER_SCRIPT := preload("res://scripts/player.gd")
## То же и для строителя карты: обращаться к нему по class_name нельзя, кэш
## глобальных классов строится только редактором и на свежем клоне его нет.
const WORLD_BUILDER := preload("res://scripts/world_builder.gd")
const WEAPONS := preload("res://scripts/combat/weapons.gd")
const PROJECTILE_SCENE := preload("res://scenes/Projectile.tscn")
const CORPSE_SCENE := preload("res://scenes/Corpse.tscn")
const BUILDING_SCENE := preload("res://scenes/Building.tscn")
const CARAVAN_SCENE := preload("res://scenes/Caravan.tscn")
const LOOT_SCENE := preload("res://scenes/Loot.tscn")
const UNIT_SCENE := preload("res://scenes/Unit.tscn")
const LABOURER_SCENE := preload("res://scenes/Labourer.tscn")
const LABOURER := preload("res://scripts/units/labourer.gd")

## Сколько батраков у злодея в начале партии.
const STARTING_LABOURERS := 2
const RES := preload("res://scripts/economy/resources.gd")
const FACTIONS := preload("res://scripts/factions.gd")

## Казарма стражи стоит во дворце с начала партии: по GDD раздел 2.2 во дворце
## «уже есть и ресурсы, и здания». Без неё условие поражения стражи («казарма
## снесена И командир убит») было бы неопределимым — сносить нечего.
const GUARD_BARRACKS_POS := Vector3(332.0, 6.0, -238.0)

## На каком расстоянии от своего склада ресурсы «при себе» перекладываются в
## него сами. Отдельной кнопки нет намеренно: вклад должен быть очевидным
## следствием возвращения на базу, а не ещё одним действием, которое забывают.
const DEPOSIT_RANGE := 14.0
## Как часто хост проверяет, не стоит ли кто у своего склада.
const DEPOSIT_INTERVAL := 1.0

## Через сколько секунд после смерти игрок возвращается в мир.
## Временное правило (DESIGN_ANSWERS.md, пункт 10) — настоящие условия
## респавна решаются вместе с кампаниями.
const RESPAWN_DELAY := 5.0
## Сколько трупов держим в мире. GDD требует, чтобы труп не исчезал мгновенно,
## но копить их без предела нельзя.
const CORPSE_LIMIT := 30
## На каком расстоянии от верстака им можно пользоваться. Проверяет ХОСТ:
## иначе клиент выдавал бы себе протезы из любой точки карты.
const WORKBENCH_RANGE := 7.0
## То же для лавки торговца.
const TRADER_RANGE := 7.0

## Дебаг-ключ --netlog: раз в секунду печатать позиции всех персонажей — видно,
## доезжает ли чужое движение до этого пира.
const DEBUG_LOG_INTERVAL := 1.0

## Сменился режим камеры: true — стратегическая, false — экшен.
signal camera_mode_changed(strategy: bool)

@onready var _players: Node3D = $Players
@onready var _menu_camera: Camera3D = $MenuCamera
@onready var _strategy_camera: Camera3D = $StrategyCamera
@onready var _terrain: Node3D = $Terrain
@onready var _spawner: MultiplayerSpawner = $PlayerSpawner
@onready var _spawned: Node3D = $Spawned
@onready var _world_spawner: MultiplayerSpawner = $WorldSpawner
@onready var build_controller: Node3D = $BuildController
@onready var route_controller: Node3D = $RouteController
@onready var mine: Node3D = $Mine
@onready var objective: Node3D = $Objective
@onready var forest: Node3D = $Forest
@onready var commander: Node3D = $Commander
@onready var treasury: Node = $Treasury
@onready var diplomacy: Node = $Diplomacy
@onready var savegame: Node = $Save
@onready var garrison: Node = $Garrison
## ÐÐ ÑÐ²Ð¾Ð±Ð¾Ð´Ð½ÑÑ ÑÑÐ¾ÑÐ¾Ð½, ÑÑÑÐ¿ÐµÐ½Ñ Â«Ð±Â»: ÐºÑÐ¾ Ð¸ ÐºÑÐ´Ð° ÑÐ¾Ð´Ð¸Ñ Ð²Ð¾ÐµÐ²Ð°ÑÑ.
@onready var warband: Node = $Warband
## Пути по карте. Печёт сетку после стройки, считает только у хоста.
@onready var navigation: Node = $Navigation

var strategy_mode := false

var _netlog := false
## Сквозной номер для снарядов и трупов: имя ноды должно совпадать на всех
## пирах, иначе команда на удаление уедет не по тому пути.
var _spawn_counter := 0
var _corpses: Array[Node] = []
var _netlog_t := 0.0
var _deposit_t := 0.0


func _ready() -> void:
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	_netlog = args.has("--netlog")
	# Кастомная spawn_function: даёт положить в пакет спавна произвольные данные
	# (сейчас — номер слота, позже сюда же ляжет фракция).
	_spawner.spawn_function = _make_player
	_world_spawner.spawn_function = _make_spawned
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	Net.session_started.connect(_on_session_started)
	Net.session_ended.connect(_on_session_ended)

	var builder := WORLD_BUILDER.new()
	builder.build(_terrain)
	# Сетку печём сразу после стройки: ИИ ходит с первой секунды партии.
	navigation.bake(_terrain)
	# Лес зоны эльфов строит отдельная система: у него impostor-LOD и своя
	# адресация деревьев по индексу (GDD раздел 5, forest.gd).
	forest.build(
		WORLD_BUILDER.ZONE_CENTERS[WORLD_BUILDER.Zone.ELVES],
		WORLD_BUILDER.ZONE_HALF - 30.0,
		70.0,
		3615,
	)
	build_controller.place_requested.connect(_on_place_requested)
	route_controller.route_sent.connect(_on_route_sent)
	mine.position = WORLD_BUILDER.MINE_POS


func _process(delta: float) -> void:
	_tick_deposit(delta)
	if not _netlog or not Net.active:
		return
	_netlog_t += delta
	if _netlog_t < DEBUG_LOG_INTERVAL:
		return
	_netlog_t = 0.0
	var parts := PackedStringArray()
	for child in _players.get_children():
		var p: Vector3 = child.global_position
		parts.append("%s%s(%.1f, %.1f, %.1f)" % [
			child.name, "*" if child.is_multiplayer_authority() else "", p.x, p.y, p.z
		])
	print("[world] id=%d | %s" % [Net.local_id(), " ".join(parts)])


## Вклад: стоящий у своего достроенного склада перекладывает в него всё, что
## нёс при себе. Считает ТОЛЬКО хост — он же владеет казной.
##
## Отдельной кнопки нет намеренно: вклад должен быть очевидным следствием
## возвращения на базу, а не ещё одним действием, которое забывают нажать.
func _tick_deposit(delta: float) -> void:
	if not Net.hosting():
		return
	_deposit_t += delta
	if _deposit_t < DEPOSIT_INTERVAL:
		return
	_deposit_t = 0.0

	for child in _players.get_children():
		if not ("faction" in child) or not child.health.alive:
			continue
		if child.stock.carried_total() <= 0:
			continue
		var storage := storage_of(int(child.peer_id))
		if storage == null:
			continue
		if child.global_position.distance_to(storage.global_position) > DEPOSIT_RANGE:
			continue
		var moved: int = child.stock.deposit()
		if moved > 0:
			print("[склад] игрок %d сложил %d единиц" % [int(child.peer_id), moved])


# --- камера ----------------------------------------------------------------

## Свой персонаж на этом пире. null, если ещё не заспавнен.
func local_player() -> Node3D:
	if not Net.active:
		return null
	return _players.get_node_or_null(str(multiplayer.get_unique_id()))


## Стратегический режим есть у вожаков: у злодея по рождению, у командира
## стражи по повышению (GDD раздел 2.2).
##
## Погибший вожак не возрождается и остаётся НАБЛЮДАТЕЛЕМ: камера у него
## остаётся, чтобы он мог досмотреть партию, а управлять уже нечем.
func toggle_camera_mode() -> void:
	var player := local_player()
	if player != null and not player.has_strategy() and not is_spectating():
		return
	set_strategy_mode(not strategy_mode)


## Игрок стал наблюдателем: его вожак пал окончательно и не вернётся.
func is_spectating() -> bool:
	var player := local_player()
	return player != null and player.is_leader and not player.health.alive


func set_strategy_mode(on: bool, height: float = -1.0) -> void:
	var player := local_player()
	if player == null:
		return
	if on == strategy_mode:
		return
	strategy_mode = on
	# Персонаж продолжает симулироваться и реплицироваться в обоих режимах,
	# но в стратегическом не принимает управление: он стоит и уязвим.
	# Мёртвый вожак управления не получает никогда — он наблюдатель.
	player.control_enabled = not on and player.health.alive
	if not on:
		build_controller.set_active(false)
	if on:
		if height > 0.0:
			_strategy_camera.activate(player.global_position, height)
		else:
			_strategy_camera.activate(player.global_position)
	else:
		_strategy_camera.deactivate()
		player.set_view_active(true)
	camera_mode_changed.emit(on)


func strategy_height() -> float:
	return _strategy_camera.height()


# --- сессия и спавн --------------------------------------------------------

func _on_session_started() -> void:
	if Net.hosting():
		# Мир поднимаем ДО игроков: восстановленная казна и репутация должны
		# существовать к моменту, когда первый персонаж встанет в мир.
		savegame.load_world()
		_spawn_guard_barracks()
		_spawn_starting_labourers()
		_spawn_player(1, Net.chosen_faction, Net.profile_id)
	else:
		# Клиент сам просит хоста о спавне — к этому моменту его World точно
		# готов принять реплицированную ноду.
		_request_spawn.rpc_id(1, Net.chosen_faction, Net.profile_id)


## Два батрака злодея на старте партии.
##
## Именно два, и это не круглое число ради круглого: батрак стоит золота, а
## золото добывают батраки. С нуля петля не запускается вовсе, с одним — тянется
## томительно долго. Двое дают выбор с первой минуты: оба на лес, оба в шахту
## или один туда, другой сюда.
##
## Сторона, а не игрок: батраки принадлежат злодею как СТОРОНЕ и существуют,
## даже если за неё ещё никто не сел. Иначе ИИ, добывающий «как игрок», начинал
## бы партию с пустыми руками.
func _spawn_starting_labourers() -> void:
	if not labourers_of(FACTIONS.Kind.VILLAIN).is_empty():
		return
	var base: Vector3 = FACTIONS.SPAWN[FACTIONS.Kind.VILLAIN]
	for i in STARTING_LABOURERS:
		var angle := TAU * float(i) / float(STARTING_LABOURERS)
		var spot := base + Vector3(cos(angle) * 5.0, 0.5, sin(angle) * 5.0)
		spawn_labourer(FACTIONS.Kind.VILLAIN, spot, base, LABOURER.Role.LUMBERJACK)


## Казарма стражи во дворце. Ставится один раз на старте сессии и принадлежит
## СТОРОНЕ, а не игроку: она переживает уход любого конкретного стражника.
func _spawn_guard_barracks() -> void:
	for node in get_tree().get_nodes_in_group("building"):
		if "faction" in node and int(node.faction) == FACTIONS.Kind.GUARD:
			return
	spawn_building(RES.Building.SWORD_BARRACKS, GUARD_BARRACKS_POS, 0, FACTIONS.Kind.GUARD, true)


func _on_session_ended() -> void:
	if strategy_mode:
		strategy_mode = false
		_strategy_camera.deactivate()
		camera_mode_changed.emit(false)
	for child in _players.get_children():
		child.queue_free()
	_menu_camera.current = true


func _on_peer_disconnected(id: int) -> void:
	if not Net.hosting():
		return
	var node := _players.get_node_or_null(str(id))
	if node != null:
		node.queue_free()


@rpc("any_peer", "reliable")
func _request_spawn(wanted_faction: int, profile: String) -> void:
	if not Net.hosting():
		return
	_spawn_player(multiplayer.get_remote_sender_id(), wanted_faction, profile)


func _spawn_player(id: int, wanted_faction: int = 0, profile: String = "") -> void:
	if _players.has_node(str(id)):
		return
	var slot := _next_free_slot()
	if slot < 0:
		push_warning("Сессия заполнена, игроку %d места нет." % id)
		return

	# Вернувшийся игрок садится за СВОЮ прежнюю сторону, а не за выбранную в
	# меню: прогресс привязан к фракции (GDD раздел 6), и пересадить его значит
	# отобрать всё нажитое.
	var asked := wanted_faction
	var remembered: int = savegame.saved_faction(profile)
	if remembered >= 0:
		asked = remembered

	# Свободных слотов у стороны может не остаться — тогда сажаем в ближайшую
	# свободную и говорим об этом вслух, а не молча.
	var faction := _assign_faction(asked)
	if faction < 0:
		push_warning("Свободных сторон не осталось, игроку %d места нет." % id)
		return
	if faction != asked:
		Net.status_changed.emit("Сторона «%s» занята, игрок %d играет за «%s»." % [
			FACTIONS.name_of(asked), id, FACTIONS.name_of(faction)
		])

	print("[world] спавню игрока %d, сторона %s, слот %d" % [id, FACTIONS.name_of(faction), slot])
	var node := _spawner.spawn({"id": id, "slot": slot, "faction": faction, "profile": profile})
	if node != null:
		# Сигналы нужны только хосту: и снаряды, и смерть считает он.
		node.death_reported.connect(_on_player_death)
		node.projectile_requested.connect(_on_projectile_requested)
		# Злодей — вожак по рождению: он один человек с личной армией. Страж
		# становится вожаком повышением у NPC, эльфы — никогда.
		node.is_leader = FACTIONS.has_strategy(faction)
		# Стартовый запас больше не выдаётся персонажу: он лежит в казне фракции
		# и разложен там ещё до появления игроков (treasury.gd).
		# Прогресс накатываем ПОСЛЕ выставления роли: сохранение знает и о
		# командовании, и его решение важнее умолчания по стороне.
		savegame.restore_player(node)


## Выполняется на всех пирах с одними и теми же данными, поэтому имя ноды и
## слот совпадают везде.
func _make_player(data: Dictionary) -> Node:
	var player := PLAYER_SCENE.instantiate()
	# Имя == peer id: по нему персонаж на всех пирах определяет своего авторитета.
	player.name = str(data["id"])
	player.spawn_slot = int(data["slot"])
	player.profile_id = String(data.get("profile", ""))
	player.faction = int(data.get("faction", 0))
	return player


## Наименьший свободный слот. Считается только на хосте.
func _next_free_slot() -> int:
	var used := {}
	for child in _players.get_children():
		used[child.spawn_slot] = true
	for i in PLAYER_SCRIPT.SPAWN_POINTS.size():
		if not used.has(i):
			return i
	return -1


# --- бой: снаряды, трупы, респавн -----------------------------------------

## Общая фабрика для всего, что мир спавнит по сети. Выполняется на всех пирах
## с одинаковыми данными, поэтому имя и параметры совпадают везде.
func _make_spawned(data: Dictionary) -> Node:
	var node: Node
	match String(data["type"]):
		"projectile":
			node = PROJECTILE_SCENE.instantiate()
		"building":
			node = BUILDING_SCENE.instantiate()
		"caravan":
			node = CARAVAN_SCENE.instantiate()
		"loot":
			node = LOOT_SCENE.instantiate()
		"unit":
			node = UNIT_SCENE.instantiate()
		"labourer":
			node = LABOURER_SCENE.instantiate()
		_:
			node = CORPSE_SCENE.instantiate()
	node.name = "%s_%d" % [data["type"], int(data["id"])]
	node.setup(data)
	return node


## Стрела бойца-лучника. Отличается от игроцкой только тем, КТО стрелок: у бойца
## нет peer id, поэтому снаряд запоминает путь ноды и по нему исключает стрелка
## из собственного попадания.
func spawn_unit_arrow(origin: Vector3, dir: Vector3, shooter: Node3D) -> Node:
	if not Net.hosting() or shooter == null:
		return null
	_spawn_counter += 1
	return _world_spawner.spawn({
		"type": "projectile",
		"id": _spawn_counter,
		"kind": WEAPONS.Kind.BOW,
		"origin": origin,
		"dir": dir,
		"shooter": int(shooter.owner_id),
		"shooter_path": String(shooter.get_path()),
		"gear": 0,
	})


func _on_projectile_requested(kind: int, origin: Vector3, dir: Vector3, shooter_id: int, gear: int) -> void:
	if not Net.hosting():
		return
	_spawn_counter += 1
	_world_spawner.spawn({
		"type": "projectile",
		"id": _spawn_counter,
		"kind": kind,
		"origin": origin,
		"dir": dir,
		"shooter": shooter_id,
		# Уровень снаряжения кладём в пакет спавна, а не читаем у стрелка при
		# попадании: стрелок к тому моменту может быть уже мёртв или отключён.
		"gear": gear,
	})


func _on_player_death(player: Node3D, killer_id: int) -> void:
	if not Net.hosting():
		return
	print("[бой] %s убит игроком %d" % [player.name, killer_id])
	commander.report_kill(killer_id, int(player.faction))
	diplomacy.on_kill(int(player.faction), faction_of(killer_id), bool(player.is_leader))
	# Гибель стража может провалить его решающий удар; гибель вожака — засчитать
	# чужой. Порядок важен: сперва снимаем провал, потом засчитываем победителю.
	commander.report_guard_death(player)
	if player.is_leader:
		commander.report_leader_kill(killer_id, int(player.faction))
	_spawn_corpse(player)
	_drop_belongings(player)
	player.set_dead.rpc(true)

	# Вожак не возвращается. Злодей — один человек с личной армией, командир
	# стражи — тот, кто заслужил место: их смерть окончательна и является
	# условием победы противника (GDD раздел 7). Рядовые эльфы и стражники
	# возрождаются как раньше.
	if player.is_leader:
		print("[смерть] вожак %s пал окончательно" % player.name)
		objective.report_leader_down(int(player.faction), faction_of(killer_id))
		# Игрок остаётся в сессии наблюдателем: партия не обрывается победой,
		# и досмотреть её он должен с камеры, а не с собственного трупа.
		if int(player.peer_id) == 1:
			player.become_spectator()
		else:
			player.become_spectator.rpc_id(int(player.peer_id))
		return

	await get_tree().create_timer(RESPAWN_DELAY).timeout
	if not is_instance_valid(player):
		return
	# Здоровье возвращаем, РАНЕНИЯ — НЕТ (GDD раздел 4.1). Раньше здесь стоял
	# body.reset(), и это подрывало весь Этап 3: умереть и встать целым было
	# дешевле и быстрее, чем идти за протезом.
	player.health.revive()
	player.respawn_at_slot()
	player.set_dead.rpc(false)


## Смерть роняет всё, что персонаж нёс на себе: ресурсы при себе и купленный
## уровень снаряжения. Поднять может любой, кто подошёл, включая убийцу —
## ровно как груз разбитого каравана (GDD раздел 4.1).
##
## Базовое оружие не теряется никогда: без меча персонаж перестал бы быть
## персонажем. Теряется только купленный апгрейд.
func _drop_belongings(player: Node3D) -> void:
	var lost: PackedInt32Array = player.stock.drop_carried()
	var gear: int = int(player.gear_tier)
	player.gear_tier = 0

	var total := 0
	for value in lost:
		total += value
	if total <= 0 and gear <= 0:
		return

	_spawn_counter += 1
	_world_spawner.spawn({
		"type": "loot",
		"id": _spawn_counter,
		"point": player.global_position + Vector3.UP * 0.6,
		"contents": lost,
		"gear": gear,
	})
	print("[смерть] с игрока %d выпало %d единиц и снаряжение уровня %d"
		% [int(player.peer_id), total, gear])


func _spawn_corpse(player: Node3D) -> void:
	place_corpse(player.global_position, player.rotation.y, player.spawn_slot, player.body.severed_mask)


## Положить труп в заданной точке. Отдельным методом, потому что этим
## пользуются инструменты проверки (tools/screenshotter.gd).
func place_corpse(point: Vector3, yaw: float, slot: int, severed: int = 0) -> void:
	if not Net.hosting():
		return
	_spawn_counter += 1
	var corpse := _world_spawner.spawn({
		"type": "corpse",
		"id": _spawn_counter,
		"point": point,
		"yaw": yaw,
		"slot": slot,
		"severed": severed,
	})
	if corpse != null:
		_corpses.append(corpse)
	while _corpses.size() > CORPSE_LIMIT:
		var oldest: Node = _corpses.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()


## Где стоит верстак. Клиент по этому же значению решает, показывать ли подсказку.
func workbench_position() -> Vector3:
	return WORLD_BUILDER.WORKBENCH_POS


func is_at_workbench(point: Vector3) -> bool:
	var flat := Vector3(point.x, 0.0, point.z)
	return flat.distance_to(workbench_position()) <= WORKBENCH_RANGE


## Где стоит торговец эльфов. Он в их поселении: чужому туда дойти можно, но
## идти придётся через весь лес — торговля намеренно не бесплатна географически.
func trader_position() -> Vector3:
	return WORLD_BUILDER.TRADER_POS


func is_at_trader(point: Vector3) -> bool:
	var flat := Vector3(point.x, 0.0, point.z)
	return flat.distance_to(trader_position()) <= TRADER_RANGE


# --- стройка ---------------------------------------------------------------

## Поставить здание. Только на хосте: сюда попадают уже проверенные заявки
## (см. player.gd::request_build — там же списывается стоимость).
func spawn_building(kind: int, point: Vector3, owner_id: int, faction := -1, prebuilt := false) -> Node:
	if not Net.hosting():
		return null
	_spawn_counter += 1
	var side: int = faction if faction >= 0 else faction_of(owner_id)
	var node := _world_spawner.spawn({
		"type": "building",
		"id": _spawn_counter,
		"kind": kind,
		"point": point,
		"owner": owner_id,
		"faction": side,
		"prebuilt": prebuilt,
	})
	if node != null:
		print("[стройка] %s стороны «%s» в %s" % [RES.BUILDING_NAMES[kind], FACTIONS.name_of(side), point])
		node.completed.connect(_on_building_completed.bind(node))
		node.destroyed_on_server.connect(_on_building_destroyed)
	return node


## Постройка разрушена. Для стражи это половина условия поражения (GDD раздел 7):
## сломлена она, только когда пал командир И снесена казарма.
func _on_building_destroyed(building: Node3D, killer_id: int) -> void:
	if not Net.hosting():
		return
	objective.check_victories()
	if building != null and "faction" in building:
		diplomacy.on_building_destroyed(int(building.faction), faction_of(killer_id))


## Достроенный склад поднимает владельцу потолок хранения — по GDD это
## «главное здание, оно же склад и пункт приёма ресурсов».
func _on_building_completed(node: Node) -> void:
	if not Net.hosting() or node == null:
		return
	if int(node.kind) != RES.Building.STORAGE:
		return
	var owner_player := _players.get_node_or_null(str(int(node.owner_id)))
	if owner_player != null:
		owner_player.stock.raise_capacity(RES.STORAGE_BONUS)
		print("[стройка] склад достроен, потолок игрока %d поднят" % int(node.owner_id))


## Клик по земле в режиме стройки: заявку отправляет свой персонаж — у него
## есть и владелец, и запас ресурсов.
func _on_place_requested(kind: int, point: Vector3) -> void:
	var me := local_player()
	if me != null:
		me.ask_build(kind, point)
	build_controller.set_active(false)


## Стройка живёт только в стратегической камере.
func set_build_mode(on: bool, kind: int = -1) -> void:
	if on and not strategy_mode:
		return
	if kind >= 0:
		build_controller.select(kind)
	build_controller.set_active(on)


# --- караван ---------------------------------------------------------------

## Игрок дорисовал маршрут и нажал Enter.
func _on_route_sent(points: PackedVector3Array) -> void:
	var me := local_player()
	if me != null:
		me.ask_send_caravan(points)


## Прокладка маршрута живёт только в стратегической камере.
func set_route_mode(on: bool) -> void:
	if on and not strategy_mode:
		return
	if on:
		build_controller.set_active(false)
		# Снимаем фокус с любого элемента интерфейса. Сфокусированные Button и
		# LineEdit съедают Enter в фазе GUI, до _unhandled_input, и отправка
		# каравана молча не срабатывает. Живой тестер сообщил ровно это:
		# маршрут рисуется, Enter не отправляет. Причину по одному его логу
		# восстановить не вышло, поэтому убираем весь класс причин сразу.
		get_viewport().gui_release_focus()
	route_controller.set_active(on)


## Ближайший ДОСТРОЕННЫЙ склад игрока. Без него каравану некуда возвращаться.
func storage_of(owner_id: int) -> Node3D:
	for node in get_tree().get_nodes_in_group("building"):
		var building := node as Node3D
		if building == null:
			continue
		if int(building.kind) != RES.Building.STORAGE:
			continue
		if int(building.owner_id) != owner_id:
			continue
		if float(building.progress) < 1.0:
			continue
		return building
	return null


## Отправить караван. Только на хосте: маршрут сюда попадает уже проверенным
## (см. player.gd::request_send_caravan).
func spawn_caravan(route: PackedVector3Array, owner_id: int) -> Node:
	if not Net.hosting():
		return null
	_spawn_counter += 1
	var node := _world_spawner.spawn({
		"type": "caravan",
		"id": _spawn_counter,
		"route": route,
		"owner": owner_id,
	})
	if node != null:
		print("[караван] игрок %d отправил караван, точек в маршруте: %d" % [owner_id, route.size()])
		node.destroyed.connect(_on_caravan_destroyed.bind(owner_id))
	return node


## Разбитый караван высыпает груз на землю: подобрать может любой
## (DESIGN_ANSWERS.md, пункт 15).
func _on_caravan_destroyed(point: Vector3, cargo: PackedInt32Array, killer_id: int, caravan_owner: int) -> void:
	if not Net.hosting():
		return
	# Приказ стражи «перехватить караван» засчитывается тут же: командир сам
	# решит, его ли это караван и тот ли игрок его разбил.
	commander.report_caravan_destroyed(killer_id, faction_of(caravan_owner))
	diplomacy.on_caravan_destroyed(faction_of(caravan_owner), faction_of(killer_id))
	var total := 0
	for value in cargo:
		total += value
	if total <= 0:
		return
	_spawn_counter += 1
	_world_spawner.spawn({
		"type": "loot",
		"id": _spawn_counter,
		"point": point,
		"contents": cargo,
	})


## Боец погиб. Приказ стражи «проредить войско злодея» засчитывает и бойцов,
## а не только самого злодея.
func report_unit_kill(killer_id: int, victim_faction: int) -> void:
	if not Net.hosting():
		return
	commander.report_kill(killer_id, victim_faction)


## Нанять батрака. Считает и спавнит ТОЛЬКО хост.
##
## Владельца батрак не имеет (owner_id = 0), как гарнизон: он принадлежит
## СТОРОНЕ, а не персонажу. Так его переживают смерть игрока и смена персонажа,
## и так же его сможет нанимать ИИ, когда до этого дойдёт.
func spawn_labourer(faction: int, point: Vector3, home_point: Vector3, role: int) -> Node:
	if not Net.hosting():
		return null
	_spawn_counter += 1
	var node := _world_spawner.spawn({
		"type": "labourer",
		"id": _spawn_counter,
		"owner": 0,
		"slot": labourers_of(faction).size(),
		"point": point,
		"beast": false,
		"champion": false,
		"faction": faction,
		"home": home_point,
		"leash": 0.0,
		"role": role,
	})
	if node != null:
		print("[батраки] %s: нанят %s, всего %d" % [FACTIONS.name_of(faction),
			node.role_name(), labourers_of(faction).size()])
	return node


## Батраки стороны, живые в этот момент.
func labourers_of(faction: int) -> Array:
	var found := []
	for node in get_tree().get_nodes_in_group("unit"):
		if not is_instance_valid(node) or not ("sync_role" in node):
			continue
		if int(node.faction) == faction:
			found.append(node)
	return found


## Караваны игрока, живые в этот момент.
func caravans_of(owner_id: int) -> Array:
	var found := []
	for child in _spawned.get_children():
		if child.has_method("state_text") and int(child.owner_id) == owner_id:
			found.append(child)
	return found


# --- отряд -----------------------------------------------------------------

## Ближайшая ДОСТРОЕННАЯ казарма игрока.
func barracks_of(owner_id: int, kind: int = RES.Building.SWORD_BARRACKS) -> Node3D:
	for node in get_tree().get_nodes_in_group("building"):
		var building := node as Node3D
		if building == null:
			continue
		if int(building.kind) != kind:
			continue
		if int(building.owner_id) != owner_id or float(building.progress) < 1.0:
			continue
		return building
	return null


## Живые бойцы игрока.
func units_of(owner_id: int) -> Array:
	var found := []
	for child in _spawned.get_children():
		if child.is_in_group("unit") and int(child.owner_id) == owner_id:
			found.append(child)
	return found


## Нанять бойца. Только на хосте: заявка сюда попадает уже проверенной
## (см. player.gd::request_train_unit).
func spawn_unit(owner_id: int, slot: int, point: Vector3, beast: bool = false,
		archer: bool = false) -> Node:
	if not Net.hosting():
		return null
	_spawn_counter += 1
	var node := _world_spawner.spawn({
		"type": "unit",
		"id": _spawn_counter,
		"owner": owner_id,
		"slot": slot,
		"point": point,
		"beast": beast,
		"archer": archer,
		"faction": faction_of(owner_id),
	})
	if node != null:
		if beast:
			print("[призыв] игрок %d призвал волка, слот %d" % [owner_id, slot])
		else:
			print("[отряд] игрок %d нанял %s, слот %d"
				% [owner_id, "лучника" if archer else "мечника", slot])
	return node


# --- фракции ---------------------------------------------------------------

## Какие стороны уже заняты в сессии.
func taken_factions() -> Array:
	var taken := []
	for child in _players.get_children():
		if "faction" in child:
			taken.append(int(child.faction))
	return taken


func faction_of(peer: int) -> int:
	var node := _players.get_node_or_null(str(peer))
	return int(node.faction) if node != null and "faction" in node else -1


## Выдать сторону: запрошенную, если свободна, иначе первую свободную.
## Выдать сторону: запрошенную, если в ней есть место, иначе первую свободную.
##
## Сторона больше не уникальна — у эльфов и стражи по нескольку слотов
## (FACTIONS.SLOTS). Уникален только злодей.
func _assign_faction(wanted: int) -> int:
	if wanted >= 0 and wanted < FACTIONS.COUNT and _has_room(wanted):
		return wanted
	for i in FACTIONS.COUNT:
		if _has_room(i):
			return i
	return -1


func _has_room(faction: int) -> bool:
	return players_of(faction).size() < FACTIONS.slots(faction)


func players_of(faction: int) -> Array:
	var found := []
	for child in _players.get_children():
		if "faction" in child and int(child.faction) == faction:
			found.append(child)
	return found


## Боец гарнизона свободной стороны (Этап 10, шаг 8а).
##
## Отличается от бойца игрока двумя вещами: у него нет владельца-пира (сторона
## задана прямо) и есть ДОМ с поводком — он обороняет зону, а не ходит за
## командиром.
func spawn_garrison_unit(faction: int, slot: int, point: Vector3, home: Vector3, leash: float,
		champion := false) -> Node:
	if not Net.hosting():
		return null
	_spawn_counter += 1
	return _world_spawner.spawn({
		"type": "unit",
		"id": _spawn_counter,
		# Владельца нет: ноль не совпадает ни с одним peer id, поэтому командира
		# такой боец не найдёт никогда и останется на посту.
		"owner": 0,
		"slot": slot,
		"point": point,
		"beast": false,
		"champion": champion,
		"faction": faction,
		"home": home,
		"leash": leash,
	})
