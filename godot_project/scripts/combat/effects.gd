extends RefCounted
##
## Визуальные эффекты боя. Рейтинг проекта 21+ (GDD, разделы 3-4), кровь
## показываем без смягчения.
##
## Всё здесь — чисто локальная отрисовка. Эффект запускается по RPC от хоста
## одновременно у всех, но сам по себе ни на что в игре не влияет.
##

const BLOOD_COLOR := Color(0.72, 0.05, 0.04)
const FIRE_COLOR := Color(1.0, 0.55, 0.12)


## Брызги крови в точке попадания. amount задаёт густоту: чем сильнее удар,
## тем больше частиц.
static func blood(world: Node, point: Vector3, direction: Vector3, amount: float) -> void:
	var count := clampi(int(amount * 0.8), 8, 64)
	_burst(world, point, direction, count, BLOOD_COLOR, 0.16, 5.0, 1.6)


## Вспышка взрыва огненного шара.
static func explosion(world: Node, point: Vector3, radius: float) -> void:
	_burst(world, point, Vector3.UP, 64, FIRE_COLOR, 0.35, radius * 1.6, 0.9)


static func _burst(
	world: Node, point: Vector3, direction: Vector3, count: int,
	color: Color, size: float, speed: float, lifetime: float
) -> void:
	if world == null or not world.is_inside_tree():
		return

	var particles := GPUParticles3D.new()
	particles.amount = count
	particles.lifetime = lifetime
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.emitting = true

	var mat := ParticleProcessMaterial.new()
	mat.direction = direction.normalized() if direction.length() > 0.01 else Vector3.UP
	mat.spread = 60.0
	mat.initial_velocity_min = speed * 0.4
	mat.initial_velocity_max = speed
	mat.gravity = Vector3(0.0, -9.8, 0.0)
	mat.scale_min = 0.5
	mat.scale_max = 1.4
	mat.color = color
	particles.process_material = mat

	var mesh := QuadMesh.new()
	mesh.size = Vector2(size, size)
	var surface := StandardMaterial3D.new()
	# Цвет несёт вершинный канал частиц, поэтому база белая: иначе цвет
	# умножается сам на себя и тёмно-красный уходит почти в чёрный.
	surface.albedo_color = Color.WHITE
	surface.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	surface.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	surface.vertex_color_use_as_albedo = true
	mesh.material = surface
	particles.draw_pass_1 = mesh

	world.add_child(particles)
	particles.global_position = point

	# Убираем за собой: партиклы одноразовые, держать их в сцене незачем.
	var timer := world.get_tree().create_timer(lifetime + 0.5)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(particles):
			particles.queue_free()
	)
