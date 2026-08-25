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

## Точки спавна — детерминированная функция peer id, одинаково считается на всех
## пирах, поэтому стартовую позицию не нужно реплицировать отдельно.
const SPAWN_POINTS: Array[Vector3] = [
	Vector3(-4.0, 1.2, 6.0),
	Vector3(4.0, 1.2, 6.0),
]

## Реплицируемое состояние (см. MultiplayerSynchronizer в Player.tscn).
@export var sync_position: Vector3 = Vector3.ZERO
@export var sync_yaw: float = 0.0

var peer_id := 1

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


static func spawn_point_for(id: int) -> Vector3:
	return SPAWN_POINTS[0] if id == 1 else SPAWN_POINTS[1]


func _enter_tree() -> void:
	peer_id = str(name).to_int()
	# Рекурсивно — чтобы MultiplayerSynchronizer получил того же авторитета.
	set_multiplayer_authority(peer_id)


func _ready() -> void:
	var spawn := spawn_point_for(peer_id)
	global_position = spawn
	sync_position = spawn
	sync_yaw = rotation.y

	_spring.add_excluded_object(get_rid())
	_apply_colors()
	_name_tag.text = "ХОСТ (1)" if peer_id == 1 else "ИГРОК (%d)" % peer_id

	var mine := is_multiplayer_authority()
	_camera.current = mine
	# Свой ник над головой не нужен — он загораживает обзор.
	_name_tag.visible = not mine
	set_process_unhandled_input(mine)


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
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


func _apply_colors() -> void:
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.85, 0.25, 0.2) if peer_id == 1 else Color(0.2, 0.45, 0.85)
	_body_mesh.material_override = body_mat

	var nose_mat := StandardMaterial3D.new()
	nose_mat.albedo_color = body_mat.albedo_color.lightened(0.5)
	_nose_mesh.material_override = nose_mat


static func _is_bot() -> bool:
	if _bot_mode == -1:
		var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
		_bot_mode = 1 if args.has("--bot") else 0
	return _bot_mode == 1
