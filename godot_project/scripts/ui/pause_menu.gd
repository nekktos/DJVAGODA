extends Control
##
## Меню паузы (Esc) и настройка клавиш.
##
## ЗАЧЕМ. Решение автора от 28.09.2026: «меню настройки, чтоб каждый мог под себя
## назначить клавиши». До него Esc только отпускал мышь, а настроек не было
## нигде: клавиши были зашиты в код.
##
## Партию пауза НЕ останавливает: игра сетевая, и один человек, открывший меню,
## не может заморозить мир троим. Поэтому меню говорит об этом прямо.
##
## Две страницы в одном окне: пауза и клавиши. Открыть клавиши можно и из
## главного меню — тогда страница паузы не показывается вовсе.
##

const STYLE := preload("res://scripts/ui/style.gd")
const KEYMAP := preload("res://scripts/ui/keymap.gd")

signal resume_requested
signal leave_requested

var _pause_page: Control
var _keys_page: Control
var _rows := {}
## Действие, которому сейчас ждём новую клавишу. Пусто — не ждём.
var _waiting: StringName = &""
var _note: Label
## Открыли клавиши прямо из главного меню: «назад» закрывает окно целиком.
var _keys_only := false
## Середина экрана: обе страницы живут в ней и сами встают по центру.
var _centre: CenterContainer


func _ready() -> void:
	# Привязку И отступы разом. С одной привязкой окно, собранное кодом,
	# оставалось нулевого размера: пауза вылезала в левый верхний угол, а
	# затемнение не рисовалось вовсе — это видно на первом снимке.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_centre = CenterContainer.new()
	_centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_centre)
	_build_pause()
	_build_keys()


func _build_pause() -> void:
	var box := STYLE.panel(24.0)
	_centre.add_child(box)
	_pause_page = box
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 10)
	list.custom_minimum_size = Vector2(320.0, 0.0)
	box.add_child(list)
	var title := STYLE.label("ПАУЗА", 26, STYLE.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	list.add_child(title)
	var note := STYLE.label("Мир не стоит: игра сетевая, остальные играют дальше.", 13, STYLE.TEXT_DIM)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list.add_child(note)
	var resume := STYLE.button("Продолжить", 18)
	resume.name = "Resume"
	resume.pressed.connect(func() -> void: resume_requested.emit())
	list.add_child(resume)
	var keys := STYLE.button("Клавиши", 18)
	keys.name = "Keys"
	keys.pressed.connect(func() -> void: show_keys(false))
	list.add_child(keys)
	var leave := STYLE.button("Выйти в главное меню", 18)
	leave.name = "Leave"
	leave.pressed.connect(func() -> void: leave_requested.emit())
	list.add_child(leave)


func _build_keys() -> void:
	var box := STYLE.panel(20.0)
	_centre.add_child(box)
	_keys_page = box
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	box.add_child(outer)

	var title := STYLE.label("КЛАВИШИ", 24, STYLE.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(title)
	_note = STYLE.label("Нажми на клавишу справа от действия, потом — новую клавишу.",
		14, STYLE.TEXT_DIM)
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(_note)

	# Три колонки по режимам: в бою, сверху и везде. Колонки, а не одна длинная
	# простыня: в каждом режиме свои клавиши, и искать их удобнее рядом.
	# В прокрутке: сорок семь действий в три колонки на экране высотой 720 не
	# помещаются, и без прокрутки низ списка с кнопкой «Назад» уходил за край.
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0.0, 470.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 18)
	scroll.add_child(columns)
	var lists := []
	for group in KEYMAP.GROUP_NAMES.size():
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 3)
		column.custom_minimum_size = Vector2(290.0, 0.0)
		column.add_child(STYLE.label(KEYMAP.GROUP_NAMES[group], 17, STYLE.ACCENT))
		columns.add_child(column)
		lists.append(column)
	for entry in KEYMAP.ACTIONS:
		var row := HBoxContainer.new()
		var name_label := STYLE.label(String(entry[1]), 13)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var key := STYLE.button("", 13)
		key.name = String(entry[0])
		key.custom_minimum_size = Vector2(84.0, 0.0)
		key.pressed.connect(_begin_capture.bind(StringName(entry[0])))
		row.add_child(key)
		lists[int(entry[2])].add_child(row)
		_rows[StringName(entry[0])] = key

	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 12)
	outer.add_child(bottom)
	var reset := STYLE.button("Сбросить всё", 16)
	reset.name = "Reset"
	reset.pressed.connect(_on_reset)
	bottom.add_child(reset)
	var back := STYLE.button("Назад", 16)
	back.name = "Back"
	back.pressed.connect(_on_back)
	bottom.add_child(back)


## Показать паузу.
func show_pause() -> void:
	_keys_only = false
	visible = true
	_pause_page.visible = true
	_keys_page.visible = false
	_waiting = &""


## Показать клавиши. `alone` — открыли из главного меню, паузы за ними нет.
func show_keys(alone: bool) -> void:
	_keys_only = alone
	visible = true
	_pause_page.visible = false
	_keys_page.visible = true
	_waiting = &""
	_refresh()


func close() -> void:
	visible = false
	_waiting = &""


## Ждём ли новую клавишу. Пока ждём, игра нажатие не получает.
func capturing() -> bool:
	return visible and _waiting != &""


func _refresh() -> void:
	for action in _rows:
		var key: Button = _rows[action]
		key.text = "…" if action == _waiting else KEYMAP.key_text(action)


func _begin_capture(action: StringName) -> void:
	_waiting = action
	_note.text = "«%s»: нажми новую клавишу. Esc — отмена." % KEYMAP.entry_of(action)[1]
	_note.add_theme_color_override("font_color", STYLE.ACCENT)
	_refresh()


## Ловим нажатие РАНЬШЕ всех (`_input`, а не `_unhandled_input`): иначе
## назначаемая клавиша успевала бы сработать в игре.
func _input(event: InputEvent) -> void:
	if not capturing():
		return
	var wanted: InputEvent = null
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE:
			_waiting = &""
			_note.text = "Отменено."
			_note.add_theme_color_override("font_color", STYLE.TEXT_DIM)
			_refresh()
			get_viewport().set_input_as_handled()
			return
		wanted = event
	elif event is InputEventMouseButton and event.pressed:
		wanted = event
	if wanted == null:
		return
	get_viewport().set_input_as_handled()
	assign(_waiting, wanted)


## Назначить клавишу. Открыто наружу ради проверок: нажатие в headless-прогоне
## не смоделировать честно, а правило обмена проверить надо.
func assign(action: StringName, event: InputEvent) -> void:
	var swapped: StringName = KEYMAP.rebind(action, event)
	var name_of: String = KEYMAP.entry_of(action)[1]
	if swapped != &"":
		_note.text = "«%s» — %s. Клавиша была у «%s», ему отдана старая: %s." % [
			name_of, KEYMAP.key_text(action), KEYMAP.entry_of(swapped)[1],
			KEYMAP.key_text(swapped)]
		_note.add_theme_color_override("font_color", STYLE.ACCENT)
	else:
		_note.text = "«%s» — %s. Сохранено." % [name_of, KEYMAP.key_text(action)]
		_note.add_theme_color_override("font_color", STYLE.GOOD)
	_waiting = &""
	_refresh()


func _on_reset() -> void:
	KEYMAP.reset_all()
	_note.text = "Все клавиши вернулись к умолчаниям."
	_note.add_theme_color_override("font_color", STYLE.TEXT_DIM)
	_refresh()


func _on_back() -> void:
	if _keys_only:
		close()
	else:
		show_pause()
