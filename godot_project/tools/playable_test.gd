extends "res://tools/test_base.gd"
##
## Проходимость: может ли ОДИНОЧНЫЙ игрок этой стороны дойти до своей победы.
##
## Запуск: godot --headless --path godot_project -- --host --faction=N --playabletest
##
## ЗАЧЕМ ОТДЕЛЬНЫЙ НАБОР, КОГДА ИХ УЖЕ ТРИДЦАТЬ. Все остальные проверяют, что
## система РАБОТАЕТ: караван доезжает, урон доходит, дворец захватывается. Ни
## один не спрашивает, может ли человек ДОБРАТЬСЯ до этих систем с пустыми
## руками. На этом и умер playtest-1: тестер бросил игру на пятнадцатой минуте,
## упёршись в три стены — караван не выезжал, железо было неоткуда взять, а во
## дворец нельзя было войти, потому что у него не было дверей. Все три системы
## при этом были «сделаны» и покрыты зелёными проверками.
##
## Поэтому здесь проверяется не работа, а ДОСТИЖИМОСТЬ: дойти ногами, купить на
## имеющееся, выполнить условие победы. Цепочка рвётся в первом же месте, и
## именно это место и есть отчёт.
##
## ЧЕГО ЭТОТ НАБОР НЕ ЗАМЕНЯЕТ. Он не знает, интересно ли играть, понятно ли,
## что делать, и в какую минуту становится скучно. Это спрашивают у человека
## (`PLAYTEST_FORM.md`), и подменить его машиной нельзя — можно только не
## тратить его время на стены, которые машина находит за минуту.
##

const FACTIONS := preload("res://scripts/factions.gd")
const RES := preload("res://scripts/economy/resources.gd")
const WEAPONS := preload("res://scripts/combat/weapons.gd")
const OBJECTIVE := preload("res://scripts/objective.gd")
const WORLD_BUILDER := preload("res://scripts/world_builder.gd")

## Насколько близко к цели должен подвести путь, чтобы считать её достижимой.
##
## Число взято не с потолка: караван считает точку достигнутой с трёх метров
## (`caravan.gd::WAYPOINT_REACH`), лавка отвечает с TRADER_RANGE. Берём вдвое
## больше самого строгого: путь кладёт последнюю точку на край сетки, и
## упереться в стену вплотную — это всё-таки «дошёл».
const ARRIVED := 6.0

## Насколько близко считается «подошёл к постройке».
##
## У сплошного строения центр НЕДОСТИЖИМ по определению: шахта — глыба
## пятьдесят метров в поперечнике, вход — коробка шесть метров толщиной, и
## навигация честно останавливается у стены. Требовать шесть метров до центра
## значит ругаться на габарит, а не на дыру в мире.
const NEAR_STRUCTURE := 12.0

var _world: Node3D
var _side := 0


func start(world: Node3D) -> void:
	tag = "проходимость"
	expected_host = 8
	expected_client = 1
	_world = world
	_run.call_deferred()


func _run() -> void:
	if not session_ready():
		finish()
		return
	await get_tree().create_timer(3.0).timeout
	var me: Node3D = _world.local_player()
	if me == null:
		fail("персонаж не заспавнен")
		finish()
		return
	_side = int(me.faction)
	print("[проходимость] сторона: %s" % FACTIONS.name_of(_side))

	_test_victory_reachable(me)
	_test_landmarks_reachable(me)
	_test_first_purchase_affordable()
	await _test_iron_has_a_source(me)
	finish()


## Условие победы достижимо НОГАМИ.
##
## Блокер playtest-1: «во дворец нельзя зайти — нет дверей», и злодей физически
## не мог победить, даже делая всё правильно. Проверка спрашивает ровно это:
## ведёт ли навигация от спавна стороны к точке захвата.
func _test_victory_reachable(me: Node3D) -> void:
	var from: Vector3 = me.global_position
	var palace: Vector3 = OBJECTIVE.PALACE
	# Порог берём У ИГРЫ: захват засчитывается в радиусе RADIUS от центра
	# дворца, и дойти ровно в точку не нужно — внутрь стен достаточно. Свой
	# порог в шесть метров был строже самой игры и ругался бы на исправное.
	var gap: float = _walk_gap(from, palace)
	_trace("спавн -> дворец", from, palace)
	_trace("спавн -> форт злодея", from, FACTIONS.SPAWN[FACTIONS.Kind.VILLAIN])
	_trace("спавн -> двор стражи", from, FACTIONS.SPAWN[FACTIONS.Kind.GUARD])
	_trace("спавн -> центр карты", from, Vector3(0.0, 0.0, 0.0))
	# Складывается ли путь из двух половин? Проверено: да, складывается, но
	# целиком не ищется. Трассы оставлены НАМЕРЕННО — по ним видно, что
	# короткие маршруты доходят, а длинные обрываются, и с них начнёт тот, кто
	# возьмётся чинить.
	var yard: Vector3 = FACTIONS.SPAWN[FACTIONS.Kind.GUARD]
	_trace("двор стражи -> дворец", yard, palace)
	_trace("двор стражи -> спавн эльфа", yard, from)
	# ВЫСОТА В ТРАССЕ НЕ ДЛЯ КРАСОТЫ. Именно она показала, что эльф выходит на
	# плато по поверхности y = 9.1, а двор и дворец лежат на y = 6.9: сетка
	# рвётся на ступеньке в 2.2 м при пределе подъёма 0.5. Без высоты видно
	# только «не дошёл», и искать можно долго.
	_trace("эльф -> точка перед воротами", from, Vector3(300.0, 6.0, -265.0))
	_trace("эльф -> плато у кромки", from, Vector3(300.0, 6.0, -130.0))
	# А не в самом ли спавне дело? Деревня эльфов стоит на сваях, и если
	# персонаж привязан к настилу, поиск пути начнётся с отдельного островка.
	for z in [-150.0, -170.0, -200.0, -240.0, -280.0]:
		_trace("эльф -> за стену z=%.0f" % z, from, Vector3(300.0, 6.0, z))
	_trace("середина -> дворец", Vector3(0.0, 0.0, -200.0), palace)
	check(gap >= 0.0 and gap < OBJECTIVE.RADIUS,
		"до дворца можно дойти ногами и встать на точку захвата",
		"не дошёл %.1f м" % gap if gap >= 0.0 else "пути нет вовсе")

	# И обратно: если человек погиб, он возвращается на базу и идёт снова.
	var back: float = _walk_gap(palace, FACTIONS.SPAWN[_side])
	check(back >= 0.0 and back < ARRIVED,
		"от дворца можно вернуться на свою базу",
		"не дошёл %.1f м" % back if back >= 0.0 else "пути нет вовсе")


## Места, без которых сторона не играет, достижимы.
func _test_landmarks_reachable(me: Node3D) -> void:
	var from: Vector3 = me.global_position

	var bench: float = _walk_gap(from, _world.workbench_position())
	check(bench >= 0.0 and bench < ARRIVED,
		"до верстака (протезы и коляска) можно дойти",
		"не дошёл %.1f м" % bench if bench >= 0.0 else "пути нет вовсе")

	var trader: float = _walk_gap(from, _world.trader_position())
	check(trader >= 0.0 and trader < ARRIVED,
		"до лавки можно дойти",
		"не дошёл %.1f м" % trader if trader >= 0.0 else "пути нет вовсе")


## На стартовые ресурсы можно сделать ПЕРВЫЙ шаг, а не только смотреть на цены.
##
## У стороны без стройки шаг другой — покупка в лавке, — но он тоже обязан быть
## по карману: сторона, которой нечего сделать в первую минуту, стоит на месте.
func _test_first_purchase_affordable() -> void:
	var start: Array = FACTIONS.STARTING_RESOURCES[_side]
	if FACTIONS.can_build(_side):
		var cost: Array = RES.BUILDING_COST[RES.Building.STORAGE]
		var enough := true
		var missing := PackedStringArray()
		for kind in RES.COUNT:
			if int(start[kind]) < int(cost[kind]):
				enough = false
				missing.append("%s не хватает %d" % [
					RES.SHORT[kind], int(cost[kind]) - int(start[kind])])
		check(enough, "на стартовые ресурсы хватает на первую постройку",
			"склад по карману" if enough else ", ".join(missing))
	else:
		# У ЭЛЬФОВ НА СТАРТЕ НОЛЬ, И ЭТО ЗАМЫСЕЛ, А НЕ ПОЛОМКА: по GDD они живут
		# грабежом, а начинают с топора и леса. Первый заход требовал у них
		# золота и честно «нашёл» блокер там, где его нет, — проверка считала
		# единственным началом покупку в лавке.
		var can_harvest := false
		for slot in 4:
			var kind: int = FACTIONS.weapon_on_slot(_side, slot)
			if kind == WEAPONS.Kind.AXE or kind == WEAPONS.Kind.SWORD:
				can_harvest = true
		var gold: int = int(start[RES.Kind.GOLD])
		check(can_harvest or gold > 0, "стороне без стройки есть чем начать",
			"золота %d, добывать %s" % [gold, "есть чем" if can_harvest else "нечем"])


## У ЖЕЛЕЗА ЕСТЬ ИСТОЧНИК, И ОН НАХОДИТСЯ.
##
## Второй блокер playtest-1 дословно: «где брать железо — непонятно, пробовал
## бить всё подряд». Железо упирает всю ветку злодея: без него нет казармы, без
## казармы нет армии, без армии играть нечем.
func _test_iron_has_a_source(me: Node3D) -> void:
	var mine: Node3D = _world.mine
	check(mine != null, "источник железа в мире существует",
		"шахта найдена" if mine != null else "шахты нет вовсе")
	if mine == null:
		return

	# Идём КО ВХОДУ, а не в центр шахты. Шахта — глыба пятьдесят метров в
	# поперечнике, её центр внутри камня, и путь туда честно не доходит
	# двадцать пять метров. Первый заход так и отчитался «не дошёл 31 м» — то
	# есть ругался на радиус скалы, а не на дыру в мире.
	var door := Vector3(WORLD_BUILDER.MINE_POS.x, 0.0,
		WORLD_BUILDER.MINE_POS.z + WORLD_BUILDER.MINE_ENTRANCE_AHEAD)
	var gap: float = _walk_gap(me.global_position, door)
	check(gap >= 0.0 and gap < NEAR_STRUCTURE, "до входа в шахту можно дойти ногами",
		"не дошёл %.1f м" % gap if gap >= 0.0 else "пути нет вовсе")

	# Шахта обязана КОПИТЬ сама: иначе «дойти» ничего не даёт.
	var before: int = _mine_iron(mine)
	await get_tree().create_timer(4.0).timeout
	var after: int = _mine_iron(mine)
	check(after > before, "шахта копит железо сама",
		"было %d, стало %d" % [before, after])


func _mine_iron(mine: Node3D) -> int:
	if not ("stored" in mine):
		return 0
	return int(mine.stored[RES.Kind.IRON])


## Где именно рвётся дорога: идём лучом к цели и смотрим, докуда достаём.
func _scan(from: Vector3, to: Vector3) -> void:
	print("[скан] от (%.0f, %.0f) к (%.0f, %.0f)" % [from.x, from.z, to.x, to.z])
	for i in range(1, 11):
		var t: float = float(i) / 10.0
		var point := from.lerp(to, t)
		var gap: float = _walk_gap(from, point)
		var back: float = _walk_gap(to, point)
		print("  %3d%%  (%5.0f,%5.0f)  туда %6.1f   обратно %6.1f"
			% [t * 100.0, point.x, point.z, gap, back])


## Печать пути для разбора: куда дошёл и сколько точек.
func _trace(label: String, from: Vector3, to: Vector3) -> void:
	var nav: Node = _world.navigation
	if nav == null:
		return
	var path: PackedVector3Array = nav.path_between(from, to)
	if path.is_empty():
		print("[путь] %-24s ПУТИ НЕТ" % label)
		return
	var end: Vector3 = path[path.size() - 1]
	print("[путь] %-24s точек %2d, конец (%.0f, %.1f, %.0f), недошёл %.1f м" % [
		label, path.size(), end.x, end.y, end.z,
		Vector2(end.x, end.z).distance_to(Vector2(to.x, to.z))])


## Сколько метров НЕ дошёл путь до цели. -1 — пути нет совсем.
##
## Меряем результат ходьбы, а не наличие точки на карте: точка может стоять за
## стеной без двери, и именно так дворец и оказался невзятым.
func _walk_gap(from: Vector3, to: Vector3) -> float:
	var nav: Node = _world.navigation
	if nav == null or not nav.has_method("path_between"):
		return -1.0
	var path: PackedVector3Array = nav.path_between(from, to)
	if path.is_empty():
		return -1.0
	# ПО ПЛОСКОСТИ, а не в трёх измерениях. Карта холмистая: у шахты и склада
	# высоты за шестьдесят метров, и объёмное расстояние до точки, чья высота
	# задана не по рельефу, даёт десятки метров разницы на ровном месте. Первый
	# заход так и отчитался — «до шахты не дошёл 31 м», хотя караваны туда
	# ездят и набор `caravan` это подтверждает. Игра всюду меряет плоско
	# (`world.is_at_trader`), меряем и мы.
	var end: Vector3 = path[path.size() - 1]
	return Vector2(end.x, end.z).distance_to(Vector2(to.x, to.z))
