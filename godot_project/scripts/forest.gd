extends Node3D
##
## Лес зоны эльфов с impostor-LOD (GDD раздел 5).
##
## Деревья НЕ создаются нодами заранее: их описывает массив данных,
## сгенерированный по фиксированному сиду. Лес поэтому одинаков на всех пирах и
## по сети не реплицируется — как и остальная карта (world_builder.gd).
##
## Три состояния дерева:
##   - далеко   — одна инстанция в MultiMesh, billboard-квад, без физики;
##   - близко   — настоящий 3D: ствол с коллизией и крона;
##   - срублено — не отрисовывается нигде.
##
## Переход далеко<->близко идёт с ГИСТЕРЕЗИСОМ: входим на одном радиусе,
## выходим на большем. Без него дерево, стоящее ровно на границе, мигает
## туда-сюда каждый кадр — это ровно та проблема, которую GDD называет
## «настройка перехода без мигания».
##
## Физику определяет близость к ИГРОВЫМ ОБЪЕКТАМ, а не к камере. Камера у
## каждого пира своя, а бой считает хост за всех: если бы коллизия зависела от
## камеры, стрела пролетала бы сквозь дерево рядом с далёким игроком.
##

const RES := preload("res://scripts/economy/resources.gd")

## Сколько деревьев в лесу. В grey-box было 220 на зону 600x600 — одно дерево
## на 1600 м², редколесье. При таких числах impostor-система не окупается.
##
## Верхний предел задаёт не производительность, а полог: при 3200 кроны
## перекрывают землю на 170%, под лесом наступает полная темнота и сквозь него
## не пройти. 1700 дают сомкнутость около 60% — светлые прогалы остаются.
const TREE_COUNT := 1700

## Вокруг игроков и бойцов: дерево твёрдое и объёмное.
const SOLID_RADIUS := 70.0
const SOLID_RELEASE := 88.0
## Вокруг локальной камеры: дерево объёмное, но может быть без физики.
const VISUAL_RADIUS := 110.0
const VISUAL_RELEASE := 135.0

## Пересчёт LOD 8 раз в секунду. Чаще не нужно: за 125 мс бегущий персонаж
## проходит меньше метра, а запас гистерезиса — 18 метров.
const UPDATE_INTERVAL := 0.125

## Размер ячейки пространственной сетки, метры. Сетка нужна, чтобы не
## перебирать все 3200 деревьев для каждого игрока восемь раз в секунду.
const CELL := 32.0

## Пропорции дерева при масштабе 1. Билборд рисуется ПО ЭТИМ ЖЕ числам —
## иначе силуэт прыгнет в момент подмены, и весь смысл гистерезиса пропадёт.
const TRUNK_H := 11.0
const TRUNK_R := 1.1
const CROWN_R := 4.4
## Крона начинается чуть ниже верхушки ствола, чтобы не было щели.
const CROWN_BASE := 10.0
const CROWN_TOP := 22.0
const TREE_H := CROWN_TOP

const TRUNK_COLOR := Color(0.33, 0.25, 0.17)
const CROWN_COLOR := Color(0.24, 0.44, 0.24)

## Разрешение билборда. Больше не нужно: на дистанции подмены дерево занимает
## заметно меньше пикселей.
const TEX_W := 64
const TEX_H := 128

# --- данные леса (одинаковы на всех пирах) ---------------------------------

var _pos := PackedVector3Array()
var _scale := PackedFloat32Array()
## Осталось ударов до падения. Меняет только ХОСТ.
var _hits := PackedInt32Array()
## 1 — дерево срублено. Синхронизируется с хоста.
var _felled := PackedByteArray()
## 1 — билборд дерева сейчас отрисовывается. Ведём сами, а не спрашиваем
## MultiMesh: в headless он данные инстанций не хранит вообще, и автопроверки
## читали бы единичную матрицу вместо настоящей.
var _impostor_on := PackedByteArray()
## Ячейка сетки (Vector2i) -> индексы деревьев в ней.
var _cells := {}

# --- отрисовка -------------------------------------------------------------

var _impostors: MultiMeshInstance3D
var _multimesh: MultiMesh
## Индекс дерева -> нода объёмного дерева.
var _near := {}
## Индексы, у которых сейчас есть коллизия (подмножество _near).
var _solid := {}

var _trunk_mesh: CylinderMesh
var _crown_mesh: CylinderMesh
var _trunk_material: StandardMaterial3D
var _crown_material: StandardMaterial3D

var _update_t := 0.0
var _players_root: Node3D


func _ready() -> void:
	_players_root = get_parent().get_node_or_null("Players")
	multiplayer.peer_connected.connect(_on_peer_connected)


## Построить лес. center — центр зоны, radius — до какого радиуса сажать,
## clearing — радиус поляны в середине, где деревьев нет (там поселение).
func build(center: Vector2, radius: float, clearing: float, tree_seed: int) -> void:
	_make_resources()

	var rng := RandomNumberGenerator.new()
	rng.seed = tree_seed

	var attempts := 0
	while _pos.size() < TREE_COUNT and attempts < TREE_COUNT * 4:
		attempts += 1
		var a := rng.randf() * TAU
		# Край леса «дышит» по углу: ровная окружность из деревьев на общем
		# плане читается как штамп, а не как лес.
		var wobble := 0.85 - 0.15 * (sin(a * 3.0) * 0.5 + sin(a * 7.0 + 2.1) * 0.3 + sin(a * 11.0 + 4.7) * 0.2)
		# sqrt даёт равномерную плотность по площади, а не сгущение к центру.
		var r := sqrt(rng.randf()) * radius * wobble
		if r < clearing:
			continue
		var p := center + Vector2(cos(a), sin(a)) * r
		_add_tree(Vector3(p.x, 0.0, p.y), rng.randf_range(0.75, 1.45))

	_build_grid()
	_build_impostors()


func _add_tree(pos: Vector3, s: float) -> void:
	_pos.append(pos)
	_scale.append(s)
	_hits.append(RES.SOURCE_HITS)
	_felled.append(0)
	_impostor_on.append(1)


func _build_grid() -> void:
	for i in _pos.size():
		var key := _cell_of(_pos[i])
		if not _cells.has(key):
			_cells[key] = PackedInt32Array()
		var bucket: PackedInt32Array = _cells[key]
		bucket.append(i)
		_cells[key] = bucket


func _cell_of(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / CELL)), int(floor(p.z / CELL)))


# --- ресурсы отрисовки -----------------------------------------------------

func _make_resources() -> void:
	_trunk_mesh = CylinderMesh.new()
	_trunk_mesh.top_radius = TRUNK_R
	_trunk_mesh.bottom_radius = TRUNK_R
	_trunk_mesh.height = TRUNK_H
	_trunk_mesh.radial_segments = 6

	_crown_mesh = CylinderMesh.new()
	_crown_mesh.top_radius = 0.0
	_crown_mesh.bottom_radius = CROWN_R
	_crown_mesh.height = CROWN_TOP - CROWN_BASE
	_crown_mesh.radial_segments = 7

	_trunk_material = StandardMaterial3D.new()
	_trunk_material.albedo_color = TRUNK_COLOR
	_trunk_material.roughness = 0.9

	_crown_material = StandardMaterial3D.new()
	_crown_material.albedo_color = CROWN_COLOR
	_crown_material.roughness = 0.9


func _build_impostors() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(CROWN_R * 2.0, TREE_H)

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _make_billboard_texture()
	# ALPHA_SCISSOR, а не полупрозрачность: билборды не нужно сортировать между
	# собой, и они корректно пишутся в буфер глубины.
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	# Порог занижен: мипмапы усредняют альфу, и при 0.5 дальние деревья
	# начинали бы растворяться.
	mat.alpha_scissor_threshold = 0.3
	# FIXED_Y, а не полный billboard: дерево не должно заваливаться, когда
	# камера смотрит сверху — стратегический режим именно так и смотрит.
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.billboard_keep_scale = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 1.0

	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.mesh = quad
	_multimesh.instance_count = _pos.size()

	for i in _pos.size():
		_multimesh.set_instance_transform(i, _impostor_transform(i))

	_impostors = MultiMeshInstance3D.new()
	_impostors.name = "Impostors"
	_impostors.multimesh = _multimesh
	_impostors.material_override = mat
	# Билборд повёрнут к камере, тень от него выглядит плоской кляксой.
	_impostors.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_impostors)


func _impostor_transform(index: int) -> Transform3D:
	var s: float = _scale[index]
	# QuadMesh центрирован, поэтому поднимаем его на половину высоты дерева.
	var origin: Vector3 = _pos[index] + Vector3(0.0, TREE_H * 0.5 * s, 0.0)
	return Transform3D(Basis().scaled(Vector3(s, s, s)), origin)


## Спрятать инстанцию в MultiMesh. Отдельного «выключить» у MultiMesh нет,
## поэтому схлопываем её в точку — вырожденные треугольники не растеризуются.
func _hide_impostor(index: int) -> void:
	_impostor_on[index] = 0
	_multimesh.set_instance_transform(index, Transform3D(Basis().scaled(Vector3.ZERO), _pos[index]))


func _show_impostor(index: int) -> void:
	if _felled[index] == 1:
		return
	_impostor_on[index] = 1
	_multimesh.set_instance_transform(index, _impostor_transform(index))


## Силуэт билборда рисуется теми же пропорциями, что и объёмное дерево.
func _make_billboard_texture() -> ImageTexture:
	var img := Image.create_empty(TEX_W, TEX_H, true, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))

	for py in TEX_H:
		# Мир: y=0 внизу картинки, y=TREE_H наверху.
		var wy := (1.0 - (py + 0.5) / float(TEX_H)) * TREE_H
		for px in TEX_W:
			var wx := ((px + 0.5) / float(TEX_W) - 0.5) * CROWN_R * 2.0
			var color := Color(0, 0, 0, 0)

			if wy >= CROWN_BASE:
				# Конус: полуширина линейно убывает к верхушке.
				var t := (CROWN_TOP - wy) / (CROWN_TOP - CROWN_BASE)
				if absf(wx) <= CROWN_R * t:
					# Низ кроны темнее — иначе плоский билборд рядом с
					# затенённым 3D-деревом бросается в глаза.
					color = CROWN_COLOR * (0.72 + 0.28 * t)
					color.a = 1.0
			if color.a == 0.0 and wy <= TRUNK_H and absf(wx) <= TRUNK_R:
				color = TRUNK_COLOR
				color.a = 1.0

			if color.a > 0.0:
				img.set_pixel(px, py, color)

	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# --- LOD -------------------------------------------------------------------

func _process(delta: float) -> void:
	if _pos.is_empty():
		return
	_update_t += delta
	if _update_t < UPDATE_INTERVAL:
		return
	_update_t = 0.0
	_update_lod()


func _update_lod() -> void:
	var actors := _actor_positions()
	var camera := get_viewport().get_camera_3d()

	# Кто должен быть твёрдым и кто объёмным на этот момент.
	var want_solid := {}
	for a in actors:
		_collect_around(a, SOLID_RADIUS, SOLID_RELEASE, _solid, want_solid)

	var want_near := want_solid.duplicate()
	if camera != null:
		_collect_around(camera.global_position, VISUAL_RADIUS, VISUAL_RELEASE, _near, want_near)

	# Убрать те, что вышли за радиус.
	for index in _near.keys():
		if not want_near.has(index):
			_drop_near(index)

	# Добавить новые и поправить наличие коллизии у существующих.
	for index in want_near:
		if _felled[index] == 1:
			continue
		var solid: bool = want_solid.has(index)
		if _near.has(index):
			_set_solid(index, solid)
		else:
			_spawn_near(index, solid)


## Радиусы с гистерезисом: дерево входит в набор на radius, а выходит только
## за release. current — набор прошлого кадра, out — куда складывать результат.
func _collect_around(point: Vector3, radius: float, release: float, current: Dictionary, out: Dictionary) -> void:
	var reach := int(ceil(release / CELL))
	var base := _cell_of(point)
	var r_in := radius * radius
	var r_out := release * release

	for cx in range(base.x - reach, base.x + reach + 1):
		for cz in range(base.y - reach, base.y + reach + 1):
			var bucket: PackedInt32Array = _cells.get(Vector2i(cx, cz), PackedInt32Array())
			for index in bucket:
				if _felled[index] == 1 or out.has(index):
					continue
				var d := _pos[index].distance_squared_to(point)
				var limit := r_out if current.has(index) else r_in
				if d <= limit:
					out[index] = true


func _actor_positions() -> Array[Vector3]:
	var result: Array[Vector3] = []
	if _players_root != null:
		for child in _players_root.get_children():
			if child is Node3D:
				result.append((child as Node3D).global_position)
	for unit in get_tree().get_nodes_in_group("unit"):
		if unit is Node3D:
			result.append((unit as Node3D).global_position)
	return result


func _spawn_near(index: int, solid: bool) -> void:
	var s: float = _scale[index]

	var body := StaticBody3D.new()
	body.position = _pos[index]
	# Метки те же, что у деревьев из world_builder: рубка узнаёт цель по группе.
	body.add_to_group("harvestable")
	body.set_meta("resource", RES.Kind.WOOD)
	# По этому индексу рубка адресует дерево в сети. Путь ноды для этого не
	# годится: объёмное дерево живёт только пока рядом кто-то есть.
	body.set_meta("tree", index)

	var trunk := MeshInstance3D.new()
	trunk.mesh = _trunk_mesh
	trunk.material_override = _trunk_material
	trunk.position = Vector3(0.0, TRUNK_H * 0.5 * s, 0.0)
	trunk.scale = Vector3(s, s, s)
	body.add_child(trunk)

	var crown := MeshInstance3D.new()
	crown.mesh = _crown_mesh
	crown.material_override = _crown_material
	crown.position = Vector3(0.0, (CROWN_BASE + CROWN_TOP) * 0.5 * s, 0.0)
	crown.scale = Vector3(s, s, s)
	body.add_child(crown)

	var col := CollisionShape3D.new()
	col.name = "Col"
	var shape := CylinderShape3D.new()
	shape.radius = TRUNK_R * s
	shape.height = TRUNK_H * s
	col.shape = shape
	col.position = Vector3(0.0, TRUNK_H * 0.5 * s, 0.0)
	col.disabled = not solid
	body.add_child(col)

	add_child(body)
	_near[index] = body
	if solid:
		_solid[index] = true
	_hide_impostor(index)


func _set_solid(index: int, solid: bool) -> void:
	if _solid.has(index) == solid:
		return
	var body: Node = _near.get(index)
	if body == null:
		return
	var col := body.get_node_or_null("Col") as CollisionShape3D
	if col != null:
		col.disabled = not solid
	if solid:
		_solid[index] = true
	else:
		_solid.erase(index)


func _drop_near(index: int) -> void:
	var body: Node = _near.get(index)
	if body != null:
		body.queue_free()
	_near.erase(index)
	_solid.erase(index)
	_show_impostor(index)


# --- рубка -----------------------------------------------------------------

## Удар по дереву. Считает только ХОСТ. Возвращает, сколько ударов осталось;
## -1 — индекс неверный или дерево уже срублено.
func hit_tree(index: int) -> int:
	if index < 0 or index >= _hits.size() or _felled[index] == 1:
		return -1
	_hits[index] -= 1
	return _hits[index]


func is_felled(index: int) -> bool:
	return index >= 0 and index < _felled.size() and _felled[index] == 1


## Индексы всех срубленных деревьев — для догрузки опоздавшему клиенту.
func felled_indices() -> PackedInt32Array:
	var result := PackedInt32Array()
	for i in _felled.size():
		if _felled[i] == 1:
			result.append(i)
	return result


@rpc("any_peer", "call_local", "reliable")
func fell_tree(index: int) -> void:
	if not _sender_is_host():
		return
	_apply_felled(index)


## Догрузка состояния леса тому, кто подключился позже. Без неё опоздавший
## видел бы уже срубленные деревья стоящими: fell_tree его не застал.
@rpc("any_peer", "reliable")
func sync_felled(indices: PackedInt32Array) -> void:
	if not _sender_is_host():
		return
	for index in indices:
		_apply_felled(index)


func _apply_felled(index: int) -> void:
	if index < 0 or index >= _felled.size() or _felled[index] == 1:
		return
	_felled[index] = 1
	_hits[index] = 0
	if _near.has(index):
		var body: Node = _near[index]
		if body != null:
			body.queue_free()
		_near.erase(index)
		_solid.erase(index)
	_hide_impostor(index)


func _sender_is_host() -> bool:
	var sender := multiplayer.get_remote_sender_id()
	return sender == 0 or sender == 1


func _on_peer_connected(id: int) -> void:
	if not Net.hosting():
		return
	var felled := felled_indices()
	if felled.is_empty():
		return
	sync_felled.rpc_id(id, felled)


# --- инспекция (автопроверки, консоль) -------------------------------------

func tree_count() -> int:
	return _pos.size()


func tree_position(index: int) -> Vector3:
	if index < 0 or index >= _pos.size():
		return Vector3.ZERO
	return _pos[index]


func hits_left(index: int) -> int:
	if index < 0 or index >= _hits.size():
		return -1
	return _hits[index]


## Сколько деревьев сейчас отрисовано объёмно, а не билбордом.
func near_count() -> int:
	return _near.size()


## Сколько деревьев сейчас имеет коллизию.
func solid_count() -> int:
	return _solid.size()


func is_near(index: int) -> bool:
	return _near.has(index)


func is_solid(index: int) -> bool:
	return _solid.has(index)


func felled_count() -> int:
	var n := 0
	for i in _felled.size():
		if _felled[i] == 1:
			n += 1
	return n


## Виден ли билборд дерева (не схлопнут ли он в точку).
func impostor_visible(index: int) -> bool:
	if index < 0 or index >= _impostor_on.size():
		return false
	return _impostor_on[index] == 1


## Пересчитать LOD немедленно. Нужно автопроверкам: ждать очередного тика
## в тесте бессмысленно.
func refresh_lod() -> void:
	_update_lod()
