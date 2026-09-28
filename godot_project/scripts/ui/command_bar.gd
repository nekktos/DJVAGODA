extends VBoxContainer
##
## Панель команд вида сверху: стройка, батраки, обоз и отряд — карточками с
## картинками, по которым щёлкают.
##
## ЗАЧЕМ. Решение автора от 28.09.2026: «меню стройки надо» и «HUD, чтоб всё
## было не текстом, а интерактивными менюшками с картинками». До этого стройка
## жила в строке подсказки «1 — склад (дер 40, кам 20)   2 — казарма мечников
## (...)» длиной в экран, а роли батраков — цифрами, которые приходилось
## запоминать.
##
## КЛАВИШИ ОСТАЮТСЯ. Карточка — второй путь к тому же действию, а не замена:
## в углу каждой карточки нарисована её клавиша, взятая из раскладки, и кто
## привык к клавишам, продолжает жать их.
##
## Карточка, на которую не хватает, не прячется, а тускнеет, и её цена
## показывает, чего именно недостаёт — красным. Спрятанная постройка не
## объясняет, почему её нет.
##

const STYLE := preload("res://scripts/ui/style.gd")
const RES := preload("res://scripts/economy/resources.gd")
const KEYMAP := preload("res://scripts/ui/keymap.gd")
const FACTIONS := preload("res://scripts/factions.gd")
const LABOURER := preload("res://scripts/units/labourer.gd")

## Что строится с какой клавиши. Совпадает с `main.gd::BUILD_ACTIONS`.
const BUILD := [
	[&"build_storage", RES.Building.STORAGE],
	[&"build_sword", RES.Building.SWORD_BARRACKS],
	[&"build_archer", RES.Building.ARCHER_BARRACKS],
	[&"build_stable", RES.Building.STABLE],
	[&"build_house", RES.Building.HOUSE],
	[&"build_farm", RES.Building.FARM],
]
const ROLES := [
	[&"role_lumberjack", LABOURER.Role.LUMBERJACK],
	[&"role_miner", LABOURER.Role.MINER],
	[&"role_militia", LABOURER.Role.MILITIA],
	[&"role_builder", LABOURER.Role.BUILDER],
	[&"role_farmer", LABOURER.Role.FARMER],
]

## Подпись на карточке. Короче полного названия: «казарма мечников» в карточку
## шириной в картинку не влезала и обрезалась на полуслове. Полное — в
## подсказке.
const BUILD_CAPTIONS := ["склад", "мечники", "лучники", "конюшня", "дом", "поле"]

## Что делает каждая постройка — во всплывающей подсказке карточки.
const BUILD_NOTES := [
	"Хранит добычу: сложенное в склад не теряется со смертью. Сюда возвращаются обозы.",
	"Здесь нанимают мечников.",
	"Здесь нанимают лучников.",
	"Здесь покупают лошадей: без лошади обоз не выедет.",
	"Поднимает потолок отряда: без домов держишь только охрану.",
	"Растит еду сама; фермер уносит её на склад. Батраки едят.",
]
const ROLE_NOTES := [
	"Рубит лес и носит дерево на склад.",
	"Бьёт камень и руду в залежах. Руду из шахт эльфов возит только обоз.",
	"Дерётся, если к нему подошли враги.",
	"Помогает строить: стройка идёт быстрее.",
	"Уносит урожай с полей на склад.",
]

var _world: Node3D
var _icons: Node
var _build_cards := {}
var _role_cards := {}
var _hire: Button
var _route: Button
var _follow: Button
var _escort: Button
var _build_row: HBoxContainer
var _crew_row: HBoxContainer
## Какую цену сейчас показать красным в полосе запасов: карточка под мышью.
var hovered_cost: Array = []


func setup(world: Node3D, icons: Node) -> void:
	_world = world
	_icons = icons
	add_theme_constant_override("separation", 6)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_build_row = _row("Стройка")
	for pair in BUILD:
		var kind: int = pair[1]
		var card := _card("bld_%d" % kind, BUILD_CAPTIONS[kind], pair[0], 64.0)
		# Шире картинки: у казарм цена в три ресурса, и в карточку по ширине
		# картинки последнее число не влезало — как раз железо, которого и
		# не хватает чаще всего.
		card.custom_minimum_size.x = 112.0
		card.name = "Build%d" % kind
		card.tooltip_text = "%s — %s" % [RES.BUILDING_NAMES[kind].capitalize(), BUILD_NOTES[kind]]
		card.pressed.connect(_on_build.bind(kind))
		card.mouse_entered.connect(func() -> void: hovered_cost = RES.BUILDING_COST[kind])
		card.mouse_exited.connect(func() -> void: hovered_cost = [])
		card.get_meta("box").add_child(_cost_row(RES.BUILDING_COST[kind]))
		_build_row.add_child(card)
		_build_cards[kind] = card

	_crew_row = _row("Батраки")
	_hire = _card("labourer", "нанять", &"hire_labourer", 48.0)
	_hire.name = "Hire"
	_hire.tooltip_text = "Нанять батрака. Встаёт у склада и берётся за работу."
	_hire.pressed.connect(_on_hire)
	_hire.mouse_entered.connect(func() -> void: hovered_cost = RES.LABOURER_COST)
	_hire.mouse_exited.connect(func() -> void: hovered_cost = [])
	_hire.get_meta("box").add_child(_cost_row(RES.LABOURER_COST))
	_crew_row.add_child(_hire)
	_crew_row.add_child(VSeparator.new())
	for pair in ROLES:
		var role: int = pair[1]
		var card := _card("role_%d" % role, LABOURER.ROLE_NAMES[role], pair[0], 48.0)
		card.name = "Role%d" % role
		card.tooltip_text = "%s — %s\nЩелчок переводит одного батрака на это дело." % [
			LABOURER.ROLE_NAMES[role].capitalize(), ROLE_NOTES[role]]
		card.pressed.connect(_on_role.bind(role))
		var count := STYLE.label("0", 15, STYLE.ACCENT)
		count.name = "Count"
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.get_meta("box").add_child(count)
		_crew_row.add_child(card)
		_role_cards[role] = card
	_crew_row.add_child(VSeparator.new())
	_route = _card("cart", "обоз", &"route", 48.0)
	_route.name = "Route"
	_route.tooltip_text = "Нарисовать маршрут обоза: щелчки по карте, последняя точка — у шахты, Enter — отправить."
	_route.pressed.connect(func() -> void: _world.set_route_mode(not _world.route_controller.active))
	_crew_row.add_child(_route)
	_follow = _card("unit_sword", "ко мне", &"squad_follow", 48.0)
	_follow.name = "Follow"
	_follow.tooltip_text = "Отряд идёт за тобой."
	_follow.pressed.connect(func() -> void: _world.get_parent()._squad_order("follow", 0))
	_crew_row.add_child(_follow)
	_escort = _card("horse", "с обозом", &"squad_escort", 48.0)
	_escort.name = "Escort"
	_escort.tooltip_text = "Отряд идёт охранять обоз."
	_escort.pressed.connect(_on_escort)
	_crew_row.add_child(_escort)
	_icons.changed.connect(_reload_icons)


func _row(title: String) -> HBoxContainer:
	var box := STYLE.panel(10.0)
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add_child(box)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	box.add_child(line)
	var caption := STYLE.label(title, 13, STYLE.TEXT_DIM)
	caption.custom_minimum_size = Vector2(62.0, 0.0)
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(caption)
	return line


## Карточка: картинка, клавиша в углу, подпись. Щелчок — действие.
##
## Карточка — кнопка, а всё внутри неё мышь пропускает: иначе щелчок по
## картинке доставался бы картинке, а не кнопке.
func _card(icon_key: String, caption: String, action: StringName, picture_size: float) -> Button:
	var card := Button.new()
	card.focus_mode = Control.FOCUS_NONE
	card.add_theme_stylebox_override("normal", STYLE.flat(STYLE.CARD_BG, 6, Color(0, 0, 0, 0), 5.0))
	card.add_theme_stylebox_override("hover", STYLE.flat(STYLE.CARD_HOVER, 6, STYLE.ACCENT, 5.0))
	card.add_theme_stylebox_override("pressed", STYLE.flat(STYLE.CARD_HOVER, 6, STYLE.ACCENT, 5.0))
	card.add_theme_stylebox_override("disabled", STYLE.flat(STYLE.CARD_OFF, 6, Color(0, 0, 0, 0), 5.0))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	card.add_child(box)

	var holder := Control.new()
	holder.custom_minimum_size = Vector2(picture_size + 20.0, picture_size)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(holder)
	var picture := TextureRect.new()
	picture.name = "Picture"
	picture.texture = _icons.icon(icon_key)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.set_anchors_preset(Control.PRESET_FULL_RECT)
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(picture)
	var cap := STYLE.keycap(KEYMAP.key_text(action), 12)
	cap.name = "Key"
	cap.position = Vector2(0.0, 0.0)
	holder.add_child(cap)

	var name_label := STYLE.label(caption, 13)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name_label)

	card.set_meta("icon", icon_key)
	card.set_meta("action", action)
	card.set_meta("box", box)
	card.custom_minimum_size = Vector2(picture_size + 26.0, picture_size + 44.0)
	return card


## Цена картинками: иконка ресурса и число. Красным — то, чего не хватает.
func _cost_row(cost: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Cost"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 2)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for kind in RES.COUNT:
		var amount: int = RES.at(cost, kind)
		if amount <= 0:
			continue
		var picture := TextureRect.new()
		picture.name = "Icon%d" % kind
		picture.texture = _icons.icon("res_%d" % kind)
		picture.custom_minimum_size = Vector2(16.0, 16.0)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(picture)
		var number := STYLE.label(str(amount), 12)
		number.name = "Amount%d" % kind
		number.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(number)
	return row


func _reload_icons() -> void:
	for card in _all_cards():
		var picture: TextureRect = card.find_child("Picture", true, false)
		picture.texture = _icons.icon(String(card.get_meta("icon")))
		var cost: Node = card.find_child("Cost", true, false)
		if cost == null:
			continue
		for child in cost.get_children():
			if child is TextureRect:
				child.texture = _icons.icon("res_%s" % String(child.name).trim_prefix("Icon"))


func _all_cards() -> Array:
	var out: Array = _build_cards.values() + _role_cards.values()
	out.append_array([_hire, _route, _follow, _escort])
	return out


## Раз в кадр: что доступно, что выбрано, кто чем занят, какие клавиши.
func refresh() -> void:
	var me: Node3D = _world.local_player()
	var show: bool = me != null and _world.strategy_mode and me.has_strategy()
	visible = show
	if not show:
		hovered_cost = []
		return
	var faction := int(me.faction)
	var builder: bool = me.can_build()
	_build_row.get_parent().visible = builder
	_crew_row.get_parent().visible = true
	for card in _all_cards():
		var cap: Label = card.find_child("Key", true, false).get_child(0)
		cap.text = KEYMAP.key_text(card.get_meta("action"))

	var building: bool = _world.build_controller.active
	for kind in _build_cards:
		var card: Button = _build_cards[kind]
		var cost: Array = RES.BUILDING_COST[kind]
		card.disabled = not me.stock.can_afford(cost)
		_paint_cost(card, cost, me)
		_mark(card, building and int(_world.build_controller.kind) == kind)

	var crew: Array = _world.labourers_of(faction)
	var labourers: bool = FACTIONS.can_build(faction)
	_hire.visible = labourers
	_hire.disabled = not me.stock.can_afford(RES.LABOURER_COST) or crew.size() >= RES.LABOURER_LIMIT
	_paint_cost(_hire, RES.LABOURER_COST, me)
	var counts := {}
	for worker in crew:
		counts[int(worker.sync_role)] = int(counts.get(int(worker.sync_role), 0)) + 1
	for role in _role_cards:
		var card: Button = _role_cards[role]
		card.visible = labourers
		card.disabled = crew.is_empty()
		(card.find_child("Count", true, false) as Label).text = str(int(counts.get(role, 0)))
	_mark(_route, _world.route_controller.active)
	_route.disabled = _world.storage_of(faction) == null
	var squad_empty: bool = _world.units_of(me.peer_id).is_empty()
	_follow.disabled = squad_empty
	_escort.disabled = squad_empty


## Выбранная карточка — в золотой рамке, пока режим включён.
func _mark(card: Button, on: bool) -> void:
	var edge := STYLE.ACCENT if on else Color(0, 0, 0, 0)
	card.add_theme_stylebox_override("normal", STYLE.flat(STYLE.CARD_BG, 6, edge, 5.0))


func _paint_cost(card: Button, cost: Array, me: Node3D) -> void:
	var row: Node = card.find_child("Cost", true, false)
	if row == null:
		return
	for kind in RES.COUNT:
		var number := row.get_node_or_null("Amount%d" % kind) as Label
		if number == null:
			continue
		var enough: bool = int(me.stock.get_amount(kind)) >= RES.at(cost, kind)
		number.add_theme_color_override("font_color", STYLE.TEXT_MAIN if enough else STYLE.DANGER)


func _on_build(kind: int) -> void:
	var same: bool = _world.build_controller.active and int(_world.build_controller.kind) == kind
	# Второй щелчок по выбранной карточке снимает выбор: так же, как ПКМ.
	_world.set_build_mode(not same, kind)


func _on_hire() -> void:
	var me: Node3D = _world.local_player()
	if me != null:
		me.ask_hire_labourer()


func _on_role(role: int) -> void:
	var me: Node3D = _world.local_player()
	if me != null:
		me.ask_set_labourer_role(role)


func _on_escort() -> void:
	var me: Node3D = _world.local_player()
	if me != null:
		me.ask_escort_caravan()
