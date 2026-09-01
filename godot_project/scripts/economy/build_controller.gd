extends Node3D
##
## Режим стройки: выбор здания, призрак на земле, отправка заявки хосту.
##
## Работает только в стратегической камере — по GDD раздел 1 это и есть
## «управление войсками, экономикой, стройкой» сверху.
##
## Всё здесь — сторона КЛИЕНТА: призрак и подсветка годности места нужны только
## чтобы игрок понимал, что делает. Решение принимает хост и проверяет всё
## заново по своей копии мира (см. world.gd::request_build).
##

const RES := preload("res://scripts/economy/resources.gd")

## ПЕРЕПАД ВЫСОТ БОЛЬШЕ НЕ ЗАПРЕЩЁН.
##
## Здесь стоял предел в полтора метра, и на плоской карте он ничего не стоил:
## ровного места было сколько угодно. С появлением рельефа он запретил стройку
## почти везде — склад не вставал даже там, где земля кажется ровной.
##
## Решение владельца проекта: строить можно на любой поверхности, а разницу
## высот закрывают СВАИ и ПОДМОСТКИ. Дом садится полом на самую высокую точку
## под собой, под низкими углами вырастают опоры, а ко входу приставляется
## пандус, по которому можно войти. Смотри `building.gd::_apply_footing`.
## Насколько далеко от камеры ищем землю.
const PICK_DISTANCE := 900.0
## Минимальный зазор между постройками, метры.
const CLEARANCE := 3.0

signal selection_changed(kind: int, active: bool)

var active := false
var kind: int = RES.Building.STORAGE

var _ghost: MeshInstance3D
var _valid := false
var _point := Vector3.ZERO


func _ready() -> void:
	_build_ghost()
	set_process(false)


func _build_ghost() -> void:
	_ghost = MeshInstance3D.new()
	_ghost.mesh = BoxMesh.new()
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost.material_override = mat
	_ghost.visible = false
	add_child(_ghost)


func set_active(on: bool) -> void:
	active = on
	set_process(on)
	_ghost.visible = on
	if on:
		_resize_ghost()
	selection_changed.emit(kind, active)


func select(new_kind: int) -> void:
	kind = clampi(new_kind, 0, RES.BUILDING_NAMES.size() - 1)
	_resize_ghost()
	selection_changed.emit(kind, active)


func _resize_ghost() -> void:
	var size: Vector3 = RES.BUILDING_SIZE[kind]
	(_ghost.mesh as BoxMesh).size = size


func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var mouse := get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(mouse)
	var to := from + camera.project_ray_normal(mouse) * PICK_DISTANCE

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		_ghost.visible = false
		_valid = false
		return

	_point = hit["position"]
	_valid = is_spot_buildable(self, _point, kind)
	var size: Vector3 = RES.BUILDING_SIZE[kind]
	_ghost.visible = true
	_ghost.global_position = _point + Vector3(0.0, size.y * 0.5, 0.0)
	var mat: StandardMaterial3D = _ghost.material_override
	mat.albedo_color = Color(0.3, 0.9, 0.4, 0.4) if _valid else Color(0.9, 0.25, 0.2, 0.4)


func current_point() -> Vector3:
	return _point


func is_valid() -> bool:
	return _valid


## Годится ли место под здание. Одна и та же проверка у клиента (для подсветки)
## и у хоста (для решения) — иначе призрак обещал бы одно, а хост делал другое.
static func is_spot_buildable(context: Node3D, point: Vector3, building_kind: int) -> bool:
	var size: Vector3 = RES.BUILDING_SIZE[building_kind]
	var half_x := size.x * 0.5
	var half_z := size.z * 0.5
	var space := context.get_world_3d().direct_space_state

	# Земля под каждым углом обязана БЫТЬ. Перепад между углами больше не
	# проверяем (см. шапку про сваи), но повиснуть в пустоте дом не должен:
	# луч, не нашедший опоры, — это край карты или дыра, а не склон.
	for dx in [-half_x, half_x]:
		for dz in [-half_z, half_z]:
			var probe := point + Vector3(dx, 0.0, dz)
			var query := PhysicsRayQueryParameters3D.create(
				probe + Vector3.UP * 60.0, probe + Vector3.DOWN * 60.0
			)
			query.collision_mask = 1
			if space.intersect_ray(query).is_empty():
				return false

	# Не залезаем на уже построенное.
	for node in context.get_tree().get_nodes_in_group("building"):
		var other := node as Node3D
		if other == null:
			continue
		var other_size: Vector3 = RES.BUILDING_SIZE[int(other.kind)]
		var gap_x: float = (size.x + other_size.x) * 0.5 + CLEARANCE
		var gap_z: float = (size.z + other_size.z) * 0.5 + CLEARANCE
		var delta: Vector3 = other.global_position - point
		if absf(delta.x) < gap_x and absf(delta.z) < gap_z:
			return false
	return true


## Игрок кликнул по земле в режиме стройки.
signal place_requested(kind: int, point: Vector3)


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and _valid:
			place_requested.emit(kind, _point)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			set_active(false)
			get_viewport().set_input_as_handled()


## Точка на земле под курсором. Общий помощник: им пользуются и призрак здания,
## и прокладка маршрута, и приказ отряду — чтобы все три брали одну и ту же
## точку и не расходились в мелочах.
static func pick_ground(context: Node3D) -> Dictionary:
	var camera := context.get_viewport().get_camera_3d()
	if camera == null:
		return {}
	var mouse := context.get_viewport().get_mouse_position()
	var query := PhysicsRayQueryParameters3D.create(
		camera.project_ray_origin(mouse),
		camera.project_ray_origin(mouse) + camera.project_ray_normal(mouse) * PICK_DISTANCE
	)
	query.collision_mask = 1
	return context.get_world_3d().direct_space_state.intersect_ray(query)
