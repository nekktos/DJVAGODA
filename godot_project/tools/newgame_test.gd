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
const DIP := preload("res://scripts/diplomacy.gd")

var _world: Node3D


func start(world: Node3D) -> void:
	tag = "новая игра"
	expected_host = 25
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

	if not multiplayer.get_peers().is_empty():
		await get_tree().create_timer(6.0).timeout
	finish()


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

	# Файл мира стираем НАСИЛЬНО: набор гоняют по многу раз подряд, а прошлый
	# прогон оставляет после себя сейв. Без этого ветка «продолжать нечего»
	# проверялась бы ровно один раз в жизни — на чистой машине, — а дальше
	# молча пропускалась, и сломать её было бы некому заметить.
	DirAccess.remove_absolute(_world.savegame.save_path())
	main._show_menu(true)
	check(main._save_info.text.contains("Сохранений нет"),
		"без сейва меню честно говорит, что продолжать нечего", main._save_info.text)
	check(main._continue_btn.disabled, "и гасит «Продолжить»", "погашена")

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
	wallet.carried.amounts = PackedInt32Array([555, 555, 555, 555])
	wallet.stored.capacity = 4321
	wallet.horses = 11
	_world.diplomacy.values = PackedFloat32Array([99.0, 99.0, 99.0])
	objective.palace_owner = FACTIONS.Kind.VILLAIN
	objective.victors = PackedByteArray([1, 1, 1])
	objective.leader_down = PackedByteArray([1, 1, 1])
	_world.mine.stored = PackedInt32Array([300, 300, 300, 300])
	await get_tree().physics_frame

	var path: String = _world.savegame.save_world()
	check(not path.is_empty(), "нажитое сохранено", path)

	# 2. Меню умеет рассказать, что именно предлагает продолжить.
	var main: Node = get_parent()
	main._show_menu(true)
	check(not main._continue_btn.disabled, "с сейвом «Продолжить» ожила", "доступна")
	check(main._save_info.text.contains(_world.savegame.world_id),
		"и подпись называет мир", main._save_info.text)
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
	check(wallet.carried.amounts == PackedInt32Array(FACTIONS.STARTING_RESOURCES[side]),
		"казна вернулась к стартовой", str(wallet.carried.amounts))
	check(int(wallet.stored.capacity) == 0, "потолок склада обнулён",
		"%d" % int(wallet.stored.capacity))
	check(int(wallet.horses) == int(FACTIONS.STARTING_HORSES.get(side, 0)),
		"лошади вернулись к стартовым", "%d" % int(wallet.horses))
	check(_world.diplomacy.values[0] < 0.0, "вражда пересчитана заново",
		"%.1f вместо 99" % _world.diplomacy.values[0])
	check(int(objective.palace_owner) == FACTIONS.Kind.GUARD
			and objective.victors == PackedByteArray([0, 0, 0])
			and objective.leader_down == PackedByteArray([0, 0, 0]),
		"исход партии снова не решён",
		"дворец у «%s»" % FACTIONS.name_of(int(objective.palace_owner)))
	check(_world.mine.stored == PackedInt32Array([0, 0, 0, 0]), "шахта пуста",
		str(_world.mine.stored))

	# 4. И главное: прошлую партию мы НЕ стёрли. Новая игра заводит новый мир, а
	# не выжигает старый — иначе промах мимо кнопки стоил бы человеку кампании.
	check(_world.savegame.has_save(), "файл прошлой партии цел", _world.savegame.save_path())

	# 5. Персонажа из тела при этом не выбросило.
	check(_world.local_player() != null, "игрок остался в мире", "персонаж на месте")


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
