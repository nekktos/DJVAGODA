extends Node3D
##
## Постройка форта (Этап 4, GDD раздел 2.3): склад и казарма.
##
## Стройку ведёт ТОЛЬКО хост: он же принял решение, что место годное и ресурсы
## списаны. Клиенты получают тип, владельца и прогресс и просто рисуют.
##
## Склад по GDD — «главное здание, оно же склад и пункт приёма ресурсов»:
## достроившись, он поднимает потолок хранения владельцу. Приём от каравана
## встанет сюда же на Этапе 5.
##

const RES := preload("res://scripts/economy/resources.gd")

## Достроено (на любом пире, после репликации).
signal completed

## Реплицируемое состояние.
@export var progress: float = 0.0

var kind := 0
var owner_id := 1

var _mesh: MeshInstance3D
var _done := false


## Вызывается спавнером на всех пирах с одинаковыми данными.
func setup(data: Dictionary) -> void:
	kind = int(data["kind"])
	owner_id = int(data["owner"])
	position = data["point"]
	rotation.y = float(data.get("yaw", 0.0))


func _ready() -> void:
	var size: Vector3 = RES.BUILDING_SIZE[kind]

	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	shape.position = Vector3(0.0, size.y * 0.5, 0.0)
	body.add_child(shape)
	add_child(body)
	add_to_group("building")

	_mesh = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	_mesh.mesh = box
	_mesh.material_override = _material()
	add_child(_mesh)
	_apply_progress()


func _material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.30, 0.19) if kind == RES.Building.STORAGE else Color(0.34, 0.33, 0.36)
	mat.roughness = 0.9
	return mat


func _process(delta: float) -> void:
	if multiplayer.is_server() and progress < 1.0:
		progress = minf(1.0, progress + delta / float(RES.BUILD_TIME[kind]))
	_apply_progress()
	if progress >= 1.0 and not _done:
		_done = true
		completed.emit()


## Пока строится — коробка растёт из земли и просвечивает.
func _apply_progress() -> void:
	if _mesh == null:
		return
	var size: Vector3 = RES.BUILDING_SIZE[kind]
	var grown: float = maxf(0.05, progress)
	_mesh.scale = Vector3(1.0, grown, 1.0)
	_mesh.position = Vector3(0.0, size.y * grown * 0.5, 0.0)

	var mat: StandardMaterial3D = _mesh.material_override
	if mat == null:
		return
	if progress < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color.a = 0.55
	else:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		mat.albedo_color.a = 1.0


func label() -> String:
	return RES.BUILDING_NAMES[clampi(kind, 0, RES.BUILDING_NAMES.size() - 1)]
