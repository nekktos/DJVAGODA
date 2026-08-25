extends CharacterBody3D
##
## Боец отряда (Этап 6, GDD раздел 2.3): мечник из казармы.
##
## Ведёт себя просто и намеренно: держит свой слот в построении, а если рядом
## оказался враг — бьёт его и возвращается в строй. GDD прямо ограничивает
## объём этого этапа: «не полноценный ИИ-пафайндинг для сложных манёвров, а
## заранее заданные формации». Обхода препятствий тут нет, движение прямое.
##
## Всё считает ТОЛЬКО хост: движение, выбор цели, урон. Клиенты получают
## позицию и здоровье и просто рисуют.
##

const FORMATIONS := preload("res://scripts/units/formations.gd")
const HIT_ZONE := preload("res://scripts/combat/hit_zone.gd")
const WEAPON_VISUAL := preload("res://scripts/combat/weapon_visual.gd")
const WEAPONS := preload("res://scripts/combat/weapons.gd")
const EFFECTS := preload("res://scripts/combat/effects.gd")

const MODELS := [
	"res://assets/characters/character-d.glb",
	"res://assets/characters/character-e.glb",
	"res://assets/characters/character-f.glb",
]
const MODEL_SCALE := 0.68

const PART_ZONES := {
	"head": "head",
	"torso": "torso",
	"arm-left": "arm_l",
	"arm-right": "arm_r",
	"leg-left": "leg_l",
	"leg-right": "leg_r",
}
const ZONE_MULTIPLIERS := {
	"head": 2.0, "torso": 1.0,
	"arm_l": 0.7, "arm_r": 0.7, "leg_l": 0.7, "leg_r": 0.7,
}

const MAX_HEALTH := 90.0
const BASE_SPEED := 5.2
## Дальше этого боец врага не замечает и держит строй.
const ENGAGE_RANGE := 14.0
## Ближе этого можно бить.
const STRIKE_RANGE := 2.4
const STRIKE_DAMAGE := 22.0
const STRIKE_COOLDOWN := 1.1
## Насколько точно надо встать в свой слот, чтобы считать себя в строю.
const SLOT_TOLERANCE := 1.2

const BODY_LAYER := 2
const HITBOX_LAYER := 4

signal died_on_server(unit: Node3D)

## Реплицируемое состояние.
@export var sync_position: Vector3 = Vector3.ZERO
@export var sync_yaw: float = 0.0
@export var health: float = MAX_HEALTH
@export var sync_moving: bool = false

var owner_id := 1
var slot := 0

var _model: Node3D
var _anim: AnimationPlayer
var _parts := {}
var _cooldown := 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _current_anim := ""
var _alive := true


## Вызывается спавнером на всех пирах с одинаковыми данными.
func setup(data: Dictionary) -> void:
	owner_id = int(data["owner"])
	slot = int(data["slot"])
	position = data["point"]
	sync_position = position


func _ready() -> void:
	add_to_group("unit")
	collision_layer = BODY_LAYER
	# Со статичным миром сталкиваемся, друг с другом — нет. Расстояние между
	# бойцами задают слоты построения, а взаимные столкновения в плотном строю
	# только тормозят марш втрое и распирают шеренгу. Игрок при этом сквозь
	# бойцов не проходит: у него в маске слой тел остался.
	collision_mask = 1
	_build_model()


func _build_model() -> void:
	var packed: PackedScene = load(MODELS[slot % MODELS.size()])
	_model = packed.instantiate()
	_model.name = "Model"
	_model.scale = Vector3.ONE * MODEL_SCALE
	# Модель смотрит в +Z, игра считает передом -Z — см. player.gd::_build_model.
	_model.rotation.y = PI
	add_child(_model)

	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	shape.shape = capsule
	shape.position = Vector3(0.0, 0.9, 0.0)
	add_child(shape)

	_anim = _find_anim(_model)
	for part_name in PART_ZONES.keys():
		var mesh := _find_by_name(_model, part_name) as MeshInstance3D
		if mesh == null:
			continue
		var key: String = PART_ZONES[part_name]
		_parts[key] = mesh
		HIT_ZONE.attach(mesh, key, ZONE_MULTIPLIERS.get(key, 1.0), HITBOX_LAYER)
	# Мечник — с мечом в руке, точка хвата считается по габаритам руки.
	WEAPON_VISUAL.attach(_parts.get("arm_r"), WEAPONS.Kind.SWORD, null)
	_play("idle")


func _find_anim(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_anim(child)
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


func _play(anim_name: String) -> void:
	if _anim == null or anim_name == _current_anim:
		return
	if not _anim.has_animation(anim_name):
		return
	_current_anim = anim_name
	_anim.play(anim_name)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		var t := clampf(delta * 14.0, 0.0, 1.0)
		global_position = global_position.lerp(sync_position, t)
		rotation.y = lerp_angle(rotation.y, sync_yaw, t)
		_play("walk" if sync_moving else "idle")
		return

	if not _alive:
		return

	_cooldown = maxf(0.0, _cooldown - delta)

	var commander := _commander()
	var target := _find_target()
	var destination: Vector3
	var facing_target := false

	if target != null and global_position.distance_to(target.global_position) <= ENGAGE_RANGE:
		destination = target.global_position
		facing_target = true
	elif commander != null:
		destination = _slot_point(commander)
	else:
		destination = global_position

	var to_dest := destination - global_position
	to_dest.y = 0.0
	var distance := to_dest.length()
	var stop_at: float = STRIKE_RANGE if facing_target else SLOT_TOLERANCE

	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0

	if distance > stop_at:
		var dir := to_dest.normalized()
		var speed := BASE_SPEED * FORMATIONS.speed_scale(_formation())
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
		rotation.y = atan2(-dir.x, -dir.z)
		sync_moving = true
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		sync_moving = false
		if facing_target:
			_strike(target)

	move_and_slide()
	sync_position = global_position
	sync_yaw = rotation.y
	_play("walk" if sync_moving else "idle")


## Куда встать по построению. Якорь и разворот берём у командира или у точки,
## которую он назначил приказом.
func _slot_point(commander: Node3D) -> Vector3:
	var anchor: Vector3 = commander.squad_anchor()
	var yaw: float = commander.squad_facing()
	var offset: Vector3 = FORMATIONS.slot_offset(_formation(), slot, 0)
	return anchor + Basis(Vector3.UP, yaw) * offset


func _formation() -> int:
	var commander := _commander()
	return int(commander.squad_formation) if commander != null else 0


func _commander() -> Node3D:
	var world := get_parent().get_parent()
	if world == null:
		return null
	return world.get_node_or_null("Players/%d" % owner_id)


## Ближайший враг: чужой игрок, чужой боец или чужой караван.
## Фракций в коде ещё нет, поэтому «чужой» это «другой владелец».
func _find_target() -> Node3D:
	var best: Node3D = null
	var best_distance := ENGAGE_RANGE
	var world := get_parent().get_parent()
	if world == null:
		return null

	for player in world.get_node("Players").get_children():
		# В Players может лежать не только персонаж, поэтому проверяем, а не верим.
		if not ("peer_id" in player) or not player.has_method("take_damage"):
			continue
		if int(player.peer_id) == owner_id or not player.health.alive:
			continue
		var d: float = global_position.distance_to(player.global_position)
		if d < best_distance:
			best_distance = d
			best = player

	for other in get_parent().get_children():
		if other == self or not other.has_method("take_damage"):
			continue
		if not ("owner_id" in other) or int(other.owner_id) == owner_id:
			continue
		var d: float = global_position.distance_to(other.global_position)
		if d < best_distance:
			best_distance = d
			best = other
	return best


func _strike(target: Node3D) -> void:
	if _cooldown > 0.0 or target == null:
		return
	_cooldown = STRIKE_COOLDOWN
	var point := target.global_position + Vector3.UP * 1.1
	var dir := (target.global_position - global_position).normalized()
	target.take_damage(STRIKE_DAMAGE, owner_id, "torso", point, dir)


## Принять урон. Только на хосте. Построение режет или усиливает входящий урон
## (DESIGN_ANSWERS.md, пункт 16).
func take_damage(amount: float, attacker_id: int, _zone: String, point: Vector3, dir: Vector3, aoe := false) -> void:
	if not multiplayer.is_server() or not _alive:
		return
	var scaled: float = amount * FORMATIONS.damage_scale(_formation(), aoe)
	health = maxf(0.0, health - scaled)
	show_hit.rpc(point, dir, scaled)
	if health > 0.0:
		return
	_alive = false
	print("[отряд] боец игрока %d убит игроком %d" % [owner_id, attacker_id])
	died_on_server.emit(self)
	queue_free()


@rpc("any_peer", "call_local", "unreliable")
func show_hit(point: Vector3, dir: Vector3, amount: float) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	# В мир, а не в Spawned: за той нодой следит MultiplayerSpawner.
	EFFECTS.blood(get_parent().get_parent(), point, dir, amount)
