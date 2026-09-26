extends Control
##
## Интерфейс боя и стратегии (Этап 10, шаг 9 — полировка по просьбе к живому
## playtest).
##
## ЧТО БЫЛО. Одна надпись в левом верхнем углу, куда сваливалось всё разом:
## роль в сети, id, число пиров, fps, версия сборки, цель партии, состояние
## сторон под ИИ, здоровье, оружие, бинты, склад, ранения, откаты заклинаний,
## приказ стражи, перемирие, подбор груза и вдобавок список всех клавиш. Семь
## строк одинакового размера, белым по светлому миру, без единой рамки. Как
## отладочная печать это работало; для живого человека — нет: здоровье, ради
## которого в HUD и смотрят, лежало в середине четвёртой строки между «пиров» и
## «оружие».
##
## ЧТО СТАЛО. Разное — в разные места, по важности и по частоте взгляда:
##
##   левый низ      — жизнь: полоса здоровья, бинты, раны, проклятия;
##   правый низ     — хозяйство: сторона, цель, склад, отряд;
##   низ по центру  — ОДНА строка: что можно сделать прямо сейчас;
##   правый край    — заклинания с откатами;
##   левый верх     — техническая строка, мелко и тускло: она нужна в отчёте
##                    об ошибке, а не в бою;
##   центр по F1    — полный список клавиш, скрыт по умолчанию.
##
## ПОЧЕМУ КОДОМ, А НЕ В СЦЕНЕ. Панелей и надписей полтора десятка, и собранные
## руками в `.tscn` они превращаются в двести строк текста, где не видно ни
## отступов, ни причин. Здесь же рядом лежат и вёрстка, и объяснение, зачем она
## такая.
##

const FACTIONS := preload("res://scripts/factions.gd")
const RES := preload("res://scripts/economy/resources.gd")
const WEAPONS := preload("res://scripts/combat/weapons.gd")
const ABILITIES := preload("res://scripts/combat/abilities.gd")

## Картинки интерфейса — Kenney UI Pack 2.0, лицензия CC0 (см. LICENSE.txt рядом
## с ними). Из тысячи с лишним файлов набора взяты четыре: рамка панели, две
## половины полосы и разделитель. Класть в репозиторий весь архив ради четырёх
## картинок значит навсегда засорить поиск по проекту.
const PANEL_TEX := preload("res://assets/ui/kenney/button_square_depth_border.png")
const BAR_BACK_TEX := preload("res://assets/ui/kenney/slide_horizontal_grey.png")
const BAR_FILL_TEX := preload("res://assets/ui/kenney/slide_horizontal_color.png")

## Отступ панелей от края экрана.
const MARGIN := 18.0

## Фон панелей. Тёмный и полупрозрачный: мир под ним светлый, и белый текст без
## подложки на нём не читается вовсе — это видно на снимке старого интерфейса.
const PANEL_BG := Color(0.05, 0.05, 0.07, 0.62)

## Чем красим рамку Kenney: она светло-серая, а нам нужна тёмная подложка.
const PANEL_TINT := Color(0.10, 0.11, 0.14, 0.88)
const PANEL_EDGE := Color(1.0, 1.0, 1.0, 0.10)

const TEXT_DIM := Color(1.0, 1.0, 1.0, 0.55)
const TEXT_MAIN := Color(1.0, 1.0, 1.0, 0.92)
const ACCENT := Color(0.98, 0.78, 0.35)
const DANGER := Color(0.90, 0.28, 0.24)

var tech: Label
var vitals_box: VBoxContainer
## Панель вокруг полосы жизни. Нужна снаружи, чтобы прятать её целиком: скрытая
## полоса внутри видимой панели оставляет под меню пустой чёрный прямоугольник.
var vitals_panel: PanelContainer
var health_bar: ProgressBar
var stamina_bar: ProgressBar
var health_text: Label
var body_text: Label
var right_box: VBoxContainer
var prompt: Label
## Прицел. Рисуется кодом, а не картинкой: четыре чёрточки и точка — это
## четыре ColorRect, и менять их проще, чем искать файл.
var crosshair: Control
var spells: Label
var help_panel: PanelContainer
var help_text: RichTextLabel
var task_panel: PanelContainer
var task_step: Label
var task_text: Label
var task_keys: Label
var task_where: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	_build_crosshair()
	set_crosshair(false)


# --- сборка ----------------------------------------------------------------

## Прицел: точка в центре и четыре чёрточки вокруг неё.
##
## Зачем он вообще нужен. Камера смотрит из-за плеча, снаряд летит в точку под
## прицелом — и без метки на экране игрок не знает, ГДЕ эта точка. До сих пор её
## не было вовсе, и целиться приходилось по памяти о том, где середина экрана.
##
## Просвет в середине оставлен намеренно: сплошной крест закрывает собой то
## самое место, в которое смотришь, и на мелкой цели мешает больше, чем помогает.
func _build_crosshair() -> void:
	crosshair = Control.new()
	crosshair.name = "Crosshair"
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(crosshair)

	var gap := 5.0
	var arm := 7.0
	var thick := 2.0
	# Чёрточки: слева, справа, сверху, снизу. Смещения считаются от центра
	# экрана — якорь по центру, позиция в пикселях от него.
	var bars := [
		[Vector2(-gap - arm, -thick * 0.5), Vector2(arm, thick)],
		[Vector2(gap, -thick * 0.5), Vector2(arm, thick)],
		[Vector2(-thick * 0.5, -gap - arm), Vector2(thick, arm)],
		[Vector2(-thick * 0.5, gap), Vector2(thick, arm)],
	]
	for bar in bars:
		_crosshair_piece(bar[0], bar[1], Color(1.0, 1.0, 1.0, 0.85))
	# Точка в самом центре: по ней и целятся, чёрточки лишь помогают её найти.
	_crosshair_piece(Vector2(-1.0, -1.0), Vector2(2.0, 2.0), Color(1.0, 0.85, 0.35, 0.95))


func _crosshair_piece(at: Vector2, size: Vector2, color: Color) -> void:
	var bar := ColorRect.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.color = color
	bar.set_anchors_preset(Control.PRESET_CENTER)
	bar.offset_left = at.x
	bar.offset_top = at.y
	bar.offset_right = at.x + size.x
	bar.offset_bottom = at.y + size.y
	crosshair.add_child(bar)


## Показывать ли прицел. Сверху он не нужен: там мышью отдают приказы, а не
## целятся, и метка в центре экрана только сбивает с толку.
func set_crosshair(on: bool) -> void:
	if crosshair != null:
		crosshair.visible = on


func _build() -> void:
	# Техническая строка. Мелко и тускло — она нужна, когда тестер пишет отчёт,
	# а не когда он дерётся.
	tech = Label.new()
	tech.add_theme_font_size_override("font_size", 13)
	tech.add_theme_color_override("font_color", TEXT_DIM)
	tech.position = Vector2(MARGIN, 10.0)
	add_child(tech)

	# Жизнь: левый низ. Сюда смотрят чаще всего и в самый неподходящий момент,
	# поэтому здесь полоса, а не число: цифру надо читать, полосу — видно.
	var vitals := _panel()
	vitals_panel = vitals
	vitals.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	vitals.position = Vector2(MARGIN, -MARGIN)
	vitals.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(vitals)
	vitals_box = VBoxContainer.new()
	vitals_box.add_theme_constant_override("separation", 4)
	vitals.add_child(vitals_box)

	health_bar = ProgressBar.new()
	health_bar.custom_minimum_size = Vector2(240.0, 22.0)
	health_bar.show_percentage = false
	health_bar.max_value = 100.0
	vitals_box.add_child(health_bar)

	# Выносливость — ПОЛОСОЙ и прямо под здоровьем. Числом её читать некогда:
	# на неё смотрят в тот момент, когда убегают.
	stamina_bar = ProgressBar.new()
	stamina_bar.custom_minimum_size = Vector2(240.0, 13.0)
	stamina_bar.show_percentage = false
	stamina_bar.max_value = 100.0
	# ЦВЕТА ЗАДАЁМ ЯВНО. С умолчаниями движка полоса высотой в десять пикселей
	# выходила ровно серой: скруглённая заливка съедала всю высоту, и на снимке
	# полная выносливость выглядела пустой. Заодно янтарный отличает её от
	# зелёного здоровья — две одинаковые полосы друг под другом читались бы как
	# одна разорванная.
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.08, 0.08, 0.10, 0.85)
	back.set_corner_radius_all(3)
	var fill := StyleBoxFlat.new()
	fill.bg_color = ACCENT
	fill.set_corner_radius_all(3)
	stamina_bar.add_theme_stylebox_override("background", back)
	stamina_bar.add_theme_stylebox_override("fill", fill)
	vitals_box.add_child(stamina_bar)

	health_text = Label.new()
	health_text.add_theme_font_size_override("font_size", 16)
	health_text.add_theme_color_override("font_color", TEXT_MAIN)
	vitals_box.add_child(health_text)

	body_text = Label.new()
	body_text.add_theme_font_size_override("font_size", 14)
	body_text.add_theme_color_override("font_color", TEXT_DIM)
	vitals_box.add_child(body_text)

	# Хозяйство: правый низ. Смотрят реже и осознанно.
	var right := _panel()
	right.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	right.position = Vector2(-MARGIN, -MARGIN)
	right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	right.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(right)
	right_box = VBoxContainer.new()
	right_box.add_theme_constant_override("separation", 3)
	right.add_child(right_box)

	# Что можно сделать прямо сейчас — одной строкой по центру внизу. Это
	# единственное место, куда игрок смотрит, не зная, что ищет.
	prompt = Label.new()
	prompt.add_theme_font_size_override("font_size", 20)
	prompt.add_theme_color_override("font_color", ACCENT)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	prompt.offset_top = -84.0
	prompt.offset_bottom = -56.0
	add_child(prompt)

	# Заклинания — тоже ЛИЧНОЕ состояние, поэтому живут рядом со здоровьем, а не
	# у правого края. У края они вдобавок обрезались: строка длинная, а места
	# справа ровно столько, сколько отдали.
	spells = Label.new()
	spells.add_theme_font_size_override("font_size", 14)
	spells.add_theme_color_override("font_color", ACCENT)
	vitals_box.add_child(spells)

	# ЗАДАЧА: верх по центру. Единственное место на экране, куда смотрит
	# человек, который не понимает, что происходит, — и единственное, которое
	# до сих пор пустовало. Здесь ровно один шаг: что делать сейчас, какими
	# клавишами и куда для этого идти.
	task_panel = _panel()
	task_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	task_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	task_panel.position = Vector2(0.0, 34.0)
	task_panel.visible = false
	add_child(task_panel)
	var task_box := VBoxContainer.new()
	task_box.add_theme_constant_override("separation", 2)
	task_panel.add_child(task_box)

	task_step = Label.new()
	task_step.add_theme_font_size_override("font_size", 12)
	task_step.add_theme_color_override("font_color", TEXT_DIM)
	task_step.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	task_box.add_child(task_step)

	task_text = Label.new()
	task_text.add_theme_font_size_override("font_size", 21)
	task_text.add_theme_color_override("font_color", TEXT_MAIN)
	task_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	task_box.add_child(task_text)

	task_keys = Label.new()
	task_keys.add_theme_font_size_override("font_size", 15)
	task_keys.add_theme_color_override("font_color", ACCENT)
	task_keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	task_box.add_child(task_keys)

	task_where = Label.new()
	task_where.add_theme_font_size_override("font_size", 15)
	task_where.add_theme_color_override("font_color", TEXT_DIM)
	task_where.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	task_box.add_child(task_where)

	# Полный список клавиш — по F1 и только по нему. Постоянно висящий список
	# перестают читать на второй минуте, а найти его потом негде.
	help_panel = _panel()
	help_panel.set_anchors_preset(Control.PRESET_CENTER)
	help_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	help_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	help_panel.visible = false
	add_child(help_panel)
	help_text = RichTextLabel.new()
	help_text.bbcode_enabled = true
	help_text.fit_content = true
	help_text.custom_minimum_size = Vector2(760.0, 0.0)
	help_text.add_theme_font_size_override("normal_font_size", 15)
	help_panel.add_child(help_text)


## Панель на рамке Kenney, растянутой девятипатчем.
##
## Нарисованная кодом прямоугольная плашка читалась, но выглядела ровно тем, чем
## была, — прямоугольником. Рамка с фаской даёт краю толщину, и панель перестаёт
## сливаться с миром на светлом фоне.
##
## Углы у картинки 64×64 скруглены на 12 пикселей — столько и отдаём девятипатчу,
## иначе скругление растянется вместе с серединой и превратится в дугу.
func _panel() -> PanelContainer:
	var box := PanelContainer.new()
	var style := StyleBoxTexture.new()
	style.texture = PANEL_TEX
	style.set_texture_margin_all(12.0)
	# Затемняем и делаем полупрозрачной: набор светло-серый, а под панелью мир.
	style.modulate_color = PANEL_TINT
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	box.add_theme_stylebox_override("panel", style)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return box


# --- наполнение ------------------------------------------------------------

## Текущий шаг подсказки. Пустой словарь прячет панель целиком.
##
## Панель именно ПРЯЧЕТСЯ, а не пустеет: рамка без текста посреди экрана
## читается как поломка интерфейса.
func set_task(step: Dictionary) -> void:
	if step.is_empty():
		task_panel.visible = false
		return
	task_panel.visible = true
	task_step.text = "ЗАДАЧА %d из %d" % [int(step["number"]), int(step["total"])]
	task_text.text = String(step["text"])
	task_keys.text = String(step.get("keys", ""))
	task_keys.visible = task_keys.text != ""
	task_where.text = String(step.get("where", ""))
	task_where.visible = task_where.text != ""


## Выносливость: доля от полной, от нуля до единицы.
func set_stamina(part: float) -> void:
	stamina_bar.value = clampf(part, 0.0, 1.0) * 100.0


## Техническая строка: то, что просят приложить к отчёту об ошибке.
func set_tech(text: String) -> void:
	tech.text = text


## Жизнь. `current` и `maximum` — здоровье, остальное строками.
func set_vitals(current: float, maximum: float, note: String, wounds: String) -> void:
	health_bar.max_value = maxf(1.0, maximum)
	health_bar.value = clampf(current, 0.0, maximum)
	var share: float = current / maxf(1.0, maximum)
	# Полоса собрана из двух картинок набора: серая подложка и цветная заливка.
	# Заливка одна, зелёная, а краснота делается МОДУЛЯЦИЕЙ: цвет меняется
	# плавно от доли здоровья, и двумя разными картинками такого перехода не
	# получить — вышел бы скачок, которого в бою не замечают.
	var fill := StyleBoxTexture.new()
	fill.texture = BAR_FILL_TEX
	# Поля девятипатча ТОЛЬКО по горизонтали. С полями по всем сторонам на
	# картинке высотой шестнадцать пикселей середины почти не остаётся, и
	# заливка раздувается посередине, как линза, — это видно на снимке.
	fill.texture_margin_left = 8.0
	fill.texture_margin_right = 8.0
	fill.modulate_color = DANGER.lerp(Color(0.45, 0.95, 0.50), share)
	health_bar.add_theme_stylebox_override("fill", fill)
	var back := StyleBoxTexture.new()
	back.texture = BAR_BACK_TEX
	back.texture_margin_left = 8.0
	back.texture_margin_right = 8.0
	back.modulate_color = Color(0.55, 0.55, 0.60, 0.85)
	health_bar.add_theme_stylebox_override("background", back)

	health_text.text = "%d / %d   %s" % [int(current), int(maximum), note]
	body_text.text = wounds
	body_text.visible = wounds != ""


## Правая колонка: по строке на пункт. Пустые строки не показываем — пустая
## строка в панели выглядит как поломка.
func set_right(lines: PackedStringArray) -> void:
	for child in right_box.get_children():
		child.queue_free()
	for line in lines:
		if line.strip_edges() == "":
			continue
		var label := Label.new()
		label.add_theme_font_size_override("font_size", 14)
		label.add_theme_color_override("font_color", TEXT_MAIN)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		label.text = line
		right_box.add_child(label)
	right_box.get_parent().visible = right_box.get_child_count() > 0


## Одна строка о том, что доступно прямо сейчас. Пусто — прячем.
func set_prompt(text: String) -> void:
	prompt.text = text
	prompt.visible = text != ""


## Заклинания с откатами. Пусто — прячем: у стражи их нет вовсе.
func set_spells(text: String) -> void:
	spells.text = text
	spells.visible = text != ""


func toggle_help() -> void:
	help_panel.visible = not help_panel.visible


func set_help(text: String) -> void:
	help_text.text = text
