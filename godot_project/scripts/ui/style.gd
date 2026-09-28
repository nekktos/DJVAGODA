extends RefCounted
##
## Общее оформление меню: панели, кнопки, карточки, цвета.
##
## Одним местом, потому что меню стало много — пауза, клавиши, стройка, батраки,
## лавка, — и каждое, собранное со своими числами, расходилось бы с соседним на
## пиксель и на оттенок. На снимке это читается как «сделано разными людьми».
##
## Рамка — Kenney UI Pack 2.0 (CC0), та же, что у HUD.
##

const PANEL_TEX := preload("res://assets/ui/kenney/button_square_depth_border.png")

const PANEL_TINT := Color(0.10, 0.11, 0.14, 0.90)
const TEXT_DIM := Color(1.0, 1.0, 1.0, 0.55)
const TEXT_MAIN := Color(1.0, 1.0, 1.0, 0.92)
const ACCENT := Color(0.98, 0.78, 0.35)
const DANGER := Color(0.90, 0.28, 0.24)
const GOOD := Color(0.45, 0.90, 0.50)

## Карточка: фон, рамка при наведении, рамка выбранной.
const CARD_BG := Color(0.16, 0.17, 0.21, 0.95)
const CARD_HOVER := Color(0.24, 0.25, 0.31, 0.98)
const CARD_OFF := Color(0.12, 0.12, 0.14, 0.80)


## Панель на рамке Kenney, растянутой девятипатчем.
static func panel(padding := 14.0) -> PanelContainer:
	var box := PanelContainer.new()
	var style := StyleBoxTexture.new()
	style.texture = PANEL_TEX
	style.set_texture_margin_all(12.0)
	style.modulate_color = PANEL_TINT
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding * 0.7
	style.content_margin_bottom = padding * 0.7
	box.add_theme_stylebox_override("panel", style)
	return box


static func label(text: String, size := 15, color := TEXT_MAIN) -> Label:
	var out := Label.new()
	out.text = text
	out.add_theme_font_size_override("font_size", size)
	out.add_theme_color_override("font_color", color)
	return out


## Кнопка меню: тёмная плашка со светлой обводкой при наведении.
static func button(text: String, size := 16) -> Button:
	var out := Button.new()
	out.text = text
	out.add_theme_font_size_override("font_size", size)
	out.focus_mode = Control.FOCUS_NONE
	out.add_theme_stylebox_override("normal", flat(CARD_BG, 6))
	out.add_theme_stylebox_override("hover", flat(CARD_HOVER, 6, ACCENT))
	out.add_theme_stylebox_override("pressed", flat(CARD_HOVER, 6, ACCENT))
	out.add_theme_stylebox_override("disabled", flat(CARD_OFF, 6))
	out.add_theme_color_override("font_color", TEXT_MAIN)
	out.add_theme_color_override("font_hover_color", ACCENT)
	out.add_theme_color_override("font_disabled_color", TEXT_DIM)
	return out


static func flat(color: Color, radius := 6, edge := Color(0, 0, 0, 0), padding := 8.0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	if edge.a > 0.0:
		box.set_border_width_all(2)
		box.border_color = edge
	box.content_margin_left = padding
	box.content_margin_right = padding
	box.content_margin_top = padding * 0.6
	box.content_margin_bottom = padding * 0.6
	return box


## «Клавиша» — надпись в рамке, как на клавиатуре. По ней видно, что это
## нажимают, а не читают.
static func keycap(text: String, size := 14) -> PanelContainer:
	var cap := PanelContainer.new()
	cap.add_theme_stylebox_override("panel",
		flat(Color(0.92, 0.90, 0.84, 0.95), 4, Color(0.35, 0.33, 0.30, 1.0), 5.0))
	var text_label := label(text, size, Color(0.10, 0.10, 0.12))
	text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_child(text_label)
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return cap
