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
##   --combattest    автопроверка боевой петли на двух пирах (headless)
##   --woundtest     автопроверка системы ранений и протезов (headless)
##   --econtest      автопроверка добычи и стройки (headless)
##   --caravantest   автопроверка шахты, каравана и грабежа (headless)
##   --squadtest     автопроверка отряда и построений (headless)
##   --slicetest     автопроверка вертикального среза (headless)
##   --consoletest   автопроверка консольных команд (headless)
##   --foresttest    автопроверка impostor-леса (headless)
##   --elftest       автопроверка магии поддержки эльфов (headless)
##   --tradetest     автопроверка торговли и снаряжения (headless)
##   --guardtest     автопроверка приказов командира стражи (headless)
##   --deathtest     автопроверка смерти, респавна и мародёрства (headless)
##   --victorytest   автопроверка условий победы и командования (headless)
##   --diptest       автопроверка репутации и дипломатии (headless)
##   --savetest      автопроверка сохранений и профиля игрока (headless)
##   --garrisontest  автопроверка гарнизонов свободных сторон (headless)
##   --warbandtest   автопроверка воюющего ИИ свободных сторон (headless)
##   --soaktest      трёхминутный прогон мира без людей: не деградирует ли ИИ
##   --navtest       автопроверка путей по карте (headless)
##   --labtest       автопроверка батраков: наём, роли, добыча (headless)
##   --faction=N     выбрать сторону: 0 злодей, 1 эльфы, 2 стража
##   --profile=ИМЯ   подменить профиль игрока (нужно для двух окон на одной машине)
##   --world=ИМЯ     работать с отдельным файлом мира
##   --freshworld    не загружать сохранение и не сохраняться (для автопроверок)
##   --playerprobe   печать состава собранного персонажа и выход (headless)
## Их можно передавать как напрямую, так и после "--".
##

const LOCAL_HINT := "Локально: порт 24545, второе окно подключается к 127.0.0.1."
const STEAM_HINT := "Steam: хост сообщает свой Steam ID, второй игрок вставляет его в поле."

const WEAPONS := preload("res://scripts/combat/weapons.gd")
const ABILITIES := preload("res://scripts/combat/abilities.gd")
const RES := preload("res://scripts/economy/resources.gd")
const FORMATIONS := preload("res://scripts/units/formations.gd")
const BUILD_CONTROLLER := preload("res://scripts/economy/build_controller.gd")
const FACTIONS := preload("res://scripts/factions.gd")
const WARBAND := preload("res://scripts/ai/warband.gd")
const LABOURER := preload("res://scripts/units/labourer.gd")
const ORDERS := preload("res://scripts/orders.gd")

## Сколько секунд держится объявление о результате.
const ANNOUNCE_SECONDS := 7.0

@onready var _menu: Control = $UI/Menu
@onready var _status: Label = $UI/Menu/Panel/VBox/Status
@onready var _transport_opt: OptionButton = $UI/Menu/Panel/VBox/TransportRow/TransportOpt
@onready var _ip_edit: LineEdit = $UI/Menu/Panel/VBox/JoinRow/IpEdit
@onready var _host_btn: Button = $UI/Menu/Panel/VBox/HostBtn
@onready var _join_btn: Button = $UI/Menu/Panel/VBox/JoinRow/JoinBtn
@onready var _hud: Label = $UI/Hud/Info
@onready var _world: Node3D = $World
@onready var _blind_left: ColorRect = $UI/Blind/Left
@onready var _blind_right: ColorRect = $UI/Blind/Right
@onready var _bench: Control = $UI/Bench
@onready var _bench_chair: Button = $UI/Bench/Panel/VBox/Chair
@onready var _trader: Control = $UI/Trader
@onready var _commander_ui: Control = $UI/Commander
@onready var _announce: Label = $UI/Hud/Announce
@onready var _faction_opt: OptionButton = $UI/Menu/Panel/VBox/FactionRow/FactionOpt
@onready var _console: Control = $UI/Console
@onready var _console_out: RichTextLabel = $UI/Console/Panel/VBox/Output
@onready var _console_in: LineEdit = $UI/Console/Panel/VBox/Input


func _ready() -> void:
	Net.status_changed.connect(_on_status)
	Net.session_started.connect(_on_session_started)
	Net.session_ended.connect(_on_session_ended)
	_host_btn.pressed.connect(_on_host_pressed)
	_join_btn.pressed.connect(_on_join_pressed)
	_transport_opt.item_selected.connect(_on_transport_selected)
	_ip_edit.text_submitted.connect(func(_t: String) -> void: _on_join_pressed())
	_world.camera_mode_changed.connect(_on_camera_mode_changed)
	_world.objective.announced.connect(_on_announced)
	_faction_opt.item_selected.connect(func(index: int) -> void: Net.chosen_faction = index)
	Net.chosen_faction = _faction_opt.selected
	_console_in.text_submitted.connect(_on_console_submitted)

	var bench := $UI/Bench/Panel/VBox
	bench.get_node("Wooden").pressed.connect(_on_bench_prosthetic.bind(1))
	bench.get_node("Iron").pressed.connect(_on_bench_prosthetic.bind(2))
	bench.get_node("Master").pressed.connect(_on_bench_prosthetic.bind(3))
	bench.get_node("Chair").pressed.connect(_on_bench_chair)
	bench.get_node("Close").pressed.connect(_close_bench)

	var trader := $UI/Trader/Panel/VBox
	trader.get_node("Bandages").pressed.connect(_on_trade.bind(RES.Trade.BANDAGES))
	trader.get_node("Gear").pressed.connect(_on_trade.bind(RES.Trade.GEAR))
	trader.get_node("Close").pressed.connect(_close_trader)

	var commander := $UI/Commander/Panel/VBox
	commander.get_node("Report").pressed.connect(_on_report)
	commander.get_node("Promote").pressed.connect(_on_promote)
	commander.get_node("Close").pressed.connect(_close_commander)

	if not Net.steam_available():
		_transport_opt.set_item_disabled(1, true)
		_transport_opt.set_item_text(1, "Steam (аддон не загружен)")

	_on_transport_selected(0)
	_show_menu(true)
	_apply_cmdline()


func _process(delta: float) -> void:
	_tick_announce(delta)
	_tick_refusal(delta)
	if not Net.active:
		_hud.text = "Оффлайн   сборка: %s" % ProjectSettings.get_setting("application/config/version", "?")
		return
	var role := "ХОСТ" if Net.is_host else "КЛИЕНТ"
	var kind := "Steam" if Net.transport == Net.Transport.STEAM else "IP"
	var mode := "СТРАТЕГИЯ" if _world.strategy_mode else "ЭКШЕН"
	if _world.is_spectating():
		mode = "НАБЛЮДАТЕЛЬ (вожак пал, возврата нет)"
	var line := "%s (%s)   id: %d   пиров: %d   fps: %d   камера: %s   сборка: %s" % [
		role, kind, Net.local_id(), Net.peer_count(), Engine.get_frames_per_second(), mode,
		ProjectSettings.get_setting("application/config/version", "?")
	]
	if Net.is_host and Net.transport == Net.Transport.STEAM:
		line += "\nSteam ID для друга: %d   (F9 — скопировать)" % Net.local_steam_id()
	line += "\n" + _objective_hint(_world.local_player())
	line += _ai_hint()
	if _world.strategy_mode:
		line += "   высота: %d м" % int(_world.strategy_height())
		var boss: Node3D = _world.local_player()
		if boss != null:
			line += "\nсклад: %s" % boss.stock.summary()
		line += "\n" + _build_hint()
		line += "\n" + _crew_hint()
		line += "\n" + _squad_hint()
		_hud.text = line + "\nWASD — двигать камеру, Q/E — поворот, колесо — зум, Tab — назад в экшен, F10 — в меню" + _refusal_line()
	else:
		var me: Node3D = _world.local_player()
		if me != null:
			line += "   HP: %d   оружие: %s   бинтов: %d" % [
				int(me.health.current), WEAPONS.NAMES[me.sync_weapon], me.body.bandages
			]
			line += "\nсклад: %s" % me.stock.summary()
			line += "\nтело: %s" % me.body.summary()
			if me.body.bleeding:
				var progress: float = me.bandage_progress()
				if progress > 0.0:
					line += "   перевязка: %d%%" % int(progress * 100.0)
				else:
					line += "   B — перевязать (стоя на месте)"
			if FACTIONS.has_abilities(me.faction):
				line += "\n" + _abilities_hint(me)
			if int(me.faction) == FACTIONS.Kind.GUARD and me.order_kind >= 0:
				line += "\nприказ: %s — %s" % [
					ORDERS.name_of(me.order_kind),
					ORDERS.progress_text(me.order_kind, me.order_progress),
				]
			var truce: Node3D = me.truce_target()
			if truce != null:
				line += "\nY — предложить перемирие: %s (сейчас %s)" % [
					FACTIONS.name_of(truce.faction),
					_world.diplomacy.label_of(me.faction, truce.faction),
				]
			var pile: Node3D = me.loot_nearby()
			if pile != null:
				line += "\nF — подобрать груз: %s" % pile.summary()
			elif me.at_trader():
				line += "\nF — лавка: бинты и снаряжение (сейчас %s)" % WEAPONS.gear_name(me.gear_tier)
			elif me.at_commander():
				line += "\nF — командир: %s" % _order_hint(me)
			elif me.at_workbench():
				line += "\nF — верстак: протезы и коляска"
		_hud.text = line + "\nWASD — движение, Space — прыжок, ЛКМ — удар, 1/2/3 — меч/лук/шар, Tab — вид сверху, F10 — в меню" + _refusal_line()
	_update_blindness()


func _unhandled_input(event: InputEvent) -> void:
	if Net.active and _world.strategy_mode and event is InputEventKey and event.pressed and not event.echo:
		# Игровые клавиши читаем по ФИЗИЧЕСКОЙ позиции, а не по символу: keycode
		# зависит от раскладки, и на русской раскладке управление отваливалось бы
		# целиком. Для игры важно, какая клавиша нажата, а не что на ней написано.
		var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		if key == KEY_1:
			_world.set_build_mode(true, RES.Building.STORAGE)
			get_viewport().set_input_as_handled()
			return
		if key == KEY_2:
			_world.set_build_mode(true, RES.Building.BARRACKS)
			get_viewport().set_input_as_handled()
			return
		if key == KEY_C:
			_world.set_route_mode(not _world.route_controller.active)
			get_viewport().set_input_as_handled()
			return
		if key >= KEY_F1 and key <= KEY_F4:
			_squad_order("formation", key - KEY_F1)
			get_viewport().set_input_as_handled()
			return
		if key == KEY_G:
			_squad_order("follow", 0)
			get_viewport().set_input_as_handled()
			return
		if key == KEY_T:
			_squad_order("train", 0)
			get_viewport().set_input_as_handled()
			return
		if key == KEY_B:
			var boss: Node3D = _world.local_player()
			if boss != null:
				boss.ask_hire_labourer()
			get_viewport().set_input_as_handled()
			return
		# 4-7 переводят одного батрака на соответствующее дело. Выбора мышью в
		# стратегическом режиме нет, и роль — это и есть «куда его отправить».
		if key >= KEY_4 and key <= KEY_7:
			var chief: Node3D = _world.local_player()
			if chief != null:
				chief.ask_set_labourer_role(key - KEY_4)
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		# Стройка и прокладка маршрута перехватывают ПКМ раньше — там это отмена.
		if _try_squad_move_order():
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed(&"truce") and Net.active and not _world.strategy_mode:
		var who: Node3D = _world.local_player()
		if who != null and who.truce_target() != null:
			who.ask_truce()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"interact") and Net.active:
		# У кучи груза F подбирает её, у верстака и лавки открывает панель.
		var me: Node3D = _world.local_player()
		if me != null and me.loot_nearby() != null:
			me.ask_collect_loot()
		elif me != null and (me.at_trader() or _trader.visible):
			_toggle_trader()
		elif me != null and (me.at_commander() or _commander_ui.visible):
			_toggle_commander()
		else:
			_toggle_bench()
		get_viewport().set_input_as_handled()
		return
	# Тильда открывает консоль. Ловим до всего остального, чтобы она работала
	# и в меню, и в бою.
	if event is InputEventKey and event.pressed and not event.echo and _physical(event) == KEY_QUOTELEFT:
		_toggle_console()
		get_viewport().set_input_as_handled()
		return
	if _console.visible:
		return
	if event.is_action_pressed(&"toggle_camera") and Net.active:
		_world.toggle_camera_mode()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"ui_cancel"):
		_toggle_mouse()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		if _physical(event) == KEY_F10:
			if Net.active:
				Net.leave()
			get_viewport().set_input_as_handled()
		elif _physical(event) == KEY_F9:
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

	if args.has("--playerprobe"):
		var probe: Node = preload("res://tools/player_probe.gd").new()
		add_child(probe)
		probe.start(_world)
		needs_session = true

	for arg in args:
		if arg.begins_with("--faction="):
			var wanted := int(arg.substr("--faction=".length()))
			_faction_opt.select(clampi(wanted, 0, FACTIONS.COUNT - 1))
			Net.chosen_faction = _faction_opt.selected

	if args.has("--labtest"):
		var lab_test: Node = preload("res://tools/labourer_test.gd").new()
		add_child(lab_test)
		lab_test.start(_world)
		needs_session = true

	if args.has("--navtest"):
		var nav_test: Node = preload("res://tools/nav_test.gd").new()
		add_child(nav_test)
		nav_test.start(_world)
		needs_session = true

	if args.has("--soaktest"):
		var soak_test: Node = preload("res://tools/soak_test.gd").new()
		add_child(soak_test)
		soak_test.start(_world)
		needs_session = true

	if args.has("--warbandtest"):
		var warband_test: Node = preload("res://tools/warband_test.gd").new()
		add_child(warband_test)
		warband_test.start(_world)
		needs_session = true

	if args.has("--garrisontest"):
		var garrison_test: Node = preload("res://tools/garrison_test.gd").new()
		add_child(garrison_test)
		garrison_test.start(_world)
		needs_session = true

	if args.has("--savetest"):
		var save_test: Node = preload("res://tools/save_test.gd").new()
		add_child(save_test)
		save_test.start(_world)
		needs_session = true

	if args.has("--diptest"):
		var dip_test: Node = preload("res://tools/diplomacy_test.gd").new()
		add_child(dip_test)
		dip_test.start(_world)
		needs_session = true

	if args.has("--victorytest"):
		var victory_test: Node = preload("res://tools/victory_test.gd").new()
		add_child(victory_test)
		victory_test.start(_world)
		needs_session = true

	if args.has("--deathtest"):
		var death_test: Node = preload("res://tools/death_test.gd").new()
		add_child(death_test)
		death_test.start(_world)
		needs_session = true

	if args.has("--guardtest"):
		var guard_test: Node = preload("res://tools/guard_test.gd").new()
		add_child(guard_test)
		guard_test.start(_world)
		needs_session = true

	if args.has("--tradetest"):
		var trade_test: Node = preload("res://tools/trade_test.gd").new()
		add_child(trade_test)
		trade_test.start(_world)
		needs_session = true

	if args.has("--elftest"):
		var elf_test: Node = preload("res://tools/elf_test.gd").new()
		add_child(elf_test)
		elf_test.start(_world)
		needs_session = true

	if args.has("--foresttest"):
		var forest_test: Node = preload("res://tools/forest_test.gd").new()
		add_child(forest_test)
		forest_test.start(_world)
		needs_session = true

	if args.has("--consoletest"):
		var console: Node = preload("res://tools/console_test.gd").new()
		add_child(console)
		console.start(_world)
		needs_session = true

	if args.has("--slicetest"):
		var slice: Node = preload("res://tools/slice_test.gd").new()
		add_child(slice)
		slice.start(_world)
		needs_session = true

	if args.has("--squadtest"):
		var squad: Node = preload("res://tools/squad_test.gd").new()
		add_child(squad)
		squad.start(_world)
		needs_session = true

	if args.has("--caravantest"):
		var caravan: Node = preload("res://tools/caravan_test.gd").new()
		add_child(caravan)
		caravan.start(_world)
		needs_session = true

	if args.has("--econtest"):
		var econ: Node = preload("res://tools/economy_test.gd").new()
		add_child(econ)
		econ.start(_world)
		needs_session = true

	if args.has("--woundtest"):
		var wounds: Node = preload("res://tools/wound_test.gd").new()
		add_child(wounds)
		wounds.start(_world)
		needs_session = true

	if args.has("--combattest"):
		var fighter: Node = preload("res://tools/combat_test.gd").new()
		add_child(fighter)
		fighter.start(_world)

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


## Слепота от потери глаза: GDD раздел 4 — «слепота на половину экрана».
## Один глаз закрывает половину, два — весь экран.
func _update_blindness() -> void:
	var me: Node3D = _world.local_player() if Net.active else null
	var lost := 0
	if me != null:
		lost = int(me.body.eyes_lost)
	_blind_right.visible = lost >= 1
	_blind_left.visible = lost >= 2


# --- верстак: протезы и коляска -------------------------------------------

func _toggle_bench() -> void:
	if _bench.visible:
		_close_bench()
		return
	var me: Node3D = _world.local_player()
	if me == null:
		return
	# Панель открывается ГДЕ УГОДНО: деревянный протез крафтится в поле, и без
	# этого раненому пришлось бы ползти через полкарты к верстаку.
	# Кованый и мастерский по-прежнему только у верстака.
	var at_bench: bool = me.at_workbench()
	_bench.visible = true
	_bench_chair.text = "Встать из коляски" if me.body.in_wheelchair else "Сесть в коляску"
	_bench_chair.disabled = not at_bench
	var box := $UI/Bench/Panel/VBox
	box.get_node("Title").text = "Верстак и медпункт" if at_bench else "Полевой ремонт"
	box.get_node("Note").text = ("Протезы ставятся на все оторванные конечности сразу, цена — за комплект."
		if at_bench else
		"В поле можно скрафтить только деревянный протез. Кованый и мастерский — у верстака.")
	for tier in [1, 2, 3]:
		var names := {1: "Wooden", 2: "Iron", 3: "Master"}
		var titles := {1: "Деревянный (скрафтить)", 2: "Кованый", 3: "Мастерский"}
		var btn: Button = box.get_node(names[tier])
		var cost: Array = RES.PROSTHETIC_COST[tier]
		btn.text = "%s — %s" % [titles[tier], RES.format_cost(cost)]
		btn.disabled = not me.stock.can_afford(cost) or (tier > 1 and not at_bench)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_bench() -> void:
	_bench.visible = false
	if Net.active and not _world.strategy_mode:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_bench_prosthetic(tier: int) -> void:
	var me: Node3D = _world.local_player()
	if me != null:
		me.ask_prosthetic(tier)
	_close_bench()


func _on_bench_chair() -> void:
	var me: Node3D = _world.local_player()
	if me != null:
		me.ask_wheelchair(not me.body.in_wheelchair)
	_close_bench()


## Подсказка по стройке в стратегическом режиме: что выбрано и почём.
func _build_hint() -> String:
	var controller: Node3D = _world.build_controller
	var parts := PackedStringArray()
	for i in RES.BUILDING_NAMES.size():
		parts.append("%d — %s (%s)" % [
			i + 1, RES.BUILDING_NAMES[i], RES.format_cost(RES.BUILDING_COST[i])
		])
	var route: Node3D = _world.route_controller
	if route.active:
		return "МАРШРУТ: ЛКМ — точка (%d), Enter ИЛИ двойной ЛКМ — отправить караван, ПКМ — отмена" % route.points().size()
	if controller.active:
		return "СТРОЙКА: %s — ЛКМ поставить, ПКМ отменить" % RES.BUILDING_NAMES[controller.kind]
	var line := "стройка: " + "   ".join(parts)
	line += "   |   C — маршрут каравана   |   шахта: %s" % _world.mine.summary()
	# Железо в мире добывается ТОЛЬКО шахтой и попадает на склад ТОЛЬКО
	# караваном. Живой тестер этого не нашёл, упёрся в казарму и бросил
	# сессию — поэтому пишем прямо, пока железа нет.
	var boss: Node3D = _world.local_player()
	if boss != null and boss.stock.get_amount(RES.Kind.IRON) <= 0:
		line += "\nЖЕЛЕЗО берётся только из шахты: построй склад (1), нажми C, отметь маршрут до шахты и отправь караван"

	var mine_caravans: Array = []
	var me: Node3D = _world.local_player()
	if me != null:
		mine_caravans = _world.caravans_of(me.peer_id)
	for caravan in mine_caravans:
		line += "
караван: %s, здоровье %d" % [caravan.state_text(), int(caravan.health)]
	return line


## Кто чем занят у злодея. Без этой строки батраки — невидимая механика: они
## работают где-то на карте, а игрок видит только, что ресурсы прибывают.
func _crew_hint() -> String:
	var me: Node3D = _world.local_player()
	if me == null or not FACTIONS.can_build(me.faction):
		return ""
	var crew: Array = _world.labourers_of(int(me.faction))
	var counts := PackedInt32Array()
	counts.resize(LABOURER.ROLE_COUNT)
	var carrying := 0
	for worker in crew:
		counts[int(worker.sync_role)] += 1
		carrying += int(worker.carrying())

	var parts := PackedStringArray()
	for role in LABOURER.ROLE_COUNT:
		parts.append("%d %s (%d)" % [role + 4, LABOURER.ROLE_NAMES[role], counts[role]])
	var line := "батраки %d/%d: " % [crew.size(), RES.LABOURER_LIMIT] + "   ".join(parts)
	line += "   |   B — нанять (%s)" % RES.format_cost(RES.LABOURER_COST)
	if carrying > 0:
		line += "   несут: %d" % carrying
	return line


# --- приказы отряду --------------------------------------------------------

func _squad_order(what: String, value: int) -> void:
	var me: Node3D = _world.local_player()
	if me == null:
		return
	match what:
		"formation":
			me.ask_formation(value)
		"follow":
			me.ask_squad_follow()
		"train":
			me.ask_train_unit()


## ПКМ в стратегической камере, когда не идёт стройка и не рисуется маршрут —
## это приказ отряду идти в точку.
func _try_squad_move_order() -> bool:
	if not (Net.active and _world.strategy_mode):
		return false
	if _world.build_controller.active or _world.route_controller.active:
		return false
	var me: Node3D = _world.local_player()
	if me == null:
		return false
	var hit := BUILD_CONTROLLER.pick_ground(_world)
	if hit.is_empty():
		return false
	me.ask_squad_move(hit["position"])
	return true


func _squad_hint() -> String:
	var me: Node3D = _world.local_player()
	if me == null:
		return ""
	var squad: Array = _world.units_of(me.peer_id)
	var stance := "держит позицию" if me.squad_hold else "следует за командиром"
	return "отряд: %d/%d, %s, %s   |   F1-F4 строй, G следовать, ПКМ идти в точку, T нанять (%s)" % [
		squad.size(), RES.SQUAD_LIMIT, stance,
		FORMATIONS.describe(me.squad_formation), RES.format_cost(RES.UNIT_COST)
	]


## Чем заняты стороны, за которые никто не сел. Мир теперь воюет сам, и игрок
## должен видеть, что кроме него в партии кто-то есть. Строка появляется только
## когда свободные стороны действительно есть — втроём её не будет вовсе.
func _ai_hint() -> String:
	var parts := PackedStringArray()
	for faction in FACTIONS.COUNT:
		if not _world.players_of(faction).is_empty():
			continue
		if _world.garrison.size_of(faction) <= 0:
			continue
		parts.append("%s — %s (%d)" % [
			FACTIONS.name_of(faction),
			WARBAND.STATE_NAMES[_world.warband.state_of(faction)],
			_world.garrison.size_of(faction),
		])
	if parts.is_empty():
		return ""
	return "\nбез игроков: " + "   ".join(parts)


# --- результат партии ------------------------------------------------------

var _announce_left := 0.0


func _on_announced(text: String) -> void:
	_announce.text = text
	_announce_left = ANNOUNCE_SECONDS
	print("[цель] ", text)


func _tick_announce(delta: float) -> void:
	if _announce_left <= 0.0:
		return
	_announce_left -= delta
	if _announce_left <= 0.0:
		_announce.text = ""


## Строка цели и состояния дворца для HUD.
func _objective_hint(me: Node3D) -> String:
	var line: String = _world.objective.status_text()
	if me != null:
		line = "сторона: %s   цель: %s\n%s" % [
			FACTIONS.name_of(me.faction), FACTIONS.goal_of(me.faction), line
		]
	return line


# --- видимые отказы --------------------------------------------------------
#
# Хост отклоняет заявку и присылает причину (см. player.gd::_refuse). Раньше
# причина уходила только в лог: тестер жал «нанять», ничего не происходило, и
# он делал вывод, что игра сломана. Держим последнюю причину на экране
# несколько секунд — этого хватает, чтобы связать нажатие с отказом.

## Сколько секунд причина висит на экране.
const REFUSAL_SHOWN := 5.0

var _refusal := ""
var _refusal_left := 0.0
## Персонаж, чьи отказы сейчас слушаем. Пересоединяем при респавне.
var _refusal_player: Node3D = null


func _tick_refusal(delta: float) -> void:
	var me: Node3D = _world.local_player() if Net.active else null
	if _refusal_player != me:
		if _refusal_player != null and is_instance_valid(_refusal_player):
			_refusal_player.refused.disconnect(_on_refused)
		_refusal_player = me
		if me != null:
			me.refused.connect(_on_refused)
	if _refusal_left <= 0.0:
		return
	_refusal_left -= delta
	if _refusal_left <= 0.0:
		_refusal = ""


func _on_refused(reason: String) -> void:
	_refusal = reason
	_refusal_left = REFUSAL_SHOWN


func _refusal_line() -> String:
	if _refusal.is_empty():
		return ""
	return "\n>>> " + _refusal


# --- консоль для playtest -------------------------------------------------

## Персонаж, чьи ответы сейчас слушаем. Пересоединяем при респавне.
var _console_player: Node3D = null


func _toggle_console() -> void:
	if not OS.is_debug_build():
		return
	_console.visible = not _console.visible
	if _console.visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_console_in.grab_focus()
	elif Net.active and not _world.strategy_mode:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _console_print(text: String) -> void:
	if text.is_empty():
		return
	_console_out.text += "\n" + text


func _on_console_submitted(line: String) -> void:
	_console_in.clear()
	if line.strip_edges().is_empty():
		return
	_console_print("> " + line)
	var me: Node3D = _world.local_player()
	if me == null:
		_console_print("персонажа нет — сначала войди в сессию")
		return
	# Ответ приходит асинхронно: команду исполняет хост.
	if _console_player != me:
		if _console_player != null and is_instance_valid(_console_player):
			_console_player.cheat_reply.disconnect(_console_print)
		_console_player = me
		me.cheat_reply.connect(_console_print)
	me.ask_cheat(line)


## Строка способностей друида: что готово, что на откате, сколько держится клич.
## Показываем только тем сторонам, у которых магия поддержки есть (эльфы).
func _abilities_hint(me: Node3D) -> String:
	var parts := PackedStringArray()
	for kind in ABILITIES.COUNT:
		if not FACTIONS.allows_ability(me.faction, kind):
			continue
		var left: float = me.sync_ability_cd[kind]
		if left > 0.0:
			parts.append("%d %s (%.0f с)" % [kind + 4, ABILITIES.name_of(kind), ceil(left)])
		else:
			parts.append("%d %s" % [kind + 4, ABILITIES.name_of(kind)])
	var line := "магия: " + "   ".join(parts)
	if me.sync_buff_left > 0.0:
		line += "   клич действует ещё %.0f с" % ceil(me.sync_buff_left)
	return line


# --- лавка торговца (Этап 8) ----------------------------------------------

func _toggle_trader() -> void:
	if _trader.visible:
		_close_trader()
		return
	var me: Node3D = _world.local_player()
	if me == null or not me.at_trader():
		return
	_refresh_trader(me)
	_trader.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _refresh_trader(me: Node3D) -> void:
	var box := $UI/Trader/Panel/VBox
	# Отношение к хозяевам лавки показываем прямо здесь: от него зависят и цены,
	# и то, обслужат ли вообще (GDD раздел 9.2).
	box.get_node("Stock").text = "склад: %s\nснаряжение: %s   лавка эльфов, отношение: %s" % [
		me.stock.summary(), WEAPONS.gear_name(me.gear_tier),
		_world.diplomacy.label_of(me.faction, me.trader_faction())
	]

	var bandages: Button = box.get_node("Bandages")
	var allowed: bool = me.trade_allowed()
	if not allowed:
		bandages.text = "Лавка не обслуживает: война"
		bandages.disabled = true
	elif me.body.bandages >= RES.BANDAGE_LIMIT:
		bandages.text = "Бинты — сумка полна (%d)" % RES.BANDAGE_LIMIT
		bandages.disabled = true
	else:
		var cost_b: Array = me.bandage_cost()
		bandages.text = "Бинты, %d шт — %s" % [RES.BANDAGE_PACK, RES.format_cost(cost_b)]
		bandages.disabled = not me.stock.can_afford(cost_b)

	var gear: Button = box.get_node("Gear")
	var cost: Array = me.next_gear_cost()
	if not allowed:
		gear.text = "Лавка не обслуживает: война"
		gear.disabled = true
	elif cost.is_empty():
		gear.text = "Снаряжение — лучше нет"
		gear.disabled = true
	else:
		gear.text = "Снаряжение: %s — %s" % [
			WEAPONS.gear_name(me.gear_tier + 1), RES.format_cost(cost)
		]
		gear.disabled = not me.stock.can_afford(cost)


func _close_trader() -> void:
	_trader.visible = false
	if Net.active and not _world.strategy_mode:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Покупку исполняет хост, поэтому панель обновляем не сразу, а следующим
## кадром: иначе она показала бы старые цифры.
func _on_trade(what: int) -> void:
	var me: Node3D = _world.local_player()
	if me == null:
		return
	me.ask_trade(what)
	await get_tree().create_timer(0.25).timeout
	if _trader.visible and is_instance_valid(me):
		_refresh_trader(me)


# --- командир стражи (Этап 9) ---------------------------------------------

func _toggle_commander() -> void:
	if _commander_ui.visible:
		_close_commander()
		return
	var me: Node3D = _world.local_player()
	if me == null or not me.at_commander():
		return
	_refresh_commander(me)
	_commander_ui.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _refresh_commander(me: Node3D) -> void:
	var box := $UI/Commander/Panel/VBox
	var order: Label = box.get_node("Order")
	var progress: Label = box.get_node("Progress")
	var reward: Label = box.get_node("Reward")
	var report: Button = box.get_node("Report")
	var promote: Button = box.get_node("Promote")
	promote.disabled = not _world.commander.can_promote(me)
	if not promote.disabled:
		promote.text = "Принять командование"
	elif not _world.commander.on_duty():
		promote.text = "Распорядитель пал"
	elif me.is_leader:
		promote.text = "Ты уже командир"
	else:
		promote.text = "Командование занято"

	if int(me.faction) != FACTIONS.Kind.GUARD:
		order.text = "Командир говорит только со стражей дворца."
		progress.text = ""
		reward.text = ""
		report.disabled = true
		return

	report.disabled = false
	if me.order_kind < 0:
		order.text = "Приказа нет. Доложись, и командир его отдаст."
		progress.text = "выполнено приказов: %d" % me.orders_done
		reward.text = ""
		report.text = "Получить приказ"
		return

	order.text = "Приказ: %s\n%s" % [
		ORDERS.name_of(me.order_kind), ORDERS.brief_of(me.order_kind)
	]
	progress.text = "прогресс: %s   выполнено приказов: %d" % [
		ORDERS.progress_text(me.order_kind, me.order_progress), me.orders_done
	]
	reward.text = "награда: %s" % RES.format_cost(ORDERS.reward_of(me.order_kind))
	var ready_now: bool = me.order_progress >= ORDERS.target_of(me.order_kind)
	report.text = "Доложить о выполнении" if ready_now else "Доложить (ещё не готово)"


func _close_commander() -> void:
	_commander_ui.visible = false
	if Net.active and not _world.strategy_mode:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Доклад исполняет хост, поэтому панель перечитываем следующим кадром.
func _on_report() -> void:
	var me: Node3D = _world.local_player()
	if me == null:
		return
	me.ask_report()
	await get_tree().create_timer(0.25).timeout
	if _commander_ui.visible and is_instance_valid(me):
		_refresh_commander(me)


## Короткая строка про текущий приказ — для подсказки у командира и в HUD.
func _order_hint(me: Node3D) -> String:
	if not _world.commander.on_duty():
		return "распорядитель пал, вернётся через %d с" % int(ceil(_world.commander.respawn_left()))
	if int(me.faction) != FACTIONS.Kind.GUARD:
		return "распорядитель стражи говорит только со стражей — но убить его можно, если хватит сил"
	if me.order_kind < 0:
		return "получить приказ"
	return "%s (%s)" % [
		ORDERS.name_of(me.order_kind),
		ORDERS.progress_text(me.order_kind, me.order_progress),
	]


## Принять командование стражей. Решает хост, панель перечитываем следующим
## кадром — как и доклад.
func _on_promote() -> void:
	var me: Node3D = _world.local_player()
	if me == null:
		return
	me.ask_promotion()
	await get_tree().create_timer(0.25).timeout
	if _commander_ui.visible and is_instance_valid(me):
		_refresh_commander(me)


## Физическая клавиша, а не символ на ней. keycode зависит от раскладки: на
## русской раскладке сравнение с KEY_C или KEY_T не сработает никогда, и всё
## управление в стратегическом режиме отвалится молча.
##
## Отступаем к keycode только там, где физического кода нет вовсе — так бывает
## у экранных клавиатур и некоторых эмуляторов ввода.
func _physical(event: InputEventKey) -> int:
	return event.physical_keycode if event.physical_keycode != 0 else event.keycode
