extends Camera3D
##
## Стратегическая камера (Этап 1): вид сверху для управления войсками и стройкой.
##
## Отдельная камера в мире, НЕ привязанная к персонажу — это прямое следствие
## дизайн-решения: пока игрок смотрит сверху, его персонаж физически остаётся
## в мире и уязвим (см. DESIGN_ANSWERS.md, пункт 7).
##
## Камера — чисто локальная штука, по сети не реплицируется ничего: другой игрок
## не знает и не должен знать, в каком режиме ты смотришь.
##
## Летает по всей карте (DESIGN_ANSWERS.md, пункт 8). Туман войны, который по
## тому же пункту должен скрывать чужое, здесь НЕ реализован: на Этапе 1 нет ни
## юнитов, ни построек, скрывать нечего. Делать его нужно авторитетно на хосте,
## когда они появятся.
##

## Скорость панорамирования на базовой высоте; выше — быстрее, как в любой RTS.
const PAN_SPEED := 90.0
const BASE_HEIGHT := 90.0
const MIN_HEIGHT := 25.0
const MAX_HEIGHT := 340.0
const ZOOM_STEP := 0.15
const ROTATE_SPEED := 1.8
## Наклон камеры к горизонту.
const PITCH_DEG := 55.0
## Отступ от края карты, чтобы не улетать за стены.
const EDGE_MARGIN := 40.0

## По class_name обращаться нельзя: кэш глобальных классов строится редактором.
const WORLD_BUILDER := preload("res://scripts/world_builder.gd")

var active := false

var _focus := Vector3.ZERO
var _height := BASE_HEIGHT
var _yaw := 0.0
var _limit := WORLD_BUILDER.WORLD_SIZE * 0.5 - EDGE_MARGIN


func _ready() -> void:
	current = false
	set_process(false)
	set_process_unhandled_input(false)


## Включить, поставив обзор над точкой (обычно — над своим персонажем).
func activate(focus_point: Vector3, height: float = BASE_HEIGHT) -> void:
	_focus = Vector3(focus_point.x, 0.0, focus_point.z)
	_height = clampf(height, MIN_HEIGHT, MAX_HEIGHT)
	active = true
	current = true
	set_process(true)
	set_process_unhandled_input(true)
	_apply()


func deactivate() -> void:
	active = false
	current = false
	set_process(false)
	set_process_unhandled_input(false)


func _process(delta: float) -> void:
	var move := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var turn := 0.0
	if Input.is_action_pressed("cam_rotate_left"):
		turn += 1.0
	if Input.is_action_pressed("cam_rotate_right"):
		turn -= 1.0

	if turn != 0.0:
		_yaw += turn * ROTATE_SPEED * delta

	if move != Vector2.ZERO:
		# Направление взгляда на плоскости и вектор вправо от него.
		var fwd := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
		var right := Vector3(cos(_yaw), 0.0, -sin(_yaw))
		var speed := PAN_SPEED * (_height / BASE_HEIGHT)
		_focus += (right * move.x - fwd * move.y) * speed * delta
		_focus.x = clampf(_focus.x, -_limit, _limit)
		_focus.z = clampf(_focus.z, -_limit, _limit)

	_apply()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_height = clampf(_height * (1.0 - ZOOM_STEP), MIN_HEIGHT, MAX_HEIGHT)
		get_viewport().set_input_as_handled()
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_height = clampf(_height * (1.0 + ZOOM_STEP), MIN_HEIGHT, MAX_HEIGHT)
		get_viewport().set_input_as_handled()


func _apply() -> void:
	# Отступ назад по горизонтали задаётся наклоном: чем выше, тем дальше.
	var dist := _height / tan(deg_to_rad(PITCH_DEG))
	global_position = _focus + Vector3(sin(_yaw) * dist, _height, cos(_yaw) * dist)
	look_at(_focus, Vector3.UP)


## Для HUD: текущая высота обзора в метрах.
func height() -> float:
	return _height
