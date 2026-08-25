extends Node
##
## Точка входа Этапа 0: меню подключения поверх уже загруженного grey-box мира.
##
## Мир НЕ подгружается после коннекта — он лежит в главной сцене с самого старта
## на обоих пирах (см. комментарий в world.gd про порядок спавна).
##
## Аргументы командной строки для быстрого теста в двух окнах:
##   --host          поднять хост сразу при запуске
##   --join=АДРЕС    сразу подключиться (по умолчанию 127.0.0.1)
## Их можно передавать как напрямую, так и после "--".
##

@onready var _menu: Control = $UI/Menu
@onready var _status: Label = $UI/Menu/Panel/VBox/Status
@onready var _ip_edit: LineEdit = $UI/Menu/Panel/VBox/JoinRow/IpEdit
@onready var _host_btn: Button = $UI/Menu/Panel/VBox/HostBtn
@onready var _join_btn: Button = $UI/Menu/Panel/VBox/JoinRow/JoinBtn
@onready var _hud: Label = $UI/Hud/Info


func _ready() -> void:
	Net.status_changed.connect(_on_status)
	Net.session_started.connect(_on_session_started)
	Net.session_ended.connect(_on_session_ended)
	_host_btn.pressed.connect(_on_host_pressed)
	_join_btn.pressed.connect(_on_join_pressed)
	_ip_edit.text_submitted.connect(func(_t: String) -> void: _on_join_pressed())
	_ip_edit.text = "127.0.0.1"
	_show_menu(true)
	_apply_cmdline()


func _process(_delta: float) -> void:
	if not Net.active:
		_hud.text = "Оффлайн"
		return
	var role := "ХОСТ" if Net.is_host else "КЛИЕНТ"
	_hud.text = "%s   id: %d   пиров: %d   fps: %d\nWASD — движение, Space — прыжок, мышь — обзор, Esc — курсор, F10 — выйти в меню" % [
		role, Net.local_id(), Net.peer_count(), Engine.get_frames_per_second()
	]


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		_toggle_mouse()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F10:
		if Net.active:
			Net.leave()
		get_viewport().set_input_as_handled()


func _toggle_mouse() -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif Net.active:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_host_pressed() -> void:
	_set_buttons_enabled(false)
	if not Net.host_game():
		_set_buttons_enabled(true)


func _on_join_pressed() -> void:
	_set_buttons_enabled(false)
	if not Net.join_game(_ip_edit.text):
		_set_buttons_enabled(true)


func _on_status(text: String) -> void:
	_status.text = text
	print("[net] ", text)
	if not Net.active:
		_set_buttons_enabled(true)


func _on_session_started() -> void:
	_show_menu(false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_window().title = "ДжваГода — %s (id %d)" % ["ХОСТ" if Net.is_host else "КЛИЕНТ", Net.local_id()]


func _on_session_ended() -> void:
	_show_menu(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_window().title = "ДжваГода"


func _show_menu(visible_now: bool) -> void:
	_menu.visible = visible_now
	_set_buttons_enabled(true)


func _set_buttons_enabled(enabled: bool) -> void:
	_host_btn.disabled = not enabled
	_join_btn.disabled = not enabled


func _apply_cmdline() -> void:
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	for arg in args:
		if arg == "--host":
			_on_host_pressed()
			return
		if arg == "--join":
			_on_join_pressed()
			return
		if arg.begins_with("--join="):
			_ip_edit.text = arg.substr("--join=".length())
			_on_join_pressed()
			return
