class_name Player
extends CharacterBody3D
##
## Персонаж игрока: передвижение (Этап 0) и бой (Этап 2).
##
## Авторитетность — разная у разных вещей, и это главное в этом файле:
##   ДВИЖЕНИЕ  считает владелец персонажа и реплицирует трансформ остальным.
##   БОЙ       считает только ХОСТ. Клиент шлёт заявку «бью оружием W в
##             направлении D», хост сам проверяет кулдаун, дистанцию и
##             попадание по СВОЕЙ копии мира и сам снимает здоровье.
##
## Поэтому на персонаже два синхронизатора: Sync принадлежит владельцу и возит
## позицию, ServerSync принадлежит хосту и возит здоровье. Если бы здоровье
## ехало по клиентскому каналу, любой клиент выставлял бы себе бессмертие.
##

const WEAPONS := preload("res://scripts/combat/weapons.gd")
const EFFECTS := preload("res://scripts/combat/effects.gd")

const SPEED := 6.0
const JUMP_VELOCITY := 5.5
const MOUSE_SENS := 0.0025
const PITCH_MIN := -1.2
const PITCH_MAX := 0.6
## Скорость подтягивания чужого персонажа к присланному состоянию.
const REMOTE_LERP := 15.0

## Слои физики. Капсулы персонажей намеренно вынесены со слоя статичного мира:
## иначе луч стрелы утыкается в капсулу, у которой нет зоны попадания, и урон
## теряется. Снаряды ищут слой мира и слой зон, а капсулы не видят вовсе.
const WORLD_LAYER := 1
const BODY_LAYER := 2
const HITBOX_LAYER := 4
## Насколько заявленная клиентом точка удара может отличаться от той, где хост
## видит этого персонажа. Защита от удара «из другого конца карты».
const MAX_ORIGIN_DRIFT := 4.0
## Откуда бьём и куда смотрим, по высоте от ног.
const EYE_HEIGHT := 1.5

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

## Хост просит мир создать труп и назначить респавн.
signal death_reported(player: Node3D, killer_id: int)
## Хост просит мир выпустить снаряд: сам персонаж спавнером не владеет.
signal projectile_requested(kind: int, origin: Vector3, dir: Vector3, shooter_id: int)

## Реплицируемое состояние (см. MultiplayerSynchronizer в Player.tscn).
@export var sync_position: Vector3 = Vector3.ZERO
@export var sync_yaw: float = 0.0
@export var sync_weapon: int = 0

var peer_id := 1
## Номер слота 0..SPAWN_POINTS.size()-1. Выставляется хостом до add_child и
## приезжает к остальным пирам как часть данных спавна.
var spawn_slot := 0

## Принимает ли персонаж управление. Выключается на время стратегической
## камеры и на время смерти.
var control_enabled := true

## Подмена ввода для автотестов (tools/walk_test.gd, tools/combat_test.gd).
var scripted_input := {}

## Дебаг-ключ --bot: персонаж ходит по кругу сам, без живого игрока.
static var _bot_mode := -1

var _pitch := 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
## Локальный кулдаун — только чтобы не слать хосту заведомо лишние заявки.
var _cooldown_left := 0.0
## Авторитетный кулдаун, тикает только на хосте.
var _server_cooldown := 0.0
var _swing_left := 0.0

@onready var _pivot: Node3D = $CamPivot
@onready var _spring: SpringArm3D = $CamPivot/SpringArm3D
@onready var _camera: Camera3D = $CamPivot/SpringArm3D/Camera3D
@onready var _name_tag: Label3D = $NameTag
@onready var _body_mesh: MeshInstance3D = $Body
@onready var _nose_mesh: MeshInstance3D = $Nose
@onready var health: Node = $Health

var _weapon_mesh: MeshInstance3D


func _enter_tree() -> void:
	peer_id = str(name).to_int()
	# Рекурсивно — чтобы синхронизатор движения получил того же авторитета.
	set_multiplayer_authority(peer_id)
	# ...а здоровье возвращаем хосту: рекурсивный вызов выше забрал и его.
	get_node("ServerSync").set_multiplayer_authority(1)


func _ready() -> void:
	var slot := clampi(spawn_slot, 0, SPAWN_POINTS.size() - 1)
	var spawn := SPAWN_POINTS[slot]
	global_position = spawn
	sync_position = spawn
	sync_yaw = rotation.y

	_spring.add_excluded_object(get_rid())
	_apply_colors(slot)
	_build_weapon_mesh(slot)
	_name_tag.text = "ХОСТ (1)" if peer_id == 1 else "ИГРОК (%d)" % peer_id

	var mine := is_multiplayer_authority()
	_camera.current = mine
	# Свой ник над головой не нужен — он загораживает обзор.
	_name_tag.visible = not mine
	set_process_unhandled_input(mine)

	if multiplayer.is_server():
		health.died.connect(_on_died_on_server)


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority() or not control_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotation.y -= event.relative.x * MOUSE_SENS
		_pitch = clampf(_pitch - event.relative.y * MOUSE_SENS, PITCH_MIN, PITCH_MAX)
		_pivot.rotation.x = _pitch


func _physics_process(delta: float) -> void:
	# Авторитетный кулдаун живёт на хосте для ВСЕХ персонажей, включая чужих.
	if multiplayer.is_server():
		_server_cooldown = maxf(0.0, _server_cooldown - delta)

	_swing_left = maxf(0.0, _swing_left - delta)
	_animate_weapon()

	if is_multiplayer_authority():
		apply_input(_gather_input(), delta)
		_update_attack(delta)
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


# --- бой: сторона клиента -------------------------------------------------

func _update_attack(delta: float) -> void:
	_cooldown_left = maxf(0.0, _cooldown_left - delta)
	if not control_enabled or not health.alive:
		return

	if Input.is_action_just_pressed("weapon_1"):
		sync_weapon = WEAPONS.Kind.SWORD
	elif Input.is_action_just_pressed("weapon_2"):
		sync_weapon = WEAPONS.Kind.BOW
	elif Input.is_action_just_pressed("weapon_3"):
		sync_weapon = WEAPONS.Kind.SPELL

	var wants: bool = scripted_input.get("attack", false)
	if not wants and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		wants = Input.is_action_pressed("attack")
	if not wants or _cooldown_left > 0.0:
		return

	_cooldown_left = WEAPONS.COOLDOWN[sync_weapon]
	_swing_left = 0.25
	# Замах рисуем сразу, чтобы удар ощущался мгновенным. Урон при этом
	# случится только когда его подтвердит хост.
	# Хост бьёт напрямую: rpc_id самому себе Godot запрещает, а делать RPC
	# call_local ради этого нельзя — тогда удар исполнялся бы и на клиенте.
	if multiplayer.is_server():
		request_attack(sync_weapon, aim_origin(), aim_direction())
	else:
		request_attack.rpc_id(1, sync_weapon, aim_origin(), aim_direction())


func aim_origin() -> Vector3:
	return global_position + Vector3.UP * EYE_HEIGHT


func aim_direction() -> Vector3:
	var b := Basis(Vector3.UP, rotation.y) * Basis(Vector3.RIGHT, _pitch)
	return -b.z


# --- бой: сторона хоста ---------------------------------------------------

## Заявка на удар. Исполняется ТОЛЬКО на хосте.
@rpc("any_peer", "reliable")
func request_attack(kind: int, origin: Vector3, dir: Vector3) -> void:
	if not multiplayer.is_server():
		return

	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	# Бить чужим персонажем нельзя.
	if sender != peer_id:
		push_warning("Пир %d пытался ударить персонажем %d" % [sender, peer_id])
		return

	if not health.alive or _server_cooldown > 0.0:
		return
	if not WEAPONS.COOLDOWN.has(kind):
		return
	# Позицию берём СВОЮ, а не присланную: клиент сообщает только намерение.
	var host_origin := aim_origin()
	if origin.distance_to(host_origin) > MAX_ORIGIN_DRIFT:
		push_warning("Заявка на удар от %d отклонена: точка удара разошлась на %.1f м"
			% [peer_id, origin.distance_to(host_origin)])
		return

	_server_cooldown = WEAPONS.COOLDOWN[kind]
	var aim := dir.normalized()
	if aim.length() < 0.5:
		return

	if kind == WEAPONS.Kind.SWORD:
		_server_swing_sword(aim)
	else:
		# Снаряд создаёт и ведёт мир — он владеет спавнером снарядов.
		projectile_requested.emit(kind, host_origin, aim, peer_id)


## Хост разрешает удар мечом: ищет зоны попадания в секторе перед персонажем.
func _server_swing_sword(aim: Vector3) -> void:
	var origin := aim_origin()
	var space := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = WEAPONS.SWORD_RANGE
	query.shape = sphere
	query.transform = Transform3D(Basis(), origin)
	query.collision_mask = HITBOX_LAYER
	query.collide_with_areas = true
	query.collide_with_bodies = false

	# По каждой цели бьём один раз — той зоной, что даёт больший множитель.
	var best := {}
	for hit in space.intersect_shape(query, 24):
		var zone: Area3D = hit.get("collider") as Area3D
		if zone == null or not zone.has_method("owner_character"):
			continue
		var target: Node3D = zone.owner_character()
		if target == null or target == self:
			continue
		var to_target := target.global_position + Vector3.UP * 1.0 - origin
		if to_target.length() > 0.01 and aim.angle_to(to_target.normalized()) > WEAPONS.SWORD_HALF_ANGLE:
			continue
		var prev: Area3D = best.get(target)
		if prev == null or zone.damage_multiplier > prev.damage_multiplier:
			best[target] = zone

	for target in best.keys():
		var zone: Area3D = best[target]
		var damage: float = WEAPONS.DAMAGE[WEAPONS.Kind.SWORD] * zone.damage_multiplier
		target.take_damage(damage, peer_id, zone.zone, zone.global_position, aim)


## Принять урон. Вызывается ТОЛЬКО на хосте (из оружия или снаряда).
func take_damage(amount: float, attacker_id: int, zone: String, point: Vector3, dir: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var dealt: float = health.apply_damage(amount, attacker_id)
	if dealt <= 0.0:
		return
	# Эффект показываем всем одновременно, включая себя.
	show_hit.rpc(point, dir, dealt, zone)


## Отрисовка попадания. Ни на что в игре не влияет, только вид.
## Прислать может только хост — проверяем отправителя, а не полагаемся на
## режим "authority": авторитет этой ноды принадлежит владельцу персонажа,
## а вызывает хост.
@rpc("any_peer", "call_local", "unreliable")
func show_hit(point: Vector3, dir: Vector3, amount: float, zone: String) -> void:
	if not _sender_is_host():
		return
	EFFECTS.blood(get_parent(), point, dir, amount)
	if is_multiplayer_authority():
		print("[бой] %s получил %.0f по зоне %s" % [name, amount, zone])


## Вызов пришёл от хоста? Локальный вызов даёт 0, удалённый от хоста — 1.
func _sender_is_host() -> bool:
	var sender := multiplayer.get_remote_sender_id()
	return sender == 0 or sender == 1


func _on_died_on_server(killer_id: int) -> void:
	death_reported.emit(self, killer_id)


## Выключить персонажа на время смерти. Вызывает мир, на всех пирах.
@rpc("any_peer", "call_local", "reliable")
func set_dead(dead: bool) -> void:
	if not _sender_is_host():
		return
	control_enabled = not dead
	visible = not dead
	# Мёртвый не должен ни ловить удары, ни мешать живым.
	for zone in $Zones.get_children():
		(zone as Area3D).collision_layer = 0 if dead else HITBOX_LAYER
	set_collision_layer_value(2, not dead)
	if not dead:
		velocity = Vector3.ZERO


## Перенести на точку спавна. Только на хосте, дальше разъедется репликацией.
func respawn_at_slot() -> void:
	var slot := clampi(spawn_slot, 0, SPAWN_POINTS.size() - 1)
	teleport.rpc(SPAWN_POINTS[slot])


@rpc("any_peer", "call_local", "reliable")
func teleport(point: Vector3) -> void:
	if not _sender_is_host():
		return
	global_position = point
	sync_position = point
	velocity = Vector3.ZERO


## Сделать камеру этого персонажа активной. Вызывается при возврате из
## стратегического режима; у чужих персонажей ничего не делает.
func set_view_active(on: bool) -> void:
	if is_multiplayer_authority():
		_camera.current = on


# --- вид ------------------------------------------------------------------

func _apply_colors(slot: int) -> void:
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = SLOT_COLORS[slot]
	_body_mesh.material_override = body_mat

	var nose_mat := StandardMaterial3D.new()
	nose_mat.albedo_color = body_mat.albedo_color.lightened(0.5)
	_nose_mesh.material_override = nose_mat


## Заглушка вместо модели оружия: коробка в руке, которой видно замах.
func _build_weapon_mesh(slot: int) -> void:
	_weapon_mesh = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.12, 0.12, 1.1)
	_weapon_mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = SLOT_COLORS[slot].lightened(0.7)
	_weapon_mesh.material_override = mat
	add_child(_weapon_mesh)
	_weapon_mesh.position = Vector3(0.45, 1.2, -0.5)


func _animate_weapon() -> void:
	if _weapon_mesh == null:
		return
	# Простейший замах: оружие проворачивается и возвращается.
	var t := _swing_left / 0.25
	_weapon_mesh.rotation = Vector3(-t * 1.6, 0.0, 0.0)


static func _is_bot() -> bool:
	if _bot_mode == -1:
		var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
		_bot_mode = 1 if args.has("--bot") else 0
	return _bot_mode == 1
