extends Node
##
## Точка входа Этапа 0: меню подключения поверх уже загруженного grey-box мира.
##
## Мир НЕ подгружается после коннекта — он лежит в главной сцене с самого старта
## на обоих пирах (см. комментарий в world.gd про порядок спавна).
##
## Аргументы командной строки для быстрого теста в нескольких окнах:
##   --host          поднять хост сразу при запуске
##   --join=АДРЕС    сразу подключиться (IP, либо Steam ID при --steam)
##   --steam         использовать Steam-транспорт вместо локального IP
##   --shots=ПАПКА   снять карту с набора ракурсов в PNG и выйти (нужно окно)
##   --walktest      автопроверка проходимости карты и выход (работает headless)
##   --perftest      замер fps в обоих режимах камеры и выход (нужно окно)
##   --strategytest  через 8 с уйти в стратегический режим и остаться в нём
## Их можно передавать как напрямую, так и после "--".
##

const LOCAL_HINT := "Локально: порт 24545, второе окно подключается к 127.0.0.1."
const STEAM_HINT := "Steam: хост сообщает свой Steam ID, второй игрок вставляет его в поле."

@onready var _menu: Control = $UI/Menu
@onready var _status: Label = $UI/Menu/Panel/VBox/Status
@onready var _transport_opt: OptionButton = $UI/Menu/Panel/VBox/TransportRow/TransportOpt
@onready var _ip_edit: LineEdit = $UI/Menu/Panel/VBox/JoinRow/IpEdit
@onready var _host_btn: Button = $UI/Menu/Panel/VBox/HostBtn
@onready var _join_btn: Button = $UI/Menu/Panel/VBox/JoinRow/JoinBtn
@onready var _hud: Label = $UI/Hud/Info
@onready var _world: Node3D = $World


func _ready() -> void:
	Net.status_changed.connect(_on_status)
	Net.session_started.connect(_on_session_started)
	Net.session_ended.connect(_on_session_ended)
	_host_btn.pressed.connect(_on_host_pressed)
	_join_btn.pressed.connect(_on_join_pressed)
	_transport_opt.item_selected.connect(_on_transport_selected)
	_ip_edit.text_submitted.connect(func(_t: String) -> void: _on_join_pressed())
	_world.camera_mode_changed.connect(_on_camera_mode_changed)

	if not Net.steam_available():
		_transport_opt.set_item_disabled(1, true)
		_transport_opt.set_item_text(1, "Steam (аддон не загружен)")

	_on_transport_selected(0)
	_show_menu(true)
	_apply_cmdline()


func _process(_delta: float) -> void:
	if not Net.active:
		_hud.text = "Оффлайн"
		return
	var role := "ХОСТ" if Net.is_host else "КЛИЕНТ"
	var kind := "Steam" if Net.transport == Net.Transport.STEAM else "IP"
	var mode := "СТРАТЕГИЯ" if _world.strategy_mode else "ЭКШЕН"
	var line := "%s (%s)   id: %d   пиров: %d   fps: %d   камера: %s" % [
		role, kind, Net.local_id(), Net.peer_count(), Engine.get_frames_per_second(), mode
	]
	if Net.is_host and Net.transport == Net.Transport.STEAM:
		line += "\nSteam ID для друга: %d   (F9 — скопировать)" % Net.local_steam_id()
	if _world.strategy_mode:
		line += "   высота: %d м" % int(_world.strategy_height())
		_hud.text = line + "\nWASD — двигать камеру, Q/E — поворот, колесо — зум, Tab — назад в экшен, F10 — в меню"
	else:
		_hud.text = line + "\nWASD — движение, Space — прыжок, мышь — обзор, Tab — вид сверху, Esc — курсор, F10 — в меню"


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_camera") and Net.active:
		_world.toggle_camera_mode()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"ui_cancel"):
		_toggle_mouse()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F10:
			if Net.active:
				Net.leave()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F9:
			_copy_steam_id()
			get_viewport().set_input_as_handled()


func _copy_steam_id() -> void:
	if not (Net.active and Net.is_host and Net.transport == Net.Transport.STEAM):
		return
	var id := Net.local_steam_id()
	DisplayServer.clipboard_set(str(id))
	print("[net] Steam ID скопирован в буфер: ", id)


func _toggle_mouse() -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif Net.active and not _world.strategy_mode:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_transport_selected(index: int) -> void:
	Net.transport = Net.Transport.STEAM if index == 1 else Net.Transport.ENET
	if Net.transport == Net.Transport.STEAM:
		_ip_edit.placeholder_text = "Steam ID хоста"
		if _ip_edit.text == "127.0.0.1":
			_ip_edit.text = ""
		_status.text = STEAM_HINT
	else:
		_ip_edit.placeholder_text = "IP хоста"
		if _ip_edit.text.is_empty():
			_ip_edit.text = "127.0.0.1"
		_status.text = LOCAL_HINT


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
	if args.has("--steam"):
		if Net.steam_available():
			_transport_opt.select(1)
			_on_transport_selected(1)
		else:
			push_warning("Передан --steam, но аддон GodotSteam не загружен. Остаюсь на IP.")
	# Инструменты проверки настраиваем ДО разбора --host/--join: те завершают
	# разбор через return, и обработка в том же цикле зависела бы от порядка
	# аргументов в командной строке.
	var needs_session := false

	# --strategytest: через 8 секунд уйти в стратегический режим и остаться в нём.
	# Нужен, чтобы с другого пира проверить, что персонаж при этом никуда не
	# девается и остаётся видимым, просто перестаёт двигаться.
	if args.has("--strategytest"):
		needs_session = true
		_arm_strategy_test()

	if args.has("--perftest"):
		var perf: Node = preload("res://tools/perf_test.gd").new()
		add_child(perf)
		perf.start(_world)
		needs_session = true

	if args.has("--walktest"):
		var walker: Node = preload("res://tools/walk_test.gd").new()
		add_child(walker)
		walker.start(_world)
		needs_session = true

	for arg in args:
		if arg.begins_with("--shots="):
			_start_screenshots(arg.substr("--shots=".length()))
			needs_session = true
			break

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

	# Инструментам нужна живая сессия, иначе персонажа в мире не будет.
	if needs_session:
		_on_host_pressed()


## В стратегическом режиме курсор нужен свободным — им будут отдавать приказы.
## В экшене он захвачен для обзора мышью.
func _on_camera_mode_changed(strategy: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if strategy else Input.MOUSE_MODE_CAPTURED


## Режим съёмки ракурсов: инструмент проверки, к геймплею отношения не имеет.
func _start_screenshots(dir: String) -> void:
	var runner: Node = preload("res://tools/screenshotter.gd").new()
	add_child(runner)
	runner.start(_world, dir)


func _arm_strategy_test() -> void:
	await get_tree().create_timer(8.0).timeout
	_world.set_strategy_mode(true)
	print("[strategytest] ушёл в стратегический режим, персонаж должен остаться в мире")
