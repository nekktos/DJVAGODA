extends "res://tools/test_base.gd"
##
## Автопроверка «Новой игры» из главного меню (Этап 10, шаг 5, GDD раздел 6).
## Работает headless.
##
## ЗАЧЕМ ОТДЕЛЬНЫЙ НАБОР. Нового файла мира для новой партии мало. Выйдя в меню
## и нажав «Новая игра», человек остаётся в том же запущенном процессе: дома,
## батраки, казна, отношения и объявленная победа никуда не делись. «Новая
## игра», начинающаяся с чужой отстроенной базой, — это обман, и заметить его
## можно только сыграв дважды подряд, не выходя из программы. Автоматика ловит
## это за секунды, человек — за полчаса и только если додумается проверить.
##
## Запуск:
##   godot --headless --path godot_project -- --host --faction=0 --newgametest
##

const FACTIONS := preload("res://scripts/factions.gd")
const RES := preload("res://scripts/economy/resources.gd")

var _world: Node3D


func start(world: Node3D) -> void:
	tag = "новая игра"
	expected_host = 47
	expected_client = 1
	_world = world
	_run.call_deferred()


func _run() -> void:
	await get_tree().create_timer(3.0).timeout
	if not session_ready():
		finish()
		return
	var me: Node3D = _world.local_player()
	if me == null:
		fail("персонаж не заспавнен")
		finish()
		return

	if not Net.hosting():
		# Клиенту тут проверять нечего: «новую игру» начинает хозяин сессии, а
		# клиент просто окажется в новом мире. Одна проверка нужна, чтобы набор
		# не молчал о том, что клиентская половина вообще запускалась.
		check(_world.local_player() != null, "клиент в мире", "персонаж есть")
		finish()
		return

	_test_menu()
	await _test_reset(me)
	_test_world_id_guard()
	_test_load_other_world()
	_test_delete_world()
	_test_choice_survives()
	_test_panel_returns_cursor(me)

	if not multiplayer.get_peers().is_empty():
		await get_tree().create_timer(6.0).timeout
	# Заморозку проверяем ПОСЛЕДНЕЙ и после ожидания клиента: она на полторы
	# секунды останавливает синхронизаторы, и клиент, ещё делающий свою
	# проверку, увидел бы застывшую картину мира и решил, что она разъехалась.
	await _test_frozen_world()
	finish()


## Имена партий, которые меню сейчас предлагает. Спрашиваем ДАННЫЕ, а не
## надписи: в надписи стоит «когда и за кого», имени мира там нет и быть не
## должно — оно случайное и человеку ничего не говорит.
func _listed_ids(main: Node) -> PackedStringArray:
	var ids := PackedStringArray()
	for entry in main._saves:
		ids.append(String(entry.get("world", "")))
	return ids


## Что сейчас НАПИСАНО в списке, одной строкой.
func _listed(main: Node) -> String:
	var parts := PackedStringArray()
	for i in main._world_opt.item_count:
		parts.append(main._world_opt.get_item_text(i))
	return " | ".join(parts)


## Само меню: две кнопки, подпись под ними и переспрос.
##
## Проверять надо именно ЗДЕСЬ, а не глазами на снимке. Кнопка, подписанная
## «Продолжить», но не подключённая ни к чему, выглядит на снимке ровно так же,
## как рабочая, — а узнают об этом, когда её нажмёт живой человек.
##
## Сессию мы не поднимаем заново: «Новую игру» жмём ОДИН раз и смотрим, что она
## переспросила, а не начала. Второе нажатие — это уже новая сессия, и её
## проверяет `_test_reset`, доставая до того же кода напрямую.
func _test_menu() -> void:
	var main: Node = get_parent()
	check(main.has_method("_on_continue_pressed") and main.has_method("_on_new_pressed"),
		"обе кнопки главного меню подключены", "«Продолжить» и «Новая игра»")

	# Свой файл мира стираем НАСИЛЬНО: набор гоняют по многу раз подряд, а
	# прошлый прогон оставляет после себя сейв. Без этого проверка «стёртой
	# партии в списке нет» сходилась бы сама собой ровно один раз в жизни, на
	# чистой машине, а дальше пропускала бы что угодно.
	DirAccess.remove_absolute(_world.savegame.save_path())
	main._show_menu(true)
	check(not _listed_ids(main).has(_world.savegame.world_id),
		"стёртой партии в списке нет", " ".join(_listed_ids(main)))

	# Ветку «продолжать нечего» проверяем НАПРЯМУЮ, а не пустой папкой: в
	# user://saves лежат файлы всех остальных наборов, и «ни одного сохранения»
	# на этой машине не бывает никогда. Опустошаем список и спрашиваем меню.
	var kept: Array = main._saves
	main._saves = []
	main._set_buttons_enabled(true)
	check(main._continue_btn.disabled, "без единой партии «Продолжить» погашена",
		"погашена" if main._continue_btn.disabled else "жива")
	check(main._selected_world().is_empty(), "и продолжать нечего",
		"«%s»" % main._selected_world())
	main._saves = kept
	main._set_buttons_enabled(true)

	# Первое нажатие «Новой игры» обязано ПЕРЕСПРОСИТЬ, а не начать.
	main._on_new_pressed()
	check(main._new_confirm, "первое нажатие «Новой игры» переспрашивает", "ждёт второго")
	check(main._new_btn.text != "Новая игра", "и кнопка это показывает", main._new_btn.text)
	check(Net.hosting(), "но игру заново не начало", "сессия та же")

	# Возврат в меню снимает переспрос: иначе человек, вышедший и вернувшийся,
	# начал бы новую партию одним нажатием, думая, что первое ещё впереди.
	main._show_menu(true)
	check(not main._new_confirm and main._new_btn.text == "Новая игра",
		"возврат в меню снимает переспрос", main._new_btn.text)
	main._show_menu(false)


## Нажили сколько смогли — и потребовали, чтобы новая партия про это не знала.
func _test_reset(me: Node3D) -> void:
	var side: int = int(me.faction)
	var wallet: Node = _world.treasury.of(side)
	var objective: Node = _world.objective

	# 1. Наживаем: дом, батраки, чужая казна, вражда, объявленная победа,
	# полная шахта. Каждое из этого переезжало бы в новую партию.
	_world.spawn_building(RES.Building.STORAGE, Vector3(120.0, 0.0, -40.0), 1, side, true)
	_world.spawn_labourer(side, Vector3(121.0, 0.5, -40.0), Vector3(120.0, 0.0, -40.0), 0)
	_world.spawn_labourer(side, Vector3(119.0, 0.5, -40.0), Vector3(120.0, 0.0, -40.0), 2)
	wallet.carried.amounts = RES.fit([555, 555, 555, 555])
	wallet.stored.capacity = 4321
	wallet.horses = 11
	objective.palace_owner = FACTIONS.Kind.VILLAIN
	objective.victors = PackedByteArray([1, 1, 1])
	objective.leader_down = PackedByteArray([1, 1, 1])
	_world.mine.stored = RES.fit([300, 300, 300, 300])
	await get_tree().physics_frame

	var path: String = _world.savegame.save_world()
	check(not path.is_empty(), "нажитое сохранено", path)

	# 2. Меню умеет рассказать, что именно предлагает продолжить.
	var main: Node = get_parent()
	# Сбиваем выбор стороны НАМЕРЕННО на чужую: иначе проверка ниже сойдётся
	# сама собой — сторона проверки и сторона по умолчанию в меню совпадают, и
	# «подставилось» было бы неотличимо от «так и стояло».
	main._faction_opt.select((side + 1) % FACTIONS.COUNT)
	main._show_menu(true)
	check(not main._continue_btn.disabled, "с сейвом «Продолжить» ожила", "доступна")
	check(_listed_ids(main).has(_world.savegame.world_id),
		"и наша партия появилась в списке", " ".join(_listed_ids(main)))
	check(main._save_info.text.contains("сейчас открыта"),
		"и отмечена как открытая сейчас", main._save_info.text)
	# Надпись в списке — то, по чему человек выбирает: когда и за кого.
	check(main._world_opt.get_item_text(0).contains("Злодей"),
		"в списке видно, за кого была партия", main._world_opt.get_item_text(0))
	# Подпись обещала «вы играли за X» — выбор рядом обязан показывать то же
	# самое. Две надписи об одном, говорящие разное, хуже одной неверной.
	check(main._faction_opt.selected == side, "и выбор стороны подставлен из сейва",
		FACTIONS.name_of(main._faction_opt.selected))
	main._show_menu(false)

	var info: Dictionary = _world.savegame.save_summary()
	check(not info.is_empty(), "меню видит сохранение", str(info.get("world", "—")))
	check(String(info.get("world", "")) == _world.savegame.world_id,
		"подпись про ТОТ мир", String(info.get("world", "")))
	check(not String(info.get("at", "")).is_empty(), "в подписи есть время",
		String(info.get("at", "")))
	check(int(info.get("faction", -1)) == side, "в подписи есть сторона",
		FACTIONS.name_of(int(info.get("faction", -1))))

	# 3. Начинаем заново.
	_world.reset_for_new_game()
	await get_tree().physics_frame

	check(get_tree().get_nodes_in_group("building").is_empty(), "ПОСТРОЙКИ снесены",
		"%d осталось" % get_tree().get_nodes_in_group("building").size())
	check(_world.labourers_of(side).is_empty(), "БАТРАКИ распущены",
		"%d осталось" % _world.labourers_of(side).size())
	check(wallet.carried.amounts == RES.fit(FACTIONS.STARTING_RESOURCES[side]),
		"казна вернулась к стартовой", str(wallet.carried.amounts))
	check(int(wallet.stored.capacity) == 0, "потолок склада обнулён",
		"%d" % int(wallet.stored.capacity))
	check(int(wallet.horses) == int(FACTIONS.STARTING_HORSES.get(side, 0)),
		"лошади вернулись к стартовым", "%d" % int(wallet.horses))
	check(int(objective.palace_owner) == FACTIONS.Kind.GUARD
			and objective.victors == PackedByteArray([0, 0, 0])
			and objective.leader_down == PackedByteArray([0, 0, 0]),
		"исход партии снова не решён",
		"дворец у «%s»" % FACTIONS.name_of(int(objective.palace_owner)))
	check(_world.mine.stored == RES.fit([0, 0, 0, 0]), "шахта пуста",
		str(_world.mine.stored))

	# 4. И главное: прошлую партию мы НЕ стёрли. Новая игра заводит новый мир, а
	# не выжигает старый — иначе промах мимо кнопки стоил бы человеку кампании.
	check(_world.savegame.has_save(), "файл прошлой партии цел", _world.savegame.save_path())

	# 5. Персонажа из тела при этом не выбросило.
	check(_world.local_player() != null, "игрок остался в мире", "персонаж на месте")


## Удаление партии — единственное необратимое действие в меню.
##
## Проверяем ТРИ вещи, и все три обязательны. Что первое нажатие переспрашивает,
## а не стирает: без переспроса промах мышью стоит кампании. Что второе стирает
## по-настоящему — и файла на диске нет, а не только строки в списке. И что мир
## из ключа `--world=` не стирается вовсе: под набором проверок это выдернуло бы
## файл, с которым он сам и работает.
func _test_delete_world() -> void:
	var main: Node = get_parent()
	var mine: String = _world.savegame.world_id

	# Заводим партию НА СНОС, а не сносим свою: своя нужна проверкам после.
	_world.savegame._world_from_cmdline = false
	var doomed := mine + "-doomed"
	_world.savegame.adopt_world(doomed)
	_world.savegame.save_world()
	_world.savegame.adopt_world(mine)
	main._show_menu(true)
	check(_listed_ids(main).has(doomed), "партия на снос заведена и видна",
		" ".join(_listed_ids(main)))

	# Выбираем её в списке и жмём «Удалить» ОДИН раз.
	var at: int = Array(_listed_ids(main)).find(doomed)
	main._world_opt.select(at)
	main._on_world_selected(at)
	main._on_delete_pressed()
	check(main._delete_confirm, "первое нажатие переспрашивает", main._delete_btn.text)
	check(_world.savegame.list_saves().size() > 0
			and _listed_ids(main).has(doomed),
		"и ничего ещё не стёрло", " ".join(_listed_ids(main)))

	# Второе — стирает.
	main._on_delete_pressed()
	check(not main._delete_confirm, "второе нажатие сняло переспрос", main._delete_btn.text)
	check(not _listed_ids(main).has(doomed), "ПАРТИЯ стёрта из списка",
		" ".join(_listed_ids(main)))
	var gone := true
	for entry in _world.savegame.list_saves():
		if String(entry.get("world", "")) == doomed:
			gone = false
	check(gone, "и файла на диске больше нет", "проверено по списку файлов")

	# А свой мир из ключа не стирается вовсе.
	_world.savegame._world_from_cmdline = true
	check(not _world.savegame.delete_world(mine), "мир из ключа --world= не стирается",
		mine)
	main._show_menu(false)


## ВЫБОР СТОРОНЫ ПЕРЕЖИВАЕТ возню со списком партий.
##
## Живой отчёт: «при начале новой игры за стражу или эльфов появляешься в форте
## злодея». Причина — подстановка стороны из сейва: она задумывалась подсказкой
## и молча перебивала выбор, стоило тронуть список партий после выбора стороны.
## Человек жал «Охрану дворца», начинал новую игру и оказывался злодеем.
##
## Выбор, который игра отменяет за спиной, хуже отсутствия выбора.
func _test_choice_survives() -> void:
	var main: Node = get_parent()
	main._show_menu(true)
	# Выбираем сторону ЧЕЛОВЕКОМ — тем же путём, что и мышью по списку.
	#
	# Мышь делает ДВА дела: переставляет сам список и шлёт сигнал. Позвав только
	# обработчик, я проверил бы половину и получил бы провал на собственной
	# небрежности — так и вышло с первого раза.
	var want: int = (int(_world.local_player().faction) + 1) % FACTIONS.COUNT
	main._faction_opt.select(want)
	main._on_faction_chosen(want)
	check(int(Net.chosen_faction) == want, "сторона выбрана человеком",
		FACTIONS.name_of(int(Net.chosen_faction)))

	# А теперь трогаем список партий — то самое действие, которое всё ломало.
	main._on_world_selected(0)
	check(int(Net.chosen_faction) == want,
		"ВЫБОР СТОРОНЫ пережил возню со списком партий",
		"хотели «%s», осталось «%s»" % [
			FACTIONS.name_of(want), FACTIONS.name_of(int(Net.chosen_faction))])
	check(main._faction_opt.selected == want, "и в самом списке сторон он же",
		FACTIONS.name_of(main._faction_opt.selected))

	# Новый показ меню — новый разговор: подсказка снова уместна.
	main._show_menu(true)
	check(not main._faction_chosen, "возврат в меню снимает пометку «выбрано»",
		"пометка снята")
	main._show_menu(false)


## Панель постройки ВОЗВРАЩАЕТ курсор, когда закрывается.
##
## Живой отчёт: «не работает управление». Панель отпускала курсор при открытии и
## не забирала при закрытии, а `_gather_input` при свободном курсоре возвращает
## ноль движения — управление умирало насовсем, до первого другого окна.
##
## Проверяем ПРОВОДКУ, а не сам курсор: headless режим мыши не держит вовсе, и
## проверка по `Input.mouse_mode` была бы зелёной при любой поломке.
func _test_panel_returns_cursor(me: Node3D) -> void:
	var main: Node = get_parent()
	check(main._building_ui.closed.is_connected(main._on_building_panel_closed),
		"закрытие панели постройки кому-то сообщается",
		"подписан главный узел")

	var told := [false]
	var probe := func() -> void: told[0] = true
	main._building_ui.closed.connect(probe)
	var house: Node3D = _world.spawn_building(
		RES.Building.STABLE, me.global_position + Vector3(0.0, 0.0, 9.0),
		int(me.peer_id), int(me.faction), true)
	main._building_ui.open_for(_world, me, house)
	main._building_ui.close_panel()
	main._building_ui.closed.disconnect(probe)
	check(told[0], "и оно ДЕЙСТВИТЕЛЬНО сообщается при закрытии",
		"сигнал пришёл" if told[0] else "сигнала нет")
	if is_instance_valid(house):
		house.free()


## Пока человек в меню, мир СТОИТ.
##
## Мир лежит в главной сцене с самого старта, и «лежит» молча превратилось в
## «живёт»: шахта копила запас, отношения дрейфовали, ИИ строил дома — всё это
## до того, как кто-нибудь нажал кнопку. Партия начиналась не с начала, а с того
## места, до которого мир дошёл сам, пока его никто не видел.
##
## Проверяем шахтой: она копит быстрее всех и ровно, три камня в секунду. Если
## за полторы секунды остановленного мира в ней прибавилось хоть что-то, значит
## мир идёт — а вместе с ним идёт и всё остальное.
func _test_frozen_world() -> void:
	_world.mine.stored = RES.fit([0, 0, 0, 0])
	_world._set_running(false)
	await get_tree().create_timer(1.5).timeout
	var frozen: PackedInt32Array = _world.mine.stored.duplicate()
	check(frozen == RES.fit([0, 0, 0, 0]), "в меню мир СТОИТ", str(frozen))

	# И обратно: остановленный навсегда мир — это не игра, а картинка.
	_world._set_running(true)
	await get_tree().create_timer(1.5).timeout
	check(_world.mine.stored != frozen, "а с началом партии идёт",
		str(_world.mine.stored))


## Мир, заданный ключом `--world=ИМЯ`, «новой игрой» не подменяется.
##
## Это не мелочь: наборы проверок работают каждый в своём файле, и подмена имени
## под ними увела бы проверку сохранений в пустой мир — а упала бы она где-то
## совсем в другом месте.
func _test_world_id_guard() -> void:
	var before: String = _world.savegame.world_id
	var after: String = _world.savegame.begin_new_world()
	check(after == before, "мир из ключа --world= не подменяется",
		"%s остался %s" % [before, after])
	check(not _world.savegame.adopt_world(before + "-другой"),
		"и загрузкой из меню тоже не уводится", _world.savegame.world_id)


## Загрузка ДРУГОЙ партии — то, ради чего в меню появился список.
##
## Замок `--world=` снимаем НАМЕРЕННО и на два вызова. Без этого проверить
## переход нечем: набор работает в мире, заданном ключом, а ключ на то и стоит,
## чтобы мир под набором не менялся. Замок — не предмет проверки здесь, его
## проверяет `_test_world_id_guard`; здесь проверяется то, что он охраняет.
##
## Соседнюю партию заводим сами, а не ищем на диске: файлов от других наборов
## там сколько угодно, но полагаться на них — значит проверять чужой мусор.
func _test_load_other_world() -> void:
	var main: Node = get_parent()
	var mine: String = _world.savegame.world_id
	var other := mine + "-second"
	_world.savegame._world_from_cmdline = false

	check(_world.savegame.adopt_world(other) and _world.savegame.world_id == other,
		"перешли в другую партию", "%s → %s" % [mine, _world.savegame.world_id])
	_world.savegame.save_world()
	check(_world.savegame.adopt_world(mine) and _world.savegame.world_id == mine,
		"и вернулись в свою", _world.savegame.world_id)

	# И соседка обязана быть видна в списке меню: партия, о которой знает файл,
	# но не знает меню, для человека не существует.
	main._show_menu(true)
	check(_listed_ids(main).has(other), "соседняя партия видна в списке",
		" ".join(_listed_ids(main)))
	main._show_menu(false)
	_world.savegame._world_from_cmdline = true
