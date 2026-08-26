extends Node3D
##
## Стрела и огненный шар. Одна сцена на оба вида — различаются параметрами.
##
## Живёт и считает попадания ТОЛЬКО хост. Клиенты получают позицию через
## MultiplayerSynchronizer с авторитетом хоста и просто её рисуют: снаряд для
## них — чистая декорация, урона он на клиенте не наносит никогда.
##

const WEAPONS := preload("res://scripts/combat/weapons.gd")
const EFFECTS := preload("res://scripts/combat/effects.gd")

## Слой статичного мира плюс слой зон попадания. Капсулы персонажей (слой 2)
## намеренно НЕ включены: попадание должно определяться зоной, а не капсулой.
const HIT_MASK := 1 | 4

@export var sync_position: Vector3 = Vector3.ZERO

var kind := 0
var shooter_id := 1
## Уровень снаряжения стрелка на момент выстрела.
var gear_tier := 0

var _velocity := Vector3.ZERO
var _life := 0.0
var _exclude: Array[RID] = []
var _mesh: MeshInstance3D


## Вызывается спавнером на всех пирах с одинаковыми данными.
func setup(data: Dictionary) -> void:
	kind = int(data["kind"])
	shooter_id = int(data["shooter"])
	gear_tier = int(data.get("gear", 0))
	position = data["origin"]
	sync_position = position
	_velocity = Vector3(data["dir"]).normalized() * WEAPONS.PROJECTILE_SPEED[kind]


func _ready() -> void:
	_build_mesh()
	if Net.hosting():
		_collect_exclusions()


func _build_mesh() -> void:
	_mesh = MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	if kind == WEAPONS.Kind.BOW:
		var shaft := BoxMesh.new()
		shaft.size = Vector3(0.06, 0.06, 0.9)
		_mesh.mesh = shaft
		mat.albedo_color = Color(0.85, 0.82, 0.7)
	else:
		var ball := SphereMesh.new()
		ball.radius = 0.35
		ball.height = 0.7
		_mesh.mesh = ball
		mat.albedo_color = EFFECTS.FIRE_COLOR
		mat.emission_enabled = true
		mat.emission = EFFECTS.FIRE_COLOR
	_mesh.material_override = mat
	add_child(_mesh)


## Свои же зоны попадания и своя капсула не должны ловить только что
## выпущенный снаряд.
func _collect_exclusions() -> void:
	var shooter := get_parent().get_parent().get_node_or_null("Players/%d" % shooter_id)
	if shooter == null or not shooter.has_method("own_collision_rids"):
		return
	_exclude = shooter.own_collision_rids()


func _physics_process(delta: float) -> void:
	if not Net.hosting():
		# Клиент только сглаживает присланную позицию.
		position = position.lerp(sync_position, clampf(delta * 20.0, 0.0, 1.0))
		_face_travel()
		return

	_life += delta
	if _life > WEAPONS.PROJECTILE_LIFETIME:
		queue_free()
		return

	var from := global_position
	var to := from + _velocity * delta
	_velocity.y -= 4.0 * delta          # лёгкая дуга, чтобы стрельба читалась

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = HIT_MASK
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.exclude = _exclude

	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		global_position = to
		sync_position = to
		_face_travel()
		return

	_resolve_hit(hit)


func _face_travel() -> void:
	if _velocity.length_squared() > 0.01 and _mesh != null:
		look_at(global_position + _velocity, Vector3.UP)


func _resolve_hit(hit: Dictionary) -> void:
	var point: Vector3 = hit["position"]
	global_position = point
	sync_position = point

	if kind == WEAPONS.Kind.SPELL:
		_explode(point)
	else:
		var zone := hit.get("collider") as Area3D
		if zone != null and zone.has_method("owner_character"):
			var target: Node3D = zone.owner_character()
			if target != null:
				var damage: float = (WEAPONS.DAMAGE[kind] * zone.damage_multiplier
					* WEAPONS.gear_damage(gear_tier))
				target.take_damage(damage, shooter_id, zone.zone, point, _velocity.normalized())
		else:
			# Воткнулась в землю или стену — просто показать.
			_show_impact.rpc(point, false)
	queue_free()


## Взрыв: урон по площади с падением к краю радиуса. Каждой цели — один раз.
func _explode(point: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = WEAPONS.SPELL_BLAST_RADIUS
	query.shape = sphere
	query.transform = Transform3D(Basis(), point)
	query.collision_mask = 4
	query.collide_with_areas = true
	query.collide_with_bodies = false

	var nearest := {}
	for result in space.intersect_shape(query, 32):
		var zone := result.get("collider") as Area3D
		if zone == null or not zone.has_method("owner_character"):
			continue
		var target: Node3D = zone.owner_character()
		if target == null:
			continue
		var d: float = zone.global_position.distance_to(point)
		if not nearest.has(target) or d < nearest[target][1]:
			nearest[target] = [zone, d]

	for target in nearest.keys():
		var zone: Area3D = nearest[target][0]
		var dist: float = nearest[target][1]
		var falloff := clampf(1.0 - dist / WEAPONS.SPELL_BLAST_RADIUS, 0.0, 1.0)
		var damage: float = (WEAPONS.DAMAGE[kind] * zone.damage_multiplier * falloff
			* WEAPONS.gear_damage(gear_tier))
		if damage > 0.5:
			var dir: Vector3 = (target.global_position - point).normalized()
			# Флаг «по площади»: рассыпной строй именно его и гасит.
			target.take_damage(damage, shooter_id, zone.zone, zone.global_position, dir, true)

	_show_impact.rpc(point, true)


@rpc("authority", "call_local", "unreliable")
func _show_impact(point: Vector3, blast: bool) -> void:
	var world := get_parent().get_parent()
	if blast:
		EFFECTS.explosion(world, point, WEAPONS.SPELL_BLAST_RADIUS)
