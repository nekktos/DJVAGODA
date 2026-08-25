class_name Player
extends CharacterBody3D
##
## Персонаж игрока: передвижение (Этап 0), бой (Этап 2), ранения (Этап 3).
##
## Авторитетность — разная у разных вещей, и это главное в этом файле:
##   ДВИЖЕНИЕ  считает владелец персонажа и реплицирует трансформ остальным.
##   БОЙ       считает только ХОСТ: клиент шлёт заявку, хост проверяет её по
##             СВОЕЙ копии мира и сам снимает здоровье.
##   РАНЕНИЯ   тоже только хост (см. combat/body.gd).
##
## Модель — Kenney Blocky Characters 2.0 (CC0). Части тела в ней отдельные
## меши, поэтому отрыв конечности это буквально «спрятать ноду и выбросить
## копию», без скелетов и шейдеров. Зоны попадания строятся ИЗ РАЗМЕРОВ самих
## мешей и вешаются на них же — так они едут за анимацией и не зависят от
## захардкоженных чисел.
##

const WEAPONS := preload("res://scripts/combat/weapons.gd")
const EFFECTS := preload("res://scripts/combat/effects.gd")
const HIT_ZONE := preload("res://scripts/combat/hit_zone.gd")
const SEVERED_LIMB := preload("res://scenes/SeveredLimb.tscn")

const MODELS := [
	"res://assets/characters/character-a.glb",
	"res://assets/characters/character-b.glb",
	"res://assets/characters/character-c.glb",
]
## Модель Kenney ростом 2.70 м — приводим к человеческим 1.84 м.
const MODEL_SCALE := 0.68

## Имя меша в модели -> ключ зоны попадания.
const PART_ZONES := {
	"head": "head",
	"torso": "torso",
	"arm-left": "arm_l",
	"arm-right": "arm_r",
	"leg-left": "leg_l",
	"leg-right": "leg_r",
}

const ZONE_MULTIPLIERS := {
	"head": 2.0,
	"torso": 1.0,
	"arm_l": 0.7,
	"arm_r": 0.7,
	"leg_l": 0.7,
	"leg_r": 0.7,
}

const SPEED := 6.0
const JUMP_VELOCITY := 5.5
const MOUSE_SENS := 0.0025
const PITCH_MIN := -1.2
const PITCH_MAX := 0.6
const REMOTE_LERP := 15.0

## Слои физики. Капсулы персонажей намеренно вынесены со слоя статичного мира:
## иначе луч стрелы утыкается в капсулу, у которой нет зоны попадания, и урон
## теряется. Снаряды ищут слой мира и слой зон, а капсулы не видят вовсе.
const WORLD_LAYER := 1
const BODY_LAYER := 2
const HITBOX_LAYER := 4

const MAX_ORIGIN_DRIFT := 4.0
const EYE_HEIGHT := 1.5
## Насколько опускаем модель, когда персонаж сидит на земле без ног.
const CRAWL_MODEL_DROP := -0.45

const SPAWN_POINTS: Array[Vector3] = [
	Vector3(-14.0, 2.0, 14.0),
	Vector3(0.0, 2.0, 22.0),
	Vector3(14.0, 2.0, 14.0),
]

signal death_reported(player: Node3D, killer_id: int)
signal projectile_requested(kind: int, origin: Vector3, dir: Vector3, shooter_id: int)

@export var sync_position: Vector3 = Vector3.ZERO
@export var sync_yaw: float = 0.0
@export var sync_weapon: int = 0
## Нужен, чтобы чужие персонажи анимировались: движение у них не считается.
@export var sync_moving: bool = false

var peer_id := 1
var spawn_slot := 0
var control_enabled := true
var scripted_input := {}

static var _bot_mode := -1

var _pitch := 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _cooldown_left := 0.0
var _server_cooldown := 0.0
var _swing_left := 0.0
var _bandage_progress := 0.0

@onready var _pivot: Node3D = $CamPivot
@onready var _spring: SpringArm3D = $CamPivot/SpringArm3D
@onready var _camera: Camera3D = $CamPivot/SpringArm3D/Camera3D
@onready var _name_tag: Label3D = $NameTag
@onready var health: Node = $Health
@onready var body: Node = $Body

var _model: Node3D
var _anim: AnimationPlayer
var _parts := {}
var _zones := {}
var _weapon_mesh: MeshInstance3D
var _current_anim := ""


func _enter_tree() -> void:
	peer_id = str(name).to_int()
	# Рекурсивно — чтобы синхронизатор движения получил того же авторитета.
	set_multiplayer_authority(peer_id)
	# ...а здоровье и ранения возвращаем хосту: рекурсивный вызов забрал и их.
	get_node("ServerSync").set_multiplayer_authority(1)


func _ready() -> void:
	var slot := clampi(spawn_slot, 0, SPAWN_POINTS.size() - 1)
	var spawn := SPAWN_POINTS[slot]
	global_position = spawn
	sync_position = spawn
	sync_yaw = rotation.y

	_build_model(slot)
	_spring.add_excluded_object(get_rid())
	_name_tag.text = "ХОСТ (1)" if peer_id == 1 else "ИГРОК (%d)" % peer_id

	var mine := is_multiplayer_authority()
	_camera.current = mine
	_name_tag.visible = not mine
	set_process_unhandled_input(mine)

	body.limb_severed.connect(_on_limb_severed)
	body.state_changed.connect(_refresh_posture)

	if multiplayer.is_server():
		health.died.connect(_on_died_on_server)


func _build_model(slot: int) -> void:
	var packed: PackedScene = load(MODELS[slot % MODELS.size()])
	_model = packed.instantiate()
	_model.name = "Model"
	_model.scale = Vector3.ONE * MODEL_SCALE
	add_child(_model)

	_anim = _find_node(_model, AnimationPlayer) as AnimationPlayer
	for part_name in PART_ZONES.keys():
		var mesh := _find_by_name(_model, part_name) as MeshInstance3D
		if mesh == null:
			push_warning("В модели нет части «%s»" % part_name)
			continue
		var key: String = PART_ZONES[part_name]
		_parts[key] = mesh
		_zones[key] = _attach_zone(mesh, key)

	_build_weapon_mesh()
	_play("idle")


## Зона попадания строится из собственного AABB меша и вешается на него же:
## тогда она едет за анимацией и переживает замену модели.
func _attach_zone(mesh: MeshInstance3D, key: String) -> Area3D:
	var box := mesh.get_aabb()
	var area := Area3D.new()
	area.set_script(HIT_ZONE)
	area.zone = key
	area.damage_multiplier = ZONE_MULTIPLIERS.get(key, 1.0)
	area.collision_layer = HITBOX_LAYER
	area.collision_mask = 0
	area.monitoring = false
	area.position = box.get_center()

	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = box.size
	shape.shape = box_shape
	area.add_child(shape)

	mesh.add_child(area)
	return area


func _find_node(node: Node, type) -> Node:
	if is_instance_of(node, type):
		return node
	for child in node.get_children():
		var found := _find_node(child, type)
		if found != null:
			return found
	return null


func _find_by_name(node: Node, wanted: String) -> Node:
	if String(node.name) == wanted:
		return node
	for child in node.get_children():
		var found := _find_by_name(child, wanted)
		if found != null:
			return found
	return null


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority() or not control_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotation.y -= event.relative.x * MOUSE_SENS
		_pitch = clampf(_pitch - event.relative.y * MOUSE_SENS, PITCH_MIN, PITCH_MAX)
		_pivot.rotation.x = _pitch


func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		_server_cooldown = maxf(0.0, _server_cooldown - delta)

	_swing_left = maxf(0.0, _swing_left - delta)

	if is_multiplayer_authority():
		var inp := _gather_input()
		apply_input(inp, delta)
		_update_attack(delta)
		_update_bandage(delta, inp)
		sync_position = global_position
		sync_yaw = rotation.y
		sync_moving = Vector2(velocity.x, velocity.z).length() > 0.4
	else:
		var t := clampf(delta * REMOTE_LERP, 0.0, 1.0)
		global_position = global_position.lerp(sync_position, t)
		rotation.y = lerp_angle(rotation.y, sync_yaw, t)

	_update_animation()


## Снимок ввода за кадр. Отдельный слой специально: когда авторитет над
## движением переедет на хост, сюда встанет отправка инпута по сети, а
## apply_input() будет вызываться на хосте без изменений.
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
		"bandage": Input.is_action_pressed("bandage"),
	}


## Чистая симуляция персонажа от снимка ввода. Не читает Input напрямую.
## Скорость и прыжок берутся у тела: без ноги персонаж ползёт, с мастерским
## протезом прыгает выше живого (GDD раздел 4).
func apply_input(inp: Dictionary, delta: float) -> void:
	var move: Vector2 = inp.get("move", Vector2.ZERO)
	var jump: bool = inp.get("jump", false)

	var speed: float = body.move_speed(SPEED)
	var jump_power: float = body.jump_velocity(JUMP_VELOCITY)

	if is_on_floor():
		if jump and jump_power > 0.0:
			velocity.y = jump_power
	else:
		velocity.y -= _gravity * delta

	var dir := (transform.basis * Vector3(move.x, 0.0, move.y))
	dir.y = 0.0
	dir = dir.normalized()
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed

	move_and_slide()


# --- анимация и поза -------------------------------------------------------

func _play(anim_name: String, force := false) -> void:
	if _anim == null or (anim_name == _current_anim and not force):
		return
	if not _anim.has_animation(anim_name):
		return
	_current_anim = anim_name
	_anim.play(anim_name)


func _update_animation() -> void:
	if _anim == null:
		return
	if not health.alive:
		_play("die")
		return
	if _swing_left > 0.0:
		return
	var moving := sync_moving if not is_multiplayer_authority() else (
		Vector2(velocity.x, velocity.z).length() > 0.4
	)
	if body.in_wheelchair:
		_play("wheelchair-move-forward" if moving else "wheelchair-sit")
	elif body.is_crawling():
		_play("sit")
	else:
		_play("walk" if moving else "idle")


## Поза меняется вместе с состоянием тела.
##
## Отдельной анимации ползания в паке Kenney нет. Готовая CC0-библиотека с
## ползанием существует (Quaternius Universal Animation Library), но она сделана
## под скелетный гуманоидный риг, а у Kenney скелета нет — там анимируются
## трансформы отдельных нод. Взять её значит сменить персонажа и переделать
## расчленение на сжатие костей, то есть переписать интеграцию Этапа 3.
## Поэтому безногого показываем сидящим на земле — поза "sit" из того же пака.
func _refresh_posture() -> void:
	if _model == null:
		return
	if body.is_crawling() and not body.in_wheelchair:
		_model.position.y = CRAWL_MODEL_DROP
	else:
		_model.position.y = 0.0
	_play(_current_anim, true)


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
	if not _weapon_allowed(sync_weapon):
		return

	_cooldown_left = WEAPONS.COOLDOWN[sync_weapon] * body.attack_speed_scale()
	_swing_left = 0.45
	_play("attack-melee-right" if sync_weapon == WEAPONS.Kind.SWORD else "holding-right-shoot", true)

	# Замах рисуем сразу, чтобы удар ощущался мгновенным. Урон при этом
	# случится только когда его подтвердит хост.
	# Хост бьёт напрямую: rpc_id самому себе Godot запрещает, а делать RPC
	# call_local ради этого нельзя — тогда удар исполнялся бы и на клиенте.
	if multiplayer.is_server():
		request_attack(sync_weapon, aim_origin(), aim_direction())
	else:
		request_attack.rpc_id(1, sync_weapon, aim_origin(), aim_direction())


## Деревянный протез руки годится только для ближнего боя: лук и заклинания
## требуют полноценной кисти (GDD раздел 4 — «ограничены действия»).
func _weapon_allowed(kind: int) -> bool:
	if kind == WEAPONS.Kind.SWORD:
		return body.can_attack_melee()
	return body.can_attack_ranged()


func aim_origin() -> Vector3:
	return global_position + Vector3.UP * EYE_HEIGHT


func aim_direction() -> Vector3:
	var b := Basis(Vector3.UP, rotation.y) * Basis(Vector3.RIGHT, _pitch)
	return -b.z


## Перевязка: держать клавишу, стоя на месте. Расходует бинт (DESIGN_ANSWERS,
## пункт 11). Прогресс считает клиент, но сам факт перевязки — хост.
func _update_bandage(delta: float, inp: Dictionary) -> void:
	if not body.bleeding or not control_enabled:
		_bandage_progress = 0.0
		return
	var holding: bool = inp.get("bandage", false)
	var still: bool = Vector2(velocity.x, velocity.z).length() < 0.3
	if not holding or not still:
		_bandage_progress = 0.0
		return
	_bandage_progress += delta
	if _bandage_progress < body.BANDAGE_TIME:
		return
	_bandage_progress = 0.0
	if multiplayer.is_server():
		request_bandage()
	else:
		request_bandage.rpc_id(1)


func bandage_progress() -> float:
	return clampf(_bandage_progress / body.BANDAGE_TIME, 0.0, 1.0)


# --- бой: сторона хоста ---------------------------------------------------

@rpc("any_peer", "reliable")
func request_bandage() -> void:
	if not multiplayer.is_server():
		return
	if not _sender_is_owner():
		return
	body.apply_bandage()


## Заявка на удар. Исполняется ТОЛЬКО на хосте.
@rpc("any_peer", "reliable")
func request_attack(kind: int, origin: Vector3, dir: Vector3) -> void:
	if not multiplayer.is_server():
		return

	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	if sender != peer_id:
		push_warning("Пир %d пытался ударить персонажем %d" % [sender, peer_id])
		return

	if not health.alive or _server_cooldown > 0.0:
		return
	if not WEAPONS.COOLDOWN.has(kind):
		return
	if not _weapon_allowed(kind):
		return
	# Позицию берём СВОЮ, а не присланную: клиент сообщает только намерение.
	var host_origin := aim_origin()
	if origin.distance_to(host_origin) > MAX_ORIGIN_DRIFT:
		push_warning("Заявка на удар от %d отклонена: точка удара разошлась на %.1f м"
			% [peer_id, origin.distance_to(host_origin)])
		return

	_server_cooldown = WEAPONS.COOLDOWN[kind] * body.attack_speed_scale()
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
	# Судьбу конечности считает тело — отдельно от общего здоровья.
	body.register_hit(zone, dealt)
	show_hit.rpc(point, dir, dealt, zone)


## Прислать может только хост — проверяем отправителя, а не полагаемся на
## режим "authority": авторитет этой ноды принадлежит владельцу персонажа,
## а вызывает хост.
@rpc("any_peer", "call_local", "unreliable")
func show_hit(point: Vector3, dir: Vector3, amount: float, zone: String) -> void:
	if not _sender_is_host():
		return
	EFFECTS.blood(get_parent(), point, dir, amount)


## Вызов пришёл от хоста? Локальный вызов даёт 0, удалённый от хоста — 1.
func _sender_is_host() -> bool:
	var sender := multiplayer.get_remote_sender_id()
	return sender == 0 or sender == 1


func _on_died_on_server(killer_id: int) -> void:
	death_reported.emit(self, killer_id)


# --- ранения: визуал ------------------------------------------------------

## Реагируем на РЕПЛИЦИРОВАННОЕ состояние, поэтому отрыв виден одинаково на
## хосте и на клиентах, и отдельной сетевой команды для этого не нужно.
func _on_limb_severed(limb: int) -> void:
	var key: String = body.LIMB_KEYS[limb]
	var mesh: MeshInstance3D = _parts.get(key)
	if mesh == null:
		return

	var at := mesh.global_transform
	mesh.visible = false
	var zone: Area3D = _zones.get(key)
	if zone != null:
		zone.collision_layer = 0

	# Кровь и сама оторванная часть, которая падает и остаётся лежать.
	EFFECTS.blood(get_parent(), at.origin, Vector3.UP, 80.0)
	var piece: Node3D = SEVERED_LIMB.instantiate()
	# Кладём прямо в мир, а не в Spawned: за той нодой следит MultiplayerSpawner,
	# а оторванная часть — локальный визуал, её каждый пир создаёт себе сам по
	# реплицированному состоянию тела.
	get_parent().get_parent().add_child(piece)
	piece.setup(mesh.mesh, at, MODEL_SCALE)
	_refresh_posture()


## Вернуть все части на место. Зовётся при респавне.
func restore_body() -> void:
	for key in _parts.keys():
		var mesh: MeshInstance3D = _parts[key]
		mesh.visible = true
		var zone: Area3D = _zones.get(key)
		if zone != null:
			zone.collision_layer = HITBOX_LAYER
	_refresh_posture()


# --- служебное ------------------------------------------------------------

@rpc("any_peer", "call_local", "reliable")
func set_dead(dead: bool) -> void:
	if not _sender_is_host():
		return
	control_enabled = not dead
	for key in _zones.keys():
		(_zones[key] as Area3D).collision_layer = 0 if dead else HITBOX_LAYER
	set_collision_layer_value(2, not dead)
	if dead:
		_play("die", true)
	else:
		velocity = Vector3.ZERO
		restore_body()
		_play("idle", true)


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


func set_view_active(on: bool) -> void:
	if is_multiplayer_authority():
		_camera.current = on


## Заглушка вместо модели оружия: коробка в руке. Висит на правой руке, чтобы
## ехать вместе с ней по анимации и исчезать вместе с оторванной рукой.
func _build_weapon_mesh() -> void:
	var hand: MeshInstance3D = _parts.get("arm_r")
	if hand == null:
		return
	_weapon_mesh = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.16, 0.16, 1.5)
	_weapon_mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.82, 0.84, 0.88)
	_weapon_mesh.material_override = mat
	hand.add_child(_weapon_mesh)
	_weapon_mesh.position = Vector3(0.0, -0.5, -0.5)


static func _is_bot() -> bool:
	if _bot_mode == -1:
		var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
		_bot_mode = 1 if args.has("--bot") else 0
	return _bot_mode == 1


## Физические RID капсулы и всех своих зон попадания. Нужны снаряду, чтобы
## только что выпущенная стрела не воткнулась в самого стрелка.
func own_collision_rids() -> Array[RID]:
	var rids: Array[RID] = [get_rid()]
	for key in _zones.keys():
		var zone: Area3D = _zones[key]
		if zone != null:
			rids.append(zone.get_rid())
	return rids


# --- верстак: протезы и коляска -------------------------------------------

## Стоит ли персонаж у верстака. Клиент по этому решает, показывать ли панель,
## хост — можно ли выдать протез.
func at_workbench() -> bool:
	var world := get_parent().get_parent()
	if world == null or not world.has_method("is_at_workbench"):
		return false
	return world.is_at_workbench(global_position)


func ask_prosthetic(new_tier: int) -> void:
	if multiplayer.is_server():
		request_prosthetic(new_tier)
	else:
		request_prosthetic.rpc_id(1, new_tier)


func ask_wheelchair(on: bool) -> void:
	if multiplayer.is_server():
		request_wheelchair(on)
	else:
		request_wheelchair.rpc_id(1, on)


## Поставить протезы на все оторванные конечности. Только на хосте.
##
## Оплата и крафт — заглушка: деньги и древесина появятся вместе с экономикой
## и ресурсами (Этапы 4-5), тогда сюда встанет проверка кошелька и склада.
@rpc("any_peer", "reliable")
func request_prosthetic(new_tier: int) -> void:
	if not multiplayer.is_server():
		return
	if not _sender_is_owner():
		return
	if not health.alive or not at_workbench():
		return
	for limb in body.LIMB_KEYS.size():
		if body.is_severed(limb):
			body.grant_prosthetic(limb, new_tier)


@rpc("any_peer", "reliable")
func request_wheelchair(on: bool) -> void:
	if not multiplayer.is_server():
		return
	if not _sender_is_owner():
		return
	if not health.alive or not at_workbench():
		return
	body.set_wheelchair(on)


## Заявку прислал владелец этого персонажа, а не посторонний пир?
func _sender_is_owner() -> bool:
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	return sender == peer_id
