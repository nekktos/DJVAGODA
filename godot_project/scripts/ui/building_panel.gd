extends Control
##
## Панель постройки: то, чем занимается ИМЕННО ЭТА постройка, и ничего больше.
##
## ЗАЧЕМ. До этого всё управление хозяйством висело на горячих клавишах
## стратегического режима: T — мечник, Y — лучник, N — лошадь, K — упряжка,
## C — маршрут. Запомнить их можно, но узнать неоткуда: список под F1 читают
## один раз, а дальше человек помнит две клавиши из пяти. И главное — казармы
## при этом были не зданиями, а галочкой «построено»: наняв бойца из любой точки
## карты, к казарме можно было не подойти ни разу за партию.
##
## Теперь дело делается ТАМ, где ему место: у казармы мечников нанимают
## мечников, у казармы лучников — лучников, в конюшне берут лошадей, у склада
## снаряжают обоз. Место видно на карте, и к нему надо прийти.
##
## ПАНЕЛЬ СТРОИТСЯ КОДОМ, как и HUD. Содержимое зависит от вида постройки, и
## держать в сцене четыре почти одинаковых заготовки значило бы править каждую
## правку четырежды.
##

const RES := preload("res://scripts/economy/resources.gd")
const CARAVAN := preload("res://scripts/economy/caravan.gd")

## Как часто пересчитываем строки состояния. Каждый кадр незачем: обоз едет
## восемь метров в секунду, и цифра «осталось метров» на глаз не меняется.
const REFRESH_INTERVAL := 0.25

signal route_requested

var _world: Node3D
var _player: Node3D
var _building: Node3D
var _title: Label
var _note: Label
var _rows: VBoxContainer
var _refresh_t := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_build()


func _build() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -240.0
	panel.offset_top = -170.0
	panel.offset_right = 240.0
	panel.offset_bottom = 170.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 22)
	box.add_child(_title)

	_note = Label.new()
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_note)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 6)
	box.add_child(_rows)

	var close := Button.new()
	close.text = "Закрыть (E)"
	close.custom_minimum_size = Vector2(0.0, 40.0)
	close.pressed.connect(close_panel)
	box.add_child(close)


func _process(delta: float) -> void:
	if not visible:
		return
	# Постройку могли снести, пока панель открыта. Держать открытым окно
	# несуществующего дома нельзя: кнопки в нём ведут в никуда.
	if not is_instance_valid(_building) or not is_instance_valid(_player):
		close_panel()
		return
	if _player.building_at_hand(int(_building.kind)) != _building:
		close_panel()
		return
	_refresh_t += delta
	if _refresh_t < REFRESH_INTERVAL:
		return
	_refresh_t = 0.0
	_fill()


## Открыть панель для постройки. Возвращает false, если открывать нечего.
func open_for(world: Node3D, player: Node3D, building: Node3D) -> bool:
	if world == null or player == null or building == null:
		return false
	_world = world
	_player = player
	_building = building
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_refresh_t = 0.0
	_fill()
	return true


func close_panel() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_building = null


func is_open() -> bool:
	return visible


## Заново собрать содержимое под вид постройки.
func _fill() -> void:
	for child in _rows.get_children():
		child.queue_free()
	var kind: int = int(_building.kind)
	_title.text = RES.BUILDING_NAMES[kind]
	match kind:
		RES.Building.SWORD_BARRACKS:
			_fill_barracks(false)
		RES.Building.ARCHER_BARRACKS:
			_fill_barracks(true)
		RES.Building.STABLE:
			_fill_stable()
		RES.Building.STORAGE:
			_fill_storage()
		_:
			_note.text = "Делать тут нечего."


func _fill_barracks(archer: bool) -> void:
	var cost: Array = RES.ARCHER_COST if archer else RES.UNIT_COST
	var squad: Array = _world.units_of(int(_player.peer_id))
	var alive := 0
	for node in squad:
		if is_instance_valid(node) and not bool(node.is_beast):
			alive += 1
	_note.text = "В отряде %d из %d. Отряд идёт за вами и слушает приказы сверху." % [
		alive, RES.SQUAD_LIMIT
	]
	var who := "лучника" if archer else "мечника"
	var hire := _button("Нанять %s — %s" % [who, RES.format_cost(cost)])
	hire.disabled = alive >= RES.SQUAD_LIMIT
	hire.pressed.connect(func() -> void: _player.ask_train_unit(archer))
	_line("В казну: %s" % _purse_text())


func _fill_stable() -> void:
	var wallet: Node = _world.treasury.of(int(_player.faction))
	if wallet == null:
		return
	_note.text = "Лошадей: %d свободно из %d. Больше %d конюшня не держит." % [
		wallet.horses_free(), int(wallet.horses), RES.HORSE_LIMIT
	]
	var buy := _button("Купить лошадь — %s" % RES.format_cost(RES.HORSE_COST))
	buy.disabled = int(wallet.horses) >= RES.HORSE_LIMIT
	buy.pressed.connect(func() -> void: _player.ask_hire_horse())

	_line("В упряжку следующего обоза: %d" % int(_player.harness_size))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_rows.add_child(row)
	for step in [-1, 1]:
		var button := Button.new()
		button.text = "−1 лошадь" if step < 0 else "+1 лошадь"
		button.custom_minimum_size = Vector2(0.0, 36.0)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var next: int = clampi(int(_player.harness_size) + step,
			CARAVAN.HORSES_MIN, CARAVAN.HORSES_MAX)
		button.disabled = next == int(_player.harness_size)
		button.pressed.connect(func() -> void: _player.ask_set_harness(next))
		row.add_child(button)
	_line("В казну: %s" % _purse_text())


func _fill_storage() -> void:
	var wallet: Node = _world.treasury.of(int(_player.faction))
	_note.text = "Отсюда обоз уходит на шахту и сюда же привозит груз."
	if wallet != null:
		_line("В складе: %s" % _stored_text(wallet))
	_line("В упряжку: %d лошадей, свободно %d" % [
		int(_player.harness_size),
		wallet.horses_free() if wallet != null else 0
	])

	var route := _button("Проложить маршрут и отправить обоз")
	route.pressed.connect(func() -> void:
		close_panel()
		route_requested.emit())

	# Состояние обозов В ПУТИ — то, ради чего к складу и приходят. Без этого
	# отправленный обоз пропадал с глаз: жив ли, где он, когда ждать — узнать
	# было неоткуда, кроме как найти его глазами на карте.
	var carts: Array = _world.caravans_of(int(_player.peer_id))
	if carts.is_empty():
		_line("Обозов в пути нет.")
		return
	for node in carts:
		if not is_instance_valid(node):
			continue
		_line(_cart_line(node))


## Строка про один обоз: что делает, сколько осталось и когда придёт.
func _cart_line(cart: Node) -> String:
	var left: float = _path_length(cart.path_ahead())
	var speed: float = float(cart.speed_now())
	var when := "стоит" if speed <= 0.01 else "%d с" % int(round(left / speed))
	return "Обоз: %s, лошадей %d, осталось %d м, придёт через %s" % [
		cart.state_text(), int(cart.horses), int(round(left)), when
	]


static func _path_length(path: PackedVector3Array) -> float:
	var total := 0.0
	for i in range(1, path.size()):
		total += path[i - 1].distance_to(path[i])
	return total


func _purse_text() -> String:
	var parts := PackedStringArray()
	for kind in RES.Kind.values():
		parts.append("%s %d" % [RES.SHORT[kind], _player.stock.get_amount(kind)])
	return " ".join(parts)


func _stored_text(wallet: Node) -> String:
	var parts := PackedStringArray()
	for kind in RES.Kind.values():
		parts.append("%s %d" % [RES.SHORT[kind], wallet.stored.get_amount(kind)])
	return " ".join(parts)


func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0.0, 40.0)
	_rows.add_child(button)
	return button


func _line(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rows.add_child(label)
