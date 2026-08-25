extends Node3D
##
## Ручная прокладка маршрута каравана (GDD раздел 8.2: «маршрут игрок
## прокладывает сам, рисует путь» — жёстко зашитой дороги нет).
##
## Игрок ставит точки кликами в стратегической камере. Хост дорисовывает начало
## и конец сам: караван всегда выходит от склада и всегда едет к шахте, а вот
## КАК он туда попадёт — решает игрок. В этом и смысл: короткий путь быстрее,
## но идёт через открытое место, где его перехватят.
##
## Всё здесь — сторона клиента. Отправку и проверку маршрута делает хост.
##

const RES := preload("res://scripts/economy/resources.gd")

## Больше точек рисовать бессмысленно, а хосту их ещё проверять.
const MAX_POINTS := 12
const PICK_DISTANCE := 1200.0

signal route_changed(count: int)
signal route_sent(points: PackedVector3Array)

var active := false

var _points: PackedVector3Array = PackedVector3Array()
var _markers: Node3D


func _ready() -> void:
	_markers = Node3D.new()
	add_child(_markers)
	set_process_unhandled_input(false)


func set_active(on: bool) -> void:
	active = on
	set_process_unhandled_input(on)
	if not on:
		clear()
	route_changed.emit(_points.size())


func clear() -> void:
	_points = PackedVector3Array()
	for child in _markers.get_children():
		child.queue_free()
	route_changed.emit(0)


func points() -> PackedVector3Array:
	return _points


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_add_point()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			set_active(false)
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			route_sent.emit(_points)
			set_active(false)
			get_viewport().set_input_as_handled()


func _add_point() -> void:
	if _points.size() >= MAX_POINTS:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var mouse := get_viewport().get_mouse_position()
	var query := PhysicsRayQueryParameters3D.create(
		camera.project_ray_origin(mouse),
		camera.project_ray_origin(mouse) + camera.project_ray_normal(mouse) * PICK_DISTANCE
	)
	query.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return

	var point: Vector3 = hit["position"]
	_points.append(point)
	_draw_marker(point)
	if _points.size() >= 2:
		_draw_segment(_points[_points.size() - 2], point)
	route_changed.emit(_points.size())


func _draw_marker(point: Vector3) -> void:
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.8
	cyl.bottom_radius = 0.8
	cyl.height = 4.0
	mesh.mesh = cyl
	mesh.material_override = _marker_material(Color(0.95, 0.80, 0.25))
	mesh.position = point + Vector3.UP * 2.0
	_markers.add_child(mesh)


func _draw_segment(from: Vector3, to: Vector3) -> void:
	var middle := (from + to) * 0.5
	var span := to - from
	var length := span.length()
	if length < 0.5:
		return
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.6, 0.3, length)
	mesh.mesh = box
	mesh.material_override = _marker_material(Color(0.95, 0.80, 0.25, 0.7))
	mesh.position = middle + Vector3.UP * 0.6
	mesh.look_at_from_position(mesh.position, to + Vector3.UP * 0.6, Vector3.UP)
	_markers.add_child(mesh)


func _marker_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat
