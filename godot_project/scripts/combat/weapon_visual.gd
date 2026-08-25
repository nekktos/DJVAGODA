extends RefCounted
##
## Модель оружия в руке. Заглушка из примитивов, но держится правильно.
##
## Точка хвата берётся ИЗ ГАБАРИТОВ САМОЙ РУКИ, а не из захардкоженных чисел —
## по тому же принципу, что и зоны попадания. Поэтому оружие остаётся в кисти
## при смене модели и едет за рукой по анимации.
##
## Оси в местных координатах руки: y вниз по руке (кисть — нижний конец),
## +z — направление взгляда персонажа (корень модели развёрнут на 180°,
## см. player.gd::_build_model).
##

const WEAPONS := preload("res://scripts/combat/weapons.gd")

## Насколько вынести оружие вперёд от кисти и как высоко над нижним краем руки.
const GRIP_FORWARD := 0.55
const GRIP_RISE := 0.12


## Повесить оружие в руку, сняв предыдущее. Возвращает узел оружия.
static func attach(arm: MeshInstance3D, kind: int, previous: Node3D) -> Node3D:
	if previous != null and is_instance_valid(previous):
		previous.queue_free()
	if arm == null:
		return null

	var holder := Node3D.new()
	holder.name = "Weapon"
	_build(holder, kind)
	arm.add_child(holder)

	var box := arm.get_aabb()
	holder.position = Vector3(
		box.get_center().x,
		box.position.y + GRIP_RISE,
		box.get_center().z + GRIP_FORWARD
	)
	return holder


static func _build(holder: Node3D, kind: int) -> void:
	match kind:
		WEAPONS.Kind.BOW:
			# Лук держат вертикально, поперёк направления взгляда.
			_add_box(holder, Vector3(0.07, 1.30, 0.14), Vector3.ZERO, Color(0.52, 0.36, 0.20))
			_add_box(holder, Vector3(0.03, 1.24, 0.03), Vector3(0.0, 0.0, -0.10), Color(0.88, 0.86, 0.78))
		WEAPONS.Kind.SPELL:
			# Посох с навершием.
			_add_box(holder, Vector3(0.08, 0.08, 1.40), Vector3.ZERO, Color(0.35, 0.26, 0.18))
			_add_glow(holder, 0.16, Vector3(0.0, 0.0, 0.72))
		_:
			# Меч: клинок вперёд, гарда у кисти.
			_add_box(holder, Vector3(0.09, 0.09, 1.25), Vector3(0.0, 0.0, 0.10), Color(0.82, 0.84, 0.88))
			_add_box(holder, Vector3(0.34, 0.09, 0.09), Vector3(0.0, 0.0, -0.46), Color(0.55, 0.45, 0.22))
			_add_box(holder, Vector3(0.11, 0.11, 0.26), Vector3(0.0, 0.0, -0.62), Color(0.30, 0.22, 0.14))


static func _add_box(holder: Node3D, size: Vector3, offset: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.8
	mesh.material_override = mat
	mesh.position = offset
	holder.add_child(mesh)


static func _add_glow(holder: Node3D, radius: float, offset: Vector3) -> void:
	var mesh := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = radius
	ball.height = radius * 2.0
	mesh.mesh = ball
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.55, 0.12)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.55, 0.12)
	mesh.material_override = mat
	mesh.position = offset
	holder.add_child(mesh)
