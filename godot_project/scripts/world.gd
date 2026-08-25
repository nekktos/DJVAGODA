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

var strategy_mode := false

var _netlog := false
var _netlog_t := 0.0


func _ready() -> void:
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	_netlog = args.has("--netlog")
	# Кастомная spawn_function: даёт положить в пакет спавна произвольные данные
	# (сейчас — номер слота, позже сюда же ляжет фракция).
	_spawner.spawn_function = _make_player
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	Net.session_started.connect(_on_session_started)
	Net.session_ended.connect(_on_session_ended)

	var builder := WORLD_BUILDER.new()
	builder.build(_terrain)


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
	_spawner.spawn({"id": id, "slot": slot})


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
