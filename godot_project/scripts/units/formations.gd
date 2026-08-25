extends RefCounted
##
## Построения отряда (Этап 6, GDD разделы 2.3 и 8.3).
##
## Ровно четыре из GDD: шеренга, стена щитов, колонна, рассыпной строй.
## GDD там же прямо ограничивает объём: «не полноценный ИИ-пафайндинг для
## сложных манёвров, а заранее заданные формации» — поэтому здесь именно
## заранее заданные смещения слотов, без обхода препятствий.
##
## Кроме формы построения дают боевые модификаторы (DESIGN_ANSWERS.md, п. 16),
## иначе выбор строя был бы косметикой.
##

enum Kind { LINE, SHIELD_WALL, COLUMN, LOOSE }

const NAMES := ["шеренга", "стена щитов", "колонна", "рассыпной строй"]

## Множитель обычного входящего урона.
const DAMAGE_TAKEN := [1.0, 0.6, 1.15, 1.0]
## Множитель урона ПО ПЛОЩАДИ. Рассыпной строй затем и нужен: огненный шар
## по плотному строю выкашивает всех, по рассыпному почти никого.
const AOE_TAKEN := [1.0, 1.1, 1.25, 0.35]
## Множитель скорости марша.
const SPEED_SCALE := [1.0, 0.6, 1.3, 1.05]

## Интервал между бойцами по фронту и в глубину, метры.
const SPACING := [
	Vector2(2.2, 2.4),    # шеренга
	Vector2(1.3, 1.6),    # стена щитов — плечом к плечу
	Vector2(2.2, 2.6),    # колонна
	Vector2(4.6, 4.2),    # рассыпной строй
]

## Сколько бойцов в ряду по фронту.
const RANK_WIDTH := [8, 8, 2, 4]

## Отступ первого ряда от командира, метры. Без него слот нулевого ряда
## приходится ровно на точку командира: бойцы собираются под ним, он влезает
## им на головы и уезжает вместе со строем.
const FRONT_GAP := 3.5


func _init() -> void:
	pass


## Смещение слота относительно якоря отряда, в местных осях: x вправо, z назад.
static func slot_offset(kind: int, index: int, _count: int) -> Vector3:
	var k: int = clampi(kind, 0, NAMES.size() - 1)
	var width: int = RANK_WIDTH[k]
	var spacing: Vector2 = SPACING[k]

	var row: int = index / width
	var column: int = index % width
	# Ряд центрируем: середина шеренги приходится на якорь.
	var offset_x: float = (float(column) - (float(width) - 1.0) * 0.5) * spacing.x
	var offset_z: float = FRONT_GAP + float(row) * spacing.y

	if k == Kind.LOOSE:
		# Шахматный порядок: соседние ряды сдвинуты, чтобы не стоять в затылок.
		offset_x += spacing.x * 0.5 if row % 2 == 1 else 0.0
	return Vector3(offset_x, 0.0, offset_z)


static func damage_scale(kind: int, aoe: bool) -> float:
	var k: int = clampi(kind, 0, NAMES.size() - 1)
	return AOE_TAKEN[k] if aoe else DAMAGE_TAKEN[k]


static func speed_scale(kind: int) -> float:
	return SPEED_SCALE[clampi(kind, 0, NAMES.size() - 1)]


static func describe(kind: int) -> String:
	var k: int = clampi(kind, 0, NAMES.size() - 1)
	return "%s (урон x%.2f, по площади x%.2f, скорость x%.2f)" % [
		NAMES[k], DAMAGE_TAKEN[k], AOE_TAKEN[k], SPEED_SCALE[k]
	]
