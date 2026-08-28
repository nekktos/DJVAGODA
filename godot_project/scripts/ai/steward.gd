extends Node
##
## Хозяйство свободной стороны (Этап 10, шаг 8, ступень «в»).
##
## ЧТО ЭТО. Последняя ступень ИИ: сторона, за которую никто не сел, начинает
## ВЕСТИ ХОЗЯЙСТВО — нанимать батраков, ставить их на работу, строить и набирать
## войско. До неё ИИ умел только воевать тем, что ему выдали (`warband.gd`), а
## взяться этому было неоткуда.
##
## ГЛАВНОЕ РЕШЕНИЕ: ИИ ДОБЫВАЕТ ТЕМ ЖЕ КОДОМ, ЧТО ИГРОК. Он не получает ресурсы
## из воздуха и не имеет своей, отдельной экономики. Он нанимает тех же батраков
## (`labourer.gd`), ставит им те же роли, платит ту же цену из того же кошелька
## стороны и строит те же постройки с той же проверкой места. Всё, что здесь
## есть, — это решения «кого нанять, куда поставить, что строить»; сама работа
## делается общим кодом.
##
## Иначе и быть не могло: своя экономика у ИИ означала бы вторую её реализацию,
## которая расходится с игроцкой при первой же правке баланса и в которой ошибки
## некому заметить — в игре за людей этот код не выполняется вовсе.
##
## ТОЛЬКО ЗЛОДЕЙ. Строить и вести хозяйство по GDD умеет одна сторона; у эльфов
## и стражи экономики нет вовсе, и выдумывать её здесь неправильно. Для них
## ступень «в» пустая, и это не недоделка, а асимметрия сторон.
##
## Считает ТОЛЬКО хост.
##

const FACTIONS := preload("res://scripts/factions.gd")
const RES := preload("res://scripts/economy/resources.gd")
const LABOURER := preload("res://scripts/units/labourer.gd")
const BUILD_CONTROLLER := preload("res://scripts/economy/build_controller.gd")

## Как часто пересматривать хозяйство. Реже, чем воюющий отряд: стройка и наём —
## решения на десятки секунд, и частить тут нечем.
const THINK_INTERVAL := 4.0

## Что и в каком порядке строить. Склад первым не по привычке: без него у
## стороны нет безопасного запаса вовсе, и всё добытое теряется с первой смертью.
const BUILD_ORDER := [
	RES.Building.STORAGE,
	RES.Building.SWORD_BARRACKS,
	RES.Building.ARCHER_BARRACKS,
]

## Сколько батраков ставить на стройку, пока она идёт. Двое дают тройную
## скорость и не оголяют добычу совсем.
const BUILDERS_WANTED := 2

## Больше этого ИИ войско не набирает. Потолок отряда игрока вдвое выше: ИИ не
## должен выигрывать числом там, где человек выигрывает решениями.
const SQUAD_WANTED := 6

## Больше одного каравана ИИ в пути не держит: у игрока потолок два, и
## соперник, возящий вдвое больше, выигрывал бы расписанием, а не решениями.
const CARAVANS_WANTED := 1

## Сколько батраков уходит в охрану повозки. Двое: один не остановит отряд из
## четверых, а трое и больше оголяют добычу.
const GUARDS_PER_CARAVAN := 2

## Где искать место под постройку: кольцами вокруг базы.
## Кольца доходят до ста с лишним метров, и это не запас на будущее. С прежними
## четырьмя кольцами до 68 м ИИ за три минуты живого прогона построил склад и
## ВСТАЛ НАСОВСЕМ: двор форта тесный, склад занял единственное годное место, а
## казарма 14 на 9 метров больше никуда не влезала. Молча — ресурсы копились,
## караваны ходили, стройка не начиналась.
const SPOT_RADII := [26.0, 38.0, 52.0, 68.0, 86.0, 106.0, 128.0]
const SPOT_ANGLES := 12

var _think_t := 0.0
## Стороны, которым уже сказали, что строить негде: чтобы не повторяться.
var _cramped := {}


func _process(delta: float) -> void:
	if not Net.hosting():
		return
	_think_t += delta
	if _think_t < THINK_INTERVAL:
		return
	_think_t = 0.0
	for faction in FACTIONS.COUNT:
		if not _runs_for(faction):
			continue
		_hire(faction)
		_build(faction)
		_assign_roles(faction)
		_send_caravan(faction)
		_train(faction)


## Ведём хозяйство только за незанятую сторону, которая умеет строить. Сел
## живой игрок — немедленно перестаём: его батраки не должны получать приказы
## от кого-то ещё.
func _runs_for(faction: int) -> bool:
	if not FACTIONS.can_build(faction):
		return false
	return get_parent().players_of(faction).is_empty()


func _wallet(faction: int) -> Node:
	return get_parent().treasury.of(faction)


## Батраки, которыми хозяйство вправе распоряжаться.
##
## Приставленных к обозу тут нет: они уже при деле, и переставить их обратно на
## добычу значит оставить груз без прикрытия через такт после того, как охрану
## назначили. Ровно так и вышло в первом прогоне.
func _crew(faction: int) -> Array:
	var free := []
	for worker in get_parent().labourers_of(faction):
		if worker.has_meta("escorting"):
			continue
		free.append(worker)
	return free


## Нанять ещё рук, если есть на что. Батрак окупается быстро, поэтому копить
## золото ради золота смысла нет.
func _hire(faction: int) -> void:
	var crew := _crew(faction)
	if crew.size() >= RES.LABOURER_LIMIT:
		return
	var wallet := _wallet(faction)
	if wallet == null or not wallet.spend(RES.LABOURER_COST):
		return
	var base: Vector3 = FACTIONS.SPAWN[clampi(faction, 0, FACTIONS.COUNT - 1)]
	var angle := float(crew.size()) * 0.9
	var radius := 5.0 + float(crew.size())
	var spot := base + Vector3(cos(angle) * radius, 0.5, sin(angle) * radius)
	get_parent().spawn_labourer(faction, spot, base, LABOURER.Role.LUMBERJACK)


## Поставить следующую по очереди постройку, если есть на что и есть куда.
func _build(faction: int) -> void:
	if _under_construction(faction) != null:
		# По одной стройке за раз: две недостроенных коробки — это вдвое дольше
		# ждать первой готовой, а нужна как раз первая.
		return
	var kind := _next_building(faction)
	if kind < 0:
		return
	var wallet := _wallet(faction)
	if wallet == null or not wallet.can_afford(RES.BUILDING_COST[kind]):
		return
	var spot := _find_spot(faction, kind)
	if spot == Vector3.INF:
		# Есть на что, но негде. Раньше это молчало, и сторона стояла до конца
		# партии с полной казной. Говорим один раз на сторону: само по себе
		# положение не изменится, пока что-нибудь не снесут.
		if not _cramped.has(faction):
			_cramped[faction] = true
			print("[хозяйство] %s: есть на %s, но негде строить"
				% [FACTIONS.name_of(faction), RES.BUILDING_NAMES[kind]])
		return
	_cramped.erase(faction)
	if not wallet.spend(RES.BUILDING_COST[kind]):
		return
	get_parent().spawn_building(kind, spot, 0, faction, false)
	print("[хозяйство] %s строит %s" % [FACTIONS.name_of(faction), RES.BUILDING_NAMES[kind]])


## Чего у стороны ещё нет. -1 — построено всё.
func _next_building(faction: int) -> int:
	for kind in BUILD_ORDER:
		if _building_of(faction, kind) == null:
			return kind
	return -1


func _building_of(faction: int, kind: int) -> Node3D:
	for node in get_tree().get_nodes_in_group("building"):
		var building := node as Node3D
		if building == null or not ("faction" in building):
			continue
		if int(building.faction) == faction and int(building.kind) == kind:
			return building
	return null


func _under_construction(faction: int) -> Node3D:
	for node in get_tree().get_nodes_in_group("building"):
		var building := node as Node3D
		if building == null or not ("faction" in building):
			continue
		if int(building.faction) == faction and float(building.progress) < 1.0:
			return building
	return null


## Место под постройку: кольцами вокруг базы, пока не найдётся годное.
##
## Проверка места — ТА ЖЕ, что у игрока (`build_controller.is_spot_buildable`):
## перепад высот, пересечения, границы. Своей проверки у ИИ нет намеренно, иначе
## он строил бы там, где человеку нельзя, и это заметили бы не сразу.
func _find_spot(faction: int, kind: int) -> Vector3:
	var base: Vector3 = FACTIONS.SPAWN[clampi(faction, 0, FACTIONS.COUNT - 1)]
	var world := get_parent()
	for radius in SPOT_RADII:
		for i in SPOT_ANGLES:
			var angle := TAU * float(i) / float(SPOT_ANGLES)
			var point := base + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
			point.y = 0.0
			if BUILD_CONTROLLER.is_spot_buildable(world, point, kind):
				return point
	return Vector3.INF


## Расставить батраков по делам.
##
## Порядок нужд простой и намеренно грубый: сперва стройка, если она идёт, потом
## тот ресурс, которого не хватает на следующую постройку, потом дерево. Тонкая
## оптимизация тут не нужна — нужна сторона, которая не стоит.
func _assign_roles(faction: int) -> void:
	var crew := _crew(faction)
	if crew.is_empty():
		return
	var wanted := PackedInt32Array()
	wanted.resize(LABOURER.ROLE_COUNT)

	var building := _under_construction(faction)
	if building != null:
		wanted[LABOURER.Role.BUILDER] = mini(BUILDERS_WANTED, crew.size())

	var rest: int = crew.size() - wanted[LABOURER.Role.BUILDER]
	if rest > 0:
		# Чего не хватает на следующую постройку — тем и займёмся.
		var kind := _next_building(faction)
		var need_stone := false
		if kind >= 0:
			var wallet := _wallet(faction)
			var cost: Array = RES.BUILDING_COST[kind]
			need_stone = wallet != null and (
				wallet.get_amount(RES.Kind.STONE) < int(cost[RES.Kind.STONE])
				or wallet.get_amount(RES.Kind.IRON) < int(cost[RES.Kind.IRON]))
		if need_stone:
			wanted[LABOURER.Role.MINER] = rest - rest / 2
			wanted[LABOURER.Role.LUMBERJACK] = rest / 2
		else:
			wanted[LABOURER.Role.LUMBERJACK] = rest - rest / 2
			wanted[LABOURER.Role.MINER] = rest / 2

	_apply_roles(crew, wanted)


## Привести состав к желаемому, трогая только тех, кого надо переставить.
func _apply_roles(crew: Array, wanted: PackedInt32Array) -> void:
	var have := PackedInt32Array()
	have.resize(LABOURER.ROLE_COUNT)
	for worker in crew:
		have[int(worker.sync_role)] += 1

	for role in LABOURER.ROLE_COUNT:
		while have[role] < wanted[role]:
			var donor := _donor_role(have, wanted)
			if donor < 0:
				return
			var moved := false
			for worker in crew:
				if int(worker.sync_role) == donor:
					worker.set_role(role)
					have[donor] -= 1
					have[role] += 1
					moved = true
					break
			if not moved:
				return


## У кого забрать пару рук: у роли, где их больше, чем нужно.
func _donor_role(have: PackedInt32Array, wanted: PackedInt32Array) -> int:
	var best := -1
	var surplus := 0
	for role in LABOURER.ROLE_COUNT:
		var extra: int = have[role] - wanted[role]
		if extra > surplus:
			surplus = extra
			best = role
	return best


## Отправить караван к шахте, если есть куда возвращаться.
##
## Батрак-шахтёр носит понемногу и своими ногами; караван возит помногу и по
## расписанию. Для стороны, которая строится, второе важнее — а раньше ИИ не
## умел вовсе, и это была единственная незакрытая часть стратегического слоя.
##
## Маршрут — самый простой: склад, потом шахта. Игрок рисует его руками и может
## выбрать длинный путь в обход (GDD 2.3); ИИ такого выбора не делает, за него
## это решает навигация в `world.spawn_caravan`.
func _send_caravan(faction: int) -> void:
	var world := get_parent()
	var storage := _ready_building(faction, RES.Building.STORAGE)
	if storage == null:
		return
	if world.caravans_of(0).size() >= CARAVANS_WANTED:
		return
	if world.mine == null:
		return
	var route := PackedVector3Array([storage.global_position, world.mine.global_position])
	var cart: Node = world.spawn_caravan(route, 0, faction)
	_guard_caravan(faction, cart)


## Приставить к повозке охрану.
##
## Берём БАТРАКОВ и переводим их в ополчение, а не спавним новых бойцов. Так у
## охраны есть настоящая цена: пока двое стоят при повозке, они не рубят и не
## копают. Бесплатная охрана была бы прибавкой к войску из воздуха.
##
## Мечников и лучников из казарм не трогаем намеренно: они — ударная сила
## набега, и растащив их по обозам, сторона перестанет воевать вовсе. Живой
## игрок вправе поступить иначе, у него выбор свой.
func _guard_caravan(faction: int, cart: Node) -> void:
	if cart == null or not cart.has_method("add_guard"):
		return
	var world := get_parent()
	var crew := _crew(faction)
	var taken := 0
	for worker in crew:
		if taken >= GUARDS_PER_CARAVAN:
			break
		if int(worker.sync_role) == LABOURER.Role.BUILDER:
			continue
		worker.set_role(LABOURER.Role.MILITIA)
		if cart.add_guard(worker):
			taken += 1
	if taken > 0:
		print("[караван] %s: с повозкой идёт охрана, ополченцев %d"
			% [FACTIONS.name_of(faction), taken])


## Набрать войско. Бойцы безвладельческие: их подберёт `warband.gd` и поведёт в
## набег вместе с гарнизоном — второй системы командования ИИ не заводим.
func _train(faction: int) -> void:
	var world := get_parent()
	if world.warband._band(faction).size() >= SQUAD_WANTED:
		return
	var archer := _ready_building(faction, RES.Building.ARCHER_BARRACKS) != null
	if not archer and _ready_building(faction, RES.Building.SWORD_BARRACKS) == null:
		return
	var cost: Array = RES.ARCHER_COST if archer else RES.UNIT_COST
	var wallet := _wallet(faction)
	if wallet == null or not wallet.spend(cost):
		return
	var base: Vector3 = FACTIONS.SPAWN[clampi(faction, 0, FACTIONS.COUNT - 1)]
	var slot: int = world.warband._band(faction).size()
	var angle := float(slot) * 0.9
	var spot := base + Vector3(cos(angle) * 8.0, 0.5, sin(angle) * 8.0)
	world.spawn_garrison_unit(faction, slot, spot, base, 90.0, false, archer)
	print("[хозяйство] %s набрал %s" % [FACTIONS.name_of(faction),
		"лучника" if archer else "мечника"])


func _ready_building(faction: int, kind: int) -> Node3D:
	var building := _building_of(faction, kind)
	if building == null or float(building.progress) < 1.0:
		return null
	return building


## Что сторона успела построить. Для автопроверок и HUD.
func built_count(faction: int) -> int:
	var count := 0
	for kind in BUILD_ORDER:
		if _ready_building(faction, kind) != null:
			count += 1
	return count
