extends Node3D
##
## Маяк: столб света над местом, куда сейчас велит идти подсказка.
##
## ЗАЧЕМ ОН, А НЕ СТРОКА «шахта на севере». Тестер спросил дважды и в разных
## словах: «не понятно где шахта», «не понятно моя зона в начале». Словами это
## не чинится. Шахта стоит в шестистах метрах, за холмом и за лесом; «на
## севере» — ответ наполовину, а на карте из одинаковых зелёных холмов и
## половины не остаётся. Место надо ПОКАЗАТЬ.
##
## ВИДЕН СКВОЗЬ РЕЛЬЕФ, И ЭТО НЕ НЕДОСМОТР. Маяк, пропадающий за первым же
## холмом, бесполезен ровно там, где нужен: пока цель на виду, игрок и так
## дойдёт. Поэтому материал без глубины (`no_depth_test`) и без света
## (`SHADING_MODE_UNSHADED`) — столб проступает поверх карты, как метка на
## стекле.
##
## ТОЛЬКО СВОЙ. Маяк рождается у КАЖДОГО пира отдельно, ничего не
## реплицируется и в сохранение не попадает: это подсказка одному человеку, а
## не предмет мира. Чужой маяк выдавал бы противнику, куда идёт игрок.
##
## ВЫСОТУ НЕ СЧИТАЕМ ПО РЕЛЬЕФУ. Столб начинается заметно ниже указанной точки
## и уходит высоко вверх: так он остаётся виден и когда цель на плато, и когда
## она в низине, и не требует ни луча вниз, ни знания карты.
##

## Высота столба. Плато поднимает дворец на шесть метров, гряда — на
## семьдесят; столб обязан быть выше всего, что может встать перед ним.
const HEIGHT := 90.0
## Насколько столб опущен ниже точки: цель бывает в яме, и маяк, начатый ровно
## на её высоте, висел бы в воздухе.
const SINK := 10.0
## Толщина столба. Три метра, а не метр: цель бывает в шестистах метрах, и
## метровый столб выходит там в два пикселя — его попросту не видно.
const RADIUS := 3.0
## Как быстро пульсирует, раз в секунду. Ровно светящийся столб глаз принимает
## за деталь карты; мигающий — за метку.
const PULSE := 0.8

var _mesh: MeshInstance3D
var _label: Label3D
var _material: StandardMaterial3D
var _time := 0.0
var _name := ""


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.no_depth_test = true
	# Не отбрасывать тень: столб — это метка на стекле, а тень от неё на поле
	# выглядела бы как настоящая постройка.
	_material.albedo_color = Color(1.0, 0.82, 0.30, 0.34)

	var cylinder := CylinderMesh.new()
	cylinder.top_radius = RADIUS * 0.35
	cylinder.bottom_radius = RADIUS
	cylinder.height = HEIGHT
	cylinder.radial_segments = 10
	_mesh = MeshInstance3D.new()
	_mesh.mesh = cylinder
	_mesh.material_override = _material
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.position = Vector3(0.0, HEIGHT * 0.5 - SINK, 0.0)
	add_child(_mesh)

	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.fixed_size = true
	# ПОСТОЯННЫЙ РАЗМЕР НА ЭКРАНЕ, но маленький. С умолчанием `pixel_size`
	# подпись занимала пол-экрана и закрывала собой и столб, и мир: она ведь не
	# уменьшается с расстоянием, в том и смысл.
	_label.pixel_size = 0.0014
	_label.font_size = 64
	_label.outline_size = 18
	_label.modulate = Color(1.0, 0.88, 0.52)
	_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	_label.position = Vector3(0.0, 8.0, 0.0)
	add_child(_label)


## Показать маяк в точке. Пустое имя или `null` — спрятать.
func aim(at, place_name: String) -> void:
	if at == null or place_name == "":
		visible = false
		return
	visible = true
	global_position = at
	_name = place_name


## Обновить подпись расстоянием. Зовёт HUD: считать его здесь значило бы искать
## игрока из маяка, а игрок и так есть у того, кто маяк ставит.
func show_gap(metres: float) -> void:
	if not visible:
		return
	_label.text = "%s\n%d м" % [_name, int(metres)]


func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	# Пульс по синусу, но НЕ до нуля: пропадающий столб читается как сбой
	# отрисовки, а не как мигание.
	var beat: float = 0.26 + 0.14 * (0.5 + 0.5 * sin(_time * TAU * PULSE))
	_material.albedo_color.a = beat
