extends "res://tools/test_base.gd"
##
## Автопроверка каравана (Этап 5). Работает headless.
##
## Запуск: godot --headless --path godot_project -- --host --caravantest
##
## Проверяем то, ради чего караван в GDD вообще есть: он везёт ресурсы из
## далёкой шахты на склад, едет по НАРИСОВАННОМУ игроком пути и остаётся
## уязвимой целью — разбитый высыпает груз, который может подобрать любой.
##

const RES := preload("res://scripts/economy/resources.gd")
const BUILDER := preload("res://scripts/world_builder.gd")
const FACTIONS := preload("res://scripts/factions.gd")

var _world: Node3D


func start(world: Node3D) -> void:
	tag = "караван-тест"
	expected_host = 28
	expected_client = 1
	_world = world
	_run.call_deferred()

func _caravans(me: Node3D) -> Array:
	return _world.caravans_of(me.peer_id)


func _loot() -> Array:
	return get_tree().get_nodes_in_group("loot")


func _run() -> void:
	await get_tree().create_timer(3.0).timeout
	var me: Node3D = _world.local_player()
	if me == null:
		fail("персонаж не заспавнен")
		finish()
		return

	_test_mine_is_fair_game()
	await _test_needs_storage(me)
	await _build_storage(me)
	_test_route_goes_around(me)
	await _test_enter_key(me)
	await _test_delivery(me)
	await _test_avoids_buildings(me)
	await _test_rides_smoothly(me)
	await _test_raid(me)
	await _test_escort(me)

	finish()


## Шахта стоит там, где её караваны есть кому грабить.
##
## Это ПРАВИЛО КАРТЫ, а не вкусовщина: обозы злодея должны быть добычей для
## эльфов и стражи (GDD раздел 2.3). Со старой шахтой в углу самого злодея обоз
## ехал двести сорок метров по своей же земле — грабить его было негде и некому.
##
## Проверяем ровно два свойства, которыми место и задано: до злодея дальше, чем
## до кого бы то ни было, и до эльфов со стражей одинаково. Число метров тут
## менять можно, свойства — нельзя, и проверка сторожит именно их.
func _test_mine_is_fair_game() -> void:
	var mine := Vector2(BUILDER.MINE_POS.x, BUILDER.MINE_POS.z)
	var villain := _flat(FACTIONS.SPAWN[FACTIONS.Kind.VILLAIN])
	var elves := _flat(FACTIONS.SPAWN[FACTIONS.Kind.ELVES])
	var guard := _flat(FACTIONS.SPAWN[FACTIONS.Kind.GUARD])

	var to_villain: float = mine.distance_to(villain)
	var to_elves: float = mine.distance_to(elves)
	var to_guard: float = mine.distance_to(guard)

	check(to_villain > to_elves and to_villain > to_guard,
		"шахта дальше всего от злодея — ему за ней и ехать",
		"злодей %.0f, эльфы %.0f, стража %.0f" % [to_villain, to_elves, to_guard])
	# Допуск метр: место задано построением, и округление координат до целых
	# метров даёт расхождение меньше метра на четырёхстах.
	check(absf(to_elves - to_guard) < 1.5,
		"и ровно посередине между эльфами и стражей",
		"разница %.2f м" % absf(to_elves - to_guard))
	# И она за пределами карты не оказалась: край мира — шестьсот метров.
	check(absf(mine.x) < BUILDER.WORLD_SIZE * 0.5 - 20.0
			and absf(mine.y) < BUILDER.WORLD_SIZE * 0.5 - 20.0,
		"и не за краем мира", "(%.0f, %.0f)" % [mine.x, mine.y])


func _flat(at: Vector3) -> Vector2:
	return Vector2(at.x, at.z)


func _test_needs_storage(me: Node3D) -> void:
	me.stock.grant([500, 500, 500, 500])
	# Потолок держим выше выданного: иначе карман полон, и проверка «груз с
	# разбитого каравана можно подобрать» падала бы не потому, что подбор сломан,
	# а потому, что подбирать некуда.
	me.stock.set_carried_capacity(2000)
	await get_tree().process_frame
	me.request_send_caravan(PackedVector3Array())
	await get_tree().create_timer(0.5).timeout
	check(_caravans(me).is_empty(), "без достроенного склада караван не отправляется",
		"караванов %d" % _caravans(me).size())


## Ставим склад и ждём, пока он достроится: каравану нужно куда возвращаться.
func _build_storage(me: Node3D) -> void:
	me.request_build(RES.Building.STORAGE, Vector3(-380.0, 0.0, 400.0))
	await get_tree().create_timer(RES.BUILD_TIME[RES.Building.STORAGE] + 1.5).timeout
	check(_world.storage_of(int(me.faction)) != null, "склад достроен и найден",
		"склад %s" % ("есть" if _world.storage_of(int(me.faction)) != null else "нет"))


func _test_delivery(me: Node3D) -> void:
	# Даём шахте накопить.
	_world.mine.stored = RES.fit([0, 0, 200, 200])
	await get_tree().process_frame

	var iron_before: int = me.stock.get_amount(RES.Kind.IRON)
	# Маршрут из одной промежуточной точки: хост сам добавит склад в начало и
	# шахту в конец.
	me.request_send_caravan(PackedVector3Array([Vector3(-430.0, 0.0, 430.0)]))
	await get_tree().create_timer(0.5).timeout
	var sent: bool = _caravans(me).size() == 1
	check(sent, "караван отправлен по нарисованному маршруту", "караванов %d" % _caravans(me).size())
	if not sent:
		return

	# Ждём полный цикл: туда, погрузка, обратно, разгрузка.
	var caravan: Node3D = _caravans(me)[0]
	var loaded := false
	# Запас шахты запоминаем В МОМЕНТ ПОГРУЗКИ, а не в конце круга.
	#
	# Шахта копит сама, полтора железа в секунду, а круг после её переезда на
	# север длится минуты четыре. Проверка «в конце осталось меньше, чем было»
	# мерила не отдачу, а накопление — и упала, показав 278 при исходных 200,
	# хотя обоз честно увёз сто двадцать.
	var mined_at_load := -1
	# Круг стал длинным: шахта уехала на север, до неё девятьсот метров вместо
	# двухсот сорока. Обоз идёт восемь метров в секунду, значит только дорога
	# туда и обратно — почти четыре минуты. Ждём с запасом, иначе набор упадёт не
	# на ошибке, а на секундомере.
	for i in 700:
		await get_tree().create_timer(0.5).timeout
		if not is_instance_valid(caravan):
			break
		if caravan.state == caravan.State.TO_HOME:
			if not loaded:
				mined_at_load = _world.mine.stored[RES.Kind.IRON]
			loaded = true
		if me.stock.get_amount(RES.Kind.IRON) > iron_before:
			break

	check(loaded, "караван погрузился на шахте", "гружёным вышел обратно")
	check(me.stock.get_amount(RES.Kind.IRON) > iron_before,
		"груз доставлен на склад", "железо %d -> %d" % [iron_before, me.stock.get_amount(RES.Kind.IRON)])
	check(mined_at_load >= 0 and mined_at_load < 200,
		"шахта отдала накопленное",
		"в миг погрузки осталось железа %d из 200" % mined_at_load)


## Обоз ЕДЕТ, а не трясётся.
##
## Живой тестер описал это тремя словами: «трясёт, дрожит, прыгает». Прыжки шли
## от того, что высота тянулась к высоте следующей ТОЧКИ МАРШРУТА: точки идут
## через десяток метров, каждая на своей высоте, и цель менялась ступенькой.
## Дрожь — от объезда построек: направление меняется рывками, а разворот
## выставлялся мгновенно.
##
## Проверяем ЗАМЕРОМ ПО КАДРАМ, а не на глаз: копим наибольший скачок высоты и
## разворота между соседними кадрами физики. Глазами тряску видно, но не
## измерить, а значит нельзя и сказать, стало ли лучше.
func _test_rides_smoothly(me: Node3D) -> void:
	for i in 60:
		if _caravans(me).is_empty():
			break
		await get_tree().create_timer(0.5).timeout
	_world.mine.stored = RES.fit([0, 0, 200, 200])
	me.request_send_caravan(PackedVector3Array([Vector3(-430.0, 0.0, 430.0)]))
	await get_tree().create_timer(0.5).timeout
	var list: Array = _caravans(me)
	if list.is_empty():
		fail("обоз для замера тряски не отправлен")
		return
	var cart: Node3D = list[0]

	# Даём отъехать от склада: первые метры он трогается с места, и разворот
	# там меняется по делу, а не от тряски.
	await get_tree().create_timer(2.0).timeout

	var worst_step := 0.0
	var worst_turn := 0.0
	var last_y: float = cart.position.y
	var last_yaw: float = cart.rotation.y
	var frames := 0
	for i in 400:
		await get_tree().physics_frame
		if not is_instance_valid(cart):
			break
		frames += 1
		worst_step = maxf(worst_step, absf(cart.position.y - last_y))
		worst_turn = maxf(worst_turn, absf(angle_difference(cart.rotation.y, last_yaw)))
		last_y = cart.position.y
		last_yaw = cart.rotation.y

	check(frames > 200, "обоз ехал достаточно долго для замера", "%d кадров" % frames)
	# Обоз идёт восемь метров в секунду, кадр — шестидесятая доля: за кадр он
	# проезжает тринадцать сантиметров. Скачок высоты больше четверти метра за
	# кадр — это не склон, это прыжок.
	check(worst_step < 0.25, "высота меняется плавно, без прыжков",
		"наибольший скачок за кадр %.3f м" % worst_step)
	# Разворот: восемь градусов за кадр — это уже рывок руля, а не поворот.
	check(worst_turn < deg_to_rad(8.0), "разворот плавный, без дрожи",
		"наибольший доворот за кадр %.1f°" % rad_to_deg(worst_turn))


## Обоз объезжает постройки, а не проходит сквозь них.
##
## Обоз — единственное, что ездит НЕ характер-телом: Node3D, двигаемый
## прибавлением к позиции. Все остальные упираются в стены сами, а он проезжал
## дома насквозь, и увидеть это можно было только глазами: проверки смотрели,
## ДОШЁЛ ли обоз, и ни одна не смотрела, ГДЕ он ехал.
##
## Дом ставим посреди уже проложенного маршрута — так он заведомо на пути, а не
## рядом с ним. И проверяем ДВЕ вещи, а не одну: что обоз к дому подъехал и что
## не въехал в него. Без первой проверки вторая проходила бы и у обоза, который
## до дома вообще не доехал, — а это самый вероятный способ сломать её случайно.
func _test_avoids_buildings(me: Node3D) -> void:
	# Ждём, пока прошлые обозы уедут: взяв первый попавшийся, мы взяли бы
	# чужой, уже прошедший половину пути, и поставили бы дом ПОЗАДИ него.
	for i in 60:
		if _caravans(me).is_empty():
			break
		await get_tree().create_timer(0.5).timeout
	_world.mine.stored = RES.fit([0, 0, 200, 200])
	me.request_send_caravan(PackedVector3Array([Vector3(-430.0, 0.0, 430.0)]))
	await get_tree().create_timer(0.5).timeout
	var list: Array = _caravans(me)
	if list.is_empty():
		fail("обоз для проверки объезда не отправлен")
		return
	var caravan: Node3D = list[0]

	var route: PackedVector3Array = caravan.route
	var spot := Vector3.ZERO
	for i in range(1, route.size()):
		var mid: Vector3 = (route[i - 1] + route[i]) * 0.5
		if mid.distance_to(caravan.position) > 30.0:
			spot = mid
			break
	if spot == Vector3.ZERO:
		fail("маршрут слишком короткий, ставить дом некуда")
		return
	spot.y = 0.0
	# Ставим ТРИ казармы поперёк дороги, а не одну.
	#
	# С одной проверка проходила и с ВЫКЛЮЧЕННЫМ объездом: дом четырнадцать
	# метров шириной, а точки маршрута идут через пятнадцать, и обозу хватало
	# пропустить одну точку, чтобы прицелиться уже за домом и промахнуться мимо
	# него по прямой. Проверка охраняла пропуск точек, а не объезд — и молчала бы
	# о сломанном объезде ровно до первого тестера.
	#
	# Три казармы дают стену метров в сорок пять: обогнуть её пропуском точек
	# нельзя, только рулём.
	var kind: int = RES.Building.SWORD_BARRACKS
	var size: Vector3 = RES.BUILDING_SIZE[kind]
	var along: Vector3 = (route[route.size() - 1] - route[0])
	along.y = 0.0
	var across: Vector3 = Vector3(-along.z, 0.0, along.x).normalized() * (size.x + 1.0)
	var wall: Array = []
	for step in [-1.0, 0.0, 1.0]:
		wall.append(_world.spawn_building(kind, spot + across * step, 0, int(me.faction), true))

	var nearest := 9999.0
	var deepest := 9999.0
	for i in 900:
		await get_tree().physics_frame
		if not is_instance_valid(caravan):
			break
		nearest = minf(nearest, caravan.position.distance_to(spot))
		deepest = minf(deepest, _gap_to_any_building(caravan.position))
		if caravan.state == caravan.State.TO_HOME:
			break

	check(nearest < 30.0, "обоз доехал до поставленной на пути постройки",
		"подошёл на %.1f м" % nearest)
	check(deepest > 0.0, "и НЕ въехал в неё",
		"ближе всего был на %.1f м от стены" % deepest)

	# Убираем за собой: стена из трёх казарм поперёк дороги и обоз, который её
	# объезжает, — это декорация ЭТОЙ проверки. Оставленные, они достаются
	# следующей: та отправляет свой обоз тем же коридором, он идёт в объезд
	# дольше обычного, и проверка падает на секундомере в другом конце файла.
	# Один раз так и вышло, и искал я это не там.
	for node in wall:
		if is_instance_valid(node):
			node.free()
	# Обоз убираем ВМЕСТЕ С ВОЗВРАТОМ ЛОШАДЕЙ. Просто снести ноду мало: лошади
	# числятся уведёнными у стороны, а не у обоза, и снесённый обоз уносит их с
	# собой навсегда. Следующая проверка тогда падает на «караван не отправился»
	# — и выглядит это как поломка отправки, хотя сломана уборка.
	for node in _caravans(me):
		var team: int = int(node.horses) if "horses" in node else 0
		node.free()
		_world._on_caravan_home(team, int(me.faction))
	await get_tree().physics_frame


## Ближайшая стена ЛЮБОЙ постройки. Отрицательное — внутри.
##
## Меряем по всем, а не по одной поставленной. Первая версия смотрела только на
## среднюю казарму из трёх — и проверка проходила с выключенным объездом: обоз
## аккуратно обходил ту, за которой следили, и ехал сквозь соседнюю.
func _gap_to_any_building(at: Vector3) -> float:
	var worst := 9999.0
	for node in get_tree().get_nodes_in_group("building"):
		if not is_instance_valid(node):
			continue
		# Склад — конец маршрута, к нему обоз обязан подъехать вплотную и даже
		# заехать: его в счёт не берём.
		if int(node.kind) == RES.Building.STORAGE:
			continue
		var size: Vector3 = RES.BUILDING_SIZE[int(node.kind)]
		worst = minf(worst, _outside_by(at, node.position, size))
	return worst


## На сколько метров точка снаружи коробки. Отрицательное — внутри.
func _outside_by(at: Vector3, box_at: Vector3, size: Vector3) -> float:
	var dx: float = absf(at.x - box_at.x) - size.x * 0.5
	var dz: float = absf(at.z - box_at.z) - size.z * 0.5
	if dx <= 0.0 and dz <= 0.0:
		return maxf(dx, dz)
	return Vector2(maxf(dx, 0.0), maxf(dz, 0.0)).length()


func _test_raid(me: Node3D) -> void:
	_world.mine.stored = RES.fit([0, 0, 200, 200])
	me.request_send_caravan(PackedVector3Array([Vector3(-430.0, 0.0, 430.0)]))
	await get_tree().create_timer(0.5).timeout
	if _caravans(me).is_empty():
		check(false, "караван для перехвата отправлен", "не отправился")
		return
	var caravan: Node3D = _caravans(me)[0]

	# Ждём, пока он загрузится и повезёт груз — грабить пустой смысла нет.
	# Долго: до шахты девятьсот метров, это две минуты хода в одну сторону.
	for i in 400:
		await get_tree().create_timer(0.5).timeout
		if not is_instance_valid(caravan):
			break
		if caravan.state == caravan.State.TO_HOME:
			break
	if not is_instance_valid(caravan) or caravan.state != caravan.State.TO_HOME:
		check(false, "караван вышел с грузом", "не дождались")
		return

	var carried := 0
	for value in caravan.cargo:
		carried += value
	check(carried > 0, "караван везёт груз", "единиц %d" % carried)

	var loot_before: int = _loot().size()
	var point: Vector3 = caravan.global_position
	# Разбиваем: караван — уязвимая цель по GDD.
	caravan.take_damage(9999.0, 2, "cargo", point, Vector3.FORWARD)
	await get_tree().create_timer(0.6).timeout
	check(_loot().size() > loot_before, "разбитый караван высыпал груз",
		"куч на земле %d" % _loot().size())

	# Подбирает любой, кто подошёл.
	if _loot().is_empty():
		return
	var pile: Node3D = _loot()[0]
	me.global_position = pile.global_position + Vector3(0.0, 1.0, 1.0)
	me.sync_position = me.global_position
	await get_tree().create_timer(0.3).timeout
	var before: int = me.stock.get_amount(RES.Kind.GOLD)
	me.request_collect_loot()
	await get_tree().create_timer(0.3).timeout
	check(me.stock.get_amount(RES.Kind.GOLD) > before, "груз подобран с земли",
		"золото %d -> %d" % [before, me.stock.get_amount(RES.Kind.GOLD)])


## Отправка каравана ЧЕРЕЗ КЛАВИШУ, а не вызовом хостовой функции напрямую.
##
## Это дыра, которую вскрыл живой тестер: все прежние проверки дёргали
## request_send_caravan сами и потому не замечали, доходит ли до неё нажатие
## Нарисованный маршрут прокладывается ПО КАРТЕ, а не по прямой.
##
## Точки игрока остаются его решением и все посещаются — меняется только то, как
## караван идёт между ними. Проверяем длину против прямой: караван, срезающий
## сквозь гору, дал бы ровно прямую, и отличить его от исправного иначе нельзя.
func _test_route_goes_around(me: Node3D) -> void:
	var from: Vector3 = FACTIONS.SPAWN[FACTIONS.Kind.VILLAIN]
	var to: Vector3 = FACTIONS.SPAWN[FACTIONS.Kind.GUARD]
	var drawn := PackedVector3Array([from, to])
	var walked: PackedVector3Array = _world._walkable_route(drawn)

	check(walked.size() > drawn.size(), "маршрут развернулся в путь по карте",
		"%d точек из %d нарисованных" % [walked.size(), drawn.size()])
	var straight: float = from.distance_to(to)
	var length := 0.0
	for i in range(1, walked.size()):
		length += walked[i - 1].distance_to(walked[i])
	check(length > straight * 1.05, "и он длиннее прямой — значит что-то обходит",
		"%.0f м против %.0f по прямой" % [length, straight])


## Enter. У тестера маршрут рисовался, а караван не выезжал — и ни одна
## автопроверка этого не видела.
func _test_enter_key(me: Node3D) -> void:
	_world.set_strategy_mode(true)
	_world.set_route_mode(true)
	await get_tree().process_frame
	check(_world.route_controller.active, "режим прокладки маршрута включился",
		"active=%s" % _world.route_controller.active)

	# Воспроизводим то, что делал живой тестер: инструкция для playtest велит
	# сверяться через консоль, значит консоль открывалась и закрывалась. Поле
	# ввода консоли — LineEdit, и если после закрытия оно удержало фокус, все
	# нажатия Enter уходят в него, а не в игру.
	var main := _world.get_parent()
	main._toggle_console()
	await get_tree().process_frame
	main._toggle_console()
	await get_tree().process_frame
	var focused: Control = get_viewport().gui_get_focus_owner()
	note("фокус после закрытия консоли: %s" % ("нет" if focused == null else focused.name))
	check(focused == null, "закрытая консоль отпустила фокус",
		"фокус у %s" % ("никого" if focused == null else focused.name))

	var before: int = _caravans(me).size()

	var press := InputEventKey.new()
	press.keycode = KEY_ENTER
	press.pressed = true
	Input.parse_input_event(press)
	await get_tree().process_frame
	await get_tree().process_frame

	check(not _world.route_controller.active, "Enter закрыл режим прокладки",
		"active=%s" % _world.route_controller.active)
	check(_caravans(me).size() > before, "Enter отправил караван",
		"караванов %d -> %d" % [before, _caravans(me).size()])

	# Убираем за собой: следующая проверка считает караваны штучно, и лишний
	# из этой проверки ломал бы её.
	for caravan in _caravans(me):
		caravan.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	_world.set_strategy_mode(false)
	await get_tree().process_frame


## Охрана каравана: приставленный боец едет с повозкой и её поводок движется
## вместе с ней (GDD, решение по ходу шага 8).
##
## Проверяем не «охрана назначена», а то, ради чего она нужна: что боец
## СЛЕДУЕТ за грузом. Назначение без следования — украшение.
func _test_escort(me: Node3D) -> void:
	var world := _world
	var start: Vector3 = me.global_position + Vector3(0.0, 0.0, 20.0)
	var far: Vector3 = start + Vector3(140.0, 0.0, 0.0)
	var cart: Node3D = world.spawn_caravan(PackedVector3Array([start, far]),
		int(me.peer_id), int(me.faction))
	await get_tree().physics_frame
	if cart == null:
		fail("повозку для проверки охраны создать не удалось")
		return

	var guard: Node3D = world.spawn_garrison_unit(int(me.faction), 7,
		start + Vector3(3.0, 0.5, 0.0), start, 40.0)
	await get_tree().physics_frame
	if guard == null:
		fail("бойца для охраны создать не удалось")
		if is_instance_valid(cart):
			cart.queue_free()
		return

	check(cart.add_guard(guard), "бойца приставили к повозке", "принят")
	check(not cart.add_guard(guard), "дважды одного не приставить", "отклонён")
	check(cart.guards() == 1, "охрана считается", "%d" % cart.guards())
	check(is_equal_approx(guard.leash, cart.GUARD_LEASH),
		"поводок охраны стал коротким",
		"%.0f м" % guard.leash)

	# Едем и смотрим, что дом охраны уехал вместе с повозкой: именно он и держит
	# бойца при грузе.
	var home_before: Vector3 = guard.home
	await get_tree().create_timer(3.0).timeout
	var moved: float = home_before.distance_to(guard.home) if is_instance_valid(guard) else 0.0
	check(moved > 3.0, "дом охраны едет вместе с повозкой",
		"сместился на %.0f м" % moved)

	if is_instance_valid(guard):
		guard.queue_free()
	if is_instance_valid(cart):
		cart.queue_free()
	await get_tree().physics_frame
