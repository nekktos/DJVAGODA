extends RefCounted
##
## Облик постройки: дом из модулей вместо серой коробки.
##
## ЗАЧЕМ ОТДЕЛЬНЫЙ ФАЙЛ. Постройка и так знает про здоровье, стройку, зону
## попадания и сеть. Сборка стен и крыши к этому не относится вовсе: её меняют
## по виду, а не по правилам, и держать её рядом с уроном значит править одно,
## задевая другое.
##
## ЧТО СОБИРАЕМ. Модули набора — кубики со стороной 1 метр, а постройки в игре
## по 10-14 метров. Значит модуль масштабируется до целого числа пролётов, стены
## ставятся по периметру в один-два этажа, а крыша складывается из двух скатов
## примитивами.
##
## ПОЧЕМУ КРЫША НЕ ИЗ НАБОРА. В наборе она тоже модульная, и стыковать её надо
## по коньку, углам и торцам — пять разных деталей, каждая со своим смещением.
## Два скошенных бруса читаются как крыша с первого взгляда и не разъезжаются
## ни при каком размере постройки, а разница в детализации на фоне grey-box
## карты незаметна.
##
## КОЛЛИЗИЯ ОСТАЁТСЯ КОРОБКОЙ. Дом с настоящей геометрией стен означал бы, что
## в него можно зайти, а внутри ничего нет. Постройка — препятствие и цель, а не
## помещение, и трогать это здесь мы не собираемся.
##

const RES := preload("res://scripts/economy/resources.gd")
const TEXTURES := preload("res://scripts/textures.gd")

## Каменные модули — для склада и конюшни, деревянные — для казарм: разные
## стороны и разные постройки должны отличаться хоть чем-то, кроме размера.
const STONE := {
	"wall": preload("res://assets/buildings/wall.glb"),
	"door": preload("res://assets/buildings/wall-door.glb"),
	"window": preload("res://assets/buildings/wall-window-round.glb"),
}
const WOOD := {
	"wall": preload("res://assets/buildings/wall-wood.glb"),
	"door": preload("res://assets/buildings/wall-wood-door.glb"),
	"window": preload("res://assets/buildings/wall-wood-window-round.glb"),
}
const BANNER_RED := preload("res://assets/buildings/banner-red.glb")
const BANNER_GREEN := preload("res://assets/buildings/banner-green.glb")
const FENCE := preload("res://assets/buildings/fence.glb")

## Высота одного этажа в метрах. Модуль набора высотой ровно 1, поэтому это же
## и его масштаб по вертикали.
const FLOOR_HEIGHT := 3.5
## Цвет черепицы. Взят с крыш набора, чтобы дом не спорил сам с собой.
const ROOF_COLOR := Color(0.78, 0.29, 0.24)
## Насколько крыша нависает над стенами.
const ROOF_OVERHANG := 0.6
## Высота конька над верхом стен.
const ROOF_RISE := 2.2
## Перехлёст скатов на коньке.
const ROOF_RIDGE_OVERLAP := 1.0


## Собрать дом заданного вида и размера. Возвращает узел, который постройка
## кладёт себе внутрь и растит по высоте, пока идёт стройка.
static func build(kind: int, size: Vector3, grade: int = 0) -> Node3D:
	var root := Node3D.new()
	root.name = "Look"
	if kind in RES.ELF_HOUSES:
		_elf_house(root, size, kind == RES.Building.ELF_STONE_HOUSE)
		return root

	# Ступень материала читается глазом (ответ автора от 29.09): деревянная —
	# деревянные стены, «дерево и камень» — каменный первый этаж, «камень» —
	# вся каменная, «камень и железо» — каменная в железных оковках.
	var set_name := WOOD if _wooden(kind) else STONE
	if RES.gradeable(kind):
		set_name = WOOD if grade <= RES.Grade.WOOD_STONE else STONE
	var floors := maxi(1, int(round(size.y / FLOOR_HEIGHT)))
	var floor_h: float = size.y / float(floors)
	# Пролётов по каждой стороне — целое число, иначе угол не сойдётся с углом.
	var span_x := maxi(2, int(round(size.x / floor_h)))
	var span_z := maxi(2, int(round(size.z / floor_h)))
	var step_x: float = size.x / float(span_x)
	var step_z: float = size.z / float(span_z)

	for level in floors:
		var y: float = float(level) * floor_h
		# Дверь — только на первом этаже и только по фасаду: дверь на втором
		# этаже выглядит ошибкой, а не украшением.
		var door_at := span_x / 2 if level == 0 else -1
		var row_set: Dictionary = set_name
		if RES.gradeable(kind) and grade == RES.Grade.WOOD_STONE and level == 0:
			row_set = STONE
		_wall_row(root, row_set, y, floor_h, span_x, step_x, size.z * 0.5, door_at, false)
		_wall_row(root, row_set, y, floor_h, span_x, step_x, size.z * 0.5, -1, true)
		_side_row(root, row_set, y, floor_h, span_z, step_z, size.x * 0.5, false)
		_side_row(root, row_set, y, floor_h, span_z, step_z, size.x * 0.5, true)

	# Каменные ступени — в тёсаном камне, как стены форта. Модули набора
	# «камень» белые и на снимке читались штукатуркой: «дерево», «камень» и
	# «камень с железом» различались хуже, чем должны.
	if RES.gradeable(kind) and grade >= RES.Grade.WOOD_STONE:
		for piece in root.get_children():
			if piece.get_meta("stone_module", false):
				_skin(piece, TEXTURES.of("stone"))
	# Одноэтажная «дерево и камень» — каменный цоколь под деревянной стеной.
	if RES.gradeable(kind) and grade == RES.Grade.WOOD_STONE and floors == 1:
		_plinth(root, size)
	if RES.gradeable(kind) and grade >= RES.Grade.STONE_IRON:
		_iron_bands(root, size)
	_roof(root, size)
	_trim(root, kind, size)
	if kind == RES.Building.FORGE:
		_forge_trim(root, size)
	return root


## Обтянуть модуль материалом целиком.
static func _skin(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = mat
	for child in node.get_children():
		_skin(child, mat)


## Каменный цоколь по периметру.
static func _plinth(root: Node3D, size: Vector3) -> void:
	var mat: StandardMaterial3D = TEXTURES.of("stone")
	var h := 1.1
	for side in [-1.0, 1.0]:
		_block(root, Vector3(0.0, h * 0.5, side * (size.z * 0.5 + 0.05)),
			Vector3(size.x + 0.4, h, 0.5), mat)
		_block(root, Vector3(side * (size.x * 0.5 + 0.05), h * 0.5, 0.0),
			Vector3(0.5, h, size.z + 0.4), mat)


## Железные оковки: стойки по углам и пояс по верху стен.
static func _iron_bands(root: Node3D, size: Vector3) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.21, 0.23)
	mat.metallic = 0.85
	mat.roughness = 0.35
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_block(root, Vector3(sx * size.x * 0.5, size.y * 0.5, sz * size.z * 0.5),
				Vector3(0.7, size.y + 0.2, 0.7), mat)
	for side in [-1.0, 1.0]:
		_block(root, Vector3(0.0, size.y - 0.35, side * (size.z * 0.5 + 0.08)),
			Vector3(size.x + 0.5, 0.35, 0.3), mat)
		_block(root, Vector3(side * (size.x * 0.5 + 0.08), size.y - 0.35, 0.0),
			Vector3(0.3, 0.35, size.z + 0.5), mat)


static func _block(root: Node3D, at: Vector3, box_size: Vector3, mat: Material) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = box_size
	mesh.mesh = box
	mesh.material_override = mat
	mesh.position = at
	root.add_child(mesh)


## Дом эльфов: на сваях, как хижины их поселения, под острой крышей цвета
## листвы. Каменный — на каменном цоколе и с каменными стенами: прочность по
## материалу должна читаться глазом, а не только числом.
static func _elf_house(root: Node3D, size: Vector3, stone: bool) -> void:
	# ДОМ НА ДЕРЕВЕ. Прежде это была коробка на сваях под зелёным конусом, и
	# автор сказал прямо: «дома эльфов должны выглядеть как дома эльфов». Эльфы
	# живут В лесу, а не на вырубке: дом обнимает живой ствол, стоит на круглой
	# площадке, крыт куполом листвы и светится тёплыми окнами и фонариками.
	# Каменный — на каменном цоколе и с каменными стенами: прочность по
	# материалу читается глазом.
	var walls: StandardMaterial3D = TEXTURES.of("stone" if stone else "elf_wood")
	var planks: StandardMaterial3D = TEXTURES.of("elf_wood")
	var bark: StandardMaterial3D = TEXTURES.of("bark")
	var leaves := _flat_mat(Color(0.30, 0.52, 0.27), 0.9)
	var deep_leaves := _flat_mat(Color(0.20, 0.40, 0.22), 0.9)
	var vine := _flat_mat(Color(0.26, 0.47, 0.22), 0.9)
	var glow := _flat_mat(Color(1.0, 0.82, 0.45), 0.5)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.72, 0.35)
	glow.emission_energy_multiplier = 1.6

	var radius: float = minf(size.x, size.z) * 0.5
	var lift: float = size.y * 0.35
	var room_h: float = size.y - lift

	# Живой ствол сквозь дом и крона над ним.
	_cylinder(root, Vector3(0.0, size.y * 0.8, 0.0), 1.0, 1.25, size.y * 1.6, bark)
	for crown in [Vector3(0.0, size.y * 1.62, 0.0), Vector3(1.8, size.y * 1.45, 0.9),
			Vector3(-1.6, size.y * 1.5, -1.1)]:
		_sphere(root, crown, radius * 0.55, deep_leaves)

	# Опора: резные сваи с вьюнком — у каменного вместо свай цоколь.
	if stone:
		_cylinder(root, Vector3(0.0, lift * 0.5, 0.0), radius * 0.78, radius * 0.86, lift, walls)
	else:
		for i in 6:
			var angle := TAU * float(i) / 6.0
			var at := Vector3(cos(angle), 0.0, sin(angle)) * radius * 0.72
			_cylinder(root, at + Vector3(0.0, lift * 0.5, 0.0), 0.22, 0.32, lift, planks)
			_cylinder(root, at + Vector3(0.12, lift * 0.45, 0.12), 0.07, 0.07, lift * 0.9, vine)

	# Круглая площадка с перилами-фонариками.
	_cylinder(root, Vector3(0.0, lift, 0.0), radius * 0.98, radius * 0.98, 0.35, planks)
	for i in 8:
		var angle := TAU * (float(i) + 0.5) / 8.0
		var at := Vector3(cos(angle), 0.0, sin(angle)) * radius * 0.92
		_cylinder(root, at + Vector3(0.0, lift + 0.6, 0.0), 0.06, 0.06, 1.2, planks)
		if i % 2 == 0:
			_sphere(root, at + Vector3(0.0, lift + 1.3, 0.0), 0.2, glow)

	# Круглый сруб вокруг ствола.
	var room_r: float = radius * 0.66
	_cylinder(root, Vector3(0.0, lift + room_h * 0.4, 0.0), room_r, room_r, room_h * 0.8, walls)
	# Дверь-арка по фасаду (+Z) и круглые окна.
	var door := MeshInstance3D.new()
	var door_box := BoxMesh.new()
	door_box.size = Vector3(1.3, 2.2, 0.3)
	door.mesh = door_box
	door.material_override = _flat_mat(Color(0.28, 0.2, 0.12), 0.8)
	door.position = Vector3(0.0, lift + 1.2, room_r)
	root.add_child(door)
	_sphere(root, Vector3(0.0, lift + 2.3, room_r), 0.65, door.material_override)
	for angle in [PI * 0.25, PI * 0.75, PI * 1.25, PI * 1.75]:
		var at := Vector3(sin(angle), 0.0, cos(angle)) * room_r
		_sphere(root, at + Vector3(0.0, lift + room_h * 0.45, 0.0), 0.45, glow)

	# Купол листвы вместо крыши.
	var dome := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = room_r * 1.35
	sphere.height = room_r * 1.6
	sphere.is_hemisphere = true
	dome.mesh = sphere
	dome.material_override = leaves
	dome.position = Vector3(0.0, lift + room_h * 0.8, 0.0)
	root.add_child(dome)

	# Лесенка на землю — с фасада.
	for step in 5:
		var t := float(step) / 5.0
		_block(root, Vector3(0.0, lift * (1.0 - t) - 0.1, radius * (1.0 + t * 0.45)),
			Vector3(1.4, 0.18, 0.55), planks)


static func _cylinder(root: Node3D, at: Vector3, top: float, bottom: float, height: float,
		mat: Material) -> void:
	var mesh := MeshInstance3D.new()
	var shape := CylinderMesh.new()
	shape.top_radius = top
	shape.bottom_radius = bottom
	shape.height = height
	mesh.mesh = shape
	mesh.material_override = mat
	mesh.position = at
	root.add_child(mesh)


static func _sphere(root: Node3D, at: Vector3, r: float, mat: Material) -> void:
	var mesh := MeshInstance3D.new()
	var shape := SphereMesh.new()
	shape.radius = r
	shape.height = r * 2.0
	mesh.mesh = shape
	mesh.material_override = mat
	mesh.position = at
	root.add_child(mesh)


static func _flat_mat(color: Color, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	return mat


## Казармы деревянные, склад и конюшня каменные. Дерево у казарм не случайно:
## их сносят чаще всего, и вид «сарай, который не жалко» тут к месту.
## Кузня узнаётся по трубе и наковальне у входа.
static func _forge_trim(root: Node3D, size: Vector3) -> void:
	var stone: StandardMaterial3D = TEXTURES.of("stone")
	var chimney := MeshInstance3D.new()
	var tall := BoxMesh.new()
	tall.size = Vector3(1.6, 4.0, 1.6)
	chimney.mesh = tall
	chimney.material_override = stone
	chimney.position = Vector3(size.x * 0.3, size.y + ROOF_RISE + 1.0, 0.0)
	root.add_child(chimney)
	var anvil := MeshInstance3D.new()
	var block := BoxMesh.new()
	block.size = Vector3(1.2, 0.8, 0.6)
	anvil.mesh = block
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.22, 0.22, 0.25)
	iron.metallic = 0.7
	iron.roughness = 0.4
	anvil.material_override = iron
	anvil.position = Vector3(-size.x * 0.25, 0.4, size.z * 0.5 + 1.6)
	root.add_child(anvil)


static func _wooden(kind: int) -> bool:
	# Дом дружины тоже деревянный: он и строится из дерева с камнем, и должен
	# читаться жильём, а не укреплением.
	if kind == RES.Building.HOUSE:
		return true
	return kind == RES.Building.SWORD_BARRACKS or kind == RES.Building.ARCHER_BARRACKS


## Как устроен модуль стены в наборе: тонкая плита длиной в целый пролёт по
## СВОЕЙ оси Z, толщиной в десятую по X, и стоит она не по центру клетки, а у её
## края — на 0.45 в сторону +X. Оба числа нужны при расстановке: без первого
## стены встают решёткой из вертикальных ламелей, без второго — уезжают наружу
## на полклетки.
const MODULE_EDGE_OFFSET := 0.45
## Насколько знамя выносится вперёд от плоскости фасада. Больше половины
## толщины стены — иначе полотнище окажется внутри неё.
const BANNER_STANDOFF := 0.6


## Ряд модулей вдоль длинной стороны. Фасад смотрит на +Z, задняя стена на -Z.
static func _wall_row(root: Node3D, set_name: Dictionary, y: float, floor_h: float,
		span: int, step: float, half_z: float, door_at: int, back: bool) -> void:
	var half_x: float = step * float(span) * 0.5
	var out: float = -1.0 if back else 1.0
	for i in span:
		var key := "wall"
		if i == door_at:
			key = "door"
		elif i % 2 == 1:
			key = "window"
		var piece: Node3D = set_name[key].instantiate()
		piece.set_meta("stone_module", set_name == STONE)
		piece.position = Vector3(
			-half_x + step * (float(i) + 0.5),
			y,
			out * (half_z - MODULE_EDGE_OFFSET * step),
		)
		piece.scale = Vector3(step, floor_h, step)
		# Плита смотрит в свой +X, а стене надо смотреть наружу по Z.
		piece.rotation.y = PI * 0.5 if back else -PI * 0.5
		root.add_child(piece)


## Ряд вдоль короткой стороны: те же модули, развёрнутые на четверть оборота.
static func _side_row(root: Node3D, set_name: Dictionary, y: float, floor_h: float,
		span: int, step: float, half_x: float, left: bool) -> void:
	var half_z: float = step * float(span) * 0.5
	var out: float = -1.0 if left else 1.0
	for i in span:
		var key := "wall" if i % 2 == 0 else "window"
		var piece: Node3D = set_name[key].instantiate()
		piece.set_meta("stone_module", set_name == STONE)
		piece.position = Vector3(
			out * (half_x - MODULE_EDGE_OFFSET * step),
			y,
			-half_z + step * (float(i) + 0.5),
		)
		piece.scale = Vector3(step, floor_h, step)
		piece.rotation.y = PI if left else 0.0
		root.add_child(piece)


## Двускатная крыша из двух брусьев и двух торцов.
static func _roof(root: Node3D, size: Vector3) -> void:
	# Черепица с текстурой: скат — самая большая сплошная плоскость постройки, и
	# заливка одним цветом на ней читалась как пластмасса. Материал общий на все
	# крыши мира и не копируется: его никто не меняет на месте.
	var mat: StandardMaterial3D = TEXTURES.of("roof")

	var length: float = size.z * 0.5 + ROOF_OVERHANG
	var slope := sqrt(length * length + ROOF_RISE * ROOF_RISE)
	var angle := atan2(ROOF_RISE, length)
	for side in [-1.0, 1.0]:
		var panel := MeshInstance3D.new()
		var box := BoxMesh.new()
		# Скаты делаем ДЛИННЕЕ пролёта и кладём с перехлёстом на коньке: встык они
		# сходятся кромка в кромку, между ними остаётся щель в толщину доски, и
		# сквозь неё виден тёмный нутряк. Снаружи перехлёст незаметен, щель —
		# заметна сразу.
		box.size = Vector3(size.x + ROOF_OVERHANG * 2.0, 0.22, slope + ROOF_RIDGE_OVERLAP)
		panel.mesh = box
		panel.material_override = mat
		panel.position = Vector3(0.0, size.y + ROOF_RISE * 0.5, side * length * 0.5)
		# Знак важен: при обратном скаты задираются от конька к карнизу, крыша
		# превращается в две доски домиком наоборот, и сверху видно нутро.
		panel.rotation.x = angle * side
		root.add_child(panel)

	# Торцы: без них крыша просвечивает насквозь и выглядит навесом.
	var gable_mat: StandardMaterial3D = TEXTURES.of("plaster")
	for side in [-1.0, 1.0]:
		var wedge := MeshInstance3D.new()
		var prism := PrismMesh.new()
		prism.size = Vector3(size.z, ROOF_RISE, 0.3)
		wedge.mesh = prism
		wedge.material_override = gable_mat
		wedge.position = Vector3(side * size.x * 0.5, size.y + ROOF_RISE * 0.5, 0.0)
		wedge.rotation.y = PI * 0.5
		root.add_child(wedge)


## Мелочь, по которой постройку узнают издали: знамя на казарме, изгородь у
## конюшни. Без неё три дома одного размера различаются только цветом стен.
static func _trim(root: Node3D, kind: int, size: Vector3) -> void:
	match kind:
		RES.Building.SWORD_BARRACKS:
			_banner(root, BANNER_RED, size)
		RES.Building.ARCHER_BARRACKS:
			_banner(root, BANNER_GREEN, size)
		RES.Building.STABLE:
			# Загон перед конюшней: лошадей в ней держат, и это должно быть
			# видно раньше, чем игрок прочитает подпись.
			# Прясло изгороди устроено так же, как модуль стены: плита вдоль
			# своей оси Z, тонкая по X, и смещена к краю клетки. Без разворота
			# загон встанет частоколом поперёк себя.
			var rail_scale := 2.0
			var span := int(size.x / rail_scale)
			for i in span:
				var rail: Node3D = FENCE.instantiate()
				rail.position = Vector3(
					-size.x * 0.5 + rail_scale * (float(i) + 0.5),
					0.0,
					size.z * 0.5 + 3.0 - MODULE_EDGE_OFFSET * rail_scale,
				)
				rail.scale = Vector3.ONE * rail_scale
				rail.rotation.y = -PI * 0.5
				root.add_child(rail)


## Знамя висит на фасаде. Полотнище в наборе — такая же прижатая к краю
## клетки плита, что и стена, поэтому и разворот, и поправка те же.
##
## ВЫНОС ВПЕРЁД обязателен. Стена — не плоскость, а плита толщиной в десятую
## клетки, то есть почти в треть метра при нашем масштабе. Знамя, поставленное
## «вровень с фасадом», оказывается ВНУТРИ этой толщины, и снаружи его не видно
## вовсе — ровно это и случилось: знамёна на казармах строились, а на снимке их
## не было. Разницу между «не создали» и «создали не там» глазами не увидеть,
## её показал `tools/look_probe.gd`.
static func _banner(root: Node3D, packed: PackedScene, size: Vector3) -> void:
	var flag_scale := 2.2
	for side in [-1.0, 1.0]:
		var flag: Node3D = packed.instantiate()
		flag.position = Vector3(
			side * size.x * 0.28,
			size.y * 0.55,
			size.z * 0.5 - MODULE_EDGE_OFFSET * flag_scale + BANNER_STANDOFF,
		)
		flag.scale = Vector3.ONE * flag_scale
		flag.rotation.y = -PI * 0.5
		root.add_child(flag)
