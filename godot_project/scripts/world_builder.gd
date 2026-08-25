class_name WorldBuilder
extends RefCounted
##
## Процедурный grey-box карты из 4 зон (Этап 1).
##
## Геометрия строится кодом с ФИКСИРОВАННЫМ сидом: результат одинаков на всех
## пирах, поэтому карту не нужно реплицировать по сети вообще.
##
## Это заглушка по смыслу GDD (раздел 9, этап 1) — объёмы и планировка, чтобы
## проверить масштаб и камеру. Позже её заменят сцены, собранные руками.
##

## Карта занимает от -600 до +600 по X и Z. Зона — четверть, 600x600 м.
const RES := preload("res://scripts/economy/resources.gd")

const WORLD_SIZE := 1200.0
const ZONE_SIZE := 600.0
const ZONE_HALF := ZONE_SIZE * 0.5

## Верстак у точки спавна: здесь ставят протезы и берут коляску.
const WORKBENCH_POS := Vector3(-24.0, 0.0, 22.0)

## Шахта злодея: далеко от форта, ресурсы оттуда возит караван (GDD 2.3).
const MINE_POS := Vector3(-470.0, 0.0, 470.0)

enum Zone { ELVES, EMPEROR, VILLAIN, HUMANS }

const ZONE_CENTERS := {
	Zone.ELVES: Vector2(-300.0, -300.0),
	Zone.EMPEROR: Vector2(300.0, -300.0),
	Zone.VILLAIN: Vector2(-300.0, 300.0),
	Zone.HUMANS: Vector2(300.0, 300.0),
}

const ZONE_NAMES := {
	Zone.ELVES: "Зона эльфов",
	Zone.EMPEROR: "Зона императора",
	Zone.VILLAIN: "Зона злодея",
	Zone.HUMANS: "Зона людей",
}

var _materials := {}
var _root: Node3D


func build(root: Node3D) -> void:
	_root = root
	_make_materials()
	_build_ground()
	_build_roads()
	_build_elves(ZONE_CENTERS[Zone.ELVES])
	_build_emperor(ZONE_CENTERS[Zone.EMPEROR])
	_build_villain(ZONE_CENTERS[Zone.VILLAIN])
	_build_humans(ZONE_CENTERS[Zone.HUMANS])
	_build_crossroads()


func _make_materials() -> void:
	_add_material("ground", Color(0.36, 0.40, 0.32))
	_add_material("road", Color(0.46, 0.42, 0.35))
	_add_material("stone", Color(0.55, 0.55, 0.58))
	_add_material("dark_stone", Color(0.34, 0.33, 0.36))
	_add_material("wood", Color(0.45, 0.32, 0.20))
	_add_material("foliage", Color(0.24, 0.44, 0.24))
	_add_material("trunk", Color(0.33, 0.25, 0.17))
	_add_material("marble", Color(0.80, 0.78, 0.72))
	_add_material("rock", Color(0.42, 0.38, 0.36))
	_add_material("accent", Color(0.72, 0.24, 0.22))


func _add_material(key: String, color: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	_materials[key] = mat


## Коробка с коллизией. pos — центр коробки.
func _box(parent: Node3D, pos: Vector3, size: Vector3, mat: String, yaw: float = 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.transform = Transform3D(Basis(Vector3.UP, yaw), pos)

	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _materials[mat]
	body.add_child(mesh)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)

	parent.add_child(body)
	return body


## Цилиндр с коллизией. pos — центр цилиндра.
func _cylinder(parent: Node3D, pos: Vector3, radius: float, height: float, mat: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos

	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	cyl.radial_segments = 8
	mesh.mesh = cyl
	mesh.material_override = _materials[mat]
	body.add_child(mesh)

	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	col.shape = shape
	body.add_child(col)

	parent.add_child(body)
	return body


## Наклонная плита-пандус: подъём rise метров на длине run метров.
## Угол выходит пологим (около 8 градусов), так что CharacterBody3D по ней
## поднимается штатно — floor_max_angle по умолчанию 45 градусов.
func _ramp(parent: Node3D, foot: Vector3, width: float, run: float, rise: float, mat: String) -> StaticBody3D:
	var length := sqrt(run * run + rise * rise)
	var pitch := atan2(rise, run)
	var body := StaticBody3D.new()
	# foot — точка у земли; плита уходит вверх в сторону -Z.
	var centre := foot + Vector3(0.0, rise * 0.5, -run * 0.5)
	body.transform = Transform3D(Basis(Vector3.RIGHT, pitch), centre)

	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(width, 2.0, length)
	mesh.mesh = box
	mesh.material_override = _materials[mat]
	body.add_child(mesh)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, 2.0, length)
	col.shape = shape
	body.add_child(col)

	parent.add_child(body)
	return body


## Конус (крона, крыша). Без коллизии — она уже есть у ствола или стен.
func _cone(parent: Node3D, pos: Vector3, radius: float, height: float, mat: String) -> void:
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.0
	cyl.bottom_radius = radius
	cyl.height = height
	cyl.radial_segments = 8
	mesh.mesh = cyl
	mesh.material_override = _materials[mat]
	mesh.position = pos
	parent.add_child(mesh)


func _group(group_name: String) -> Node3D:
	var node := Node3D.new()
	node.name = group_name
	_root.add_child(node)
	return node


func _build_ground() -> void:
	var g := _group("Ground")
	_box(g, Vector3(0, -1.0, 0), Vector3(WORLD_SIZE, 2.0, WORLD_SIZE), "ground")

	# Стены по краю карты, чтобы нельзя было уйти в пустоту.
	var h := WORLD_SIZE * 0.5
	for i in 4:
		var yaw := PI * 0.5 * i
		var dir := Vector3(sin(yaw), 0.0, cos(yaw))
		_box(g, dir * h + Vector3.UP * 10.0, Vector3(WORLD_SIZE, 20.0, 4.0), "dark_stone", yaw)


func _build_roads() -> void:
	var g := _group("Roads")
	# Крест через центр карты: связывает все четыре зоны.
	_box(g, Vector3(0, 0.05, 0), Vector3(WORLD_SIZE, 0.1, 14.0), "road")
	_box(g, Vector3(0, 0.05, 0), Vector3(14.0, 0.1, WORLD_SIZE), "road")


func _build_crossroads() -> void:
	# Ориентир в центре карты: видно, где сходятся все четыре зоны.
	var g := _group("Crossroads")
	# Верстак и медпункт: здесь ставят протезы и берут коляску (Этап 3).
	# Оплата и крафт появятся вместе с экономикой и ресурсами (Этапы 4-5),
	# сейчас выдача бесплатная — заглушка, помеченная в коде и в README.
	_box(g, Vector3(WORKBENCH_POS.x, 1.2, WORKBENCH_POS.z), Vector3(6.0, 2.4, 3.0), "wood")
	_box(g, Vector3(WORKBENCH_POS.x, 2.7, WORKBENCH_POS.z), Vector3(6.6, 0.6, 3.6), "stone")
	_cylinder(g, Vector3(WORKBENCH_POS.x - 3.6, 2.0, WORKBENCH_POS.z), 0.4, 4.0, "accent")
	_cylinder(g, Vector3(0, 6.0, 0), 3.0, 12.0, "marble")
	_box(g, Vector3(0, 13.0, 0), Vector3(4.0, 2.0, 4.0), "accent")
	# Малая полоса препятствий у спавна — быстрая проверка прыжка и ступеней.
	for i in 3:
		_box(g, Vector3(30.0 + i * 12.0, 0.4 + i * 0.8, 25.0), Vector3(10.0, 0.8 + i * 1.6, 10.0), "stone")

	_build_starting_resources(g)


func _build_elves(c: Vector2) -> void:
	var g := _group("ZoneElves")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3615                                   # фиксированный сид: лес одинаков у всех

	for i in 220:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * (ZONE_HALF - 30.0)
		if r < 70.0:
			continue                                  # поляна вокруг поселения
		var p := c + Vector2(cos(a), sin(a)) * r
		var th := rng.randf_range(10.0, 20.0)
		_harvestable(_cylinder(g, Vector3(p.x, th * 0.5, p.y), 1.1, th, "trunk"), RES.Kind.WOOD)
		_cone(g, Vector3(p.x, th + 5.0, p.y), 5.5, 12.0, "foliage")

	# Поселение на сваях.
	for i in 7:
		var a := TAU * i / 7.0
		var p := c + Vector2(cos(a), sin(a)) * 45.0
		for leg in 4:
			var ox := 6.0 if leg % 2 == 0 else -6.0
			var oz := 6.0 if leg < 2 else -6.0
			_cylinder(g, Vector3(p.x + ox, 3.0, p.y + oz), 0.6, 6.0, "wood")
		_box(g, Vector3(p.x, 7.5, p.y), Vector3(16.0, 3.0, 16.0), "wood")
		_cone(g, Vector3(p.x, 11.5, p.y), 12.0, 6.0, "foliage")


func _build_emperor(c: Vector2) -> void:
	var g := _group("ZoneEmperor")
	# Плато, на нём дворец за стеной.
	_box(g, Vector3(c.x, 3.0, c.y), Vector3(360.0, 6.0, 360.0), "stone")
	# Пандус на плато: без него 6-метровый уступ непроходим — прыжок берёт 1.5 м.
	_ramp(g, Vector3(c.x, -1.0, c.y + 225.0), 40.0, 45.0, 6.0, "stone")

	var w := 130.0
	# Стена с проёмом с южной стороны (со стороны центра карты).
	_box(g, Vector3(c.x, 12.0, c.y - w), Vector3(w * 2.0, 12.0, 6.0), "marble")
	_box(g, Vector3(c.x - w, 12.0, c.y), Vector3(6.0, 12.0, w * 2.0), "marble")
	_box(g, Vector3(c.x + w, 12.0, c.y), Vector3(6.0, 12.0, w * 2.0), "marble")
	_box(g, Vector3(c.x - 75.0, 12.0, c.y + w), Vector3(116.0, 12.0, 6.0), "marble")
	_box(g, Vector3(c.x + 75.0, 12.0, c.y + w), Vector3(116.0, 12.0, 6.0), "marble")

	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_cylinder(g, Vector3(c.x + sx * w, 16.0, c.y + sz * w), 9.0, 20.0, "marble")

	# Дворец.
	_box(g, Vector3(c.x, 18.0, c.y), Vector3(90.0, 24.0, 60.0), "marble")
	_box(g, Vector3(c.x, 33.0, c.y), Vector3(60.0, 6.0, 40.0), "marble")
	_cylinder(g, Vector3(c.x, 44.0, c.y), 12.0, 28.0, "marble")
	_cone(g, Vector3(c.x, 62.0, c.y), 15.0, 14.0, "accent")


func _build_villain(c: Vector2) -> void:
	var g := _group("ZoneVillain")
	var rng := RandomNumberGenerator.new()
	rng.seed = 2989

	# Горы по краю зоны.
	for i in 40:
		var a := rng.randf() * TAU
		var r := 150.0 + rng.randf() * (ZONE_HALF - 170.0)
		var p := c + Vector2(cos(a), sin(a)) * r
		var mh := rng.randf_range(24.0, 70.0)
		var mw := rng.randf_range(30.0, 70.0)
		_harvestable(_box(g, Vector3(p.x, mh * 0.5, p.y), Vector3(mw, mh, mw), "rock", rng.randf() * PI), RES.Kind.STONE, 10)

	# Форт: стены, донжон, казарма, склад.
	var f := c + Vector2(0.0, -40.0)
	var w := 80.0
	_box(g, Vector3(f.x, 8.0, f.y - w), Vector3(w * 2.0, 16.0, 5.0), "dark_stone")
	_box(g, Vector3(f.x - w, 8.0, f.y), Vector3(5.0, 16.0, w * 2.0), "dark_stone")
	_box(g, Vector3(f.x + w, 8.0, f.y), Vector3(5.0, 16.0, w * 2.0), "dark_stone")
	_box(g, Vector3(f.x - 50.0, 8.0, f.y + w), Vector3(65.0, 16.0, 5.0), "dark_stone")
	_box(g, Vector3(f.x + 50.0, 8.0, f.y + w), Vector3(65.0, 16.0, 5.0), "dark_stone")
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_cylinder(g, Vector3(f.x + sx * w, 11.0, f.y + sz * w), 8.0, 22.0, "dark_stone")

	_box(g, Vector3(f.x, 16.0, f.y - 20.0), Vector3(40.0, 32.0, 40.0), "dark_stone")  # донжон
	_box(g, Vector3(f.x - 45.0, 5.0, f.y + 30.0), Vector3(30.0, 10.0, 20.0), "wood")  # казарма
	_box(g, Vector3(f.x + 45.0, 5.0, f.y + 30.0), Vector3(30.0, 10.0, 20.0), "wood")  # склад

	# Шахта на удалении от форта — задел под маршрут каравана (GDD, этап 5).
	var m := Vector2(MINE_POS.x, MINE_POS.z)
	# Шахта: железо и золото. Полноценная добыча с караваном — Этап 5.
	_harvestable(_box(g, Vector3(m.x, 10.0, m.y), Vector3(50.0, 20.0, 50.0), "rock"), RES.Kind.IRON, 40)
	_box(g, Vector3(m.x, 4.0, m.y + 26.0), Vector3(14.0, 8.0, 6.0), "dark_stone")     # вход


func _build_humans(c: Vector2) -> void:
	var g := _group("ZoneHumans")
	var rng := RandomNumberGenerator.new()
	rng.seed = 273

	# Деревня: дома вдоль двух улиц.
	for i in 14:
		var row := -1.0 if i < 7 else 1.0
		var t := float(i % 7) - 3.0
		var p := c + Vector2(t * 34.0, row * 26.0)
		var hh := rng.randf_range(7.0, 11.0)
		_box(g, Vector3(p.x, hh * 0.5, p.y), Vector3(18.0, hh, 14.0), "wood")
		_cone(g, Vector3(p.x, hh + 3.0, p.y), 14.0, 6.0, "accent")

	# Рыночная площадь и колодец.
	_box(g, Vector3(c.x, 0.1, c.y), Vector3(80.0, 0.2, 20.0), "road")
	_cylinder(g, Vector3(c.x, 1.5, c.y), 4.0, 3.0, "stone")

	# Поля: низкие плиты, чтобы читался масштаб с высоты.
	for i in 10:
		var p := c + Vector2(rng.randf_range(-260.0, 260.0), rng.randf_range(-260.0, 260.0))
		if p.distance_to(c) < 90.0:
			continue
		_box(g, Vector3(p.x, 0.15, p.y), Vector3(60.0, 0.3, 40.0), "foliage", rng.randf() * PI)


## Пометить объект как источник ресурсов. Добычу считает хост, объект хранит
## только тип ресурса и остаток ударов (см. player.gd::_server_try_harvest).
func _harvestable(body: StaticBody3D, kind: int, hits: int = -1) -> void:
	if body == null:
		return
	body.add_to_group("harvestable")
	body.set_meta("resource", kind)
	body.set_meta("hits_left", hits if hits > 0 else RES.SOURCE_HITS)


## Рощица и камни у точки спавна: без них за первым деревом пришлось бы идти
## 300 метров в зону эльфов, и петля «добыл — построил» не проверялась бы.
func _build_starting_resources(g: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7717

	for i in 14:
		var a := rng.randf() * TAU
		var r := rng.randf_range(26.0, 60.0)
		var p := Vector2(cos(a), sin(a)) * r + Vector2(0.0, 30.0)
		var h := rng.randf_range(9.0, 15.0)
		_harvestable(_cylinder(g, Vector3(p.x, h * 0.5, p.y), 1.1, h, "trunk"), RES.Kind.WOOD)
		_cone(g, Vector3(p.x, h + 4.0, p.y), 5.0, 11.0, "foliage")

	for i in 9:
		var a := rng.randf() * TAU
		var r := rng.randf_range(30.0, 65.0)
		var p := Vector2(cos(a), sin(a)) * r + Vector2(-35.0, 5.0)
		var s := rng.randf_range(3.0, 5.5)
		_harvestable(_box(g, Vector3(p.x, s * 0.4, p.y), Vector3(s, s * 0.8, s), "rock", rng.randf() * PI), RES.Kind.STONE)
