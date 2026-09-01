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
const TEXTURES := preload("res://scripts/textures.gd")
const RELIEF := preload("res://scripts/relief.gd")
const ROCKS := preload("res://scripts/rocks.gd")

const WORLD_SIZE := 1200.0
const ZONE_SIZE := 600.0
const ZONE_HALF := ZONE_SIZE * 0.5

## Верстак у точки спавна: здесь ставят протезы и берут коляску.
const WORKBENCH_POS := Vector3(-24.0, 0.0, 22.0)

## Шахта: дальше всех от злодея и РОВНО посередине между эльфами и стражей.
##
## Место выбрано не на глаз, а построением. Точки, равноудалённые от эльфов
## (-300, -300) и стражи (300, -240), лежат на серединном перпендикуляре к
## отрезку между ними; из них берём самую дальнюю от форта злодея (-300, 296),
## не выходя за край мира. Получается север карты, у самой границы зон эльфов и
## императора.
##
## Зачем: караваны злодея должны быть добычей, а не формальностью. Со старой
## шахтой в углу самого злодея (-470, 470) обоз ехал 240 метров по своей же
## земле, и грабить его было негде и некому — до неё эльфам было 788 метров, а
## страже больше километра. Теперь путь идёт через всю карту мимо обеих чужих
## зон: 898 метров от форта, по 406 до эльфов и до стражи.
##
## Двадцать восемь метров вправо от нуля — не описка: без наклона равноудалённой
## точки не бывает вовсе, серединный перпендикуляр наклонён, потому что спавны
## эльфов и стражи стоят на разной высоте карты.
const MINE_POS := Vector3(28.0, 0.0, -540.0)

## Лавка эльфов: на поляне их поселения. Тратить награбленное можно только
## дойдя сюда (GDD раздел 2.1).
const TRADER_POS := Vector3(-300.0, 0.0, -272.0)

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
## Рельеф. Наружу торчит намеренно: по нему кладут всё, что стоит на земле, и
## спрашивать высоту обязаны у него, а не считать заново.
var relief: RefCounted
## Какую модель дерева ставить следующей. Не случайно: карта строится
## одинаково на всех пирах, и случайность здесь развела бы миры.
var _tree_pick := 0
var _root: Node3D


func build(root: Node3D) -> void:
	_root = root
	_make_materials()
	# Рельеф заводим ПЕРВЫМ: по нему потом кладут траву, камни и деревья, и
	# высота у всех должна быть одна и та же.
	relief = RELIEF.new(WORLD_SIZE, ZONE_CENTERS.values(), [
		Vector2(MINE_POS.x, MINE_POS.z),
		Vector2(TRADER_POS.x, TRADER_POS.z),
		Vector2(WORKBENCH_POS.x, WORKBENCH_POS.z),
		Vector2.ZERO,
	])
	_build_ground()
	_build_roads()
	_build_elves(ZONE_CENTERS[Zone.ELVES])
	_build_emperor(ZONE_CENTERS[Zone.EMPEROR])
	_build_villain(ZONE_CENTERS[Zone.VILLAIN])
	_build_humans(ZONE_CENTERS[Zone.HUMANS])
	_build_mine()
	_build_crossroads()
	_build_hamlets()
	_build_scatter()


func _make_materials() -> void:
	# Земля и рельеф — ОДНИМ материалом, и это не украшательство.
	#
	# Рельеф лежит поверх плоской подложки и во многих местах поднимается на
	# считанные сантиметры. Разными материалами эти места читались тёмными
	# многоугольными кляксами по всему полю — не холмами, а грязью на текстуре.
	# Одинаковый материал делает низкий рельеф незаметным, а высокий — холмом,
	# то есть ровно тем, чем он и должен быть.
	_materials["ground"] = TEXTURES.of("grass")
	_add_material("road", Color(0.46, 0.42, 0.35))
	_add_material("foliage", Color(0.24, 0.44, 0.24))
	_add_material("trunk", Color(0.33, 0.25, 0.17))
	_add_material("accent", Color(0.72, 0.24, 0.22))
	# Камень, кладка и доски — с текстурой, нарисованной кодом (`textures.gd`).
	# Именно из них сложены стены форта, дворец, донжон, казармы и горы, то есть
	# всё, на что игрок смотрит вблизи и подолгу. Земля, листва и стволы остаются
	# заливкой: землю видно под ногами вскользь, а листву и стволы давно закрыли
	# модели деревьев.
	for key in ["stone", "dark_stone", "marble", "wood", "rock"]:
		_materials[key] = TEXTURES.of(key)


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


## Камень настоящей формы. pos — точка НА ЗЕМЛЕ, камень встаёт на неё низом.
##
## Низом, а не центром: у коробки высоту делили пополам и считали от центра, а
## у булыжника низ неровный, и «половина высоты» промахивается то в землю, то в
## воздух. Проще класть его на землю и не думать.
func _rock(parent: Node3D, pos: Vector3, size: Vector3, yaw: float, seed_value: int) -> StaticBody3D:
	var body := ROCKS.build(size, yaw, seed_value, _materials["rock"])
	body.position = Vector3(pos.x, pos.y + size.y * 0.42, pos.z)
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
	# Подложку опускаем на пять сантиметров ПОД полотно рельефа.
	#
	# Рельеф теперь сплошной и накрывает карту целиком, а две совпадающие
	# плоскости на одной высоте дают мерцание по всему полю. Пять сантиметров
	# ничего не решают для игры и решают всё для картинки.
	_box(g, Vector3(0, -1.05, 0), Vector3(WORLD_SIZE, 2.0, WORLD_SIZE), "ground")
	# Холмы поверх плоской подложки. Подложка остаётся: на ней стоит вся игра
	# (см. шапку `relief.gd`), а холмы — добавка там, где ничего не построено.
	g.add_child(relief.build(TEXTURES.of("grass")))

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
	# Сам лес строит forest.gd: у него impostor-LOD и адресация по индексу.
	# Здесь остаётся только поселение.

	# Лавка торговца: навес на столбах у края поляны, чтобы её было видно
	# издалека и не спутать с домиками.
	_box(g, TRADER_POS + Vector3(0.0, 1.0, 0.0), Vector3(7.0, 2.0, 4.0), "wood")
	_box(g, TRADER_POS + Vector3(0.0, 2.3, 0.0), Vector3(8.0, 0.6, 5.0), "stone")
	for corner in 4:
		var ox := 3.4 if corner % 2 == 0 else -3.4
		var oz := 2.0 if corner < 2 else -2.0
		_cylinder(g, TRADER_POS + Vector3(ox, 3.4, oz), 0.25, 2.2, "wood")
	_box(g, TRADER_POS + Vector3(0.0, 4.7, 0.0), Vector3(9.0, 0.4, 6.0), "accent")

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

	# Дворец. Раньше это был МОНОЛИТНЫЙ куб, и точка захвата, лежащая в его
	# центре, оказывалась внутри камня — условие победы злодея было физически
	# невыполнимо. Живой тестер обошёл здание кругом и не нашёл входа.
	#
	# Теперь это коробка из стен с воротами с юга, со стороны центра карты:
	# внутрь можно войти, и точка захвата достижима.
	var pw := 45.0                                   # полуширина по X
	var pd := 30.0                                   # полуглубина по Z
	var ph := 24.0                                   # высота стен
	var wall := 4.0                                  # толщина стены
	var gate := 16.0                                 # полуширина проёма ворот

	# Задняя и боковые стены.
	_box(g, Vector3(c.x, 6.0 + ph * 0.5, c.y - pd), Vector3(pw * 2.0, ph, wall), "marble")
	_box(g, Vector3(c.x - pw, 6.0 + ph * 0.5, c.y), Vector3(wall, ph, pd * 2.0), "marble")
	_box(g, Vector3(c.x + pw, 6.0 + ph * 0.5, c.y), Vector3(wall, ph, pd * 2.0), "marble")
	# Передняя стена с воротами: два простенка и перемычка над проёмом.
	var jamb := (pw - gate) * 0.5
	for side in [-1.0, 1.0]:
		_box(g, Vector3(c.x + side * (gate + jamb), 6.0 + ph * 0.5, c.y + pd),
			Vector3(jamb * 2.0, ph, wall), "marble")
	_box(g, Vector3(c.x, 6.0 + ph - 3.0, c.y + pd), Vector3(gate * 2.0, 6.0, wall), "marble")
	# Крыша: без неё дворец просматривается и простреливается сверху.
	_box(g, Vector3(c.x, 6.0 + ph + 1.0, c.y), Vector3(pw * 2.0, 2.0, pd * 2.0), "marble")

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
		# Скала, а не куб. Форма читается раньше цвета: коробку в семьдесят
		# метров никакая каменная текстура камнем не сделает.
		_harvestable(_rock(g, Vector3(p.x, 0.0, p.y),
			Vector3(mw, mh, mw * rng.randf_range(0.7, 1.2)),
			rng.randf() * TAU, rng.randi()), RES.Kind.STONE, 10)

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

	# Роща за южными воротами форта.
	#
	# До неё своего леса у злодея не было вовсе: горы, форт и шахта. Ближайшие
	# деревья росли у перекрёстка, в четырёхстах метрах, и полный круг батрака —
	# дойти, нарубить, донести — занимал больше двух минут. С появлением батраков
	# это перестало быть мелочью: сторона, которая рубит постоянно, не может
	# ходить за каждым бревном через полкарты.
	#
	# Ставим ЗА ВОРОТАМИ и только в южной половине: батрак выходит из форта и
	# сразу попадает в лес. Радиус выбран между стеной (80 м от середины форта) и
	# кольцом гор — так роща не влезает ни в стены, ни в скалы.
	var grove := RandomNumberGenerator.new()
	grove.seed = 4231
	for i in 26:
		var a := grove.randf_range(0.18, 0.82) * PI
		var r := grove.randf_range(96.0, 132.0)
		var p := f + Vector2(cos(a), sin(a)) * r
		var h := grove.randf_range(9.0, 15.0)
		_harvestable(_tree(g, p, h), RES.Kind.WOOD)



## Шахта. СВОЯ группа, а не часть зоны злодея.
##
## Раньше она строилась внутри `_build_villain`, потому что и стояла в его углу.
## Теперь она на другом конце карты, и оставлять её в чужой группе значит
## оставить ловушку: тот, кто однажды выключит или переставит зону злодея,
## переставит вместе с ней шахту, до которой ему нет дела.
func _build_mine() -> void:
	var g := _group("Mine")
	var m := Vector2(MINE_POS.x, MINE_POS.z)
	_harvestable(_box(g, Vector3(m.x, 10.0, m.y), Vector3(50.0, 20.0, 50.0), "rock"),
		RES.Kind.IRON, 40)
	_box(g, Vector3(m.x, 4.0, m.y + 26.0), Vector3(14.0, 8.0, 6.0), "dark_stone")  # вход


## Модели, которые раскладываются по холмам пачками. Камни набора Kenney —
## плоские плитки в четверть метра высотой, и на валуны они не годятся вовсе
## (обмерено), зато как галька под ногами они ровно то, что нужно.
const SCATTER_ROCKS := [
	preload("res://assets/nature/rock_largeA.glb"),
	preload("res://assets/nature/rock_smallA.glb"),
]
const SCATTER_STUMP := preload("res://assets/nature/stump_old.glb")

## Хутора: по одному в каждой четверти карты, на полпути от центра к зоне.
## Мир из четырёх крепостей и пустоты между ними выглядит декорацией; хутор
## говорит, что тут живут, и даёт глазу за что зацепиться по дороге.
const HAMLETS := [
	Vector2(-150.0, 150.0),
	Vector2(155.0, 140.0),
	Vector2(150.0, -160.0),
	Vector2(-160.0, -140.0),
]


## Мелочь на холмах: трава, кусты, галька, пни и деревья.
##
## Всё через MultiMesh: пять тысяч кустиков отдельными узлами положили бы игру,
## а одной пачкой они рисуются за один вызов и не стоят почти ничего.
##
## КЛАДЁМ ТОЛЬКО НА ХОЛМЫ — там, где рельеф поднялся хоть немного. Это и есть
## места, где ничего не построено: маска рельефа уже отогнала холмы от дорог,
## зон, шахты и перекрёстка, и повторять тот же список здесь не нужно.
func _build_scatter() -> void:
	var g := _group("Scatter")
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210

	_scatter(g, rng, _tuft_mesh(Color(0.36, 0.47, 0.26)), 5200, 0.4, 0.8, 1.2, null)
	_scatter(g, rng, _bush_mesh(Color(0.25, 0.38, 0.22)), 1100, 0.9, 1.6, 1.2, null)
	# Камням и пням материал задаём ЯВНО.
	#
	# Меш, вынутый из модели набора, приходит без него: материал у Kenney висит
	# на узле, а не на меше, и MultiMesh о нём не знает. На снимке это выглядело
	# как розовые и голубые крапинки по всему полю — «материала нет» в чистом
	# виде, и принять их можно за что угодно, только не за камни.
	# Галька — те же булыжники, только мелкие: плитки из набора Kenney на камни
	# не похожи вовсе, они плоские в четверть метра.
	for shape_seed in [3, 7, 11]:
		_scatter(g, rng, ROCKS.mesh(shape_seed), 340, 0.5, 1.6, 0.6, TEXTURES.of("rock"))
	_scatter(g, rng, _first_mesh(SCATTER_STUMP), 130, 1.6, 2.6, 1.0, TEXTURES.of("wood"))
	# Деревья на склонах — с коллизией, иначе сквозь рощу можно пройти насквозь,
	# и лес перестаёт быть препятствием. Их немного и они НЕ добываются: рубка
	# леса — это зона эльфов и роща у спавна, а не вся карта.
	_hill_trees(g, rng)


## Одна пачка одинаковых мелочей, разбросанная по холмам.
func _scatter(parent: Node3D, rng: RandomNumberGenerator, mesh: Mesh, count: int,
		low: float, high: float, min_height: float, material: Material) -> void:
	if mesh == null:
		return
	var spots: Array = []
	# Пробуем вчетверо больше точек, чем нужно: холмы занимают меньше половины
	# карты, и слепой разброс без отбора дал бы вчетверо меньше видимого добра.
	for i in count * 4:
		if spots.size() >= count:
			break
		var x: float = rng.randf_range(-WORLD_SIZE * 0.5, WORLD_SIZE * 0.5)
		var z: float = rng.randf_range(-WORLD_SIZE * 0.5, WORLD_SIZE * 0.5)
		var y: float = relief.height(x, z)
		if y < min_height:
			continue
		spots.append(Vector3(x, y, z))
	if spots.is_empty():
		return

	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = spots.size()
	for i in spots.size():
		var scale_to: float = rng.randf_range(low, high)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * scale_to)
		multi.set_instance_transform(i, Transform3D(basis, spots[i]))
	var node := MultiMeshInstance3D.new()
	node.multimesh = multi
	if material != null:
		node.material_override = material
	# Мелочь теней не отбрасывает: пять тысяч кустиков в карте теней стоят
	# дороже, чем видно глазу.
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)


## Деревья на склонах: ствол с коллизией и крона от модели.
func _hill_trees(parent: Node3D, rng: RandomNumberGenerator) -> void:
	var placed := 0
	for i in 900:
		if placed >= 170:
			break
		var x: float = rng.randf_range(-WORLD_SIZE * 0.5, WORLD_SIZE * 0.5)
		var z: float = rng.randf_range(-WORLD_SIZE * 0.5, WORLD_SIZE * 0.5)
		var y: float = relief.height(x, z)
		if y < 3.0:
			continue
		placed += 1
		var trunk := _tree(parent, Vector2(x, z), rng.randf_range(8.0, 13.0))
		trunk.position.y = y


static func _first_mesh(packed: PackedScene) -> Mesh:
	var node: Node3D = packed.instantiate()
	for child in node.get_children():
		if child is MeshInstance3D:
			return (child as MeshInstance3D).mesh
	return null


## Пучок травы: два скрещённых прямоугольника. Дешевле любой модели и с любой
## стороны выглядит одинаково.
static func _tuft_mesh(color: Color) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for turn in [0.0, PI * 0.5]:
		var dir := Vector3(cos(turn), 0.0, sin(turn)) * 0.5
		var up := Vector3.UP * 0.9
		st.add_vertex(-dir)
		st.add_vertex(dir)
		st.add_vertex(dir + up)
		st.add_vertex(-dir)
		st.add_vertex(dir + up)
		st.add_vertex(-dir + up)
	st.generate_normals()
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 1.0
	mesh.surface_set_material(0, mat)
	return mesh


static func _bush_mesh(color: Color) -> Mesh:
	var ball := SphereMesh.new()
	ball.radius = 0.9
	ball.height = 1.4
	ball.radial_segments = 6
	ball.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	ball.surface_set_material(0, mat)
	return ball


## Хутор: несколько дворов у дороги. Домики маленькие и без коллизии внутри —
## это декорация, а не постройки: воевать за них нельзя и жить в них некому.
func _build_hamlets() -> void:
	var g := _group("Hamlets")
	var rng := RandomNumberGenerator.new()
	rng.seed = 4477
	for spot in HAMLETS:
		var center: Vector2 = spot
		for i in 5:
			var angle: float = TAU * float(i) / 5.0 + rng.randf_range(-0.3, 0.3)
			var radius: float = rng.randf_range(14.0, 26.0)
			var at: Vector2 = center + Vector2(cos(angle), sin(angle)) * radius
			_cottage(g, at, rng.randf() * TAU, rng.randf_range(0.85, 1.25))
		# Колодец посреди двора: по нему хутор и узнают.
		_cylinder(g, Vector3(center.x, 0.6, center.y), 1.6, 1.2, "stone")
		_box(g, Vector3(center.x, 2.4, center.y), Vector3(3.2, 0.3, 3.2), "wood")


## Один двор: сруб под двускатной крышей.
func _cottage(parent: Node3D, at: Vector2, yaw: float, size: float) -> void:
	var w: float = 6.0 * size
	var d: float = 5.0 * size
	var h: float = 3.4 * size
	_box(parent, Vector3(at.x, h * 0.5, at.y), Vector3(w, h, d), "wood", yaw)
	# Крыша: два ската навстречу друг другу.
	var slope: float = 0.55
	for side in [-1.0, 1.0]:
		var panel := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(w * 1.15, 0.3, d * 0.75)
		panel.mesh = box
		panel.material_override = TEXTURES.of("roof")
		var offset := Vector3(0.0, h + 0.9 * size, side * d * 0.28)
		panel.transform = Transform3D(
			Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, slope * side),
			Vector3(at.x, 0.0, at.y) + Basis(Vector3.UP, yaw) * offset)
		parent.add_child(panel)


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
## Дерево ЦЕЛИКОМ: ствол и крона одним телом.
##
## Раньше крона ставилась отдельным узлом рядом со стволом. Рубка удаляет то,
## во что попал луч, — то есть ствол, — и крона оставалась висеть в воздухе.
## На снимке из живой игры это первое, что бросается в глаза: полтора десятка
## крон парят над пустой землёй.
##
## Крона — ребёнок ствола, поэтому исчезает вместе с ним и переносить её при
## этом не нужно ничем: тело уходит со всеми детьми разом.
## Модели деревьев. Kenney Nature Kit, лицензия CC0 (LICENSE.txt рядом с ними).
##
## Из трёхсот тридцати моделей набора взято четыре: разнообразие тут нужно ровно
## настолько, чтобы лес не выглядел одним деревом, скопированным сто раз.
const TREE_MODELS := [
	preload("res://assets/nature/tree_default.glb"),
	preload("res://assets/nature/tree_detailed.glb"),
	preload("res://assets/nature/tree_tall.glb"),
	preload("res://assets/nature/tree_pineDefaultA.glb"),
]

## Модели набора ростом около четырёх метров: приводим к нашим девяти-пятнадцати.
const TREE_MODEL_HEIGHT := 4.0


## Дерево ЦЕЛИКОМ: ствол с коллизией и модель кроны на нём.
##
## Раньше и ствол, и крона рисовались коробкой и конусом. Модель ставится ВМЕСТО
## них, но коллизия остаётся своя — цилиндр по стволу. Брать коллизию из модели
## нельзя: у дерева она пришла бы вместе с кроной, и обойти дерево стало бы
## можно только по большой дуге, а бойцы начали бы застревать в ветках.
##
## Крона — ребёнок ствола, поэтому исчезает вместе с ним при рубке. До этого она
## висела отдельным узлом и оставалась в воздухе.
func _tree(parent: Node3D, foot: Vector2, height: float) -> StaticBody3D:
	var trunk := StaticBody3D.new()
	trunk.position = Vector3(foot.x, 0.0, foot.y)

	var model: Node3D = TREE_MODELS[_tree_pick % TREE_MODELS.size()].instantiate()
	_tree_pick += 1
	var scale_to: float = height / TREE_MODEL_HEIGHT
	model.scale = Vector3(scale_to, scale_to, scale_to)
	_repaint(model)
	trunk.add_child(model)

	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 1.1
	shape.height = height
	col.shape = shape
	col.position = Vector3(0.0, height * 0.5, 0.0)
	trunk.add_child(col)

	parent.add_child(trunk)
	return trunk


## Перекрасить модель под палитру мира.
##
## Материалы набора взяты как есть, и это было видно сразу: листва у Kenney
## бирюзовая, а не зелёная, и вдобавок помечена полностью металлической — под
## нашим светом дерево выходило блестящим и голубым, споря с дальним лесом,
## который рисуют билборды нашего цвета.
##
## Меняем ЦВЕТ, а не модель: форма нам и нужна, ради неё модель и брали. Узнаём
## части по имени материала — в наборе они названы честно (`woodBark`,
## `leafsGreen`), и это надёжнее, чем угадывать по номеру поверхности.
func _repaint(model: Node3D) -> void:
	for node in _all_meshes(model):
		var mesh: MeshInstance3D = node
		for surface in mesh.mesh.get_surface_count():
			var from: Material = mesh.mesh.surface_get_material(surface)
			var name: String = from.resource_name if from != null else ""
			var key := "trunk"
			if name.containsn("leaf") or name.containsn("green"):
				key = "foliage"
			elif name.containsn("stone") or name.containsn("rock"):
				key = "stone"
			mesh.set_surface_override_material(surface, _materials[key])


func _all_meshes(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		found.append(node as MeshInstance3D)
	for child in node.get_children():
		found.append_array(_all_meshes(child))
	return found


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
		_harvestable(_tree(g, p, h), RES.Kind.WOOD)

	for i in 9:
		var a := rng.randf() * TAU
		var r := rng.randf_range(30.0, 65.0)
		var p := Vector2(cos(a), sin(a)) * r + Vector2(-35.0, 5.0)
		var s := rng.randf_range(3.0, 5.5)
		_harvestable(_rock(g, Vector3(p.x, 0.0, p.y),
			Vector3(s, s * 0.75, s * rng.randf_range(0.75, 1.15)),
			rng.randf() * TAU, rng.randi()), RES.Kind.STONE)
