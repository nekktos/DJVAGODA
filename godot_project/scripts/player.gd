class_name Player
extends CharacterBody3D
##
## Персонаж игрока. Этап 0: только передвижение (WASD + прыжок + мышь),
## без боя и любого другого контента.
##
## Авторитетность: имя ноды == peer id владельца, авторитет выставляется в
## _enter_tree() рекурсивно (вместе с MultiplayerSynchronizer внутри).
## Симулирует персонажа только его владелец; остальные пиры интерполируют
## пришедший трансформ.
##

const SPEED := 6.0
const JUMP_VELOCITY := 5.5
const MOUSE_SENS := 0.0025
const PITCH_MIN := -1.2
const PITCH_MAX := 0.6
## Скорость подтягивания чужого персонажа к присланному состоянию.
const REMOTE_LERP := 15.0

## Точки спавна по номеру слота. Слот выдаёт хост при спавне (world.gd) и он
## одинаков на всех пирах, поэтому стартовую позицию не нужно реплицировать.
## Размер массива задаёт максимум игроков в сессии — 3 (GDD: от 1 до 3).
const SPAWN_POINTS: Array[Vector3] = [
	Vector3(-14.0, 2.0, 14.0),
	Vector3(0.0, 2.0, 22.0),
	Vector3(14.0, 2.0, 14.0),
]

const SLOT_COLORS: Array[Color] = [
	Color(0.85, 0.25, 0.2),
	Color(0.2, 0.45, 0.85),
	Color(0.3, 0.7, 0.32),
]

## Реплицируемое состояние (см. MultiplayerSynchronizer в Player.tscn).
@export var sync_position: Vector3 = Vector3.ZERO
@export var sync_yaw: float = 0.0

var peer_id := 1
## Номер слота 0..SPAWN_POINTS.size()-1. Выставляется хостом до add_child и
## приезжает к остальным пирам как часть данных спавна.
var spawn_slot := 0

## Принимает ли персонаж управление. Выключается на время стратегической
## камеры: персонаж при этом продолжает симулироваться и оставаться уязвимым,
## просто стоит на месте (см. DESIGN_ANSWERS.md, пункт 7).
var control_enabled := true

## Подмена ввода для автотестов проходимости (tools/walk_test.gd).
## Пустой словарь — обычный ввод игрока.
var scripted_input := {}

## Дебаг-ключ --bot: персонаж ходит по кругу сам, без живого игрока.
## Нужен, чтобы прогнать синхронизацию соло (в т.ч. headless). На геймплей не
## влияет — без ключа этот код мёртв.
static var _bot_mode := -1

var _pitch := 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)

@onready var _pivot: Node3D = $CamPivot
@onready var _spring: SpringArm3D = $CamPivot/SpringArm3D
@onready var _camera: Camera3D = $CamPivot/SpringArm3D/Camera3D
@onready var _name_tag: Label3D = $NameTag
@onready var _body_mesh: MeshInstance3D = $Body
@onready var _nose_mesh: MeshInstance3D = $Nose


func _enter_tree() -> void:
	peer_id = str(name).to_int()
	# Рекурсивно — чтобы MultiplayerSynchronizer получил того же авторитета.
	set_multiplayer_authority(peer_id)


func _ready() -> void:
	var slot := clampi(spawn_slot, 0, SPAWN_POINTS.size() - 1)
	var spawn := SPAWN_POINTS[slot]
	global_position = spawn
	sync_position = spawn
	sync_yaw = rotation.y

	_spring.add_excluded_object(get_rid())
	_apply_colors(slot)
	_name_tag.text = "ХОСТ (1)" if peer_id == 1 else "ИГРОК (%d)" % peer_id

	var mine := is_multiplayer_authority()
	_camera.current = mine
	# Свой ник над головой не нужен — он загораживает обзор.
	_name_tag.visible = not mine
	set_process_unhandled_input(mine)


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority() or not control_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotation.y -= event.relative.x * MOUSE_SENS
		_pitch = clampf(_pitch - event.relative.y * MOUSE_SENS, PITCH_MIN, PITCH_MAX)
		_pivot.rotation.x = _pitch


func _physics_process(delta: float) -> void:
	if is_multiplayer_authority():
		apply_input(_gather_input(), delta)
		sync_position = global_position
		sync_yaw = rotation.y
	else:
		var t := clampf(delta * REMOTE_LERP, 0.0, 1.0)
		global_position = global_position.lerp(sync_position, t)
		rotation.y = lerp_angle(rotation.y, sync_yaw, t)


## Снимок ввода за кадр. Отдельный слой специально: когда на будущем этапе
## авторитет над движением переедет на хост, сюда встанет отправка инпута по
## сети, а apply_input() будет вызываться на хосте без изменений.
func _gather_input() -> Dictionary:
	if not scripted_input.is_empty():
		return scripted_input
	if not control_enabled:
		return {"move": Vector2.ZERO, "jump": false}
	if _is_bot():
		var t := Time.get_ticks_msec() / 1000.0
		return {"move": Vector2(cos(t), sin(t)), "jump": false}
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return {"move": Vector2.ZERO, "jump": false}
	return {
		"move": Input.get_vector("move_left", "move_right", "move_forward", "move_back"),
		"jump": Input.is_action_just_pressed("jump"),
	}


## Чистая симуляция персонажа от снимка ввода. Не читает Input напрямую.
func apply_input(inp: Dictionary, delta: float) -> void:
	var move: Vector2 = inp.get("move", Vector2.ZERO)
	var jump: bool = inp.get("jump", false)

	if is_on_floor():
		if jump:
			velocity.y = JUMP_VELOCITY
	else:
		velocity.y -= _gravity * delta

	var dir := (transform.basis * Vector3(move.x, 0.0, move.y))
	dir.y = 0.0
	dir = dir.normalized()
	velocity.x = dir.x * SPEED
	velocity.z = dir.z * SPEED

	move_and_slide()


func _apply_colors(slot: int) -> void:
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = SLOT_COLORS[slot]
	_body_mesh.material_override = body_mat

	var nose_mat := StandardMaterial3D.new()
	nose_mat.albedo_color = body_mat.albedo_color.lightened(0.5)
	_nose_mesh.material_override = nose_mat


static func _is_bot() -> bool:
	if _bot_mode == -1:
		var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
		_bot_mode = 1 if args.has("--bot") else 0
	return _bot_mode == 1


## Сделать камеру этого персонажа активной. Вызывается при возврате из
## стратегического режима; у чужих персонажей ничего не делает.
func set_view_active(on: bool) -> void:
	if is_multiplayer_authority():
		_camera.current = on
