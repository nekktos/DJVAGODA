extends "res://tools/test_base.gd"
##
## Автопроверка воюющего ИИ (Этап 10, шаг 8, ступень «б»). Работает headless.
##
## Запуск:
##   godot --headless --path godot_project -- --host --faction=0 --warbandtest
##   godot --headless --path godot_project -- --join=127.0.0.1 --faction=1 --warbandtest
##
## Хост берёт злодея, клиент — эльфов: стража остаётся свободной, и именно её
## отряд проверяется. Злодей нужен живым, потому что цели ИИ — вражеское
## имущество, а строит его только злодей.
##
## Проверяем не «ИИ шевелится», а именно то, что отличает ступень «б» от «а»:
## отряд ВЫХОДИТ с базы к цели, идёт СТРОЕМ и меняет его по обстановке, уважает
## перемирие и уходит домой, когда его проредили.
##

const FACTIONS := preload("res://scripts/factions.gd")
const FORMATIONS := preload("res://scripts/units/formations.gd")
const WARBAND := preload("res://scripts/ai/warband.gd")
const GARRISON := preload("res://scripts/ai/garrison.gd")
const RES := preload("res://scripts/economy/resources.gd")

var _world: Node3D
## Свободная сторона, на которой всё проверяется. Считается ОДИН раз: клиент
## отключается, доиграв свою половину, и «первая свободная» посреди прогона
## меняется. На этом прогон один раз уже сломался.
var _side := -1
## Объявления, дошедшие до этого пира. Набег обязан быть слышен: мир начал
## воевать сам, и молча это делать нельзя.
var _heard := PackedStringArray()


func start(world: Node3D) -> void:
	tag = "ИИ-отряд"
	expected_host = 20
	expected_client = 3
	_world = world
	_world.objective.announced.connect(func(text: String) -> void: _heard.append(text))
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
		await _run_client()
		finish()
		return

	_side = _free_faction()
	if _side < 0:
		fail("свободных сторон нет — проверять нечего")
		finish()
		return
	note("проверяем сторону: %s" % FACTIONS.name_of(_side))

	await _test_holds_without_target(me)
	await _test_marches_on_property(me)
	await _test_formations()
	await _test_respects_truce(me)
	await _test_retreats_when_spent()
	# Последней: она создаёт повозку в чужой зоне, и живой отряд, увидев её,
	# бросает всё и идёт туда. Соседние проверки от этого разваливались.
	await _test_ai_caravan_is_a_target()

	if not multiplayer.get_peers().is_empty():
		await get_tree().create_timer(6.0).timeout
	finish()


func _warband() -> Node:
	return _world.warband


func _free_faction() -> int:
	for faction in FACTIONS.COUNT:
		if _world.players_of(faction).is_empty():
			return faction
	return -1


func _band(faction: int) -> Array:
	return _warband()._band(faction)


## Пока бить некого, отряд стоит дома. Это граница со ступенью «а»: ИИ не должен
## бродить по карте просто так.
func _test_holds_without_target(me: Node3D) -> void:
	# Уводим злодея подальше, чтобы он сам не считался целью рядом с базой.
	me.teleport.rpc(Vector3(-300.0, 2.0, 296.0))
	await get_tree().create_timer(5.0).timeout

	var free_side := _side
	check(_band(free_side).size() == GARRISON.SIZE, "отряд свободной стороны в сборе",
		"%s: %d бойцов" % [FACTIONS.name_of(free_side), _band(free_side).size()])

	var base: Vector3 = FACTIONS.SPAWN[free_side]
	var anchor: Vector3 = _warband().anchor_of(free_side)
	check(anchor.distance_to(base) < WARBAND.ARRIVE_RADIUS, "без цели отряд стоит на базе",
		"%.0f м от базы" % anchor.distance_to(base))


## Караван стороны, за которую никто не сел, обязан быть целью набега.
##
## Он создаётся БЕЗ владельца-персонажа (`owner_id` 0), а сторона каравана
## выяснялась по владельцу. Для такого каравана это давало «стороны нет», а
## «стороны нет» отряд не трогает никогда — то есть караваны ИИ не могли стать
## целью вовсе, и две стороны под ИИ не имели друг к другу ни одного повода.
##
## Спрашиваем прямо `_pick_target`: это то самое место, где сторона выяснялась
## неверно, и проверять надо его, а не «набег случился» — набег и так случается
## по постройкам.
func _test_ai_caravan_is_a_target() -> void:
	var enemy := -1
	for faction in FACTIONS.COUNT:
		if faction != _side:
			enemy = faction
			break
	# Убираем постройки: по замыслу они важнее повозки, и пока стоит хоть одна,
	# выбор каравана не проверить вовсе.
	for node in get_tree().get_nodes_in_group("building"):
		if is_instance_valid(node):
			node.queue_free()
	await get_tree().physics_frame
	var base: Vector3 = FACTIONS.SPAWN[_side]
	var spot: Vector3 = base + Vector3(60.0, 0.0, 0.0)
	var caravan: Node3D = _world.spawn_caravan(
		PackedVector3Array([spot, spot + Vector3(20.0, 0.0, 0.0)]), 0, enemy)
	await get_tree().physics_frame
	check(caravan != null and int(caravan.faction) == enemy,
		"караван без владельца знает свою сторону",
		FACTIONS.name_of(enemy) if caravan != null else "не создан")
	if caravan == null:
		return
	var target: Vector3 = _warband()._pick_target(_side)
	var gap := INF
	if target.is_finite():
		gap = Vector2(target.x, target.z).distance_to(
			Vector2(caravan.global_position.x, caravan.global_position.z))
	check(gap < 40.0, "отряд выбирает его целью набега",
		"цель в %.0f м от повозки" % gap if target.is_finite() else "цели нет")
	if is_instance_valid(caravan):
		caravan.queue_free()
	await get_tree().physics_frame


## Появилось вражеское имущество — отряд вышел к нему. Это и есть ступень «б».
func _test_marches_on_property(me: Node3D) -> void:
	var free_side := _side
	var base: Vector3 = FACTIONS.SPAWN[free_side]

	# Склад злодея на полпути между базами: цель, которая не убегает.
	var spot := base.lerp(FACTIONS.SPAWN[int(me.faction)], 0.5)
	spot.y = 0.0
	var storage: Node3D = _world.spawn_building(RES.Building.STORAGE, spot,
		int(me.peer_id), int(me.faction), true)
	await get_tree().physics_frame
	check(storage != null, "цель для набега поставлена", "склад злодея")
	if storage == null:
		return

	# Двадцать секунд, а не восемь. За восемь отряд успевает уйти в обход
	# препятствия боком, и честный обход читается как «не приблизился» — так
	# проверка один раз и упала на ровном месте. Двадцати хватает, чтобы обход
	# кончился, и при этом мало, чтобы дойти до цели в трёхстах метрах: отряд,
	# который просто кружит, провалится наверняка.
	var before: Vector3 = _warband().anchor_of(free_side)
	await get_tree().create_timer(20.0).timeout
	var now: Vector3 = _warband().anchor_of(free_side)

	check(_warband().state_of(free_side) == WARBAND.State.MARCH, "отряд вышел в набег",
		WARBAND.STATE_NAMES[_warband().state_of(free_side)])
	check(now.distance_to(base) > before.distance_to(base) + 5.0, "отряд ушёл от базы",
		"%.0f -> %.0f м от базы" % [before.distance_to(base), now.distance_to(base)])
	check(now.distance_to(spot) < before.distance_to(spot) - 5.0, "и приблизился к цели",
		"%.0f -> %.0f м до склада" % [before.distance_to(spot), now.distance_to(spot)])

	# Бойцы получили приказ и держат строй относительно якоря, а не базы.
	var band := _band(free_side)
	if band.is_empty():
		fail("отряд исчез")
		return
	check(band[0].ai_led, "боец идёт под приказом ИИ", "ai_led=%s" % band[0].ai_led)
	var spread := 0.0
	for unit in band:
		spread = maxf(spread, unit.global_position.distance_to(now))
	check(spread < WARBAND.MARCH_LEASH, "отряд идёт вместе, а не растянулся",
		"дальний боец в %.0f м от якоря" % spread)

	var announced := false
	for text in _heard:
		if text.to_lower().contains("набег"):
			announced = true
	check(announced, "о набеге объявили всем",
		"объявлений %d: %s" % [_heard.size(), ", ".join(_heard)])


## Построение меняется по обстановке — «использует построения» из плана.
func _test_formations() -> void:
	var free_side := _side
	var band := _band(free_side)
	if band.is_empty():
		fail("отряда нет")
		return
	# Сверяем с ТЕКУЩИМ состоянием: по дороге отряд мог принять бой, и это не
	# ошибка, а как раз то, чего мы от него хотим.
	var state: int = _warband().state_of(free_side)
	check(int(band[0].ai_formation) == _warband()._formation_for(state),
		"построение отвечает обстановке",
		"%s: %s" % [WARBAND.STATE_NAMES[state], FORMATIONS.NAMES[int(band[0].ai_formation)]])
	check(_warband()._formation_for(WARBAND.State.MARCH) == FORMATIONS.Kind.COLUMN
			and _warband()._formation_for(WARBAND.State.FIGHT) == FORMATIONS.Kind.LINE
			and _warband()._formation_for(WARBAND.State.HOLD) == FORMATIONS.Kind.SHIELD_WALL,
		"в походе колонна, в бою шеренга, дома стена щитов", "все три")

	# Ставим врага вплотную к якорю: отряд обязан принять бой и развернуться.
	var anchor: Vector3 = _warband().anchor_of(free_side)
	if not anchor.is_finite():
		fail("якоря отряда нет — ставить врага некуда")
		return
	var enemy: Node3D = _world.spawn_garrison_unit(_enemy_of(free_side), 8,
		anchor + Vector3(4.0, 1.0, 0.0), anchor, 60.0)
	await get_tree().create_timer(4.0).timeout
	check(_warband().state_of(free_side) == WARBAND.State.FIGHT, "враг рядом — отряд принял бой",
		WARBAND.STATE_NAMES[_warband().state_of(free_side)])
	band = _band(free_side)
	check(not band.is_empty() and int(band[0].ai_formation) == FORMATIONS.Kind.LINE,
		"и развернулся в шеренгу",
		FORMATIONS.NAMES[int(band[0].ai_formation)] if not band.is_empty() else "отряда нет")
	if is_instance_valid(enemy):
		enemy.queue_free()
	await get_tree().physics_frame


## Перемирие обязано что-то значить и для ИИ: с дружелюбной стороной он не воюет.
func _test_respects_truce(me: Node3D) -> void:
	var free_side := _side
	var villain := int(me.faction)
	var before: bool = _warband()._hostile(free_side, villain)
	check(before, "до перемирия злодей — враг", "враждебен=%s" % before)

	var was: float = _world.diplomacy.value_of(free_side, villain)
	_world.diplomacy.shift(free_side, villain, WARBAND.FRIENDLY_ABOVE - was + 5.0)
	await get_tree().physics_frame
	check(not _warband()._hostile(free_side, villain), "дружелюбную сторону ИИ не трогает",
		"отношения %.0f" % _world.diplomacy.value_of(free_side, villain))

	# Возвращаем как было, иначе следующая проверка останется без целей.
	_world.diplomacy.shift(free_side, villain, was - _world.diplomacy.value_of(free_side, villain))
	await get_tree().physics_frame


## Проредили — отряд уходит домой, а не умирает по одному. И потери в набеге не
## восполняются на ходу: иначе отход не сработал бы ни разу.
func _test_retreats_when_spent() -> void:
	var free_side := _side
	# После перемирия отряд вернулся домой, а решения принимаются раз в
	# THINK_INTERVAL. Дожидаемся, пока он снова выйдет: бить его дома
	# бессмысленно, там пополнение как раз и должно работать.
	# Ждать приходится долго: отняв у отряда цель перемирием, мы отправили его
	# домой, а дорога занимает больше минуты.
	for i in 200:
		if _warband().state_of(free_side) == WARBAND.State.MARCH:
			break
		await get_tree().create_timer(0.5).timeout
	check(_warband().state_of(free_side) == WARBAND.State.MARCH, "отряд снова в набеге",
		WARBAND.STATE_NAMES[_warband().state_of(free_side)])

	var band := _band(free_side)
	var kill: int = band.size() - int(GARRISON.SIZE * WARBAND.RETREAT_FRACTION) + 1
	for i in maxi(kill, 0):
		if i < band.size() and is_instance_valid(band[i]):
			band[i].take_damage(9999.0, 1, "torso", band[i].global_position, Vector3.FORWARD)
	# Ждём дольше, чем шаг гарнизона (CHECK_INTERVAL = 3 с): иначе проверка
	# «не восполняются» прошла бы просто потому, что гарнизон ещё не думал.
	await get_tree().create_timer(4.5).timeout
	var left: int = _band(free_side).size()
	check(left < GARRISON.SIZE, "потери в набеге не восполняются на ходу",
		"в строю %d из %d" % [left, GARRISON.SIZE])

	await get_tree().create_timer(3.0).timeout
	var state: int = _warband().state_of(free_side)
	check(state == WARBAND.State.RETURN or state == WARBAND.State.HOLD,
		"поредевший отряд идёт домой", WARBAND.STATE_NAMES[state])


func _enemy_of(faction: int) -> int:
	for other in FACTIONS.COUNT:
		if other != faction:
			return other
	return 0


## Клиент: походы ИИ он видит как обычных бойцов, и приказы ему не приходят —
## всё решает хост.
func _run_client() -> void:
	await get_tree().create_timer(8.0).timeout
	var seen := 0
	for node in get_tree().get_nodes_in_group("unit"):
		seen += 1
	check(seen > 0, "бойцы ИИ видны клиенту", "%d нод" % seen)

	var announced := false
	for text in _heard:
		if text.to_lower().contains("набег"):
			announced = true
	check(announced, "объявление о набеге доехало до клиента",
		"объявлений %d" % _heard.size())
	check(_world.warband.state_of(0) == 0 and not _world.warband.anchor_of(0).is_finite(),
		"клиент сам ничем не командует", "состояние пустое")

	# Досиживаем до конца половины хоста. Уйдя раньше, клиент освобождает свою
	# сторону, и хост посреди прогона начинает проверять уже другую.
	await get_tree().create_timer(45.0).timeout
