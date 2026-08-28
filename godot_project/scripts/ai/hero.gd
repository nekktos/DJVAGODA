extends Node
##
## Герой свободной стороны (Этап 10, шаг 8; решение GDD 10.1).
##
## ЧТО ЭТО. У стороны, за которую никто не сел, до сих пор не было персонажа —
## только гарнизон, отряд и хозяйство. Из-за этого вся магия злодея (четыре
## заклинания вместе с готовым огненным шаром) лежала без дела: колдовать было
## некому. GDD 10.1 решает это не отдельным юнитом-заклинателем, а тем, что ИИ
## САДИТСЯ НА ТОГО ЖЕ ПЕРСОНАЖА, которым играл бы человек.
##
## ПОЧЕМУ ЭТО ДЁШЕВО. Персонаж уже написан так, что ввод отделён от симуляции:
## `_gather_input()` возвращает снимок, `apply_input()` его исполняет и Input не
## читает вовсе. Значит менять надо ровно один слой — источник снимка. Движение,
## оружие, магия, ранения, гибель вожака остаются прежним кодом, а вместе с ними
## остаются прежними и наборы проверок, которые их стерегут.
##
## ЧТО ЭТА СТУПЕНЬ ДЕЛАЕТ. Правила простые и пороговые, как и просит GDD 10.1:
## герой держится при своём отряде, дерётся тем, что достаёт до цели, бросает
## паралич, когда его самого дожимают, и огненный шар — по скоплению. Ничего
## умнее здесь не нужно и не задумано: выбор момента для каста дорабатывается
## вместе с остальной стратегией, а не сейчас.
##
## ЧЕГО ЭТА СТУПЕНЬ НЕ ДЕЛАЕТ. Не строит и не нанимает — это дело `steward.gd`,
## и дублировать его через героя значило бы завести вторую экономику. Не водит
## отряд — это `warband.gd`. Герой именно воюет.
##

const FACTIONS := preload("res://scripts/factions.gd")
const ABILITIES := preload("res://scripts/combat/abilities.gd")
const WEAPONS := preload("res://scripts/combat/weapons.gd")
const WARBAND := preload("res://scripts/ai/warband.gd")
const HEALTH := preload("res://scripts/combat/health.gd")

## Как часто пересматриваем обстановку. Чаще, чем думает отряд (2 с): герой
## дерётся лично, и полсекунды опоздания — это пропущенный размен.
const THINK_INTERVAL := 0.5

## Дальше этого от якоря своего отряда герой не отходит. Он вожак, а не
## разведчик: в одиночку его убивают, и убивают навсегда.
const LEASH := 18.0

## Ближе этого к якорю можно стоять и не семенить на месте.
const AT_ANCHOR := 6.0

## Кого вообще замечаем.
const SIGHT := 34.0

## Ближний бой до этого расстояния, дальше — огненный шар.
const MELEE_REACH := 4.0

## Порог «меня дожимают»: доля здоровья, ниже которой пора парализовать того,
## кто ближе всех. Половина — потому что паралич держит 3 с, и позже он уже не
## спасает, а красиво выглядит.
const PANIC_FRACTION := 0.5

## Сколько врагов рядом друг с другом считается скоплением, достойным шара.
const CLUSTER_SIZE := 3

## В каком радиусе они должны стоять, чтобы считаться скоплением. Радиус разрыва
## шара тут ни при чём: важно не «накроет ли», а «стоит ли тратить откат».
const CLUSTER_RADIUS := 9.0

## Ближе этого герой идёт НАПРЯМУЮ, не спрашивая пути. То же число и по той же
## причине, что у бойцов: в ближнем бою путь по сетке даёт крюк вокруг
## собственного плеча, а стену на трёх шагах видно и без навигации.
const DIRECT_RANGE := 25.0

## Насколько должна уехать цель, чтобы пересчитать путь.
const REPATH_DISTANCE := 6.0

## Насколько близко надо подойти к точке пути, чтобы считать её пройденной.
const WAYPOINT_RADIUS := 2.5

var _think_left := 0.0
## Путь героя по навигационной сетке и место в нём.
var _path := PackedVector3Array()
var _path_index := 0
var _path_goal := Vector3.INF


func _process(delta: float) -> void:
	if not Net.hosting():
		return
	_think_left -= delta
	if _think_left > 0.0:
		return
	_think_left = THINK_INTERVAL
	_sync_heroes()
	for faction in FACTIONS.COUNT:
		var hero: Node3D = get_parent().ai_hero_of(faction)
		if hero != null and hero.health.alive:
			_drive(faction, hero)


## Завести героя там, где сторона свободна, и убрать там, где сели.
##
## Тем же правилом и в том же порядке, что и гарнизон: сторона свободна ровно
## тогда, когда `players_of()` пуст, а героя ИИ эта функция намеренно не видит.
func _sync_heroes() -> void:
	var world := get_parent()
	for faction in FACTIONS.COUNT:
		# Герой заводится только там, где ему есть чем быть: вожак со
		# стратегическим слоем — это злодей. Эльфам и страже он не положен, у
		# них и у живого игрока нет ни стройки, ни своей магии атаки.
		if not FACTIONS.has_strategy(faction):
			continue
		if world.players_of(faction).is_empty():
			world.spawn_ai_hero(faction)
		else:
			world.despawn_ai_hero(faction)


## Один ход героя: куда смотреть, куда идти, чем бить, что колдовать.
##
## Всё уходит в `scripted_input` — тот самый снимок, который персонаж читает
## вместо клавиатуры. Ни одной новой точки входа в него мы не заводим.
func _drive(faction: int, hero: Node3D) -> void:
	var world := get_parent()
	var enemies := _enemies_near(faction, hero.global_position)
	var target: Node3D = _closest(hero.global_position, enemies)

	# Куда идти. Есть враг — на него, нет — к якорю своего отряда.
	var goal: Vector3 = hero.global_position
	if target != null:
		goal = target.global_position
	else:
		var anchor: Vector3 = world.warband.anchor_of(faction)
		goal = anchor if anchor.is_finite() else FACTIONS.SPAWN[faction]

	# Поводок: за отрядом герой ходит, но не убегает от него за врагом.
	var anchor_now: Vector3 = world.warband.anchor_of(faction)
	if target != null and anchor_now.is_finite():
		if _flat(anchor_now, goal) > LEASH:
			goal = anchor_now

	# Дальнюю цель берём ПО КАРТЕ, а не по прямой.
	#
	# Без этого герой упирался в стену собственного форта и стоял там, пока его
	# отряд уходил на двести метров: живой прогон показал полторы минуты на
	# одном месте вплотную к восточной стене. Ошибка того же рода, ради которой
	# навигацию заводили для бойцов, и лечится тем же способом.
	var step: Vector3 = _next_step(hero, goal)
	var to_goal: Vector3 = step - hero.global_position
	to_goal.y = 0.0
	if to_goal.length() > 0.05:
		# Разворот: вперёд у персонажа это -Z его базиса.
		hero.rotation.y = atan2(-to_goal.x, -to_goal.z)

	# Останавливаемся по расстоянию до НАСТОЯЩЕЙ цели, а не до ближайшей точки
	# пути: точка пути всегда рядом, и по ней герой замирал бы на каждом углу.
	var left: float = _flat(hero.global_position, goal)
	var walk: bool = left > (MELEE_REACH if target != null else AT_ANCHOR)
	var input := {"move": Vector2(0.0, -1.0) if walk else Vector2.ZERO, "jump": false}

	if target != null:
		var gap: float = _flat(hero.global_position, target.global_position)
		_choose_weapon(hero, gap)
		# Бьём, когда цель в пределах того, чем сейчас держим.
		var reach: float = MELEE_REACH if WEAPONS.is_melee(hero.sync_weapon) else SIGHT
		input["attack"] = gap <= reach
		var spell := _choose_spell(faction, hero, enemies, target)
		if spell >= 0:
			input["ability"] = spell

	hero.scripted_input = input


## Следующая точка на пути к цели. Тот же приём, что у бойцов: вблизи идём
## прямо, издали спрашиваем навигацию и идём по ломаной.
##
## Цель может стоять внутри постройки — туда пути нет по определению, поэтому
## спрашиваем ближайшее проходимое место рядом с ней. Пути нет вовсе — идём
## напрямую: пусть лучше упрётся, чем встанет насовсем.
func _next_step(hero: Node3D, goal: Vector3) -> Vector3:
	if hero.global_position.distance_to(goal) <= DIRECT_RANGE:
		_path.clear()
		_path_goal = Vector3.INF
		return goal

	var world := get_parent()
	if not ("navigation" in world) or not world.navigation.is_ready():
		return goal

	if _path.is_empty() or _path_index >= _path.size() \
			or _path_goal.distance_to(goal) > REPATH_DISTANCE:
		_path = world.navigation.path_between(
			hero.global_position, world.navigation.closest_point(goal))
		_path_index = 0
		_path_goal = goal

	while _path_index < _path.size():
		var point: Vector3 = _path[_path_index]
		if _flat(point, hero.global_position) > WAYPOINT_RADIUS:
			return point
		_path_index += 1
	return goal


## Чем держать: вплотную — молотом, издали — огненным шаром.
func _choose_weapon(hero: Node3D, gap: float) -> void:
	var wanted: int = WEAPONS.Kind.HAMMER if gap <= MELEE_REACH else WEAPONS.Kind.SPELL
	if FACTIONS.allows_weapon(int(hero.faction), wanted):
		hero.sync_weapon = wanted


## Пороговые правила каста — ровно два, как просит GDD 10.1.
##
## Возвращает вид способности или -1. Готовность откатов не проверяем: это
## сделает сам персонаж, и дублировать проверку значило бы завести второе место,
## где её можно забыть поправить.
func _choose_spell(faction: int, hero: Node3D, enemies: Array, target: Node3D) -> int:
	# 1. Дожимают — парализуем того, кто ближе всех.
	var share: float = hero.health.current / maxf(1.0, HEALTH.MAX_HEALTH)
	if share <= PANIC_FRACTION and _flat(hero.global_position, target.global_position) <= ABILITIES.RANGE[ABILITIES.Kind.PARALYSIS]:
		if FACTIONS.allows_ability(faction, ABILITIES.Kind.PARALYSIS):
			return ABILITIES.Kind.PARALYSIS
	# 2. Скопление — проклинаем увяданием: оно бьёт по площади дольше, чем
	#    один удар, и не требует, чтобы враги стояли смирно.
	if _cluster_size(enemies, target.global_position) >= CLUSTER_SIZE:
		if FACTIONS.allows_ability(faction, ABILITIES.Kind.WITHER):
			return ABILITIES.Kind.WITHER
	return -1


## Сколько врагов стоит кучей вокруг точки.
func _cluster_size(enemies: Array, point: Vector3) -> int:
	var count := 0
	for enemy in enemies:
		if _flat(point, enemy.global_position) <= CLUSTER_RADIUS:
			count += 1
	return count


## Живые чужие в поле зрения: и персонажи, и бойцы.
func _enemies_near(faction: int, point: Vector3) -> Array:
	var found := []
	var world := get_parent()
	# Персонажи в группах не состоят — их спрашиваем у мира по стороне. Бойцы
	# состоят, и по ним идём группой: их много и они приходят и уходят.
	var candidates := []
	for other in FACTIONS.COUNT:
		if other != faction:
			candidates.append_array(world.characters_of(other))
	candidates.append_array(get_tree().get_nodes_in_group("unit"))
	for node in candidates:
		var body := node as Node3D
		if body == null or not ("faction" in body):
			continue
		if int(body.faction) == faction:
			continue
		if not _alive(body):
			continue
		if not world.warband._hostile(faction, int(body.faction)):
			continue
		if _flat(point, body.global_position) <= SIGHT:
			found.append(body)
	return found


## Жив ли. Поле `health` называется одинаково, а тип у него разный: у персонажа
## это узел со своим `alive`, у бойца — просто число. Первая версия спрашивала
## `.alive` у всех подряд и сыпала ошибкой в каждом кадре на каждого бойца.
func _alive(body: Node3D) -> bool:
	if not ("health" in body):
		return true
	var hp = body.health
	if hp is float or hp is int:
		return float(hp) > 0.0
	return hp != null and hp.alive


func _closest(point: Vector3, nodes: Array) -> Node3D:
	var best: Node3D = null
	var closest := INF
	for node in nodes:
		var gap: float = _flat(point, node.global_position)
		if gap < closest:
			closest = gap
			best = node
	return best


## По горизонтали: высота между героем и целью законно расходится на склонах.
func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
