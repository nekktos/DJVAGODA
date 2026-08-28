extends Node3D
##
## Куча ресурсов, высыпавшаяся из разбитого каравана.
##
## Подобрать может ЛЮБОЙ, кто подошёл (DESIGN_ANSWERS.md, пункт 15) — в этом и
## смысл грабежа: эльф не просто вредит злодею, а богатеет сам, а владелец
## может отбить своё обратно, если успеет.
##
## Кто и что забрал, решает ТОЛЬКО хост.
##

const RES := preload("res://scripts/economy/resources.gd")
const ROCK_MODEL := preload("res://assets/nature/rock_smallA.glb")

## На каком расстоянии подбирается.
const PICKUP_RANGE := 3.5
## Сколько лежит, прежде чем исчезнуть.
const LIFETIME := 240.0

@export var contents: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
## Уровень снаряжения, выпавший с убитого (Этап 10, шаг 1). 0 — снаряжения в
## куче нет, это обычный груз каравана.
@export var gear: int = 0

var _taken := false


func setup(data: Dictionary) -> void:
	position = data["point"]
	contents = data["contents"]
	gear = int(data.get("gear", 0))


func _ready() -> void:
	add_to_group("loot")

	_build_pile()

	if Net.hosting():
		get_tree().create_timer(LIFETIME).timeout.connect(func() -> void:
			if is_instance_valid(self):
				queue_free()
		)


## Сложить кучу из того, что в ней лежит.
##
## Раньше это был один жёлтый ящик на всё: подойдя, игрок не знал, дерево там
## или золото, пока не подберёт. А выбор «бежать за этой кучей или за той» —
## это и есть половина смысла грабежа, и делать его вслепую бессмысленно.
##
## Камень берём готовой моделью, остальное складываем из примитивов: брёвна
## лежат стопкой, слитки — пирамидкой, и то и другое читается с десяти метров
## лучше, чем ящик любого цвета.
func _build_pile() -> void:
	var kinds := []
	for i in RES.COUNT:
		if contents[i] > 0:
			kinds.append(i)
	if kinds.is_empty():
		# Куча может быть и пустой — с трупа со снаряжением, но без ресурсов.
		kinds.append(RES.Kind.WOOD)

	# Раскладываем сорта по кругу, чтобы куча из двух ресурсов не слипалась в
	# одно пятно.
	for i in kinds.size():
		var spot := Node3D.new()
		var angle := TAU * float(i) / float(kinds.size())
		var radius := 0.0 if kinds.size() == 1 else 0.55
		spot.position = Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		spot.rotation.y = angle
		add_child(spot)
		match kinds[i]:
			RES.Kind.WOOD: _build_logs(spot)
			RES.Kind.STONE: _build_rocks(spot)
			RES.Kind.IRON: _build_ingots(spot, Color(0.62, 0.64, 0.68), 0.75)
			RES.Kind.GOLD: _build_ingots(spot, Color(0.92, 0.74, 0.20), 0.95)


## Брёвна: три цилиндра лёжа, третье сверху в ложбинке.
func _build_logs(parent: Node3D) -> void:
	var log_mesh := CylinderMesh.new()
	log_mesh.top_radius = 0.16
	log_mesh.bottom_radius = 0.16
	log_mesh.height = 1.2
	var bark := StandardMaterial3D.new()
	bark.albedo_color = Color(0.42, 0.29, 0.17)
	var spots := [Vector3(-0.18, 0.16, 0.0), Vector3(0.18, 0.16, 0.0), Vector3(0.0, 0.45, 0.0)]
	for at in spots:
		var mesh := MeshInstance3D.new()
		mesh.mesh = log_mesh
		mesh.material_override = bark
		mesh.position = at
		# Цилиндр стоит вертикально, бревну надо лежать.
		mesh.rotation = Vector3(0.0, 0.0, PI * 0.5)
		parent.add_child(mesh)


func _build_rocks(parent: Node3D) -> void:
	var spots := [Vector3(-0.32, 0.0, -0.12), Vector3(0.32, 0.0, 0.18), Vector3(0.0, 0.26, 0.0)]
	for i in spots.size():
		var rock: Node3D = ROCK_MODEL.instantiate()
		rock.position = spots[i]
		rock.rotation.y = float(i) * 1.7
		# Камень мельче бревна по природе, и в натуральную величину куча камня
		# читалась как горстка щебня. Увеличиваем, чтобы её замечали с той же
		# дистанции, что и остальные.
		rock.scale = Vector3.ONE * (2.0 if i < 2 else 1.4)
		parent.add_child(rock)
		# Материал в самой модели бирюзовый и зеркальный: Kenney красит их
		# палитрой в текстуре, а без неё камень выглядит пластиковым.
		_repaint_stone(rock)


func _repaint_stone(model: Node3D) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.55, 0.58)
	mat.roughness = 0.9
	for mesh in _all_meshes(model):
		for surface in mesh.mesh.get_surface_count():
			mesh.set_surface_override_material(surface, mat)


func _all_meshes(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		found.append(node as MeshInstance3D)
	for child in node.get_children():
		found.append_array(_all_meshes(child))
	return found


## Слитки: пирамидка из брусков. Металл блестит, и по блеску железо отличают от
## золота даже те, кто не разбирает цвета.
func _build_ingots(parent: Node3D, tint: Color, metal: float) -> void:
	var bar := BoxMesh.new()
	bar.size = Vector3(1.0, 0.24, 0.34)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.metallic = metal
	mat.roughness = 0.32
	# Три бруска в основании и два сверху: пирамидка читается как слитки, а
	# один брусок — как жёлтый кирпич непонятного назначения.
	var rows := [
		[Vector3(0.0, 0.12, -0.38), Vector3(0.0, 0.12, 0.0), Vector3(0.0, 0.12, 0.38)],
		[Vector3(0.0, 0.36, -0.19), Vector3(0.0, 0.36, 0.19)],
	]
	for row in rows:
		for at in row:
			var mesh := MeshInstance3D.new()
			mesh.mesh = bar
			mesh.material_override = mat
			mesh.position = at
			parent.add_child(mesh)


## Отдать содержимое подошедшему. Только на хосте.
func collect(player: Node3D) -> int:
	if not Net.hosting() or _taken or player == null:
		return 0
	if global_position.distance_to(player.global_position) > PICKUP_RANGE:
		return 0
	var total := 0
	for kind in RES.COUNT:
		total += player.stock.add(kind, contents[kind])

	# Снаряжение с трупа достаётся тому, у кого оно хуже. Своё лучшее на худшее
	# не меняем — иначе подобрать чужую кучу значило бы понизить себя.
	var took_gear := false
	if gear > int(player.gear_tier):
		player.gear_tier = gear
		took_gear = true

	if total <= 0 and not took_gear:
		return 0
	_taken = true
	print("[груз] игрок %d подобрал %d единиц%s"
		% [int(player.peer_id), total, ", снаряжение уровня %d" % gear if took_gear else ""])
	queue_free()
	return total


func summary() -> String:
	var parts := PackedStringArray()
	for i in RES.COUNT:
		if contents[i] > 0:
			parts.append("%s %d" % [RES.SHORT[i], contents[i]])
	return ", ".join(parts)
