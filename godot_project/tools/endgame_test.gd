extends "res://tools/test_base.gd"
##
## Конец партии: до последней стороны (GDD 9a, ответ автора от 28.09.2026).
##
## Запуск: godot --headless --path godot_project -- --host --faction=0 --endgametest
##
## Решение автора: «Захват дворца злодеем отдаёт ему контроль над всеми землями
## людей и стражу записывает на его сторону, игра продолжается до тех пор, пока
## не останется всего одна сторона».
##
## Набор идёт за злодея: стража и эльфы — под ИИ.
##

const RES := preload("res://scripts/economy/resources.gd")
const FACTIONS := preload("res://scripts/factions.gd")

var _world: Node3D
var _heard: Array[String] = []


func start(world: Node3D) -> void:
	tag = "конец партии"
	expected_host = 7
	expected_client = 1
	_world = world
	_run.call_deferred()


func _run() -> void:
	if not session_ready():
		finish()
		return
	_world.objective.announced.connect(func(text: String) -> void: _heard.append(text))
	await get_tree().create_timer(3.0).timeout
	var me: Node3D = _world.local_player()
	if me == null or int(me.faction) != FACTIONS.Kind.VILLAIN:
		fail("набор должен идти за злодея")
		finish()
		return
	var V := FACTIONS.Kind.VILLAIN
	var G := FACTIONS.Kind.GUARD
	var E := FACTIONS.Kind.ELVES
	var objective: Node3D = _world.objective

	check(FACTIONS.hostile(V, G) and FACTIONS.hostile(E, G) and FACTIONS.hostile(V, E)
			and objective.sides_left() == 3,
		"на старте все три стороны в партии и враждуют",
		"сторон %d" % objective.sides_left())

	var guard_wallet: Node = _world.treasury.of(G)
	var villain_wallet: Node = _world.treasury.of(V)
	var guard_gold: int = int(guard_wallet.get_amount(RES.Kind.GOLD))
	var villain_gold: int = int(villain_wallet.get_amount(RES.Kind.GOLD))
	var guard_buildings: int = _count_buildings(G)

	# Захват дворца злодеем. Путь «встал в точку и дождался» проверяет набор
	# «проходимость» — здесь нужна не дорога, а последствия.
	objective._capture(V)
	await get_tree().create_timer(0.5).timeout

	check(not FACTIONS.hostile(V, G) and FACTIONS.hostile(E, G) and FACTIONS.hostile(E, V),
		"после захвата стража — союзник злодея, эльфы враги обоим",
		"злодей-стража %s, эльфы-стража %s" % [FACTIONS.hostile(V, G), FACTIONS.hostile(E, G)])
	check(guard_buildings > 0 and _count_buildings(G) == 0 and _count_buildings(V) >= guard_buildings,
		"постройки стражи перешли к злодею",
		"у стражи было %d, осталось %d; у злодея %d" % [guard_buildings, _count_buildings(G),
			_count_buildings(V)])
	check(int(villain_wallet.get_amount(RES.Kind.GOLD)) >= villain_gold + guard_gold
			and int(guard_wallet.get_amount(RES.Kind.GOLD)) == 0,
		"казна стражи перешла к злодею",
		"золото злодея %d -> %d, у стражи осталось %d" % [villain_gold,
			int(villain_wallet.get_amount(RES.Kind.GOLD)), int(guard_wallet.get_amount(RES.Kind.GOLD))])

	await get_tree().create_timer(2.5).timeout
	check(int(objective.out[G]) == 1 and int(objective.out[E]) == 0
			and not _heard.any(func(t: String) -> bool: return t.contains("ПОБЕДА")),
		"стража выбыла, но победы нет: эльфы ещё в партии",
		"выбыли %s, объявлено: %s" % [objective.out, " | ".join(_heard)])

	# Эльфов вырезали: снесены все дома и перебиты все эльфы (GDD 9a).
	for house in _world.elf_houses():
		house.take_damage(99999.0, int(me.peer_id), "", house.global_position, Vector3.FORWARD)
	await get_tree().create_timer(0.5).timeout
	for unit in get_tree().get_nodes_in_group("unit"):
		if "faction" in unit and int(unit.faction) == E and float(unit.health) > 0.0:
			unit.take_damage(99999.0, int(me.peer_id), "torso", unit.global_position, Vector3.FORWARD)
	await get_tree().create_timer(3.0).timeout
	var wins: Array = _heard.filter(func(t: String) -> bool: return t.contains("ПОБЕДА"))
	check(int(objective.out[E]) == 1 and wins.size() == 1 and String(wins[0]).contains("Злодей"),
		"осталась одна сторона — объявлена одна победа, злодея",
		"выбыли %s, побед %d: %s" % [objective.out, wins.size(), " | ".join(wins)])
	check(objective.sides_left() == 1, "в партии одна сторона", "сторон %d" % objective.sides_left())
	finish()


func _count_buildings(side: int) -> int:
	var count := 0
	for node in get_tree().get_nodes_in_group("building"):
		if "faction" in node and int(node.faction) == side:
			count += 1
	return count
