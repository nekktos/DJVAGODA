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
static func build(kind: int, size: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "Look"

	var set_name := WOOD if _wooden(kind) else STONE
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
		_wall_row(root, set_name, y, floor_h, span_x, step_x, size.z * 0.5, door_at, false)
		_wall_row(root, set_name, y, floor_h, span_x, step_x, size.z * 0.5, -1, true)
		_side_row(root, set_name, y, floor_h, span_z, step_z, size.x * 0.5, false)
		_side_row(root, set_name, y, floor_h, span_z, step_z, size.x * 0.5, true)

	_roof(root, size)
	_trim(root, kind, size)
	return root


## Казармы деревянные, склад и конюшня каменные. Дерево у казарм не случайно:
## их сносят чаще всего, и вид «сарай, который не жалко» тут к месту.
static func _wooden(kind: int) -> bool:
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
	var mat := StandardMaterial3D.new()
	mat.albedo_color = ROOF_COLOR
	mat.roughness = 0.85

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
	var gable_mat := StandardMaterial3D.new()
	gable_mat.albedo_color = Color(0.86, 0.82, 0.74)
	gable_mat.roughness = 0.9
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
