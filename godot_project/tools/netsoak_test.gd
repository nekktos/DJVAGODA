extends "res://tools/test_base.gd"
##
## Автопроверка СОГЛАСИЯ ПИРОВ под нагрузкой (Этап 10, шаг 9). Работает headless.
##
## Запуск:
##   godot --headless --path godot_project -- --host --faction=0 --netsoaktest
##   godot --headless --path godot_project -- --join=127.0.0.1 --faction=1 --netsoaktest
##
## Хост берёт злодея, клиент — эльфов: стража остаётся свободной, и полторы
## минуты в мире сам по себе живёт ИИ — держит гарнизон, ходит в набеги.
##
## ЗАЧЕМ ЭТОТ НАБОР. Главное правило проекта — клиент считает своё движение,
## всё остальное считает хост, — ломается МОЛЧА. Ошибка прав не роняет игру и
## не пишет в лог: она просто разводит картины мира на пирах, и заметить это
## можно только сравнив их между собой. Ни один из прежних наборов этого не
## делал: `slice` смотрит, доехало ли до клиента одно конкретное событие, а не
## совпадают ли миры вообще.
##
## Поэтому хост в конце прогона шлёт клиенту ПЕРЕПИСЬ — сколько построек, кто
## владеет дворцом, сколько бойцов у свободной стороны, — а клиент сверяет её
## со своей. Постройки и владелец сверяются точно: они не мельтешат. Бойцы —
## с допуском, потому что перепись у пиров снимается не в один и тот же кадр, а
## между кадрами кто-то успевает погибнуть.
##
## Ещё проверяем то, чего не видно ни в одном другом наборе: не отвалился ли
## клиент за полторы минуты сам по себе, и нет ли в мире тел с невозможными
## координатами. Второе — не выдумка: якорь строя однажды получил бесконечность,
## она разошлась по расталкиванию, и лог за прогон вырос до тридцати девяти
## мегабайт.
##

const FACTIONS := preload("res://scripts/factions.gd")
const RES := preload("res://scripts/economy/resources.gd")

## Сколько варится мир. Полторы минуты — это дольше, чем живёт любой из прежних
## сетевых наборов, и достаточно, чтобы ИИ успел выйти в набег и вернуться.
const RUN_SECONDS := 90.0
const SAMPLE := 5.0

## Насколько может разойтись число бойцов. Перепись у пиров снимается не в один
## кадр; двое — это запас на смерть и подкрепление между ними.
const UNITS_TOLERANCE := 2

## Сколько клиент ждёт перепись сверх прогона.
const CENSUS_WAIT := 60.0

## Сколько хост ждёт клиента, прежде чем что-то решать.
const PEER_WAIT := 45.0

var _world: Node3D
var _census := {}
var _got_census := false


func start(world: Node3D) -> void:
	tag = "сеть-варка"
	# Имя обязано совпадать на пирах: перепись идёт вызовом по СЕТИ, а он ищет
	# ноду по пути. Без явного имени Godot назовёт её "@Node@12", у каждого
	# пира по-своему, и вызов молча не дойдёт.
	name = "NetSoakTest"
	expected_host = 7
	expected_client = 5
	_world = world
	_run.call_deferred()


func _run() -> void:
	await get_tree().create_timer(3.0).timeout
	if not session_ready():
		finish()
		return
	if Net.hosting():
		await _run_host()
	else:
		await _run_client()
	finish()


# --- хост -------------------------------------------------------------------

func _run_host() -> void:
	# СНАЧАЛА дожидаемся клиента, и только потом решаем, какая сторона
	# свободна. Иначе выходит так: хост считает свободным злодея, клиент через
	# несколько секунд садится за злодея, гарнизон распускается — и набор до
	# конца прогона проверяет сторону, которая давно занята живым игроком.
	# Ровно на этом однажды сломался и набор ИИ-отряда.
	var waited := 0.0
	while multiplayer.get_peers().is_empty() and waited < PEER_WAIT:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
	check(multiplayer.get_peers().size() == 1, "клиент подключён",
		"пиров: %d, ждали %.1f с" % [multiplayer.get_peers().size(), waited])
	# Стороне надо дать долететь: слот выдаётся не в тот же кадр, что вход.
	await get_tree().create_timer(2.0).timeout

	var free_side := _free_faction()
	if free_side < 0:
		fail("свободных сторон нет — вариться нечему")
		return
	note("свободная сторона: %s" % FACTIONS.name_of(free_side))

	# Ставим постройки САМИ. Без этого в мире стоит одна коробка, и сверять
	# переписи бессмысленно: «у меня одна, у хоста одна» сойдётся и при
	# наглухо сломанной репликации. Одну из них потом сносим — исчезновение
	# доезжает до клиента другим путём, чем появление, и ломается отдельно.
	var me: Node3D = _world.local_player()
	if me == null:
		fail("персонаж не заспавнен")
		return
	var base: Vector3 = FACTIONS.SPAWN[int(me.faction)]
	var made: Array[Node3D] = []
	for i in 3:
		var spot := base + Vector3(30.0 + 18.0 * float(i), 0.0, 30.0)
		spot.y = 0.0
		var box: Node3D = _world.spawn_building(RES.Building.STORAGE, spot,
			int(me.peer_id), int(me.faction), true)
		if box != null:
			made.append(box)
	await get_tree().physics_frame
	check(made.size() == 3, "хост поставил постройки для сверки",
		"поставлено %d из 3" % made.size())

	var broken := 0
	var lowest := 1 << 30
	var elapsed := 0.0
	while elapsed < RUN_SECONDS:
		await get_tree().create_timer(SAMPLE).timeout
		elapsed += SAMPLE
		broken += _broken_positions()
		lowest = mini(lowest, _units().size())
		# На середине сносим одну: клиент обязан увидеть, что её не стало.
		if is_equal_approx(elapsed, RUN_SECONDS * 0.5) and not made.is_empty():
			var doomed: Node3D = made.pop_back()
			if is_instance_valid(doomed):
				doomed.queue_free()
			note("снесли одну постройку на %.0f-й секунде" % elapsed)

	check(multiplayer.get_peers().size() == 1, "клиент не отвалился за прогон",
		"пиров осталось: %d" % multiplayer.get_peers().size())
	check(lowest > 0, "мир ни разу не опустел",
		"меньше всего бойцов за прогон: %d" % lowest)
	check(broken == 0, "ни одного тела в невозможной точке",
		"замеров с бесконечностью: %d" % broken)
	check(_world.warband._band(free_side).size() > 0,
		"у свободной стороны остался отряд",
		"бойцов: %d" % _world.warband._band(free_side).size())

	var census := {
		"buildings": _buildings().size(),
		"palace": int(_world.objective.palace_owner),
		"side": free_side,
		"band": _units_of(free_side),
	}
	note("перепись хоста: построек %d, дворец у %s, бойцов свободной стороны %d"
		% [census["buildings"], FACTIONS.name_of(census["palace"]), census["band"]])
	receive_census.rpc(census)
	check(not multiplayer.get_peers().is_empty(), "перепись отправлена клиенту",
		"адресатов: %d" % multiplayer.get_peers().size())
	# Клиенту нужно время дочитать перепись и досчитать своё.
	await get_tree().create_timer(10.0).timeout


# --- клиент -----------------------------------------------------------------

func _run_client() -> void:
	var waited := 0.0
	while not _got_census and waited < RUN_SECONDS + CENSUS_WAIT:
		await get_tree().create_timer(1.0).timeout
		waited += 1.0
	check(_got_census, "перепись от хоста дошла", "ждали %.0f с" % waited)
	if not _got_census:
		# Без переписи сверять не с чем, но остальные проверки обязаны
		# выполниться: иначе счётчик решит, что клиент просто не отработал.
		check(false, "построек столько же, сколько у хоста", "переписи нет")
		check(false, "дворцом владеет тот же", "переписи нет")
		check(false, "бойцы свободной стороны видны", "переписи нет")
		check(_broken_positions() == 0, "ни одного тела в невозможной точке",
			"тел с бесконечностью: %d" % _broken_positions())
		return

	var side: int = int(_census.get("side", -1))
	var mine: int = _buildings().size()
	check(mine == int(_census["buildings"]),
		"построек столько же, сколько у хоста",
		"у меня %d, у хоста %d" % [mine, int(_census["buildings"])])
	check(int(_world.objective.palace_owner) == int(_census["palace"]),
		"дворцом владеет тот же",
		FACTIONS.name_of(int(_world.objective.palace_owner)))
	var band: int = _units_of(side)
	check(absi(band - int(_census["band"])) <= UNITS_TOLERANCE,
		"бойцы свободной стороны видны и в том же числе",
		"у меня %d, у хоста %d" % [band, int(_census["band"])])
	check(_broken_positions() == 0, "ни одного тела в невозможной точке",
		"тел с бесконечностью: %d" % _broken_positions())


## Перепись мира от хоста. Считать её клиент не может и не должен: числа
## принадлежат хосту, клиент только сверяет со своими.
@rpc("authority", "call_remote", "reliable")
func receive_census(census: Dictionary) -> void:
	_census = census
	_got_census = true


# --- общее ------------------------------------------------------------------

func _free_faction() -> int:
	for faction in FACTIONS.COUNT:
		if _world.players_of(faction).is_empty():
			return faction
	return -1


func _units() -> Array:
	return get_tree().get_nodes_in_group("unit")


func _buildings() -> Array:
	return get_tree().get_nodes_in_group("building")


func _units_of(faction: int) -> int:
	var count := 0
	for unit in _units():
		if "faction" in unit and int(unit.faction) == faction:
			count += 1
	return count


## Сколько тел стоит в невозможной точке. Считаем и бойцов, и постройки: NaN
## расходится по расталкиванию и по строю, и поймать его надо там, где он
## появился, а не там, где он всё уронил.
func _broken_positions() -> int:
	var bad := 0
	for node in _units() + _buildings():
		var body := node as Node3D
		if body != null and not body.global_position.is_finite():
			bad += 1
	return bad
