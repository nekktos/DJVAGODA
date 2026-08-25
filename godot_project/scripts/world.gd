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
const PROJECTILE_SCENE := preload("res://scenes/Projectile.tscn")
const CORPSE_SCENE := preload("res://scenes/Corpse.tscn")
const BUILDING_SCENE := preload("res://scenes/Building.tscn")
const CARAVAN_SCENE := preload("res://scenes/Caravan.tscn")
const LOOT_SCENE := preload("res://scenes/Loot.tscn")
const UNIT_SCENE := preload("res://scenes/Unit.tscn")
const RES := preload("res://scripts/economy/resources.gd")

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

var strategy_mode := false

var _netlog := false
## Сквозной номер для снарядов и трупов: имя ноды должно совпадать на всех
## пирах, иначе команда на удаление уедет не по тому пути.
var _spawn_counter := 0
var _corpses: Array[Node] = []
var _netlog_t := 0.0


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
	build_controller.place_requested.connect(_on_place_requested)
	route_controller.route_sent.connect(_on_route_sent)
	mine.position = WORLD_BUILDER.MINE_POS


func _process(delta: float) -> void:
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


# --- камера ----------------------------------------------------------------

## Свой персонаж на этом пире. null, если ещё не заспавнен.
func local_player() -> Node3D:
	if not Net.active:
		return null
	return _players.get_node_or_null(str(multiplayer.get_unique_id()))


func toggle_camera_mode() -> void:
	set_strategy_mode(not strategy_mode)


func set_strategy_mode(on: bool, height: float = -1.0) -> void:
	var player := local_player()
	if player == null:
		return
	if on == strategy_mode:
		return
	strategy_mode = on
	# Персонаж продолжает симулироваться и реплицироваться в обоих режимах,
	# но в стратегическом не принимает управление: он стоит и уязвим.
	player.control_enabled = not on
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
	if multiplayer.is_server():
		_spawn_player(1)
	else:
		# Клиент сам просит хоста о спавне — к этому моменту его World точно
		# готов принять реплицированную ноду.
		_request_spawn.rpc_id(1)


func _on_session_ended() -> void:
	if strategy_mode:
		strategy_mode = false
		_strategy_camera.deactivate()
		camera_mode_changed.emit(false)
	for child in _players.get_children():
		child.queue_free()
	_menu_camera.current = true


func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	var node := _players.get_node_or_null(str(id))
	if node != null:
		node.queue_free()


@rpc("any_peer", "reliable")
func _request_spawn() -> void:
	if not multiplayer.is_server():
		return
	_spawn_player(multiplayer.get_remote_sender_id())


func _spawn_player(id: int) -> void:
	if _players.has_node(str(id)):
		return
	var slot := _next_free_slot()
	if slot < 0:
		push_warning("Сессия заполнена, игроку %d места нет." % id)
		return
	print("[world] спавню игрока %d в слот %d" % [id, slot])
	var node := _spawner.spawn({"id": id, "slot": slot})
	if node != null:
		# Сигналы нужны только хосту: и снаряды, и смерть считает он.
		node.death_reported.connect(_on_player_death)
		node.projectile_requested.connect(_on_projectile_requested)


## Выполняется на всех пирах с одними и теми же данными, поэтому имя ноды и
## слот совпадают везде.
func _make_player(data: Dictionary) -> Node:
	var player := PLAYER_SCENE.instantiate()
	# Имя == peer id: по нему персонаж на всех пирах определяет своего авторитета.
	player.name = str(data["id"])
	player.spawn_slot = int(data["slot"])
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
		_:
			node = CORPSE_SCENE.instantiate()
	node.name = "%s_%d" % [data["type"], int(data["id"])]
	node.setup(data)
	return node


func _on_projectile_requested(kind: int, origin: Vector3, dir: Vector3, shooter_id: int) -> void:
	if not multiplayer.is_server():
		return
	_spawn_counter += 1
	_world_spawner.spawn({
		"type": "projectile",
		"id": _spawn_counter,
		"kind": kind,
		"origin": origin,
		"dir": dir,
		"shooter": shooter_id,
	})


func _on_player_death(player: Node3D, killer_id: int) -> void:
	if not multiplayer.is_server():
		return
	print("[бой] %s убит игроком %d" % [player.name, killer_id])
	_spawn_corpse(player)
	player.set_dead.rpc(true)

	await get_tree().create_timer(RESPAWN_DELAY).timeout
	if not is_instance_valid(player):
		return
	player.health.revive()
	player.body.reset()
	player.respawn_at_slot()
	player.set_dead.rpc(false)


func _spawn_corpse(player: Node3D) -> void:
	place_corpse(player.global_position, player.rotation.y, player.spawn_slot, player.body.severed_mask)


## Положить труп в заданной точке. Отдельным методом, потому что этим
## пользуются инструменты проверки (tools/screenshotter.gd).
func place_corpse(point: Vector3, yaw: float, slot: int, severed: int = 0) -> void:
	if not multiplayer.is_server():
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


# --- стройка ---------------------------------------------------------------

## Поставить здание. Только на хосте: сюда попадают уже проверенные заявки
## (см. player.gd::request_build — там же списывается стоимость).
func spawn_building(kind: int, point: Vector3, owner_id: int) -> Node:
	if not multiplayer.is_server():
		return null
	_spawn_counter += 1
	var node := _world_spawner.spawn({
		"type": "building",
		"id": _spawn_counter,
		"kind": kind,
		"point": point,
		"owner": owner_id,
	})
	if node != null:
		print("[стройка] игрок %d ставит %s в %s" % [owner_id, RES.BUILDING_NAMES[kind], point])
		node.completed.connect(_on_building_completed.bind(node))
	return node


## Достроенный склад поднимает владельцу потолок хранения — по GDD это
## «главное здание, оно же склад и пункт приёма ресурсов».
func _on_building_completed(node: Node) -> void:
	if not multiplayer.is_server() or node == null:
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
	if not multiplayer.is_server():
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
		node.destroyed.connect(_on_caravan_destroyed)
	return node


## Разбитый караван высыпает груз на землю: подобрать может любой
## (DESIGN_ANSWERS.md, пункт 15).
func _on_caravan_destroyed(point: Vector3, cargo: PackedInt32Array) -> void:
	if not multiplayer.is_server():
		return
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


## Караваны игрока, живые в этот момент.
func caravans_of(owner_id: int) -> Array:
	var found := []
	for child in _spawned.get_children():
		if child.has_method("state_text") and int(child.owner_id) == owner_id:
			found.append(child)
	return found


# --- отряд -----------------------------------------------------------------

## Ближайшая ДОСТРОЕННАЯ казарма игрока.
func barracks_of(owner_id: int) -> Node3D:
	for node in get_tree().get_nodes_in_group("building"):
		var building := node as Node3D
		if building == null:
			continue
		if int(building.kind) != RES.Building.BARRACKS:
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
func spawn_unit(owner_id: int, slot: int, point: Vector3) -> Node:
	if not multiplayer.is_server():
		return null
	_spawn_counter += 1
	var node := _world_spawner.spawn({
		"type": "unit",
		"id": _spawn_counter,
		"owner": owner_id,
		"slot": slot,
		"point": point,
	})
	if node != null:
		print("[отряд] игрок %d нанял мечника, слот %d" % [owner_id, slot])
	return node
