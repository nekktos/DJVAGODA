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
##   --menushot=ПАПКА снять главное меню в PNG и выйти (нужно окно)
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
##   --newgametest   автопроверка «Новой игры»: что она правда новая (headless)
##   --reentrytest   автопроверка перезахода: вышел в меню, вернулся (headless)
##   --garrisontest  автопроверка гарнизонов свободных сторон (headless)
##   --warbandtest   автопроверка воюющего ИИ свободных сторон (headless)
##   --soaktest      трёхминутный прогон мира без людей: не деградирует ли ИИ
##   --netsoaktest   полторы минуты на двух пирах: сходятся ли их картины мира
##   --herotest      герой свободной стороны: есть, воюет, колдует, гибнет насовсем
##   --horsetest     лошади, упряжка, остановка обоза и три способа его отъёма
##   --navtest       автопроверка путей по карте (headless)
##   --labtest       автопроверка батраков: наём, роли, добыча (headless)
##   --stewardtest   автопроверка хозяйства ИИ: наём, стройка, войско (headless)
##   --sfxtest       автопроверка звука: синтез и точки вызова (headless)
##   --weapontest    автопроверка эксклюзивного оружия сторон (headless)
##   --magictest     автопроверка магии злодея и её контрплея (headless)
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
const BODY := preload("res://scripts/combat/body.gd")
const FORMATIONS := preload("res://scripts/units/formations.gd")
const BUILD_CONTROLLER := preload("res://scripts/economy/build_controller.gd")
const FACTIONS := preload("res://scripts/factions.gd")
const WARBAND := preload("res://scripts/ai/warband.gd")
const LABOURER := preload("res://scripts/units/labourer.gd")
const PROGRESS := preload("res://scripts/progression.gd")
const ORDERS := preload("res://scripts/orders.gd")
const TASKS := preload("res://scripts/elf_tasks.gd")
const CARAVAN := preload("res://scripts/economy/caravan.gd")
const ONBOARDING := preload("res://scripts/ui/onboarding.gd")
const WAYPOINT := preload("res://scripts/ui/waypoint.gd")
const KEYMAP := preload("res://scripts/ui/keymap.gd")
const PAUSE_MENU := preload("res://scripts/ui/pause_menu.gd")
const STYLE := preload("res://scripts/ui/style.gd")
const ICONS := preload("res://scripts/ui/icons.gd")
const RESOURCE_BAR := preload("res://scripts/ui/resource_bar.gd")
const COMMAND_BAR := preload("res://scripts/ui/command_bar.gd")
const HOTBAR := preload("res://scripts/ui/hotbar.gd")

## Человек ВЫБРАЛ сторону сам, а не получил её подстановкой из сейва.
##
## Подстановка — подсказка, а не приказ. Без этого флага список партий молча
## перебивал выбор: выбрал «Охрану дворца», тронул список — и начал новую игру
## злодеем, оказавшись в его форте. Выбор, который игра отменяет за спиной, хуже
## отсутствия выбора.
## Подсказка первых минут и её маяк в мире. Личные: ничего не реплицируется,
## в сохранение не идёт — это объяснение одному человеку, а не часть партии.
var _onboarding := ONBOARDING.new()
## Меню паузы и клавиш (Esc). Собирается кодом при старте.
var _settings: Control = null
## Иконки интерфейса — снимки моделей игры (`ui/icons.gd`).
var _icons: Node = null
## Полоса запасов (левый верх) и панель команд вида сверху (левый низ).
var _res_bar: Control = null
var _command_bar: Control = null
## Боевая полоса: оружие, заклинания, стрелы, бинты (низ по центру).
var _hotbar: Control = null
var _waypoint: Node3D = null
var _faction_chosen := false

## Кнопка «Новая игра» уже спросила подтверждение и ждёт второго нажатия.
var _new_confirm := false
## То же для «Удалить». Отдельный флаг, а не общий: два переспроса, сброшенные
## одной переменной, гасили бы друг друга, и человек, передумавший удалять,
## одним нажатием начинал бы новую партию.
var _delete_confirm := false
## Сохранённые партии в том порядке, в каком они лежат в списке меню.
var _saves: Array = []

## Сколько секунд держится объявление о результате.
const ANNOUNCE_SECONDS := 7.0

## Громкость: шаг, дно и потолок в децибелах.
##
## ЗАЧЕМ ВООБЩЕ. Живой игрок написал «противный звук бьёт по ушам», и
## выяснилось, что убавить его в игре НЕЧЕМ: ни клавиши, ни настройки. Сам
## звук починен (см. шапку `audio/ambience.gd`), но вывод шире починки — у
## человека всегда должен быть способ сделать тише, не убивая игру. Тем более
## у тестера, которого мы сами просим играть сорок минут подряд.
const VOLUME_STEP := 4.0
const VOLUME_FLOOR := -40.0
const VOLUME_CEIL := 6.0

var _volume_db := 0.0
var _muted := false

@onready var _menu: Control = $UI/Menu
@onready var _status: Label = $UI/Menu/Panel/VBox/Status
@onready var _transport_opt: OptionButton = $UI/Menu/Panel/VBox/TransportRow/TransportOpt
@onready var _ip_edit: LineEdit = $UI/Menu/Panel/VBox/JoinRow/IpEdit
@onready var _continue_btn: Button = $UI/Menu/Panel/VBox/ContinueBtn
@onready var _new_btn: Button = $UI/Menu/Panel/VBox/NewBtn
@onready var _save_info: Label = $UI/Menu/Panel/VBox/SaveInfo
@onready var _world_opt: OptionButton = $UI/Menu/Panel/VBox/WorldRow/WorldOpt
@onready var _delete_btn: Button = $UI/Menu/Panel/VBox/WorldRow/DeleteBtn
@onready var _join_btn: Button = $UI/Menu/Panel/VBox/JoinRow/JoinBtn
@onready var _hud: Control = $UI/Hud
@onready var _world: Node3D = $World
@onready var _blind_left: ColorRect = $UI/Blind/Left
@onready var _blind_right: ColorRect = $UI/Blind/Right
@onready var _building_ui: Control = $UI/Building
@onready var _bench: Control = $UI/Bench
@onready var _upgrade: Control = $UI/Upgrade
@onready var _bench_chair: Button = $UI/Bench/Panel/VBox/Chair
@onready var _trader: Control = $UI/Trader
@onready var _commander_ui: Control = $UI/Commander
@onready var _announce: Label = $UI/Hud/Announce
@onready var _faction_opt: OptionButton = $UI/Menu/Panel/VBox/FactionRow/FactionOpt
@onready var _console: Control = $UI/Console
@onready var _console_out: RichTextLabel = $UI/Console/Panel/VBox/Output
@onready var _console_in: LineEdit = $UI/Console/Panel/VBox/Input


func _ready() -> void:
	# Раскладку ставим ПЕРВОЙ: всё, что ниже, уже спрашивает действия, а не
	# клавиши, и сохранённые переназначения должны действовать с первого кадра.
	KEYMAP.install()
	_build_settings()
	_build_bars()
	Net.status_changed.connect(_on_status)
	Net.session_started.connect(_on_session_started)
	Net.session_ended.connect(_on_session_ended)
	_continue_btn.pressed.connect(_on_continue_pressed)
	_world_opt.item_selected.connect(_on_world_selected)
	_delete_btn.pressed.connect(_on_delete_pressed)
	_new_btn.pressed.connect(_on_new_pressed)
	_join_btn.pressed.connect(_on_join_pressed)
	_transport_opt.item_selected.connect(_on_transport_selected)
	_ip_edit.text_submitted.connect(func(_t: String) -> void: _on_join_pressed())
	_world.camera_mode_changed.connect(_on_camera_mode_changed)
	_world.objective.announced.connect(_on_announced)
	_faction_opt.item_selected.connect(_on_faction_chosen)
	Net.chosen_faction = _faction_opt.selected
	_console_in.text_submitted.connect(_on_console_submitted)

	_building_ui.route_requested.connect(func() -> void: _world.set_route_mode(true))
	_building_ui.closed.connect(_on_building_panel_closed)

	var bench := $UI/Bench/Panel/VBox
	bench.get_node("Wooden").pressed.connect(_on_bench_prosthetic.bind(1))
	bench.get_node("Iron").pressed.connect(_on_bench_prosthetic.bind(2))
	bench.get_node("Master").pressed.connect(_on_bench_prosthetic.bind(3))
	bench.get_node("Necrotic").pressed.connect(_on_bench_prosthetic.bind(BODY.NECROTIC_TIER))
	bench.get_node("Eye").pressed.connect(_on_bench_eye)
	bench.get_node("Splint").pressed.connect(_on_bench_splint)
	bench.get_node("Chair").pressed.connect(_on_bench_chair)
	bench.get_node("Close").pressed.connect(_close_bench)

	var up := $UI/Upgrade/Panel/VBox
	for stat in PROGRESS.COUNT:
		up.get_node("Stat%d" % stat).pressed.connect(_on_upgrade.bind(stat))
	up.get_node("Close").pressed.connect(_close_upgrade)

	var trader := $UI/Trader/Panel/VBox
	trader.get_node("Bandages").pressed.connect(_on_trade.bind(RES.Trade.BANDAGES))
	trader.get_node("Arrows").pressed.connect(_on_trade.bind(RES.Trade.ARROWS))
	trader.get_node("Gear").pressed.connect(_on_trade.bind(RES.Trade.GEAR))
	# Новый товар (GDD 9a): доспех и зелья. Кнопки заводим кодом и ставим
	# перед «Закрыть» — у каждой стороны в окне только её товар.
	for entry in [["Armor", RES.Trade.ARMOR], ["PotionHeal", RES.Trade.POTION_HEAL],
			["PotionMana", RES.Trade.POTION_MANA]]:
		var goods := Button.new()
		goods.name = entry[0]
		goods.custom_minimum_size = Vector2(0.0, 40.0)
		goods.pressed.connect(_on_trade.bind(int(entry[1])))
		trader.add_child(goods)
		trader.move_child(goods, trader.get_node("Close").get_index())
	trader.get_node("Close").pressed.connect(_close_trader)
	# Одеть заново: окна одевались в `_build_bars`, до новых кнопок.
	_dress_panels()

	var commander := $UI/Commander/Panel/VBox
	commander.get_node("Report").pressed.connect(_on_report)
	commander.get_node("Promote").pressed.connect(_on_promote)
	commander.get_node("Close").pressed.connect(_close_commander)

	if not Net.steam_available():
		_transport_opt.set_item_disabled(1, true)
		_transport_opt.set_item_text(1, "Steam (аддон не загружен)")

	_on_transport_selected(0)
	_show_menu(true)
	# Закрытие окна перехватываем сами: иначе крестик уносит с собой всё, что
	# наиграно после последнего автосейва, а автосейв идёт раз в минуту.
	get_tree().set_auto_accept_quit(false)
	_apply_cmdline()


## Крестик окна: сохраняемся и выходим.
##
## Сохраняет только хозяин — у клиента нет авторитетного состояния, и его файл
## был бы копией чужой правды (см. `savegame.gd`). Выход не отменяем ни при
## каких обстоятельствах: закрытие окна — не то место, где программа спорит с
## человеком.
func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_CLOSE_REQUEST:
		return
	if Net.hosting():
		_world.savegame.save_world()
	get_tree().quit()


func _process(delta: float) -> void:
	_tick_announce(delta)
	_tick_refusal(delta)
	_refresh_hud()
	_refresh_bars()
	_update_blindness()


## Разложить состояние по панелям.
##
## Раньше здесь собиралась ОДНА строка на семь переносов, и здоровье в ней
## стояло между «пиров» и «оружием». Теперь каждая величина идёт туда, куда на
## неё смотрят: жизнь влево вниз, хозяйство вправо вниз, доступное действие —
## одной строкой по центру. Сборщики строк остались прежними, изменилось только
## КУДА они попадают.
func _refresh_hud() -> void:
	if not Net.active:
		# Номер сборки в меню НУЖЕН: тестер сообщает об ошибке, и первый вопрос
		# к нему — «в какой сборке». Остальной HUD — нет: полоса здоровья
		# несуществующего персонажа под главным меню выглядит поломкой.
		_hud.set_tech("Оффлайн   сборка: %s"
			% ProjectSettings.get_setting("application/config/version", "?"))
		_hud.vitals_panel.visible = false
		_hud.set_crosshair(false)
		_hud.set_right(PackedStringArray())
		_hud.set_prompt("")
		_hud.set_spells("")
		_hud.set_task({})
		if _waypoint != null:
			_waypoint.visible = false
		return
	_hud.vitals_panel.visible = true
	# Прицел — только в бою и только у живого: сверху им не целятся, а мёртвому
	# целиться нечем.
	var alive_now: Node3D = _world.local_player()
	_hud.set_crosshair(not _world.strategy_mode
		and alive_now != null and alive_now.health.alive)

	var role := "ХОСТ" if Net.is_host else "КЛИЕНТ"
	var kind := "Steam" if Net.transport == Net.Transport.STEAM else "IP"
	var tech := "%s (%s) · id %d · пиров %d · %d fps · %s" % [
		role, kind, Net.local_id(), Net.peer_count(),
		Engine.get_frames_per_second(),
		ProjectSettings.get_setting("application/config/version", "?"),
	] + _volume_note()
	if Net.is_host and Net.transport == Net.Transport.STEAM:
		tech += "\nSteam ID для друга: %d  (F9 — скопировать)" % Net.local_steam_id()
	_hud.set_tech(tech)
	_hud.set_help(_help_text())

	var me: Node3D = _world.local_player()
	_refresh_task(me)
	var right := PackedStringArray()
	# `_objective_hint` уже говорит и сторону, и цель, и владельца дворца. Свои
	# строки рядом с ним давали ровно те же слова дважды — на снимке это первое,
	# что бросается в глаза.
	for line in _objective_hint(me).split("\n"):
		right.append(line)
	# Запасы — картинками в полосе слева вверху (`ui/resource_bar.gd`), здесь
	# их больше нет: одна и та же цифра в двух местах читается как две разные.
	var ai: String = _ai_hint().strip_edges()
	if ai != "":
		right.append(ai)

	if _world.strategy_mode:
		# Жизнь сверху не нужна: персонажа отсюда не видно, а левый низ занят
		# панелью команд. Батраки и отряд — там же, карточками.
		_hud.vitals_panel.visible = false
		right.append("высота камеры: %d м" % int(_world.strategy_height()))
		right.append(_squad_hint())
		_hud.set_right(right)
		_hud.set_spells("")
		_hud.set_prompt(_strategy_prompt())
		return

	if me == null:
		_hud.set_right(right)
		_hud.set_prompt("")
		_hud.set_spells("")
		return

	if _world.is_spectating():
		_hud.set_vitals(0.0, 1.0, "вожак пал — возврата нет", "")
		_hud.set_right(right)
		_hud.set_prompt("НАБЛЮДАТЕЛЬ. Партия продолжается без вас")
		_hud.set_spells("")
		return

	# Оружие, стрелы и бинты — картинками в боевой полосе (`ui/hotbar.gd`).
	# Здесь остаётся то, чему там места нет: опыт и трофеи.
	var note := "опыт %d" % int(me.experience)
	# Трофеи показываем только когда они есть: пустая строчка «рук 0, ног 0»
	# висела бы у всех и всегда, а нужна она одному злодею с топором.
	var haul: int = me.trophies[0] + me.trophies[1] + me.trophies[2]
	if haul > 0:
		note += " · трофеи %d/%d/%d" % [me.trophies[0], me.trophies[1], me.trophies[2]]
	var wounds: String = me.body.summary()
	var curses: String = _curse_hint(me).strip_edges()
	if curses != "":
		wounds += "   " + curses
	_hud.set_vitals(me.health.current, 100.0, note, wounds)
	_hud.set_stamina(me.sync_stamina / me.STAMINA_MAX)
	_hud.set_right(right)
	# Мана — полосой под выносливостью, заклинания — в боевой полосе. Строкой
	# остаётся только то, что картинкой не сказать: сколько ещё действует клич.
	_hud.set_mana(me.mana / me.MANA_MAX if FACTIONS.has_abilities(me.faction) else -1.0)
	var buff := ""
	if me.sync_buff_left > 0.0:
		buff = "клич действует ещё %.0f с" % ceil(me.sync_buff_left)
	_hud.set_spells(buff)
	var action: Dictionary = _action_prompt(me)
	if action.has("key") or action.has("icon"):
		var key_text := _k(action["key"]) if action.has("key") else ""
		var picture: Texture2D = _icons.icon(action["icon"]) if action.has("icon") else null
		_hud.set_action(key_text, picture, String(action.get("text", "")))
	else:
		_hud.set_prompt(String(action.get("text", "")))


## Подсказка первых минут: шаг в панели наверху и маяк над местом, куда идти.
##
## РАССТОЯНИЕ СЧИТАЕТСЯ ЗДЕСЬ, а не в маяке: игрок уже под рукой у того, кто
## маяк ставит, а маяку пришлось бы искать его по всей сцене каждый кадр.
func _refresh_task(me: Node3D) -> void:
	var step: Dictionary = _onboarding.current(_world, me)
	if step.is_empty():
		_hud.set_task({})
		if _waypoint != null:
			_waypoint.visible = false
		return

	var at = step.get("at", null)
	if at != null and me != null:
		var gap: float = Vector2(me.global_position.x, me.global_position.z).distance_to(
			Vector2(at.x, at.z))
		step["where"] = "%s — %d м" % [step.get("place", "цель"), int(gap)]
		_aim_waypoint(at, String(step.get("place", "цель")), gap)
	else:
		step["where"] = ""
		if _waypoint != null:
			_waypoint.visible = false
	_hud.set_task(step)


## Маяк родим при первой надобности и больше не трогаем: в меню он не нужен, а
## создавать его вместе с миром значит держать столб над картой до входа.
func _aim_waypoint(at: Vector3, place_name: String, gap: float) -> void:
	if _waypoint == null:
		_waypoint = WAYPOINT.new()
		_waypoint.name = "Waypoint"
		_world.add_child(_waypoint)
	_waypoint.aim(at, place_name)
	_waypoint.show_gap(gap)


## Что можно сделать ПРЯМО СЕЙЧАС. Одно действие и только самое близкое:
## полный список возможностей живёт под справкой.
##
## Словарь, а не строка: «key» — действие раскладки (его клавиша рисуется в
## рамке), «icon» — ключ иконки того, с чем имеешь дело, «text» — что будет.
## Отказ и прочие простые строки идут одним «text».
func _action_prompt(me: Node3D) -> Dictionary:
	var refusal: String = _refusal_line().strip_edges()
	if refusal != "":
		return {"text": refusal}
	if _world.build_controller.active:
		var kind: int = int(_world.build_controller.kind)
		return {"key": &"build_elf_house", "icon": "bld_%d" % kind,
			"text": "%s (%s) — ЛКМ поставить, ПКМ отмена · домов %d из %d" % [
				RES.BUILDING_NAMES[kind], RES.format_cost(RES.BUILDING_COST[kind]),
				_world.elf_houses().size(), _world.elf_house_limit()]}
	var cart: Node3D = me.caravan_to_rob()
	if cart != null and me.riding() == null:
		match me.caravan_action(cart):
			"intercept":
				return {"key": &"interact", "icon": "cart",
					"text": "перехватить обоз: поедет на твой склад с грузом и лошадьми"}
			"plunder":
				return {"key": &"interact", "icon": "res_%d" % _richest(cart.cargo),
					"text": "разграбить повозку: груз на землю"}
		return {"key": &"interact", "icon": "horse", "text": "выпрячь лошадей: %d" % int(cart.horses)}
	if me.riding() != null:
		return {"key": &"interact", "icon": "horse", "text": "спешиться"}
	if me.horse_nearby() != null:
		return {"key": &"interact", "icon": "horse", "text": "сесть на лошадь"}
	var pile: Node3D = me.loot_nearby()
	if pile != null:
		return {"key": &"interact", "icon": _pile_icon(pile), "text": "подобрать: %s" % pile.summary()}
	if me.at_trader():
		return {"key": &"interact", "icon": "res_%d" % RES.Kind.GOLD,
			"text": "лавка (снаряжение сейчас %s)" % me.gear_title(me.gear_tier)}
	if me.at_commander():
		return {"key": &"interact", "icon": "guard", "text": "командир: %s" % _order_hint(me)}
	if me.at_elder():
		var task := "получить задание" if me.order_kind < 0 else "%s (%s)" % [
			TASKS.name_of(me.order_kind), TASKS.progress_text(me.order_kind, me.order_progress)]
		return {"key": &"interact", "icon": "elf", "text": "старейшина: %s" % task}
	if me.at_workbench():
		return {"key": &"interact", "icon": "wpn_%d" % WEAPONS.Kind.HAMMER, "text": "верстак: протезы и коляска"}
	if me.body.bleeding:
		var progress: float = me.bandage_progress()
		if progress > 0.0:
			return {"icon": "bandage", "text": "перевязка: %d%%" % int(progress * 100.0)}
		return {"key": &"bandage", "icon": "bandage", "text": "перевязать (держать, стоя на месте)"}
	if int(me.faction) == FACTIONS.Kind.ELVES and me.order_kind >= 0:
		return {"icon": "elf", "text": "задание: %s — %s" % [
			TASKS.name_of(me.order_kind), TASKS.progress_text(me.order_kind, me.order_progress)]}
	if int(me.faction) == FACTIONS.Kind.GUARD and me.order_kind >= 0:
		return {"icon": "guard", "text": "приказ: %s — %s" % [
			ORDERS.name_of(me.order_kind),
			ORDERS.progress_text(me.order_kind, me.order_progress),
		]}
	return {"text": ""}


## Картинка кучи — по самому обильному в ней ресурсу.
func _pile_icon(pile: Node3D) -> String:
	if "contents" in pile:
		return "res_%d" % _richest(pile.contents)
	return "res_%d" % RES.Kind.WOOD


func _richest(amounts: Array) -> int:
	var best := RES.Kind.WOOD
	var most := -1
	for kind in RES.COUNT:
		var amount: int = RES.at(amounts, kind)
		if amount > most:
			most = amount
			best = kind
	return best


## То же для стратегического режима: там «доступное действие» — это включённый
## режим стройки или прокладки маршрута.
func _strategy_prompt() -> String:
	var refusal: String = _refusal_line().strip_edges()
	if refusal != "":
		return refusal
	var route: Node3D = _world.route_controller
	if route.active:
		return "МАРШРУТ: ЛКМ — точка (%d), Enter или двойной ЛКМ — отправить, ПКМ — отмена · едет в: %s" % [
			route.points().size(), _route_target()]
	var controller: Node3D = _world.build_controller
	if controller.active:
		return "СТРОЙКА: %s — ЛКМ поставить, ПКМ отменить" % RES.BUILDING_NAMES[controller.kind]
	var boss: Node3D = _world.local_player()
	if boss != null and boss.stock.get_amount(RES.Kind.IRON) <= 0:
		return "Железо только в шахте на земле эльфов: построй склад (1), нажми C и отправь караван"
	return "%s — все клавиши · Esc — пауза и настройка клавиш" % _k(&"help")


## К какой шахте поедет обоз, если отправить его сейчас: к ближайшей к
## последней точке маршрута, без точек — к ближайшей к складу. Правило то же,
## что у хоста (`player.gd::request_send_caravan`); показываем его, потому что
## шахт три и ошибиться шахтой — значит съездить через лес впустую.
func _route_target() -> String:
	var points: PackedVector3Array = _world.route_controller.points()
	var from := Vector3.ZERO
	if not points.is_empty():
		from = points[points.size() - 1]
	else:
		var boss: Node3D = _world.local_player()
		var storage: Node3D = _world.storage_of(int(boss.faction)) if boss != null else null
		if storage == null:
			return "—"
		from = storage.global_position
	var target: Node3D = _world.mine_near(from)
	return target.title() if target != null else "—"


## Отдать громкость звуковой шине. Одна общая на всё: и на фон, и на удары.
## Раздельные ползунки — это настройки, а нам нужна клавиша под рукой.
func _apply_volume() -> void:
	var bus := AudioServer.get_bus_index("Master")
	if bus < 0:
		return
	AudioServer.set_bus_mute(bus, _muted)
	AudioServer.set_bus_volume_db(bus, _volume_db)


## Как звук сейчас — для технической строки. Пусто, когда ничего не трогали:
## строка и без того длинная.
func _volume_note() -> String:
	if _muted:
		return " · звук ВЫКЛ (M)"
	if absf(_volume_db) < 0.5:
		return ""
	return " · звук %+d дБ" % int(_volume_db)


## Полный список клавиш. Живёт под F1 и не занимает экран постоянно: список,
## висящий всегда, перестают читать на второй минуте.
##
## КЛАВИШИ БЕРУТСЯ ИЗ РАСКЛАДКИ, а не пишутся буквами: после переназначения
## справка, говорящая «B — перевязать», врала бы.
func _help_text() -> String:
	var me: Node3D = _world.local_player()
	var lines := PackedStringArray()
	lines.append("[b]В бою[/b]")
	lines.append("%s — движение · %s — бег · %s — прыжок · %s — удар · %s — перевязать" % [
		_keys([&"move_forward", &"move_left", &"move_back", &"move_right"]),
		_k(&"sprint"), _k(&"jump"), _k(&"attack"), _k(&"bandage")])
	if me != null and bool(FACTIONS.mobility_of(int(me.faction))["dash"]):
		lines.append("ЭЛЬФ: второй прыжок в воздухе (%s ещё раз) · %s — рывок" % [
			_k(&"jump"), _k(&"dash")])
	lines.append("оружие: %s" % _keys([&"weapon_1", &"weapon_2", &"weapon_3", &"weapon_4"]))
	if me != null and FACTIONS.has_abilities(me.faction):
		lines.append("заклинания: %s" % _keys([&"ability_1", &"ability_2", &"ability_3"]))
	lines.append("%s — взаимодействие: постройка, груз, лавка, командир, верстак, лошадь" % _k(&"interact"))
	if me != null and int(me.faction) == FACTIONS.Kind.ELVES:
		lines.append("ЭЛЬФ: %s — дом (ещё раз — каменный, ещё раз — снять), ЛКМ — поставить. Дома — места возрождения" % _k(&"build_elf_house"))
	lines.append("%s — вид сверху · %s — первое/третье лицо · %s — в меню · %s — консоль" % [
		_k(&"toggle_camera"), _k(&"toggle_view"), _k(&"leave"), _k(&"console")])
	lines.append("%s — звук · %s и %s — тише и громче · %s — прокачка · Esc — пауза и клавиши" % [
		_k(&"mute"), _k(&"volume_down"), _k(&"volume_up"), _k(&"upgrade")])
	lines.append("Опыт: за донесённую добычу, за убийства, за доехавшие обозы.")
	lines.append("Стрелы и мана КОНЧАЮТСЯ. Стрелы — в лавке, мана копится сама.")
	lines.append("Бег и прыжок тратят выносливость (полоса под здоровьем). Верхом — не тратят.")
	lines.append("")
	lines.append("[b]Сверху — только у злодея и командира стражи[/b]")
	lines.append("%s — камера · %s / %s — поворот · колесо — зум" % [
		_keys([&"move_forward", &"move_left", &"move_back", &"move_right"]),
		_k(&"cam_rotate_left"), _k(&"cam_rotate_right")])
	lines.append("наём, лошади и обоз — у самих построек: подойди и нажми %s" % _k(&"interact"))
	var build := PackedStringArray()
	for pair in BUILD_ACTIONS:
		build.append("%s %s" % [_k(pair[0]), RES.BUILDING_NAMES[int(pair[1])]])
	lines.append("строить: " + " · ".join(build))
	lines.append("Дом дружины поднимает потолок отряда: без домов держишь только охрану.")
	var roles := PackedStringArray()
	for pair in ROLE_ACTIONS:
		roles.append("%s %s" % [_k(pair[0]), LABOURER.ROLE_NAMES[int(pair[1])]])
	lines.append("%s — нанять батрака · роли: %s" % [_k(&"hire_labourer"), " · ".join(roles)])
	lines.append("Поле растит еду само; фермер её уносит на склад — без него поле стоит полным.")
	lines.append("%s — отряд ко мне · %s — отряд с обозом · ПКМ — отряду идти в точку · строй: %s" % [
		_k(&"squad_follow"), _k(&"squad_escort"),
		_keys([&"formation_1", &"formation_2", &"formation_3", &"formation_4"])])
	lines.append("%s — рисовать маршрут обоза, Enter — отправить" % _k(&"route"))
	lines.append("")
	lines.append("[b]Увечья и протезы[/b]")
	lines.append("Оторванную конечность заменяет протез: %s у верстака." % _k(&"interact"))
	lines.append("Некротический протез не покупается — он крафтится из чужих конечностей:")
	lines.append("10 отрубленных рук на руку, 10 ног на ногу, 10 глаз на глаз.")
	lines.append("Счёт трофеев (руки/ноги/глаза) виден слева внизу, когда он не пуст.")
	return "\n".join(lines)


## Клавиша действия по раскладке — для справки и подсказок.
func _k(action: StringName) -> String:
	return KEYMAP.key_text(action)


func _keys(actions: Array) -> String:
	var parts := PackedStringArray()
	for action in actions:
		parts.append(KEYMAP.key_text(action))
	return "/".join(parts)


func _unhandled_input(event: InputEvent) -> void:
	# ВСЕ КЛАВИШИ — ДЕЙСТВИЯ РАСКЛАДКИ (`ui/keymap.gd`), а не зашитые коды. До
	# неё здесь стояли сравнения с KEY_1, KEY_B и так далее, и переназначить их
	# было нельзя в принципе.
	#
	# Пока открыто меню клавиш, оно ловит нажатие само: иначе клавиша, которую
	# человек назначает, заодно и срабатывала бы.
	if _settings != null and _settings.capturing():
		return
	# ПРОКАЧКА. Панель открывается ГДЕ УГОДНО и в любом режиме: опыт — это про
	# самого вожака, а не про место на карте, и гонять игрока к верстаку ради
	# собственных мышц незачем.
	if event.is_action_pressed(&"upgrade") and Net.active and not _console.visible:
		_toggle_upgrade()
		get_viewport().set_input_as_handled()
		return
	# Справка работает в любом режиме: её ищут именно тогда, когда не понимают,
	# где находятся.
	if event.is_action_pressed(&"help") and not _console.visible:
		_hud.toggle_help()
		get_viewport().set_input_as_handled()
		return
	# Громкость. Работает всегда и везде, кроме открытой консоли: сделать тише
	# нужно ровно тогда, когда звук мешает, а не тогда, когда до этого дошли
	# руки.
	if not _console.visible:
		if event.is_action_pressed(&"mute"):
			_muted = not _muted
			_apply_volume()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed(&"volume_down"):
			_volume_db = maxf(VOLUME_FLOOR, _volume_db - VOLUME_STEP)
			_muted = false
			_apply_volume()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed(&"volume_up"):
			_volume_db = minf(VOLUME_CEIL, _volume_db + VOLUME_STEP)
			_muted = false
			_apply_volume()
			get_viewport().set_input_as_handled()
			return
	if Net.active and _world.strategy_mode and not _console.visible and _strategy_key(event):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		# Стройка и прокладка маршрута перехватывают ПКМ раньше — там это отмена.
		if _try_squad_move_order():
			get_viewport().set_input_as_handled()
			return
	# ЗЕЛЬЯ (эльфы, GDD 9a): свои клавиши, из боевого вида.
	if Net.active and not _world.strategy_mode:
		var drinker: Node3D = _world.local_player()
		if drinker != null and event.is_action_pressed(&"potion_heal"):
			drinker.ask_use_potion(0)
			get_viewport().set_input_as_handled()
			return
		if drinker != null and event.is_action_pressed(&"potion_mana"):
			drinker.ask_use_potion(1)
			get_viewport().set_input_as_handled()
			return
	# ДОМ ЭЛЬФОВ (GDD 9a): N — деревянный, ещё раз N — каменный, ещё раз —
	# снять. Строят из боевого вида: вида сверху у эльфов нет.
	if event.is_action_pressed(&"build_elf_house") and Net.active and not _world.strategy_mode:
		var elf: Node3D = _world.local_player()
		if elf != null and int(elf.faction) == FACTIONS.Kind.ELVES:
			var controller: Node3D = _world.build_controller
			if not controller.active:
				_world.set_elf_build(RES.Building.ELF_HOUSE)
			elif int(controller.kind) == RES.Building.ELF_HOUSE:
				_world.set_elf_build(RES.Building.ELF_STONE_HOUSE)
			else:
				_world.set_elf_build(-1)
			get_viewport().set_input_as_handled()
			return
	# Взаимодействие — только из вида от первого лица. Сверху персонажа не видно
	# вовсе, и «нажать E» там значит нажать вслепую: до этого из стратегического
	# режима открывался верстак с протезами, хотя протез ставят себе, а сверху
	# командуют другими. Вдобавок E в этом режиме занята поворотом камеры, и обе
	# работы делались одним нажатием.
	if event.is_action_pressed(&"interact") and Net.active and not _world.strategy_mode:
		# Одна клавиша на всё, с чем можно что-то сделать. Порядок разбора — по
		# близости к руке: груз под ногами важнее лавки за спиной, а лошадь —
		# важнее верстака, до которого ещё идти.
		var me: Node3D = _world.local_player()
		if me != null and me.riding() == null and me.caravan_to_rob() != null:
			me.ask_rob_caravan()
		elif me != null and (me.riding() != null or me.horse_nearby() != null):
			me.ask_mount()
		elif me != null and me.loot_nearby() != null:
			me.ask_collect_loot()
		elif me != null and (me.at_trader() or _trader.visible):
			_toggle_trader()
		elif me != null and (me.at_commander() or me.at_elder() or _commander_ui.visible):
			_toggle_commander()
		elif _building_ui.is_open():
			_building_ui.close_panel()
		elif me != null and me.building_at_hand() != null:
			# Постройка РАНЬШЕ верстака: верстак открывается где угодно, а до
			# постройки надо было дойти. Проигрывать своё место тому, что
			# доступно отовсюду, она не должна.
			_open_building_panel(me)
		else:
			_toggle_bench()
		get_viewport().set_input_as_handled()
		return
	# Тильда открывает консоль. Ловим до всего остального, чтобы она работала
	# и в меню, и в бою.
	if event.is_action_pressed(&"console"):
		_toggle_console()
		get_viewport().set_input_as_handled()
		return
	if _console.visible:
		return
	if event.is_action_pressed(&"toggle_camera") and Net.active:
		_world.toggle_camera_mode()
		# Засчитываем шаг «открой вид сверху» ЗДЕСЬ, а не опросом состояния:
		# игрок успевает открыть и закрыть его между двумя кадрами опроса.
		if _world.strategy_mode:
			_onboarding.note_strategy()
		get_viewport().set_input_as_handled()
		return
	# Первое лицо и третье. В стратегическом режиме молчим: там своя камера, и
	# переключение вида экшена ничего бы не изменило, кроме вида после возврата.
	if event.is_action_pressed(&"toggle_view") and Net.active and not _world.strategy_mode:
		var me: Node3D = _world.local_player()
		if me != null:
			_on_announced("Вид: %s" % ("от первого лица" if me.toggle_view() else "от третьего лица"))
		get_viewport().set_input_as_handled()
		return
	# Esc — меню паузы: продолжить, клавиши, выйти. Раньше Esc только
	# отпускал мышь, и найти, где настраивается управление, было негде.
	if event.is_action_pressed(&"ui_cancel"):
		_toggle_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"leave"):
		if Net.active:
			Net.leave()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and _physical(event) == KEY_F9:
		# Не в раскладке намеренно: это служебная клавиша хоста Steam, а не
		# управление игрой.
		_copy_steam_id()
		get_viewport().set_input_as_handled()


## Клавиши вида сверху. true — нажатие разобрано.
##
## Правило раскладки осталось прежним: цифры подряд отданы постройкам, роли
## батраков идут сразу после последней, фермер — на букве. Но теперь это только
## УМОЛЧАНИЯ: кто хочет иначе, переназначает в меню клавиш.
func _strategy_key(event: InputEvent) -> bool:
	for pair in BUILD_ACTIONS:
		if event.is_action_pressed(pair[0]):
			_world.set_build_mode(true, int(pair[1]))
			return true
	if event.is_action_pressed(&"route"):
		_world.set_route_mode(not _world.route_controller.active)
		return true
	for i in 4:
		if event.is_action_pressed(StringName("formation_%d" % (i + 1))):
			_squad_order("formation", i)
			return true
	if event.is_action_pressed(&"squad_follow"):
		_squad_order("follow", 0)
		return true
	var chief: Node3D = _world.local_player()
	# H — отправить отряд с обозом. Рядом с G («ко мне») намеренно: это две
	# половины одного решения — держать войско при себе или при грузе.
	if event.is_action_pressed(&"squad_escort"):
		if chief != null:
			chief.ask_escort_caravan()
		return true
	if event.is_action_pressed(&"hire_labourer"):
		if chief != null:
			chief.ask_hire_labourer()
		return true
	for pair in ROLE_ACTIONS:
		if event.is_action_pressed(pair[0]):
			if chief != null:
				chief.ask_set_labourer_role(int(pair[1]))
			return true
	return false


## Какое действие ставит какую постройку и какую роль. Порядок — порядок
## карточек в меню стройки и в панели батраков.
const BUILD_ACTIONS := [
	[&"build_storage", 0],
	[&"build_sword", 1],
	[&"build_archer", 2],
	[&"build_stable", 3],
	[&"build_house", 4],
	[&"build_farm", 5],
	[&"build_forge", 8],
]
const ROLE_ACTIONS := [
	[&"role_lumberjack", 0],
	[&"role_miner", 1],
	[&"role_militia", 2],
	[&"role_builder", 3],
	[&"role_farmer", 4],
]


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


## Иконки, полоса запасов и панель команд. Иконки снимаются один раз при
## запуске, пока человек смотрит на главное меню.
func _build_bars() -> void:
	_icons = ICONS.new()
	_icons.name = "Icons"
	add_child(_icons)
	_res_bar = RESOURCE_BAR.new()
	_res_bar.name = "ResourceBar"
	_hud.add_child(_res_bar)
	_res_bar.setup(_world, _icons)
	_res_bar.position = Vector2(_hud.MARGIN, 8.0)
	_res_bar.visible = false
	_command_bar = COMMAND_BAR.new()
	_command_bar.name = "CommandBar"
	_hud.add_child(_command_bar)
	_command_bar.setup(_world, _icons)
	# Привязка к левому низу ОТСТУПАМИ, а не позицией: позиция, заданная после
	# привязки, считалась от верха, и на первом снимке панель висела поверх
	# полосы запасов. Растёт вверх — снизу её держит край экрана.
	_command_bar.anchor_left = 0.0
	_command_bar.anchor_right = 0.0
	_command_bar.anchor_top = 1.0
	_command_bar.anchor_bottom = 1.0
	_command_bar.offset_left = _hud.MARGIN
	_command_bar.offset_top = -_hud.MARGIN
	_command_bar.offset_bottom = -_hud.MARGIN
	_command_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_command_bar.visible = false
	_hotbar = HOTBAR.new()
	_hotbar.name = "Hotbar"
	_hud.add_child(_hotbar)
	_hotbar.setup(_world, _icons)
	# Низ по центру: растёт в обе стороны от середины и вверх от края.
	_hotbar.anchor_left = 0.5
	_hotbar.anchor_right = 0.5
	_hotbar.anchor_top = 1.0
	_hotbar.anchor_bottom = 1.0
	_hotbar.offset_top = -_hud.MARGIN
	_hotbar.offset_bottom = -_hud.MARGIN
	_hotbar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hotbar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hotbar.visible = false
	# Меню паузы должно остаться поверх полос: переносим его в конец.
	$UI.move_child(_settings, -1)
	_dress_panels()
	_icons.changed.connect(_dress_panels)
	_building_ui.icons = _icons


## Картинки на кнопках окон лавки, верстака, прокачки и командира.
##
## Окна собраны в сцене готовыми кнопками, и переделывать их в карточки
## незачем: у кнопки Godot есть своя картинка. Здесь же им общий вид с новыми
## меню — рамка Kenney, тёмные кнопки с золотой обводкой при наведении.
const PANEL_ICONS := {
	"Trader": {"Bandages": "bandage", "Arrows": "arrows", "Gear": "wpn_1",
		"Armor": "armor", "PotionHeal": "potion_heal", "PotionMana": "potion_mana"},
	"Bench": {"Wooden": "res_0", "Iron": "res_3", "Master": "res_2", "Necrotic": "abl_4",
		"Eye": "abl_5", "Splint": "bandage", "Chair": "cart"},
	"Upgrade": {"Stat0": "heart", "Stat1": "stamina", "Stat2": "horse", "Stat3": "mana"},
	"Commander": {"Report": "guard", "Promote": "xp"},
}


func _dress_panels() -> void:
	for window in PANEL_ICONS:
		var panel: PanelContainer = get_node("UI/%s/Panel" % window)
		var frame := STYLE.panel(18.0)
		panel.add_theme_stylebox_override("panel", frame.get_theme_stylebox("panel"))
		frame.free()
		var box: Node = panel.get_node("VBox")
		for child in box.get_children():
			if child is Button:
				var button: Button = child
				var styled := STYLE.button(button.text, 16)
				for state in ["normal", "hover", "pressed", "disabled"]:
					button.add_theme_stylebox_override(state, styled.get_theme_stylebox(state))
				for colour in ["font_color", "font_hover_color", "font_disabled_color"]:
					button.add_theme_color_override(colour, styled.get_theme_color(colour))
				styled.free()
				button.alignment = HORIZONTAL_ALIGNMENT_LEFT
				button.add_theme_constant_override("icon_max_width", 36)
				button.add_theme_constant_override("h_separation", 10)
				var key: String = PANEL_ICONS[window].get(String(button.name), "")
				if key != "":
					button.icon = _icons.icon(key)
			elif child is Label and String(child.name) == "Title":
				child.add_theme_color_override("font_color", STYLE.ACCENT)


## Раз в кадр: полосы и подсветка нехватки.
##
## Подсвечиваем цену того, на что сейчас смотрят: карточка под мышью или
## постройка, которую держат над землёй. Так видно, чего не хватает, ДО того,
## как стройка получит отказ.
func _refresh_bars() -> void:
	if not Net.active:
		_res_bar.visible = false
		_command_bar.visible = false
		_hotbar.visible = false
		_hud.set_prompt_lift(0.0)
		_hud.set_right_lift(0.0)
		return
	_command_bar.refresh()
	_hotbar.refresh()
	var cost: Array = _command_bar.hovered_cost
	if cost.is_empty() and _world.build_controller.active:
		cost = RES.BUILDING_COST[int(_world.build_controller.kind)]
	_res_bar.highlight_shortfall(cost)
	_res_bar.refresh()
	# Строка действия встаёт над тем, что сейчас внизу: сверху это панель
	# команд, в бою — боевая полоса.
	var lift := 0.0
	if _command_bar.visible:
		lift = _command_bar.size.y + 8.0
	elif _hotbar.visible:
		lift = _hotbar.size.y - 30.0
	_hud.set_prompt_lift(maxf(0.0, lift))
	_hud.set_right_lift(_hotbar.size.y + 8.0 if _hotbar.visible else 0.0)


## Меню паузы и клавиш. Кладём ПОСЛЕДНИМ в UI, чтобы оно было поверх всего.
func _build_settings() -> void:
	_settings = PAUSE_MENU.new()
	_settings.name = "Pause"
	$UI.add_child(_settings)
	_settings.resume_requested.connect(_close_pause)
	_settings.leave_requested.connect(func() -> void:
		_close_pause()
		if Net.active:
			Net.leave())
	# Клавиши доступны и из главного меню: настроить управление хотят ДО
	# первой партии, а не посреди неё.
	var keys := STYLE.button("Клавиши", 16)
	keys.name = "KeysBtn"
	keys.pressed.connect(func() -> void: _settings.show_keys(true))
	$UI/Menu/Panel/VBox.add_child(keys)


## Esc: сперва закрыть то, что открыто, и только потом — пауза.
##
## Порядок — от верхнего к нижнему: человек жмёт Esc, чтобы убрать то, что у
## него перед глазами, а не чтобы поверх открытой лавки вылезла ещё и пауза.
func _toggle_pause() -> void:
	if _settings.visible:
		_close_pause()
		return
	if _hud.help_panel.visible:
		_hud.toggle_help()
		return
	if _trader.visible or _bench.visible or _commander_ui.visible:
		_close_others()
		return
	if _upgrade.visible:
		_close_upgrade()
		return
	if _building_ui.is_open():
		_building_ui.close_panel()
		return
	if not Net.active:
		return
	_settings.show_pause()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_pause() -> void:
	_settings.close()
	if Net.active and not _world.strategy_mode and not _any_panel_open():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _any_panel_open() -> bool:
	return (_trader.visible or _bench.visible or _commander_ui.visible
		or _upgrade.visible or _building_ui.is_open())


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


## Продолжить ВЫБРАННУЮ партию. Раньше это было молчаливое «хост всегда грузит
## последний мир», и до других миров добирался только тот, кто знает про ключ
## `--world=ИМЯ`; для всех остальных вторая партия означала потерю первой.
func _on_continue_pressed() -> void:
	_begin_session(_selected_world())


## Имя выбранной в списке партии. Пустая строка — выбирать не из чего.
func _selected_world() -> String:
	var at := _world_opt.selected
	if at < 0 or at >= _saves.size():
		return ""
	return String(_saves[at].get("world", ""))


## Поднять сессию хозяином. `world` пустой — начать новую партию.
##
## Мир ВСЕГДА чистится перед стартом, и это не перестраховка. Человек, вышедший
## в меню и выбравший другую партию, остаётся в том же запущенном процессе: дома
## и батраки прошлой партии стоят где стояли. Загрузка накатывает поверх них
## только то, что записано в файле, — остальное осталось бы чужим наследством, и
## в чужой мир переехали бы и трупы, и обозы, и запас шахты.
func _begin_session(world: String) -> void:
	_set_buttons_enabled(false)
	_world.reset_for_new_game()
	if world.is_empty():
		print("[меню] новая партия в мире %s" % _world.savegame.begin_new_world())
	else:
		_world.savegame.adopt_world(world)
	if not Net.host_game():
		_set_buttons_enabled(true)


## Новая партия. Спрашиваем подтверждение ВТОРЫМ нажатием той же кнопки.
##
## Файл прошлой партии остаётся на диске целым — новая игра заводит новый мир, а
## не стирает старый. Но из меню к прежнему миру уже не вернуться, и для
## человека это неотличимо от потери. Второе нажатие стоит секунды, а промах
## мимо кнопки — кампании.
func _on_new_pressed() -> void:
	if not _new_confirm:
		_new_confirm = true
		_new_btn.text = "Точно? Нажмите ещё раз"
		_status.text = "Прежний мир останется на диске, но из меню к нему не вернуться."
		return
	_reset_new_button()
	_begin_session("")


## Стереть выбранную партию. Насовсем, и потому со вторым нажатием.
##
## Это единственное необратимое действие во всём меню. «Новая игра» и переход в
## другую партию ничего не уничтожают — они меняют имя текущего мира, и всё
## старое остаётся на диске. Здесь возврата нет, и потому переспрашиваем прямо,
## называя партию, которая исчезнет.
func _on_delete_pressed() -> void:
	var world: String = _selected_world()
	if world.is_empty():
		return
	if not _delete_confirm:
		_delete_confirm = true
		_delete_btn.text = "Точно?"
		_status.text = "Партия «%s» будет стёрта с диска насовсем. Нажмите ещё раз." % world
		return
	_reset_delete_button()
	if _world.savegame.delete_world(world):
		_status.text = "Партия «%s» стёрта." % world
	else:
		_status.text = "Стереть «%s» не удалось." % world
	_refresh_save_info()
	_set_buttons_enabled(true)


## Сбросить кнопку «Удалить» из состояния «переспрашиваю».
## Выбор стороны человеком. С этого мгновения подстановка из сейва молчит.
func _on_faction_chosen(index: int) -> void:
	_faction_chosen = true
	Net.chosen_faction = index


func _reset_delete_button() -> void:
	_delete_confirm = false
	_delete_btn.text = "Удалить"


## Сбросить кнопку «Новая игра» из состояния «переспрашиваю».
func _reset_new_button() -> void:
	_new_confirm = false
	_new_btn.text = "Новая игра"


## Собрать список сохранённых партий и подписать выбранную.
##
## Занимается ТОЛЬКО списком и подписью. Доступностью кнопок ведает
## `_set_buttons_enabled` и никто больше: две функции, независимо решающие одно
## и то же, однажды решат по-разному — и «Продолжить» окажется живой посреди
## подключения.
func _refresh_save_info() -> void:
	_saves = _world.savegame.list_saves()
	_world_opt.clear()
	if _saves.is_empty():
		_world_opt.add_item("сохранений нет")
		_world_opt.disabled = true
		_save_info.text = "Сохранений нет — начните новую игру"
		return
	_world_opt.disabled = false
	for entry in _saves:
		# В строке списка — КОГДА и ЗА КОГО, а не имя мира: имя случайное
		# («w865fa1ac»), человеку оно не говорит ничего, а выбирают партию
		# именно по этим двум признакам. Имя нужно только чтобы вернуться к
		# партии ключом --world=, и для этого оно есть в подписи ниже.
		var side := int(entry.get("faction", -1))
		var mark := FACTIONS.name_of(side) if side >= 0 \
			else "мир " + String(entry.get("world", "?"))
		_world_opt.add_item("%s — %s" % [
			_human_time(String(entry.get("at", ""))), mark
		])
	# Свежая партия первой и выбрана по умолчанию: «Продолжить» без единого
	# действия обязана продолжать ту, где человек только что был.
	_world_opt.select(0)
	_on_world_selected(0)


## Выбрали партию в списке: подписываем её и подставляем её сторону.
func _on_world_selected(at: int) -> void:
	# Переспрос снимаем: «Точно?» осталось бы висеть над уже ДРУГОЙ партией, и
	# следующее нажатие стёрло бы не ту.
	_reset_delete_button()
	if at < 0 or at >= _saves.size():
		return
	var info: Dictionary = _saves[at]
	var side := int(info.get("faction", -1))
	# Подставляем прошлую сторону в выбор — ПО УМОЛЧАНИЮ, а не насильно.
	#
	# Без этого подпись обещала «вы играли за Охрану дворца», а выбор рядом
	# показывал «Злодей», и нажавший «Продолжить» садился злодеем. Две надписи
	# об одном, говорящие разное, хуже, чем одна неверная: человек верит той,
	# которую прочитал, и считает игру сломанной.
	#
	# Насильно нельзя: ровно так выбор стороны однажды и перестал работать.
	# Прогресс лежит отдельно по каждой стороне (см. `_player_key`), поэтому
	# продолжить за другую — законно, просто это будет её прогресс.
	# Подставляем сторону из сейва, ТОЛЬКО пока человек не выбрал сам.
	if side >= 0 and not _faction_chosen:
		_faction_opt.select(clampi(side, 0, FACTIONS.COUNT - 1))
		Net.chosen_faction = _faction_opt.selected
	var here := " — сейчас открыта" if String(info.get("world", "")) == _world.savegame.world_id else ""
	_save_info.text = "Мир %s%s" % [info.get("world", "?"), here]


## «2026-08-29T11:54:22» человеку читать незачем.
func _human_time(stamp: String) -> String:
	if stamp.is_empty():
		return "неизвестно когда"
	var parts := stamp.split("T")
	if parts.size() < 2:
		return stamp
	var day := parts[0].split("-")
	if day.size() < 3:
		return stamp
	return "%s.%s.%s в %s" % [day[2], day[1], day[0], parts[1].substr(0, 5)]


func _on_join_pressed() -> void:
	_reset_new_button()
	_set_buttons_enabled(false)
	# Клиенту мир приедет от хозяина, но СВОЙ он должен встретить пустым: иначе
	# в чужую партию подмешаются дома и батраки той, в которую он играл сам.
	_world.reset_for_new_game()
	if not Net.join_game(_ip_edit.text):
		_set_buttons_enabled(true)


func _on_status(text: String) -> void:
	_status.text = text
	print("[net] ", text)
	if not Net.active:
		_set_buttons_enabled(true)


func _on_session_started() -> void:
	_show_menu(false)
	# Подсказку начинаем с первого шага на КАЖДОЙ партии: иначе второй заход
	# открывался бы с конца цепочки, и новый человек за вторым столом остался
	# бы без неё вовсе.
	_onboarding.reset()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_window().title = "ДжваГода — %s (id %d)" % ["ХОСТ" if Net.is_host else "КЛИЕНТ", Net.local_id()]


func _on_session_ended() -> void:
	_show_menu(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_window().title = "ДжваГода"


func _show_menu(visible_now: bool) -> void:
	_menu.visible = visible_now
	# Список СНАЧАЛА, доступность кнопок потом: «Продолжить» жива ровно тогда,
	# когда в списке что-то есть, и обратный порядок гасил бы её на первом
	# показе меню — список к тому моменту ещё пуст.
	if visible_now:
		_reset_new_button()
		_reset_delete_button()
		# Новый показ меню — новый разговор: подсказка про сторону снова уместна.
		_faction_chosen = false
		_refresh_save_info()
	_set_buttons_enabled(true)


func _set_buttons_enabled(enabled: bool) -> void:
	# «Продолжить» гасим ещё и когда продолжать нечего: кнопка, которая ничего
	# не делает, хуже отсутствующей — по ней жмут и решают, что игра сломана.
	_continue_btn.disabled = not enabled or _saves.is_empty()
	_new_btn.disabled = not enabled
	# Стирать нечего — и кнопка не притворяется, что есть.
	_delete_btn.disabled = not enabled or _saves.is_empty()
	_join_btn.disabled = not enabled


## Ключи проверок: ключ → [скрипт инструмента, нужна ли живая сессия].
##
## ТАБЛИЦА, А НЕ ТРИДЦАТЬ ДВА ОДИНАКОВЫХ БЛОКА. Каждый набор добавлялся своей
## пятистрочной копией, и к последнему разбор ключей занимал 239 строк, в
## которых уже ничего нельзя было разглядеть.
##
## И главное: инструмент грузится ПО ИМЕНИ, а не через `preload`. В сборке для
## игроков папки `res://tools/` нет вовсе — её исключает `export_presets.cfg`, —
## а `preload` разрешается при КОМПИЛЯЦИИ: с ним экспортированный скрипт просто
## не собрался бы, потому что файла нет. `load` по отсутствующему пути возвращает
## пусто, ключ молча не срабатывает, и это верно: игроку он не нужен.
const TEST_FLAGS := {
	"--perftest": ["res://tools/perf_test.gd", true],
	"--playerprobe": ["res://tools/player_probe.gd", true],
	"--magictest": ["res://tools/magic_test.gd", true],
	"--weapontest": ["res://tools/weapons_test.gd", true],
	"--sfxtest": ["res://tools/sfx_test.gd", true],
	"--stewardtest": ["res://tools/steward_test.gd", true],
	"--labtest": ["res://tools/labourer_test.gd", true],
	"--navtest": ["res://tools/nav_test.gd", true],
	"--soaktest": ["res://tools/soak_test.gd", true],
	"--netsoaktest": ["res://tools/netsoak_test.gd", true],
	"--herotest": ["res://tools/hero_test.gd", true],
	"--horsetest": ["res://tools/horse_test.gd", true],
	"--warbandtest": ["res://tools/warband_test.gd", true],
	"--garrisontest": ["res://tools/garrison_test.gd", true],
	"--reentrytest": ["res://tools/reentry_test.gd", true],
	"--newgametest": ["res://tools/newgame_test.gd", true],
	"--savetest": ["res://tools/save_test.gd", true],
	"--victorytest": ["res://tools/victory_test.gd", true],
	"--deathtest": ["res://tools/death_test.gd", true],
	"--guardtest": ["res://tools/guard_test.gd", true],
	"--tradetest": ["res://tools/trade_test.gd", true],
	"--elftest": ["res://tools/elf_test.gd", true],
	"--foresttest": ["res://tools/forest_test.gd", true],
	"--consoletest": ["res://tools/console_test.gd", true],
	"--slicetest": ["res://tools/slice_test.gd", true],
	"--squadtest": ["res://tools/squad_test.gd", true],
	"--caravantest": ["res://tools/caravan_test.gd", true],
	"--econtest": ["res://tools/economy_test.gd", true],
	"--woundtest": ["res://tools/wound_test.gd", true],
	"--walktest": ["res://tools/walk_test.gd", true],
	"--combattest": ["res://tools/combat_test.gd", false],
	"--playabletest": ["res://tools/playable_test.gd", true],
	"--onboardingtest": ["res://tools/onboarding_test.gd", true],
	"--ammotest": ["res://tools/ammo_test.gd", true],
	"--progresstest": ["res://tools/progress_test.gd", true],
	"--starttest": ["res://tools/start_test.gd", true],
	"--bootstraptest": ["res://tools/bootstrap_test.gd", true],
	"--minestest": ["res://tools/mines_test.gd", true],
	"--keystest": ["res://tools/keys_test.gd", true],
	"--hudtest": ["res://tools/hud_test.gd", true],
	"--intercepttest": ["res://tools/intercept_test.gd", true],
	"--servicetest": ["res://tools/service_test.gd", true],
	"--endgametest": ["res://tools/endgame_test.gd", true],
	"--elvestest": ["res://tools/elves_test.gd", true],
	"--shoptest": ["res://tools/shop_test.gd", true],
	"--eldertest": ["res://tools/elder_test.gd", true],
	"--elfaitest": ["res://tools/elf_ai_test.gd", true],
	"--aigeartest": ["res://tools/ai_gear_test.gd", true],
	"--longgametest": ["res://tools/long_game_test.gd", true],
	"--villaintoughtest": ["res://tools/villain_guard_test.gd", true],
	"--gradestest": ["res://tools/grades_test.gd", true],
	"--aidefensetest": ["res://tools/ai_defense_test.gd", true],
	"--navdump": ["res://tools/nav_dump.gd", true],
}


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

	# Инструменты проверки — таблицей (см. TEST_FLAGS). В сборке для игроков
	# их нет, и цикл просто ничего не находит.
	for flag in TEST_FLAGS:
		if not args.has(flag):
			continue
		var spec: Array = TEST_FLAGS[flag]
		var tool_node: Node = _start_tool(String(spec[0]))
		if tool_node != null and bool(spec[1]):
			needs_session = true

	for arg in args:
		if arg.begins_with("--faction="):
			var wanted := int(arg.substr("--faction=".length()))
			_faction_opt.select(clampi(wanted, 0, FACTIONS.COUNT - 1))
			Net.chosen_faction = _faction_opt.selected

	for arg in args:
		if arg.begins_with("--shots="):
			_start_screenshots(arg.substr("--shots=".length()))
			needs_session = true
			break

	for arg in args:
		if arg.begins_with("--hudshots="):
			_start_tool_with(arg.substr("--hudshots=".length()), "res://tools/hud_shot.gd")
			needs_session = true
			break

	for arg in args:
		if arg.begins_with("--menushot="):
			# Снимок меню делается БЕЗ сессии: меню видно, только пока её нет.
			# Поэтому и выходим отсюда сразу, не дойдя до --host.
			var menu_script: Script = (load("res://tools/menu_shot.gd")
				if ResourceLoader.exists("res://tools/menu_shot.gd") else null)
			if menu_script != null:
				var shot: Node = menu_script.new()
				add_child(shot)
				shot.start(self, arg.substr("--menushot=".length()))
			return

	for arg in args:
		if arg == "--host":
			_on_continue_pressed()
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
		_on_continue_pressed()


## В стратегическом режиме курсор нужен свободным — им будут отдавать приказы.
## В экшене он захвачен для обзора мышью.
func _on_camera_mode_changed(strategy: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if strategy else Input.MOUSE_MODE_CAPTURED


## Режим съёмки ракурсов: инструмент проверки, к геймплею отношения не имеет.
## Завести инструмент проверки. Пусто — значит это сборка для игроков и папки
## `res://tools/` в ней нет.
func _start_tool(path: String) -> Node:
	if not ResourceLoader.exists(path):
		return null
	var script: Script = load(path)
	if script == null:
		return null
	var node: Node = script.new()
	add_child(node)
	node.start(_world)
	return node


func _start_screenshots(dir: String) -> void:
	var runner: Node = _start_tool_with(dir, "res://tools/screenshotter.gd")
	if runner == null:
		push_warning("Съёмка ракурсов недоступна: это сборка без инструментов.")


## То же, но инструменту нужен ещё и путь.
func _start_tool_with(dir: String, path: String) -> Node:
	if not ResourceLoader.exists(path):
		return null
	var script: Script = load(path)
	if script == null:
		return null
	var node: Node = script.new()
	add_child(node)
	node.start(_world, dir)
	return node


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
		# Слепящее проклятие закрывает половину экрана тем же способом, что и
		# потерянный глаз, — только на таймере (GDD 3.2). Отдельный эффект
		# рисовать незачем: увечье и проклятие ощущаются одинаково, и это верно.
		if me.sync_blind > 0.0:
			lost = maxi(lost, 1)
	_blind_right.visible = lost >= 1
	_blind_left.visible = lost >= 2


## Открыть панель постройки, у которой стоит персонаж.
func _open_building_panel(me: Node3D) -> void:
	var building: Node3D = me.building_at_hand()
	if building == null:
		return
	_close_others()
	_building_ui.open_for(_world, me, building)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Панель постройки закрылась — забираем курсор обратно.
##
## Тем же условием, что у верстака: в стратегическом режиме курсор нужен
## свободным, там им отдают приказы.
func _on_building_panel_closed() -> void:
	if Net.active and not _world.strategy_mode:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Закрыть всё, что могло остаться открытым: два окна поверх друг друга — это
## два набора кнопок, из которых работает верхний, а жмут в нижний.
func _close_others() -> void:
	if _bench.visible:
		_close_bench()
	if _trader.visible:
		_toggle_trader()
	if _commander_ui.visible:
		_toggle_commander()


# --- верстак: протезы и коляска -------------------------------------------

func _toggle_bench() -> void:
	if _bench.visible:
		_close_bench()
		return
	# Сверху верстак не открывается НИКАК.
	#
	# Правило стоит здесь, а не только у клавиши. Сначала я поставил его в
	# обработчике E — и проверка, зовущая `_toggle_bench()` напрямую, открыла
	# панель как ни в чём не бывало. Клавиша не единственный путь сюда, и
	# охранять надо дверь, а не одну из троп к ней.
	#
	# Почему вообще нельзя: протез ставят СЕБЕ, а сверху командуют другими —
	# своего персонажа в этом режиме не видно вовсе.
	if _world.strategy_mode:
		return
	var me: Node3D = _world.local_player()
	if me == null:
		return
	# Панель открывается ГДЕ УГОДНО: деревянный протез крафтится в поле, и без
	# этого раненому пришлось бы ползти через полкарты к верстаку.
	# Кованый и мастерский по-прежнему только у верстака.
	_bench.visible = true
	_refresh_bench(me)


## Наполнить панель верстака. Отдельно от `_toggle_bench`, потому что после
## вправления её надо ПЕРЕРИСОВАТЬ, не закрывая: перебитых костей бывает
## несколько, а `_toggle_bench` на открытой панели её закроет.
func _refresh_bench(me: Node3D) -> void:
	var at_bench: bool = me.at_workbench()
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

	# Некротический не покупается: цена ему — чужие конечности, и на кнопке
	# должно быть видно, сколько своих трофеев уже набрано.
	var arms: int = me.trophies[me.Trophy.ARMS]
	var legs: int = me.trophies[me.Trophy.LEGS]
	var eyes: int = me.trophies[me.Trophy.EYES]
	var necro: Button = box.get_node("Necrotic")
	necro.text = "Некротический — %d чужих рук или ног (есть %d/%d)" % [
		BODY.NECROTIC_PRICE, arms, legs
	]
	necro.disabled = not at_bench or (arms < BODY.NECROTIC_PRICE and legs < BODY.NECROTIC_PRICE)
	# Вправление — отдельной кнопкой и ТОЛЬКО у верстака: перебитое лечит
	# лекарь, а в поле крафтят разве что деревянный протез.
	var splint: Button = box.get_node("Splint")
	var hurt: int = me.body.crippled_count()
	if hurt <= 0:
		splint.text = "Вправлять нечего: перебитых костей нет"
		splint.disabled = true
	else:
		splint.text = "Вправить перебитое (%d шт) — %s за одну" % [
			hurt, RES.format_cost(RES.SPLINT_COST)]
		splint.disabled = not at_bench or not me.stock.can_afford(RES.SPLINT_COST)

	var eye_btn: Button = box.get_node("Eye")
	eye_btn.text = "Некротический глаз — %d чужих глаз (есть %d)" % [BODY.NECROTIC_PRICE, eyes]
	eye_btn.disabled = (not at_bench or eyes < BODY.NECROTIC_PRICE
		or me.body.eyes_missing() <= 0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _toggle_upgrade() -> void:
	if _upgrade.visible:
		_close_upgrade()
		return
	var me: Node3D = _world.local_player()
	if me == null:
		return
	_upgrade.visible = true
	_refresh_upgrade(me)


func _refresh_upgrade(me: Node3D) -> void:
	var box := $UI/Upgrade/Panel/VBox
	box.get_node("Title").text = "Прокачка — опыта %d" % int(me.experience)
	for stat in PROGRESS.COUNT:
		var btn: Button = box.get_node("Stat%d" % stat)
		var level: int = me.level_of(stat)
		var price: int = PROGRESS.cost_of(level)
		if price < 0:
			btn.text = "%s — предел (%d из %d)" % [
				PROGRESS.name_of(stat), level, PROGRESS.MAX_LEVEL]
			btn.disabled = true
			continue
		btn.text = "%s %d/%d — %d опыта" % [
			PROGRESS.name_of(stat), level, PROGRESS.MAX_LEVEL, price]
		btn.disabled = int(me.experience) < price
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_upgrade() -> void:
	_upgrade.visible = false
	if Net.active and not _world.strategy_mode:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Панель НЕ закрывается после покупки: уровней несколько, и закрывать её на
## каждом значило бы жать P пять раз подряд.
func _on_upgrade(stat: int) -> void:
	var me: Node3D = _world.local_player()
	if me == null:
		return
	me.ask_upgrade(stat)
	await get_tree().create_timer(0.25).timeout
	if _upgrade.visible and is_instance_valid(me):
		_refresh_upgrade(me)


func _close_bench() -> void:
	_bench.visible = false
	if Net.active and not _world.strategy_mode:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_bench_prosthetic(tier: int) -> void:
	var me: Node3D = _world.local_player()
	if me != null:
		me.ask_prosthetic(tier)
	_close_bench()


## Вправление НЕ закрывает панель: перебитых костей бывает несколько, и по
## одной за открытие — это шесть подходов к верстаку. Протез закрывает, потому
## что ставится на всё сразу.
func _on_bench_splint() -> void:
	var me: Node3D = _world.local_player()
	if me == null:
		return
	me.ask_splint()
	await get_tree().create_timer(0.25).timeout
	if _bench.visible and is_instance_valid(me):
		_refresh_bench(me)


func _on_bench_eye() -> void:
	var me: Node3D = _world.local_player()
	if me != null:
		me.ask_eye()
	_close_bench()


func _on_bench_chair() -> void:
	var me: Node3D = _world.local_player()
	if me != null:
		me.ask_wheelchair(not me.body.in_wheelchair)
	_close_bench()


## Кто чем занят у злодея. Без этой строки батраки — невидимая механика: они
## работают где-то на карте, а игрок видит только, что ресурсы прибывают.
## Какой клавишей ставится эта роль. Держим ОДНИМ местом с обработчиком: подпись
## уже однажды разошлась с клавишами и показывала 4-7 там, где нажимать надо
## было 5-8.
func _role_key(role: int) -> String:
	for pair in ROLE_ACTIONS:
		if int(pair[1]) == role:
			return _k(pair[0])
	return "?"


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
		parts.append("%s %s (%d)" % [_role_key(role), LABOURER.ROLE_NAMES[role], counts[role]])
	# ГОЛОДНЫХ ВЫНОСИМ В НАЧАЛО СТРОКИ. Это единственное в артели, что требует
	# немедленного решения: остальное можно дочитать, а голод — нет.
	var hungry := 0
	for worker in crew:
		if int(worker.sync_hunger) > 0:
			hungry += 1
	var head := "батраки %d/%d" % [crew.size(), RES.LABOURER_LIMIT]
	if hungry > 0:
		head += "   ГОЛОДНЫХ %d (работают вдвое медленнее, поставь поле — клавиша 6)" % hungry
	var line := head + ": " + "   ".join(parts)
	line += "   |   %s — нанять (%s)" % [_k(&"hire_labourer"), RES.format_cost(RES.LABOURER_COST)]
	if carrying > 0:
		line += "   несут: %d" % carrying

	# Лошади — часть того же хозяйства, и держать их в другом углу экрана значит
	# заставить человека искать. Показываем, только если конюшня уже есть:
	# строка про ноль лошадей у того, кто про них не знает, — это шум.
	var wallet: Node = _world.treasury.of(int(me.faction))
	if wallet != null and (wallet.horses > 0 or _world.stable_of(int(me.faction)) != null):
		line += "\nлошади: %d свободно из %d   в упряжку: %d" % [
			wallet.horses_free(), wallet.horses, int(me.harness_size)
		]
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
			me.ask_train_unit(value == 1)


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
	var swords := 0
	var bows := 0
	for unit in squad:
		if "is_archer" in unit and unit.is_archer:
			bows += 1
		else:
			swords += 1
	# Про наём здесь больше ни слова: нанимают у казарм, а не с этой панели, и
	# подсказка о клавише, которой нет, хуже отсутствия подсказки.
	# Клавиши — из раскладки: строи с 28.09 на F2-F5, и прежняя подпись
	# «F1-F4» звала жать клавишу, которую перехватывала справка.
	return "отряд: %d/%d (мечников %d, лучников %d), %s, %s\nстрой %s · %s — за мной · ПКМ — идти в точку" % [
		squad.size(), _world.squad_capacity(int(me.faction)), swords, bows, stance,
		FORMATIONS.NAMES[clampi(me.squad_formation, 0, FORMATIONS.NAMES.size() - 1)],
		_keys([&"formation_1", &"formation_2", &"formation_3", &"formation_4"]),
		_k(&"squad_follow"),
	]


## Какое оружие на какой клавише у этой стороны.
##
## Раньше подсказка была прибита гвоздями — «1/2/3 меч/лук/шар», — и годилась
## только злодею: у эльфов третьей клавиши не было вовсе. Теперь набор свой у
## каждой стороны (GDD 3.1), и подсказка собирается по нему.
func _weapon_hint(me: Node3D) -> String:
	if me == null:
		return "WASD — движение, Space — прыжок, ЛКМ — удар"
	var parts := PackedStringArray()
	for slot in 4:
		var kind: int = FACTIONS.weapon_on_slot(int(me.faction), slot)
		if kind < 0:
			continue
		var key := str(slot + 1) if slot < 3 else "7"
		var mark := "»" if int(me.sync_weapon) == kind else ""
		parts.append("%s %s%s" % [key, WEAPONS.NAMES[kind], mark])
	return "WASD — движение, Space — прыжок, ЛКМ — удар   |   " + "   ".join(parts)


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
			_world.warband.state_name(faction),
			_world.garrison.size_of(faction),
		])
	if parts.is_empty():
		return ""
	return "\nбез игроков: " + "   ".join(parts)


# --- результат партии ------------------------------------------------------

var _announce_left := 0.0


func _on_announced(text: String) -> void:
	Sfx.flat(Sfx.Kind.NOTICE)
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
	Sfx.flat(Sfx.Kind.NOTICE, -12.0)
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


## Что сейчас наложено на персонажа. Молчит, когда ничего.
##
## Без этой строки паралич выглядит как зависшая игра, а увядание — как
## непонятно откуда взявшаяся слабость. Игрок должен знать, что с ним, и
## сколько это продлится.
func _curse_hint(me: Node3D) -> String:
	var parts := PackedStringArray()
	if me.sync_paralysis > 0.0:
		parts.append("ПАРАЛИЧ %.1f с" % me.sync_paralysis)
	if me.sync_stagger > 0.0:
		parts.append("сбит с ног %.1f с" % me.sync_stagger)
	if me.sync_wither > 0.0:
		parts.append("увядание %.0f с (урон x%.2f)" % [me.sync_wither, ABILITIES.WITHER_DAMAGE_SCALE])
	if me.sync_blind > 0.0:
		parts.append("ослеплён %.0f с" % me.sync_blind)
	if me.casting():
		parts.append("идёт каст — удар по вам его сорвёт")
	if parts.is_empty():
		return ""
	return "\n>>> " + "   ".join(parts)


## Строка способностей друида: что готово, что на откате, сколько держится клич.
## Показываем только тем сторонам, у которых магия поддержки есть (эльфы).
func _abilities_hint(me: Node3D) -> String:
	var parts := PackedStringArray()
	var slot := 0
	for kind in ABILITIES.COUNT:
		if not FACTIONS.allows_ability(me.faction, kind):
			continue
		slot += 1
		var left: float = me.sync_ability_cd[kind]
		if left > 0.0:
			parts.append("%d %s (%.0f с)" % [slot + 3, ABILITIES.name_of(kind), ceil(left)])
		else:
			parts.append("%d %s" % [slot + 3, ABILITIES.name_of(kind)])
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
	var side := int(me.faction)
	var elf := side == FACTIONS.Kind.ELVES
	# Чья лавка, видно прямо здесь. У каждой стороны она своя, и товар в ней
	# свой (GDD 9a): у эльфов травы, зелья, луки и лёгкая броня; у злодея и
	# стражи — бинты, стрелы и латы, чёрные и серебряные.
	box.get_node("Stock").text = "оружие: %s · доспех: %s · лавка стороны «%s»" % [
		me.gear_title(me.gear_tier), RES.armor_name(side, int(me.armor_tier)),
		FACTIONS.name_of(me.trader_faction())]
	box.get_node("Note").text = ("Эльфийская лавка: травы, зелья, луки и лёгкая броня — за золото."
		if elf else "Бинты, стрелы и латы. Оружие закаляют в кузне — за железо и уголь.")
	var sold: Array = RES.SHOP.get(side, [])
	var slots := {"Bandages": RES.Trade.BANDAGES, "Arrows": RES.Trade.ARROWS,
		"Gear": RES.Trade.GEAR, "Armor": RES.Trade.ARMOR,
		"PotionHeal": RES.Trade.POTION_HEAL, "PotionMana": RES.Trade.POTION_MANA}
	for slot in slots:
		box.get_node(slot).visible = int(slots[slot]) in sold

	var bandages: Button = box.get_node("Bandages")
	var herb_name := "Травы" if elf else "Бинты"
	if me.body.bandages >= RES.BANDAGE_LIMIT:
		bandages.text = "%s — сумка полна (%d)" % [herb_name, RES.BANDAGE_LIMIT]
		bandages.disabled = true
	else:
		var cost_b: Array = me.bandage_cost()
		bandages.text = "%s, %d шт — %s" % [herb_name, RES.BANDAGE_PACK, RES.format_cost(cost_b)]
		bandages.disabled = not me.stock.can_afford(cost_b)

	var quiver: Button = box.get_node("Arrows")
	if me.arrows >= RES.QUIVER_LIMIT:
		quiver.text = "Стрелы — колчан полон (%d)" % RES.QUIVER_LIMIT
		quiver.disabled = true
	else:
		var cost_a: Array = me.arrow_price()
		quiver.text = "Стрелы, %d шт (в колчане %d) — %s" % [
			RES.ARROW_PACK, me.arrows, RES.format_cost(cost_a)]
		quiver.disabled = not me.stock.can_afford(cost_a)

	var gear: Button = box.get_node("Gear")
	var cost: Array = me.next_gear_cost()
	if cost.is_empty():
		gear.text = "Эльфийское оружие — лучше нет"
		gear.disabled = true
	else:
		gear.text = "Эльфийское оружие: %s — %s" % [
			me.gear_title(me.gear_tier + 1), RES.format_cost(cost)]
		gear.disabled = not me.stock.can_afford(cost)

	var armor: Button = box.get_node("Armor")
	var armor_cost: Array = me.next_armor_cost()
	if armor_cost.is_empty():
		armor.text = "%s — лучше нет" % RES.armor_name(side, int(me.armor_tier))
		armor.disabled = true
	else:
		armor.text = "%s (урон по тебе x%.2f) — %s" % [
			RES.armor_name(side, int(me.armor_tier) + 1).capitalize(),
			RES.armor_taken(side, int(me.armor_tier) + 1), RES.format_cost(armor_cost)]
		armor.disabled = not me.stock.can_afford(armor_cost)

	for entry in [["PotionHeal", "Зелье лечения", RES.POTION_HEAL_COST, int(me.potions_heal)],
			["PotionMana", "Зелье маны", RES.POTION_MANA_COST, int(me.potions_mana)]]:
		var potion: Button = box.get_node(entry[0])
		if int(entry[3]) >= RES.POTION_LIMIT:
			potion.text = "%s — сумка полна (%d)" % [entry[1], RES.POTION_LIMIT]
			potion.disabled = true
		else:
			potion.text = "%s (есть %d) — %s" % [entry[1], int(entry[3]), RES.format_cost(entry[2])]
			potion.disabled = not me.stock.can_afford(entry[2])


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
	if me == null or not (me.at_commander() or me.at_elder()):
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
	# ЭЛЬФ У СТАРЕЙШИНЫ (GDD 9a): то же окно, свои задания, без командования.
	var title: Label = box.get_node("Title")
	promote.visible = int(me.faction) != FACTIONS.Kind.ELVES
	if int(me.faction) == FACTIONS.Kind.ELVES:
		title.text = "Старейшина"
		_refresh_elder(box, me)
		return
	title.text = "Командир стражи"
	promote.disabled = not _world.commander.can_promote(me)
	if not promote.disabled:
		promote.text = "Принять командование"
	elif not _world.commander.on_duty():
		promote.text = "Распорядитель пал"
	elif me.is_leader:
		promote.text = "Ты уже командир"
	elif int(me.orders_done) < ORDERS.ORDERS_FOR_PROMOTION:
		# Командование заслуживают службой (GDD 9a) — кнопка говорит, сколько
		# осталось, а не просто гаснет.
		promote.text = "Командование — после %d приказов (сдано %d)" % [
			ORDERS.ORDERS_FOR_PROMOTION, int(me.orders_done)]
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


func _refresh_elder(box: Node, me: Node3D) -> void:
	var order: Label = box.get_node("Order")
	var progress: Label = box.get_node("Progress")
	var reward: Label = box.get_node("Reward")
	var report: Button = box.get_node("Report")
	report.disabled = false
	if me.order_kind < 0:
		order.text = "Заданий нет. Поговори, и старейшина скажет, что нужно лесу."
		progress.text = "выполнено заданий: %d" % me.orders_done
		reward.text = ""
		report.text = "Получить задание"
		return
	order.text = "Задание: %s\n%s" % [TASKS.name_of(me.order_kind), TASKS.brief_of(me.order_kind)]
	progress.text = "прогресс: %s   выполнено заданий: %d" % [
		TASKS.progress_text(me.order_kind, me.order_progress), me.orders_done]
	reward.text = "награда: %s" % RES.format_cost(TASKS.reward_of(me.order_kind))
	var ready_now: bool = me.order_progress >= TASKS.target_of(me.order_kind)
	report.text = "Сдать задание" if ready_now else "Сдать (ещё не готово)"


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
