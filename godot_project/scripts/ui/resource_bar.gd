extends PanelContainer
##
## Полоса запасов: иконка и число на каждый ресурс, потом лошади, батраки и
## отряд. Правый верх экрана.
##
## ЗАЧЕМ. До неё запасы были строкой «склад: дер 0/40 кам 0/0 зол ...  (при
## себе/в складе, потолок на ресурс 120/0)» в панели хозяйства — её читали, а не
## видели. Решение автора от 28.09.2026: «всё не текстом, а картинками».
##
## Число — ВСЁ, что есть у стороны: при себе и в складе вместе, потому что
## тратится именно это. Разбивка и потолок — во всплывающей подсказке: они нужны
## реже, чем само число.
##
## Недостача подсвечивается сама: когда игрок целится в постройку, которую не
## потянуть, нехватающие ресурсы здесь краснеют (`highlight_shortfall`).
##

const STYLE := preload("res://scripts/ui/style.gd")
const RES := preload("res://scripts/economy/resources.gd")
const FACTIONS := preload("res://scripts/factions.gd")

## Порядок показа: сперва то, из чего строят, потом деньги и железо, еда, уголь.
const ORDER := [RES.Kind.WOOD, RES.Kind.STONE, RES.Kind.GOLD, RES.Kind.IRON,
	RES.Kind.FOOD, RES.Kind.COAL]

var _world: Node3D
var _icons: Node
var _slots := {}
var _horses: Label
var _horse_slot: Control
var _crew: Label
var _crew_slot: Control
var _squad: Label
var _squad_slot: Control
## Какие ресурсы сейчас подсвечены нехваткой.
var _short := PackedInt32Array()


func setup(world: Node3D, icons: Node) -> void:
	_world = world
	_icons = icons
	var style := StyleBoxTexture.new()
	style.texture = STYLE.PANEL_TEX
	style.set_texture_margin_all(12.0)
	style.modulate_color = STYLE.PANEL_TINT
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	add_theme_stylebox_override("panel", style)
	mouse_filter = Control.MOUSE_FILTER_PASS

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	add_child(row)
	for kind in ORDER:
		var slot := _slot(_icons.icon("res_%d" % kind))
		slot.name = "Res%d" % kind
		row.add_child(slot)
		_slots[kind] = slot
	row.add_child(VSeparator.new())
	_horse_slot = _slot(_icons.icon("horse"))
	_horse_slot.name = "Horses"
	_horses = _horse_slot.get_child(1)
	row.add_child(_horse_slot)
	_crew_slot = _slot(_icons.icon("labourer"))
	_crew_slot.name = "Crew"
	_crew = _crew_slot.get_child(1)
	row.add_child(_crew_slot)
	_squad_slot = _slot(_icons.icon("unit_sword"))
	_squad_slot.name = "Squad"
	_squad = _squad_slot.get_child(1)
	row.add_child(_squad_slot)
	_icons.changed.connect(_reload_icons)


## Иконка и число рядом.
func _slot(texture: Texture2D) -> HBoxContainer:
	var slot := HBoxContainer.new()
	slot.add_theme_constant_override("separation", 4)
	slot.mouse_filter = Control.MOUSE_FILTER_PASS
	var picture := TextureRect.new()
	picture.texture = texture
	picture.custom_minimum_size = Vector2(30.0, 30.0)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(picture)
	var number := STYLE.label("0", 17)
	number.custom_minimum_size = Vector2(34.0, 0.0)
	number.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(number)
	return slot


func _reload_icons() -> void:
	for kind in _slots:
		(_slots[kind].get_child(0) as TextureRect).texture = _icons.icon("res_%d" % kind)
	(_horse_slot.get_child(0) as TextureRect).texture = _icons.icon("horse")
	(_crew_slot.get_child(0) as TextureRect).texture = _icons.icon("labourer")
	(_squad_slot.get_child(0) as TextureRect).texture = _icons.icon("unit_sword")


## Подсветить то, чего не хватает на цену. Пустая цена снимает подсветку.
func highlight_shortfall(cost: Array) -> void:
	_short = PackedInt32Array()
	var me: Node3D = _world.local_player() if _world != null else null
	if me == null or cost.is_empty():
		return
	for kind in RES.COUNT:
		if RES.at(cost, kind) > int(me.stock.get_amount(kind)):
			_short.append(kind)


## Обновить числа. Зовёт главный цикл HUD раз в кадр.
func refresh() -> void:
	var me: Node3D = _world.local_player()
	visible = me != null
	if me == null:
		return
	var wallet: Node = me.stock
	for kind in _slots:
		var slot: Control = _slots[kind]
		var number: Label = slot.get_child(1)
		var have: int = int(wallet.get_amount(kind))
		number.text = str(have)
		var short := _short.has(kind)
		number.add_theme_color_override("font_color",
			STYLE.DANGER if short else STYLE.TEXT_MAIN)
		slot.tooltip_text = "%s: %d\nпри себе %d · в складе %d\nпотолок: при себе %d, в складе %d" % [
			RES.NAMES[kind].capitalize(), have,
			int(wallet.carried.get_amount(kind)), int(wallet.stored.get_amount(kind)),
			int(wallet.carried.capacity), int(wallet.stored.capacity)]

	var faction := int(me.faction)
	_horses.text = "%d/%d" % [int(wallet.horses_free()), int(wallet.horses)]
	_horse_slot.tooltip_text = "Лошади: свободных %d из %d\nв упряжках %d" % [
		int(wallet.horses_free()), int(wallet.horses), int(wallet.horses_out)]
	_horse_slot.visible = int(wallet.horses) > 0 or FACTIONS.can_build(faction)

	var crew: int = _world.labourers_of(faction).size()
	_crew.text = "%d/%d" % [crew, RES.LABOURER_LIMIT]
	_crew_slot.tooltip_text = "Батраки: %d из %d" % [crew, RES.LABOURER_LIMIT]
	_crew_slot.visible = FACTIONS.can_build(faction)

	var squad: int = _world.units_of(me.peer_id).size()
	_squad.text = "%d/%d" % [squad, int(_world.squad_capacity(faction))]
	_squad.get_parent().tooltip_text = "Отряд: %d, потолок %d (растёт от домов дружины)" % [
		squad, int(_world.squad_capacity(faction))]
