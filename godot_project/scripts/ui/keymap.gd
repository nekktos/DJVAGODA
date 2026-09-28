extends RefCounted
##
## Раскладка: все клавиши игры одним списком, переназначаемые (решение автора
## от 28.09.2026: «меню настройки, чтоб каждый мог под себя назначить клавиши»).
##
## ЗАЧЕМ ОДИН СПИСОК. До него половина клавиш жила в InputMap проекта, а вторая
## половина — стройка, батраки, отряд, звук, справка — была зашита в код
## сравнениями с KEY_1, KEY_B и так далее. Переназначить такую клавишу нельзя в
## принципе: она не действие, а число в условии. Теперь каждая клавиша — действие
## с русским названием, группой и значением по умолчанию, и код спрашивает
## действие, а не клавишу.
##
## ФИЗИЧЕСКИЕ КЛАВИШИ, как и было: на русской раскладке «C» и «С» — разные
## символы на одной кнопке, и управление не должно зависеть от раскладки.
##
## Одна клавиша может стоять на двух действиях из РАЗНЫХ режимов: B в бою
## перевязывает, сверху нанимает батрака. Режимы не пересекаются, и код каждого
## режима спрашивает только свои действия. Конфликтом считается совпадение
## внутри одного режима или с «общими» клавишами, которые работают везде.
##

## Где лежат переназначения. Только отличия от умолчаний не храним — храним всё
## переназначенное целиком: так файл читается глазами.
const DEFAULT_PATH := "user://keys.cfg"

## Куда сохранять. Автопроверки подменяют путь, чтобы не трогать раскладку
## живого игрока на той же машине.
static var config_path := DEFAULT_PATH

enum Group { COMBAT, STRATEGY, GENERAL }

const GROUP_NAMES := ["В бою", "Вид сверху", "Везде"]

## Мышиные кнопки кодируем отрицательными числами, чтобы список умолчаний
## оставался списком чисел: -1 — ЛКМ, -2 — ПКМ, -3 — колесо.
const MOUSE_LEFT := -1

## Все действия. Порядок — порядок строк в меню настройки.
##
## ФОРМАТ: [имя действия, подпись, группа, клавиши по умолчанию].
const ACTIONS := [
	["move_forward", "вперёд", Group.COMBAT, [KEY_W]],
	["move_back", "назад", Group.COMBAT, [KEY_S]],
	["move_left", "влево", Group.COMBAT, [KEY_A]],
	["move_right", "вправо", Group.COMBAT, [KEY_D]],
	["jump", "прыжок", Group.COMBAT, [KEY_SPACE]],
	["sprint", "бег", Group.COMBAT, [KEY_SHIFT]],
	["dash", "рывок (эльфы)", Group.COMBAT, [KEY_R]],
	["attack", "удар / выстрел", Group.COMBAT, [MOUSE_LEFT]],
	["interact", "взаимодействие", Group.COMBAT, [KEY_E, KEY_F]],
	["bandage", "перевязка (держать)", Group.COMBAT, [KEY_B]],
	["toggle_view", "первое / третье лицо", Group.COMBAT, [KEY_V]],
	["weapon_1", "оружие 1", Group.COMBAT, [KEY_1]],
	["weapon_2", "оружие 2", Group.COMBAT, [KEY_2]],
	["weapon_3", "оружие 3", Group.COMBAT, [KEY_3]],
	["weapon_4", "оружие 4", Group.COMBAT, [KEY_7]],
	["ability_1", "заклинание 1", Group.COMBAT, [KEY_4]],
	["ability_2", "заклинание 2", Group.COMBAT, [KEY_5]],
	["ability_3", "заклинание 3", Group.COMBAT, [KEY_6]],
	# Эльфы строят дома из боевого вида: вида сверху у них нет (GDD 9a).
	["build_elf_house", "эльфы: построить дом", Group.COMBAT, [KEY_N]],

	["cam_rotate_left", "поворот камеры влево", Group.STRATEGY, [KEY_Q]],
	["cam_rotate_right", "поворот камеры вправо", Group.STRATEGY, [KEY_E]],
	["build_storage", "строить: склад", Group.STRATEGY, [KEY_1]],
	["build_sword", "строить: казарма мечников", Group.STRATEGY, [KEY_2]],
	["build_archer", "строить: казарма лучников", Group.STRATEGY, [KEY_3]],
	["build_stable", "строить: конюшня", Group.STRATEGY, [KEY_4]],
	["build_house", "строить: дом дружины", Group.STRATEGY, [KEY_5]],
	["build_farm", "строить: поле", Group.STRATEGY, [KEY_6]],
	["route", "маршрут обоза", Group.STRATEGY, [KEY_C]],
	["hire_labourer", "нанять батрака", Group.STRATEGY, [KEY_B]],
	["role_lumberjack", "батрака в лесорубы", Group.STRATEGY, [KEY_7]],
	["role_miner", "батрака в шахтёры", Group.STRATEGY, [KEY_8]],
	["role_militia", "батрака в ополченцы", Group.STRATEGY, [KEY_9]],
	["role_builder", "батрака в строители", Group.STRATEGY, [KEY_0]],
	["role_farmer", "батрака в фермеры", Group.STRATEGY, [KEY_F]],
	["squad_follow", "отряд ко мне", Group.STRATEGY, [KEY_G]],
	["squad_escort", "отряд с обозом", Group.STRATEGY, [KEY_H]],
	# Строи на F2-F5, а не на F1-F4, как было. На F1 висела справка, и её
	# обработчик стоял раньше стратегического: строй «колонна» по F1 не
	# включался НИКОГДА, а справка открывалась поверх карты.
	["formation_1", "строй 1", Group.STRATEGY, [KEY_F2]],
	["formation_2", "строй 2", Group.STRATEGY, [KEY_F3]],
	["formation_3", "строй 3", Group.STRATEGY, [KEY_F4]],
	["formation_4", "строй 4", Group.STRATEGY, [KEY_F5]],

	["toggle_camera", "вид сверху / в бой", Group.GENERAL, [KEY_TAB]],
	["upgrade", "прокачка", Group.GENERAL, [KEY_P]],
	["help", "справка по клавишам", Group.GENERAL, [KEY_F1]],
	["mute", "звук выкл / вкл", Group.GENERAL, [KEY_M]],
	["volume_down", "тише", Group.GENERAL, [KEY_MINUS]],
	["volume_up", "громче", Group.GENERAL, [KEY_EQUAL]],
	["console", "консоль", Group.GENERAL, [KEY_QUOTELEFT]],
	["leave", "выйти в главное меню", Group.GENERAL, [KEY_F10]],
]


## Завести все действия в InputMap: умолчания, поверх — сохранённое.
##
## Зовётся один раз при старте. Действия из project.godot тоже переписываются
## умолчаниями отсюда: источник правды один, и разойтись двум спискам не дадим.
static func install() -> void:
	for entry in ACTIONS:
		var action: StringName = entry[0]
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		_set_defaults(action, entry[3])
	load_saved()


static func _set_defaults(action: StringName, keys: Array) -> void:
	InputMap.action_erase_events(action)
	for code in keys:
		InputMap.action_add_event(action, _event_for(int(code)))


## Событие по коду из списка умолчаний: клавиша физическая, мышь — отрицательная.
static func _event_for(code: int) -> InputEvent:
	if code < 0:
		var mouse := InputEventMouseButton.new()
		mouse.button_index = -code as MouseButton
		return mouse
	var key := InputEventKey.new()
	key.physical_keycode = code as Key
	return key


## Строка раскладки по имени действия. Пусто — такого нет.
static func entry_of(action: StringName) -> Array:
	for entry in ACTIONS:
		if StringName(entry[0]) == action:
			return entry
	return []


static func group_of(action: StringName) -> int:
	var entry := entry_of(action)
	return int(entry[2]) if not entry.is_empty() else -1


## Главная клавиша действия — первая в списке. Её и показывают, и меняют.
static func primary(action: StringName) -> InputEvent:
	if not InputMap.has_action(action):
		return null
	var events := InputMap.action_get_events(action)
	return events[0] if not events.is_empty() else null


## Клавиши, у которых движок даёт английское слово вместо значка: «Minus»,
## «QuoteLeft». Человек ищет на клавиатуре значок, а не слово.
const RUSSIAN_KEYS := {
	KEY_MINUS: "-",
	KEY_EQUAL: "=",
	KEY_QUOTELEFT: "Ё",
	KEY_SPACE: "Пробел",
	KEY_COMMA: ",",
	KEY_PERIOD: ".",
	KEY_SLASH: "/",
	KEY_SEMICOLON: ";",
	KEY_APOSTROPHE: "'",
	KEY_BRACKETLEFT: "[",
	KEY_BRACKETRIGHT: "]",
}


## Как клавишу назвать человеку: «E», «Пробел», «ЛКМ».
static func key_text(action: StringName) -> String:
	return event_text(primary(action))


static func event_text(event: InputEvent) -> String:
	if event == null:
		return "—"
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT: return "ЛКМ"
			MOUSE_BUTTON_RIGHT: return "ПКМ"
			MOUSE_BUTTON_MIDDLE: return "СКМ"
		return "мышь %d" % int(event.button_index)
	if event is InputEventKey:
		var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		# Показываем букву ТЕКУЩЕЙ раскладки: человек с русской видит «У»
		# там, где физически стоит W, — именно её он и ищет на клавиатуре.
		#
		# Без экрана (автопроверки) раскладки нет, и движок на такой вопрос
		# пишет ошибку в журнал — тогда называем клавишу по её месту.
		var shown := 0
		if DisplayServer.get_name() != "headless":
			shown = DisplayServer.keyboard_get_keycode_from_physical(code as Key)
		if RUSSIAN_KEYS.has(code):
			return RUSSIAN_KEYS[code]
		var text := OS.get_keycode_string(shown if shown != 0 else code)
		return text if text != "" else "?"
	return "?"


## Какое действие уже держит это событие в ТОМ ЖЕ режиме или среди общих.
## Пусто — конфликта нет.
static func conflict(action: StringName, event: InputEvent) -> StringName:
	var mine := group_of(action)
	for entry in ACTIONS:
		var other: StringName = entry[0]
		if other == action:
			continue
		var theirs: int = int(entry[2])
		var clash := theirs == mine or theirs == Group.GENERAL or mine == Group.GENERAL
		if not clash:
			continue
		for held in InputMap.action_get_events(other):
			if same_input(held, event):
				return other
	return &""


## Одна ли это кнопка. Сравниваем физику, а не символ.
static func same_input(a: InputEvent, b: InputEvent) -> bool:
	if a is InputEventMouseButton and b is InputEventMouseButton:
		return a.button_index == b.button_index
	if a is InputEventKey and b is InputEventKey:
		var ka: int = a.physical_keycode if a.physical_keycode != 0 else a.keycode
		var kb: int = b.physical_keycode if b.physical_keycode != 0 else b.keycode
		return ka == kb
	return false


## Назначить действию новую главную клавишу.
##
## Если её держит другое действие того же режима, МЕНЯЕМ МЕСТАМИ: тот получает
## старую клавишу этого. Просто отнять её значило бы оставить второе действие
## без клавиши вовсе — и узнать об этом игрок мог бы только в бою.
##
## Возвращает имя действия, с которым поменялись, или пустое.
static func rebind(action: StringName, event: InputEvent) -> StringName:
	if not InputMap.has_action(action) or event == null:
		return &""
	var clean := _clean(event)
	var old := primary(action)
	var other := conflict(action, clean)
	if other != &"":
		var theirs := InputMap.action_get_events(other)
		InputMap.action_erase_events(other)
		for held in theirs:
			if same_input(held, clean):
				if old != null:
					InputMap.action_add_event(other, old)
			else:
				InputMap.action_add_event(other, held)
	var rest := InputMap.action_get_events(action)
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, clean)
	# Вторые клавиши действия (у «взаимодействия» их две) сохраняем, кроме той,
	# что стала главной, и кроме старой главной — её заменили.
	for i in range(1, rest.size()):
		if not same_input(rest[i], clean):
			InputMap.action_add_event(action, rest[i])
	save()
	return other


## Событие без лишнего: только физическая клавиша или кнопка мыши. Нажатие со
## всеми флагами (shift, эхо, pressed) в InputMap хранить нельзя — действие
## потом не срабатывало бы без тех же модификаторов.
static func _clean(event: InputEvent) -> InputEvent:
	if event is InputEventMouseButton:
		var mouse := InputEventMouseButton.new()
		mouse.button_index = event.button_index
		return mouse
	var key := InputEventKey.new()
	var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	key.physical_keycode = code as Key
	return key


## Вернуть все клавиши к умолчаниям и забыть сохранённое.
static func reset_all() -> void:
	for entry in ACTIONS:
		_set_defaults(entry[0], entry[3])
	save()


static func save() -> void:
	var cfg := ConfigFile.new()
	for entry in ACTIONS:
		var action: StringName = entry[0]
		var codes := []
		for event in InputMap.action_get_events(action):
			codes.append(_code_of(event))
		cfg.set_value("keys", String(action), codes)
	var err := cfg.save(config_path)
	if err != OK:
		push_warning("раскладка не сохранилась: %s (%d)" % [config_path, err])


static func load_saved() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(config_path) != OK:
		return
	for entry in ACTIONS:
		var action: StringName = entry[0]
		if not cfg.has_section_key("keys", String(action)):
			continue
		var codes = cfg.get_value("keys", String(action), [])
		if not (codes is Array) or codes.is_empty():
			continue
		InputMap.action_erase_events(action)
		for code in codes:
			InputMap.action_add_event(action, _event_for(int(code)))


static func _code_of(event: InputEvent) -> int:
	if event is InputEventMouseButton:
		return -int(event.button_index)
	if event is InputEventKey:
		return int(event.physical_keycode if event.physical_keycode != 0 else event.keycode)
	return 0
