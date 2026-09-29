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
const WORLD_BUILDER := preload("res://scripts/world_builder.gd")
const RES := preload("res://scripts/economy/resources.gd")
const BUILD_CONTROLLER := preload("res://scripts/economy/build_controller.gd")

## Дома ИИ-эльфов: где ставить — кольцом вокруг поселения, дальше от середины,
## чем стоят стартовые (там лавка и старейшина).
const ELF_RING := [32.0, 48.0, 62.0]
const ELF_ANGLES := 12
## Лес для рубки: не дальше этого от середины поселения — ИИ-эльф не уходит
## рубить за полкарты, оставив дом без присмотра.
const ELF_WOODS := 110.0
## Покупать и закалять ИИ идёт, только когда в казне ВДВОЕ больше цены: казна
## общая со стороной, и латы вожака не должны отнимать у неё батраков и лошадей.
const SURPLUS := 2.0
## Пить зелье лечения ниже этой доли здоровья.
const POTION_AT := 0.4

## Насколько далеко от микро-шахты ещё её залежь.
const MICRO_RADIUS := 20.0
## С какого расстояния бьём залежь. Меньше дальности добычи (RES.HARVEST_RANGE):
## луч идёт от груди, и с самого края он в камень не попадает.
const MINE_REACH := 2.4

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
## Насколько шире постройки ставить точку обхода у её угла.
const DETOUR_MARGIN := 2.5

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
		# ЭЛЬФАМ ТОЖЕ (ответ автора от 29.09: «ИИ-эльфы строят так же, как
		# игрок»). Строить за пустую сторону эльфов некому, кроме такого же
		# персонажа, как игрок: он рубит лес и ставит дом тем же запросом
		# стройки — с ценой, временем, пределом и радиусом игрока.
		if not FACTIONS.has_strategy(faction) and faction != FACTIONS.Kind.ELVES:
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
	# Зелье — как пил бы человек: здоровья мало, зелье есть. В самом начале:
	# чем бы вожак ни был занят, раненый пьёт.
	if (int(hero.potions_heal) > 0 and hero.health.current
			< hero.health.maximum() * POTION_AT):
		hero.request_use_potion(0)
	var enemies := _enemies_near(faction, hero.global_position)
	var target: Node3D = _closest(hero.global_position, enemies)

	# БУТСТРАП ЗЛОДЕЯ. С новым стартом (GDD 9a) злодей начинает с нулём:
	# ни ресурсов, ни батраков, а микро-шахту у форта надо бить РУКАМИ. Живой
	# игрок так и делает. ИИ этого не умел — и замер бы на всю партию: золота
	# нет, нанять некого, а бить камень некому. Это не мелочь: пока человек
	# играет за эльфов или стражу, злодеем правит именно ИИ, и мир без него
	# мёртв. Поэтому ИИ-вожак делает ровно то, что сделал бы человек: идёт к
	# микро-шахте и бьёт её, пока там что-то есть и рядом нет врага.
	if target == null:
		var vein: Node3D = _micro_vein(faction, hero)
		if vein != null:
			_mine(hero, vein)
			return
		if faction == FACTIONS.Kind.ELVES and _elf_build(hero):
			return
		# Снаряжение — как у игрока: закалить оружие в своей кузне, купить
		# доспех в своей лавке. Только без врагов рядом и при запасе в казне.
		if _gear_errand(faction, hero):
			return

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


## Сходить за снаряжением: в кузню — закалить оружие, в лавку — доспех.
## true — занят этим.
func _gear_errand(faction: int, hero: Node3D) -> bool:
	var world := get_parent()
	var forge: Node3D = world.barracks_of(faction, RES.Building.FORGE)
	var gear_cost: Array = hero.next_gear_cost()
	if forge != null and faction != FACTIONS.Kind.ELVES and _rich(hero, gear_cost):
		if hero.building_at_hand(RES.Building.FORGE) == forge:
			hero.scripted_input = {"move": Vector2.ZERO, "jump": false}
			hero.request_forge_gear()
		else:
			_walk_to(hero, forge.global_position)
		return true
	var armor_cost: Array = hero.next_armor_cost()
	if _rich(hero, armor_cost):
		if hero.at_trader():
			hero.scripted_input = {"move": Vector2.ZERO, "jump": false}
			hero.request_trade(RES.Trade.ARMOR)
		else:
			_walk_to(hero, world.trader_position(faction))
		return true
	# Эльфу — зелье лечения про запас, если нет ни одного.
	if (faction == FACTIONS.Kind.ELVES and int(hero.potions_heal) == 0
			and _rich(hero, RES.POTION_HEAL_COST)):
		if hero.at_trader():
			hero.scripted_input = {"move": Vector2.ZERO, "jump": false}
			hero.request_trade(RES.Trade.POTION_HEAL)
		else:
			_walk_to(hero, world.trader_position(faction))
		return true
	return false


## Есть ли в казне вдвое больше цены. Пустая цена — выше некуда, не идём.
func _rich(hero: Node3D, cost: Array) -> bool:
	if cost.is_empty():
		return false
	for kind in RES.COUNT:
		if float(hero.stock.get_amount(kind)) < float(RES.at(cost, kind)) * SURPLUS:
			return false
	return true


## ИИ-эльф строит дом, как игрок: рубит лес, пока не хватает, и ставит дом у
## поселения, когда хватило. true — занят этим, в бой и к отряду не идёт.
func _elf_build(hero: Node3D) -> bool:
	var world := get_parent()
	if world.elf_houses().size() >= world.elf_house_limit():
		return false
	var cost: Array = RES.BUILDING_COST[RES.Building.ELF_HOUSE]
	if hero.stock.can_afford(cost):
		var spot := _elf_spot(hero)
		if spot == Vector3.INF:
			return false
		if _flat(hero.global_position, spot) > hero.ELF_BUILD_REACH - 6.0:
			_walk_to(hero, spot)
			return true
		hero.scripted_input = {"move": Vector2.ZERO, "jump": false}
		hero.request_build(RES.Building.ELF_HOUSE, spot)
		return true
	var tree := _nearest_tree(hero)
	if tree == null:
		return false
	_mine(hero, tree)
	# Лес рубят мечом: молота у эльфа нет. `_mine` берёт молот, если он есть в
	# наборе стороны, — у эльфов его нет, и выбор просто не сработает.
	return true


## Свободное место под дом — кольцом у поселения, где пройдёт проверка места.
func _elf_spot(hero: Node3D) -> Vector3:
	var centre: Vector3 = FACTIONS.SPAWN[FACTIONS.Kind.ELVES]
	var best := Vector3.INF
	var best_gap := INF
	for radius in ELF_RING:
		for i in ELF_ANGLES:
			var angle := TAU * float(i) / float(ELF_ANGLES)
			var at := Vector3(centre.x + cos(angle) * radius, 0.0, centre.z + sin(angle) * radius)
			if not BUILD_CONTROLLER.is_spot_buildable(get_parent(), at, RES.Building.ELF_HOUSE):
				continue
			var gap: float = _flat(hero.global_position, at)
			if gap < best_gap:
				best_gap = gap
				best = at
		if best != Vector3.INF:
			return best
	return best


## Ближайшее живое дерево у поселения.
func _nearest_tree(hero: Node3D) -> Node3D:
	var centre: Vector3 = FACTIONS.SPAWN[FACTIONS.Kind.ELVES]
	var best: Node3D = null
	var best_gap := INF
	for node in get_tree().get_nodes_in_group("harvestable"):
		var tree := node as Node3D
		if tree == null or int(tree.get_meta("resource", -1)) != RES.Kind.WOOD:
			continue
		if _flat(tree.global_position, centre) > ELF_WOODS:
			continue
		var gap: float = _flat(hero.global_position, tree.global_position)
		if gap < best_gap:
			best_gap = gap
			best = tree
	return best


func _walk_to(hero: Node3D, goal: Vector3) -> void:
	var step: Vector3 = _next_step(hero, goal)
	var to_goal: Vector3 = step - hero.global_position
	to_goal.y = 0.0
	if to_goal.length() > 0.05:
		hero.rotation.y = atan2(-to_goal.x, -to_goal.z)
	hero.scripted_input = {"move": Vector2(0.0, -1.0), "jump": false}


## Ближайшая непустая залежь микро-шахты. Только у злодея: микро-шахта его.
func _micro_vein(faction: int, hero: Node3D) -> Node3D:
	if faction != FACTIONS.Kind.VILLAIN:
		return null
	# ТОЛЬКО ПОКА У СТОРОНЫ НЕТ СКЛАДА. Это и есть старт с нуля: до первой
	# постройки вожак — единственный, кто всерьёз работает, а первые батраки
	# рубят лес на тот самый склад. Как только склад встал, хозяйство держат
	# батраки, и вожак возвращается к отряду.
	#
	# Сперва здесь стояло «пока нет ни одного батрака» — и вожак бросал шахту
	# сразу после первого найма, а единственного батрака распорядитель ставил
	# на камень, и дерева на склад рубить стало некому: набор «подъём с нуля»
	# не дождался склада. А совсем без условия вожак бросал бы отряд ради камня
	# при каждом затишье — набор «герой» показал «40 м от якоря при поводке 18».
	if get_parent().storage_of(faction) != null:
		return null
	var mine := Vector2(WORLD_BUILDER.MICRO_MINE_POS.x, WORLD_BUILDER.MICRO_MINE_POS.z)
	var best: Node3D = null
	var best_gap := INF
	for node in get_tree().get_nodes_in_group("harvestable"):
		var vein := node as Node3D
		if vein == null or not is_instance_valid(vein):
			continue
		var at := Vector2(vein.global_position.x, vein.global_position.z)
		if at.distance_to(mine) > MICRO_RADIUS:
			continue
		if int(vein.get_meta("hits_left", 0)) <= 0:
			continue
		var gap: float = _flat(hero.global_position, vein.global_position)
		if gap < best_gap:
			best_gap = gap
			best = vein
	return best


## Подойти к залежи и бить её молотом. Молот — потому что по камню он вдвое
## добычливее, и микро-шахта рассчитана именно на него.
func _mine(hero: Node3D, vein: Node3D) -> void:
	var step: Vector3 = _next_step(hero, vein.global_position)
	var to_goal: Vector3 = step - hero.global_position
	to_goal.y = 0.0
	if to_goal.length() > 0.05:
		hero.rotation.y = atan2(-to_goal.x, -to_goal.z)
	var gap: float = _flat(hero.global_position, vein.global_position)
	var close: bool = gap <= MINE_REACH + _vein_radius(vein)
	if close and hero.sync_weapon != WEAPONS.Kind.HAMMER:
		hero._select_weapon(WEAPONS.Kind.HAMMER)
	hero.scripted_input = {
		"move": Vector2.ZERO if close else Vector2(0.0, -1.0),
		"jump": false,
		"attack": close,
	}


## Полуширина залежи: мерить надо от её края, а не от середины камня — в
## середину не подойти, камень твёрдый. Та же ошибка уже была с деревом, стройкой
## и складом.
func _vein_radius(vein: Node3D) -> float:
	for child in vein.get_children():
		if child is CollisionShape3D and child.shape is BoxShape3D:
			var size: Vector3 = (child.shape as BoxShape3D).size
			return maxf(size.x, size.z) * 0.5
		# Ствол дерева — цилиндр. Без этого радиус брался «два метра по
		# умолчанию», и ИИ-эльф вставал дальше, чем достаёт удар.
		if child is CollisionShape3D and child.shape is CylinderShape3D:
			return (child.shape as CylinderShape3D).radius
	return 2.0


## Следующая точка на пути к цели. Тот же приём, что у бойцов: вблизи идём
## прямо, издали спрашиваем навигацию и идём по ломаной.
##
## Цель может стоять внутри постройки — туда пути нет по определению, поэтому
## спрашиваем ближайшее проходимое место рядом с ней. Пути нет вовсе — идём
## напрямую: пусть лучше упрётся, чем встанет насовсем.
func _next_step(hero: Node3D, goal: Vector3) -> Vector3:
	return _around_buildings(hero.global_position, _path_step(hero, goal))


## Обойти постройку, которая стоит поперёк пути.
##
## Сетку навигации пекут один раз, при старте, и поставленных потом построек в
## ней нет. А вблизи цели герой и вовсе идёт по прямой. Набор «ИИ-снаряжение»
## поймал это на деле: вожак шёл в кузню, склад стоял между ними, и вожак
## полторы минуты упирался в стену склада. Поэтому, если отрезок до следующей
## точки режет чужую постройку, идём сперва к её углу: к тому, откуда путь
## до цели короче всего.
func _around_buildings(from: Vector3, to: Vector3) -> Vector3:
	var start := Vector2(from.x, from.z)
	var finish := Vector2(to.x, to.z)
	var blocker: Node3D = null
	var blocker_gap := INF
	for node in get_tree().get_nodes_in_group("building"):
		var building := node as Node3D
		if building == null or not is_instance_valid(building):
			continue
		var centre := Vector2(building.global_position.x, building.global_position.z)
		var half := _footprint(building)
		# Цель в самой постройке (идём в кузню, к складу) — её не обходим.
		if absf(finish.x - centre.x) <= half.x and absf(finish.y - centre.y) <= half.y:
			continue
		if not _segment_hits_box(start - centre, finish - centre, half):
			continue
		var gap: float = start.distance_to(centre)
		if gap < blocker_gap:
			blocker_gap = gap
			blocker = building
	if blocker == null:
		return to
	var centre := Vector2(blocker.global_position.x, blocker.global_position.z)
	var half := _footprint(blocker)
	var wide := half + Vector2(DETOUR_MARGIN, DETOUR_MARGIN)
	var best := to
	var best_length := INF
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var corner := centre + Vector2(wide.x * sx, wide.y * sz)
			# Угол, у которого уже стоим, — пройден: иначе замерли бы на нём.
			if start.distance_to(corner) < 1.0:
				continue
			if _segment_hits_box(start - centre, corner - centre, half):
				continue
			var length: float = start.distance_to(corner) + corner.distance_to(finish)
			if length < best_length:
				best_length = length
				best = Vector3(corner.x, to.y, corner.y)
	return best


func _footprint(building: Node3D) -> Vector2:
	var size: Vector3 = RES.BUILDING_SIZE[int(building.kind)]
	return Vector2(size.x, size.z) * 0.5


## Режет ли отрезок a–b прямоугольник ±half с серединой в нуле.
func _segment_hits_box(a: Vector2, b: Vector2, half: Vector2) -> bool:
	var d := b - a
	var t0 := 0.0
	var t1 := 1.0
	for axis in 2:
		var p := [-d[axis], d[axis]]
		var q := [a[axis] + half[axis], half[axis] - a[axis]]
		for k in 2:
			if absf(p[k]) < 0.0001:
				if q[k] < 0.0:
					return false
				continue
			var t: float = q[k] / p[k]
			if p[k] < 0.0:
				t0 = maxf(t0, t)
			else:
				t1 = minf(t1, t)
	return t0 <= t1


func _path_step(hero: Node3D, goal: Vector3) -> Vector3:
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
		if not FACTIONS.hostile(faction, int(body.faction)):
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
