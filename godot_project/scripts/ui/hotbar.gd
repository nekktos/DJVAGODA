extends PanelContainer
##
## Боевая полоса: оружие, заклинания, стрелы и бинты — картинками с клавишами.
## Низ экрана по центру, только в бою.
##
## ЗАЧЕМ. До неё всё это было двумя строками: «меч · стрел 30 · бинтов 3 · опыт
## 0» под здоровьем и «4 паралич воли  5 проклятие увядания  6 слепящее
## проклятие» ниже. Откат заклинания читался числом в скобках, и понять, готово
## ли оно, можно было только прочитав строку до конца. Решение автора от
## 28.09.2026: «всё не текстом, а картинками».
##
## ОТКАТ — ЗАТЕМНЕНИЕМ, которое сходит сверху вниз, и секундами поверх: как в
## любой игре, где заклинания висят на полосе. Нехватка маны — синей рамкой,
## чтобы «ещё не остыло» и «не на что» отличались с одного взгляда.
##

const STYLE := preload("res://scripts/ui/style.gd")
const KEYMAP := preload("res://scripts/ui/keymap.gd")
const FACTIONS := preload("res://scripts/factions.gd")
const WEAPONS := preload("res://scripts/combat/weapons.gd")
const ABILITIES := preload("res://scripts/combat/abilities.gd")

const SLOT := 58.0
const MANA_BLUE := Color(0.35, 0.55, 1.0)

var _world: Node3D
var _icons: Node
var _weapons := []
var _abilities := []
var _arrows: Label
var _bandages: Label
var _potion_heal: Control
var _potion_mana: Control
var _faction := -1


func setup(world: Node3D, icons: Node) -> void:
	_world = world
	_icons = icons
	var style := StyleBoxTexture.new()
	style.texture = STYLE.PANEL_TEX
	style.set_texture_margin_all(12.0)
	style.modulate_color = STYLE.PANEL_TINT
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 7.0
	style.content_margin_bottom = 7.0
	add_theme_stylebox_override("panel", style)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icons.changed.connect(func() -> void: _faction = -1)


## Собрать слоты под сторону. Набор оружия и заклинаний у сторон разный, и
## при смене стороны (новая партия) полоса пересобирается.
func _rebuild(me: Node3D) -> void:
	for child in get_children():
		child.queue_free()
	_weapons.clear()
	_abilities.clear()
	_faction = int(me.faction)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	for slot in 4:
		var kind: int = FACTIONS.weapon_on_slot(_faction, slot)
		if kind < 0:
			continue
		var cell := _cell("wpn_%d" % kind, StringName("weapon_%d" % (slot + 1)))
		cell.name = "Weapon%d" % slot
		cell.set_meta("kind", kind)
		cell.tooltip_text = WEAPONS.NAMES[kind]
		row.add_child(cell)
		_weapons.append(cell)
	var any_magic := false
	for slot in 3:
		var kind: int = FACTIONS.ability_on_slot(_faction, slot)
		if kind < 0:
			continue
		if not any_magic:
			row.add_child(VSeparator.new())
			any_magic = true
		var cell := _cell("abl_%d" % kind, StringName("ability_%d" % (slot + 1)))
		cell.name = "Ability%d" % slot
		cell.set_meta("kind", kind)
		cell.tooltip_text = "%s — %d маны, откат %d с" % [
			ABILITIES.name_of(kind), int(ABILITIES.mana_cost(kind)), int(ABILITIES.cooldown_of(kind))]
		# Затемнение отката: растёт сверху, уходит вниз по мере готовности.
		var shade := ColorRect.new()
		shade.name = "Shade"
		shade.color = Color(0.0, 0.0, 0.0, 0.65)
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(shade)
		var seconds := STYLE.label("", 16, STYLE.TEXT_MAIN)
		seconds.name = "Seconds"
		seconds.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		seconds.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		seconds.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		seconds.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(seconds)
		row.add_child(cell)
		_abilities.append(cell)
	row.add_child(VSeparator.new())
	var arrows := _counter("arrows")
	arrows.name = "Arrows"
	arrows.tooltip_text = "Стрелы. Кончаются; докупаются в лавке."
	_arrows = arrows.get_child(1)
	row.add_child(arrows)
	var bandages := _counter("bandage")
	bandages.name = "Bandages"
	bandages.tooltip_text = "%s: держи %s, стоя на месте, чтобы перевязаться." % [
		"Травы" if _faction == FACTIONS.Kind.ELVES else "Бинты", KEYMAP.key_text(&"bandage")]
	_bandages = bandages.get_child(1)
	row.add_child(bandages)
	# Зелья — только у эльфов: только их лавка их продаёт (GDD 9a).
	if _faction == FACTIONS.Kind.ELVES:
		_potion_heal = _counter("potion_heal")
		_potion_heal.name = "PotionHeal"
		_potion_heal.tooltip_text = "Зелье лечения: %s — выпить" % KEYMAP.key_text(&"potion_heal")
		row.add_child(_potion_heal)
		_potion_mana = _counter("potion_mana")
		_potion_mana.name = "PotionMana"
		_potion_mana.tooltip_text = "Зелье маны: %s — выпить" % KEYMAP.key_text(&"potion_mana")
		row.add_child(_potion_mana)
	else:
		_potion_heal = null
		_potion_mana = null


## Ячейка: картинка во всю ячейку, клавиша в углу.
func _cell(icon_key: String, action: StringName) -> Panel:
	var cell := Panel.new()
	cell.custom_minimum_size = Vector2(SLOT, SLOT)
	cell.mouse_filter = Control.MOUSE_FILTER_PASS
	cell.add_theme_stylebox_override("panel", STYLE.flat(STYLE.CARD_BG, 6, Color(0, 0, 0, 0), 0.0))
	var picture := TextureRect.new()
	picture.name = "Picture"
	picture.texture = _icons.icon(icon_key)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 3)
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(picture)
	var cap := STYLE.keycap(KEYMAP.key_text(action), 11)
	cap.name = "Key"
	cell.add_child(cap)
	cell.set_meta("action", action)
	return cell


func _counter(icon_key: String) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_theme_constant_override("separation", 2)
	var picture := TextureRect.new()
	picture.texture = _icons.icon(icon_key)
	picture.custom_minimum_size = Vector2(34.0, 34.0)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(picture)
	var number := STYLE.label("0", 18)
	number.custom_minimum_size = Vector2(30.0, 0.0)
	number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	number.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(number)
	return box


## Раз в кадр.
func refresh() -> void:
	var me: Node3D = _world.local_player()
	var show: bool = (me != null and not _world.strategy_mode and me.health.alive
		and not _world.is_spectating())
	visible = show
	if not show:
		return
	if int(me.faction) != _faction:
		_rebuild(me)
	for cell in _weapons + _abilities:
		var cap: Label = cell.get_node("Key").get_child(0)
		cap.text = KEYMAP.key_text(cell.get_meta("action"))
	for cell in _weapons:
		var chosen: bool = int(me.sync_weapon) == int(cell.get_meta("kind"))
		cell.add_theme_stylebox_override("panel", STYLE.flat(STYLE.CARD_BG, 6,
			STYLE.ACCENT if chosen else Color(0, 0, 0, 0), 0.0))
	for cell in _abilities:
		var kind: int = cell.get_meta("kind")
		var left: float = float(me.sync_ability_cd[kind]) if kind < me.sync_ability_cd.size() else 0.0
		var full: float = maxf(0.01, ABILITIES.cooldown_of(kind))
		var shade: ColorRect = cell.get_node("Shade")
		shade.visible = left > 0.0
		shade.position = Vector2.ZERO
		shade.size = Vector2(SLOT, SLOT * clampf(left / full, 0.0, 1.0))
		(cell.get_node("Seconds") as Label).text = str(int(ceil(left))) if left > 0.0 else ""
		var broke: bool = float(me.mana) < ABILITIES.mana_cost(kind)
		cell.add_theme_stylebox_override("panel", STYLE.flat(STYLE.CARD_BG, 6,
			MANA_BLUE if broke else Color(0, 0, 0, 0), 0.0))
		cell.set_meta("broke", broke)
	_arrows.text = str(int(me.arrows))
	_arrows.add_theme_color_override("font_color", STYLE.DANGER if int(me.arrows) <= 0 else STYLE.TEXT_MAIN)
	if _potion_heal != null:
		(_potion_heal.get_child(1) as Label).text = str(int(me.potions_heal))
		(_potion_mana.get_child(1) as Label).text = str(int(me.potions_mana))
	_bandages.text = str(int(me.body.bandages))
	_bandages.add_theme_color_override("font_color", STYLE.DANGER if int(me.body.bandages) <= 0 else STYLE.TEXT_MAIN)
