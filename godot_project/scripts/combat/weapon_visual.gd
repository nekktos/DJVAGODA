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

## Цвет металла по уровню снаряжения (Этап 10). Купленный апгрейд должен быть
## ВИДЕН: иначе игрок платит 180 золота и выглядит ровно как раньше, а чужой
## уровень в бою не прочитать вовсе.
##
## Различаем именно металлом, а не формой: форма — это тип оружия, и путать два
## разных смысла в одном силуэте нельзя.
const TIER_METAL := [
	Color(0.82, 0.84, 0.88),
	Color(0.62, 0.74, 0.92),
	Color(0.95, 0.84, 0.42),
]
## Верхний уровень ещё и светится: в сумерках леса цвета мало.
const TIER_GLOW := 0.35


## Повесить оружие в руку, сняв предыдущее. Возвращает узел оружия.
static func attach(arm: MeshInstance3D, kind: int, previous: Node3D, tier: int = 0) -> Node3D:
	if previous != null and is_instance_valid(previous):
		previous.queue_free()
	if arm == null:
		return null

	var holder := Node3D.new()
	holder.name = "Weapon"
	_build(holder, kind, clampi(tier, 0, TIER_METAL.size() - 1))
	arm.add_child(holder)

	var box := arm.get_aabb()
	holder.position = Vector3(
		box.get_center().x,
		box.position.y + GRIP_RISE,
		box.get_center().z + GRIP_FORWARD
	)
	return holder


## Повесить оружие в готовую точку хвата. Возвращает узел оружия.
##
## У скелетной модели точка хвата уже есть — кость `Weapon.R`, поставленная
## художником там, где кисть смыкается. Считать её по габаритам руки, как для
## коробочной модели, не надо и вредно: габариты скиннутого меша — это габариты
## ВСЕГО тела, и оружие уехало бы человеку в живот.
static func attach_at(mount: Node3D, kind: int, previous: Node3D, tier: int = 0) -> Node3D:
	if previous != null and is_instance_valid(previous):
		previous.queue_free()
	if mount == null:
		return null
	var holder := Node3D.new()
	holder.name = "Weapon"
	_build(holder, kind, clampi(tier, 0, TIER_METAL.size() - 1))
	mount.add_child(holder)
	return holder


static func _build(holder: Node3D, kind: int, tier: int) -> void:
	var metal: Color = TIER_METAL[tier]
	var glow: float = TIER_GLOW if tier >= TIER_METAL.size() - 1 else 0.0
	match kind:
		WEAPONS.Kind.BOW:
			_bow(holder, metal, glow)
		WEAPONS.Kind.SPELL:
			# Посох с навершием.
			_add_box(holder, Vector3(0.08, 0.08, 1.40), Vector3.ZERO, Color(0.35, 0.26, 0.18), 0.0)
			_add_box(holder, Vector3(0.10, 0.10, 0.18), Vector3(0.0, 0.0, 0.55), metal, glow)
			_add_glow(holder, 0.16, Vector3(0.0, 0.0, 0.72))
		WEAPONS.Kind.CROSSBOW:
			# Арбалет: ложе вдоль взгляда, дуга поперёк на конце, тетива поперёк
			# ложа. Силуэт обязан читаться как «не лук» — иначе эльфа от
			# стражника издали не отличить.
			_add_box(holder, Vector3(0.10, 0.09, 0.85), Vector3(0.0, 0.0, 0.12), Color(0.40, 0.29, 0.17), 0.0)
			_add_box(holder, Vector3(0.09, 0.16, 0.22), Vector3(0.0, -0.06, -0.24), Color(0.34, 0.24, 0.14), 0.0)
			for side in [-1.0, 1.0]:
				_add_tilted(holder, Vector3(0.36, 0.05, 0.07),
					Vector3(side * 0.20, 0.0, 0.46), Vector3(0.0, 0.0, side * 0.25), metal, glow)
			_add_box(holder, Vector3(0.76, 0.02, 0.02), Vector3(0.0, 0.0, 0.40), Color(0.86, 0.84, 0.78), 0.0)
		WEAPONS.Kind.AXE:
			# Топор: короткое древко и широкое лезвие сбоку.
			_add_box(holder, Vector3(0.07, 0.07, 0.95), Vector3(0.0, 0.0, 0.05), Color(0.45, 0.32, 0.19), 0.0)
			_add_box(holder, Vector3(0.30, 0.34, 0.10), Vector3(0.13, 0.0, 0.44), metal, glow)
		WEAPONS.Kind.HAMMER:
			# Молот: длинное древко и тяжёлая голова — он должен выглядеть тяжёлым.
			_add_box(holder, Vector3(0.09, 0.09, 1.25), Vector3(0.0, 0.0, 0.10), Color(0.38, 0.27, 0.16), 0.0)
			_add_box(holder, Vector3(0.30, 0.30, 0.34), Vector3(0.0, 0.0, 0.62), metal, glow)
		_:
			# Меч: клинок вперёд, гарда у кисти.
			_add_box(holder, Vector3(0.09, 0.09, 1.25), Vector3(0.0, 0.0, 0.10), metal, glow)
			_add_box(holder, Vector3(0.34, 0.09, 0.09), Vector3(0.0, 0.0, -0.46), metal * 0.7, 0.0)
			_add_box(holder, Vector3(0.11, 0.11, 0.26), Vector3(0.0, 0.0, -0.62), Color(0.30, 0.22, 0.14), 0.0)


## Лук: две гнутые дуги и прямая тетива между их концами.
##
## До этого лук был ОДНОЙ коробкой метр тридцать высотой — то есть палкой, и
## выглядел ровно как палка. Дуга набирается из отрезков с нарастающим наклоном:
## это дороже одной коробки на пять мешей, но силуэт лука узнаётся мгновенно, а
## узнаваемость силуэта — единственное, ради чего эти заглушки вообще рисуются.
##
## Оси местные: +Y вверх по луку, +Z — куда смотрит персонаж. Пузо дуги смотрит
## вперёд (+Z), тетива остаётся у стрелка (-Z) — как у настоящего лука, и по
## этой асимметрии видно, куда он целится.
static func _bow(holder: Node3D, metal: Color, glow: float) -> void:
	var wood := Color(0.52, 0.36, 0.20)
	# Рукоять: чуть толще плеч, по ней и держат.
	_add_box(holder, Vector3(0.07, 0.26, 0.10), Vector3.ZERO, wood.darkened(0.15), 0.0)
	# Плечи: по три отрезка вверх и вниз, каждый следующий отогнут сильнее.
	var steps := [
		[0.22, 0.10, 0.10],
		[0.44, 0.06, 0.35],
		[0.62, 0.00, 0.70],
	]
	for side in [-1.0, 1.0]:
		for step in steps:
			var y: float = side * float(step[0])
			var z: float = float(step[1])
			var tilt: float = side * float(step[2])
			_add_tilted(holder, Vector3(0.05, 0.26, 0.07),
				Vector3(0.0, y, z), Vector3(tilt, 0.0, 0.0), wood, 0.0)
	# Тетива: прямая между концами плеч, у стрелка. Металл — на ней: древко
	# деревянное на любом уровне снаряжения, а уровень видно по нити.
	_add_box(holder, Vector3(0.02, 1.34, 0.02), Vector3(0.0, 0.0, -0.06), metal, glow)


## Коробка с наклоном. Углы в радианах по осям X, Y, Z.
static func _add_tilted(holder: Node3D, size: Vector3, offset: Vector3, tilt: Vector3,
		color: Color, glow: float = 0.0) -> void:
	var before: int = holder.get_child_count()
	_add_box(holder, size, offset, color, glow)
	var mesh: Node3D = holder.get_child(before)
	mesh.rotation = tilt


static func _add_box(holder: Node3D, size: Vector3, offset: Vector3, color: Color, glow: float = 0.0) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.8
	if glow > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = glow
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
