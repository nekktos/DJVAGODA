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
##
## ПОРЯДОК ПЕРЕСОБРАН ПОД НОВЫЙ СТАРТ (GDD 9a). Злодей начинает с нуля, и ИИ
## обязан пройти тот же путь, что и живой игрок: склад, поле, конюшня — это
## путь до первого обоза; дом и казармы — развитие, за них платит обоз.
##
## Конюшня раньше стояла ПОСЛЕДНЕЙ с пометкой «без неё обоз всё равно ходит
## парой лошадей». Лошадей на старте больше нет, и без конюшни обоз не выедет
## никогда, а без обоза не будет ни железа, ни камня на всё остальное.
##
## КОНЮШНЯ РАНЬШЕ ПОЛЯ. Сперва поле стояло сразу за складом — батраки едят, —
## и «долгая партия» поймала тупик: стража снесла поле набегом, распорядитель
## по очереди ставил его заново, и камень микро-шахты (шестьдесят на всю
## партию) ушёл на второе поле. На конюшню не осталось, без конюшни нет обоза,
## без обоза нет камня — злодей простоял двадцать пять минут. С конюшней
## вперёд камня хватает на склад, конюшню и поле, а снесённое поле
## отстраивается уже на привезённый камень. Голод не страшен: артель умирает
## только с третьей пропущенной кормёжки, через пятнадцать минут.
const BUILD_ORDER := [
	RES.Building.STORAGE,
	RES.Building.STABLE,
	RES.Building.FARM,
	RES.Building.HOUSE,
	RES.Building.SWORD_BARRACKS,
	RES.Building.ARCHER_BARRACKS,
	# Кузня последней: закалка — роскошь, когда войско уже есть (GDD 9a).
	RES.Building.FORGE,
]

## Сколько батраков ИИ нанимает, пока нет ни одной лошади. Золото микро-шахты —
## это двое батраков и лошадь ЛИБО трое батраков; нанять третьего значит не
## купить лошадь и не отправить ни одного обоза. Живой игрок выбирает сам, ИИ
## выбирает обоз.
const CREW_BEFORE_HORSE := 2

## Сколько лошадей ИИ держит в конюшне и сколько запрягает.
##
## Четыре и три: одна упряжка в пути, одна лошадь в запасе на замену убитой.
## Больше держать незачем — золото нужнее на войско.
const HORSES_WANTED := 4
const AI_HARNESS := 3

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
## Сколько батраков остаётся на работе при любой охране. «Долгая партия»
## поймала злодея, у которого все двое батраков ушли охранять первый обоз: поле
## осталось без фермера, лес без лесоруба, еду съели, и хозяйство встало.
const WORKERS_KEPT := 2

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
		_fortify(faction)
		_assign_roles(faction)
		_train(faction)
		# Лошадей покупаем ПОСЛЕ войска и ДО отправки обоза: сперва оборона,
		# потом упряжка, и только потом сам рейс — иначе обоз уедет, а лошадь,
		# на которую хватило золота, купится ему вслед и простоит без дела.
		_buy_horses(faction)
		_send_caravan(faction)
		_extra_storage(faction)
	# ОБОЗЫ СТРАЖИ (GDD 9a: «караваны есть и у людей, и у злодея»). Стройки и
	# найма у стражи нет, пока её человек не стал командиром, но хозяйство
	# дворца живёт и без него: склад, конюшня и поля стоят с начала партии, и
	# возит в них тот, кто ими распоряжается, — распорядитель. Как только у
	# стражи появился командир, обозы — его дело, и ИИ их больше не шлёт.
	if _runs_guard_logistics():
		_buy_horses(FACTIONS.Kind.GUARD)
		_send_caravan(FACTIONS.Kind.GUARD)


## Обоз стоит у полного склада — ставим ещё склад (ответ автора от 29.09:
## «было оповещение, чтоб игрок или ИИ построил склад»). Один за раз: пока
## строится, второй не закладываем.
func _extra_storage(faction: int) -> void:
	var world := get_parent()
	var waiting := false
	for cart in world.caravans_of(0):
		if int(cart.faction) == faction and bool(cart.waiting):
			waiting = true
	if not waiting:
		return
	# Строящийся СКЛАД — ждём его; прочая стройка не мешает: обоз с грузом
	# важнее казармы, и ждать её значило бы держать телегу у склада минуты.
	for node in get_tree().get_nodes_in_group("building"):
		if (int(node.faction) == faction and int(node.kind) == RES.Building.STORAGE
				and float(node.progress) < 1.0):
			return
	if not _wallet(faction).can_afford(RES.BUILDING_COST[RES.Building.STORAGE]):
		return
	var spot := _find_spot(faction, RES.Building.STORAGE)
	if spot == Vector3.INF:
		return
	_wallet(faction).spend(RES.BUILDING_COST[RES.Building.STORAGE])
	world.spawn_building(RES.Building.STORAGE, spot, 0, faction)
	print("[хозяйство] %s: склад полон, обоз ждёт — строит ещё склад" % FACTIONS.name_of(faction))


## Возит ли ИИ обозы стражи: пока у неё нет живого командира.
func _runs_guard_logistics() -> bool:
	var commander: Node = get_parent().get_node_or_null("Commander")
	if commander == null:
		return false
	return not commander.guard_has_leader()


## Сколько обозов ИИ этой стороны в пути.
##
## По СТОРОНЕ, а не по владельцу: у всех обозов ИИ владелец ноль, и обоз
## злодея под ИИ загораживал бы обоз стражи — «один в пути» считался на двоих.
func _ai_caravans(faction: int) -> int:
	var count := 0
	for cart in get_parent().caravans_of(0):
		if int(cart.faction) == faction:
			count += 1
	return count


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
	if wallet != null and int(wallet.horses) <= 0 and crew.size() >= CREW_BEFORE_HORSE:
		return
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


## В каком порядке ИИ укрепляет: склад — сердце хозяйства, конюшня — путь к
## обозу, казармы — войско.
const FORTIFY_ORDER := [
	RES.Building.STORAGE,
	RES.Building.STABLE,
	RES.Building.SWORD_BARRACKS,
	RES.Building.ARCHER_BARRACKS,
	RES.Building.HOUSE,
	RES.Building.FORGE,
]


## Укрепить постройку на ступень (ответ автора от 29.09), как сделал бы игрок:
## у самой постройки и за ту же цену. Только когда хватает и на укрепление,
## и на следующую постройку по очереди — стены не должны съедать развитие.
## Укрепляем самую слабую по очереди важности.
func _fortify(faction: int) -> void:
	if _under_construction(faction) != null:
		return
	var wallet := _wallet(faction)
	if wallet == null:
		return
	var weakest: Node3D = null
	for kind in FORTIFY_ORDER:
		var building := _ready_building(faction, kind)
		if building == null or building.upgrade_cost().is_empty():
			continue
		if weakest == null or int(building.grade) < int(weakest.grade):
			weakest = building
	if weakest == null:
		return
	var cost: Array = weakest.upgrade_cost()
	var need: PackedInt32Array = RES.fit(cost)
	var next := _next_building(faction)
	if next >= 0:
		var build_cost: PackedInt32Array = RES.fit(RES.BUILDING_COST[next])
		for kind in RES.COUNT:
			need[kind] += build_cost[kind]
	if not wallet.can_afford(Array(need)):
		return
	if not wallet.spend(cost):
		return
	weakest.apply_upgrade()


## Сколько ртов кормит одно поле (см. предложения игроков: «одно поле кормит
## примерно пятерых»).
const MOUTHS_PER_FIELD := 5


## Чего у стороны ещё нет. -1 — построено всё.
##
## Сверх очереди — ещё поле, когда ртов больше, чем поля прокормят. «Долгая
## партия» застала злодея с девятью батраками на одном поле: артель голодала,
## работала вдвое медленнее, и развитие встало. Только когда первое поле уже
## есть — стартовую очередь это не трогает.
func _next_building(faction: int) -> int:
	var fields := _count_all(faction, RES.Building.FARM)
	if fields > 0 and fields * MOUTHS_PER_FIELD < _crew(faction).size():
		return RES.Building.FARM
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
	# ФЕРМЕР — ПЕРВЫМ из оставшихся. Батраки едят (раз в пять минут), и поле без
	# фермера стоит полным: еда на нём есть, а до склада не доходит. Одного на
	# поле: одно поле кормит примерно пятерых, и больше рук ему не надо.
	if rest > 0:
		var fields: int = _count_ready(faction, RES.Building.FARM)
		wanted[LABOURER.Role.FARMER] = mini(fields, rest)
		rest -= wanted[LABOURER.Role.FARMER]
	if rest > 0:
		# Чего не хватает на следующую постройку — тем и займёмся.
		var kind := _next_building(faction)
		var need_stone := false
		if kind >= 0:
			var wallet := _wallet(faction)
			var cost: Array = RES.BUILDING_COST[kind]
			need_stone = wallet != null and (
				wallet.get_amount(RES.Kind.STONE) < RES.at(cost, RES.Kind.STONE)
				or wallet.get_amount(RES.Kind.IRON) < RES.at(cost, RES.Kind.IRON))
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


## Сколько построек такого вида у стороны, считая недостроенные.
func _count_all(faction: int, kind: int) -> int:
	var found := 0
	for node in get_tree().get_nodes_in_group("building"):
		if ("faction" in node) and ("kind" in node) and int(node.faction) == faction 				and int(node.kind) == kind:
			found += 1
	return found


## Сколько достроенных построек такого вида у стороны.
func _count_ready(faction: int, kind: int) -> int:
	var found := 0
	for node in get_tree().get_nodes_in_group("building"):
		if not ("faction" in node) or not ("kind" in node):
			continue
		if int(node.faction) != faction or int(node.kind) != kind:
			continue
		if float(node.progress) >= 1.0:
			found += 1
	return found


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
	if _ai_caravans(faction) >= CARAVANS_WANTED:
		return
	var target: Node3D = _pick_mine(faction)
	if target == null:
		return
	# Запрягаем СВОИХ лошадей, а не берём их из воздуха. Иначе конюшня у ИИ
	# декоративна: он строил бы её и не пользовался, а обозы ходили бы парой
	# лошадей всегда, сколько ни покупай.
	var wallet := _wallet(faction)
	var free: int = wallet.horses_free() if wallet != null else 0
	if free <= 0:
		# Без лошадей обоз не поедет вовсе, и отправлять его значит поставить
		# посреди карты неподвижную мишень с грузом.
		return
	var team: int = mini(AI_HARNESS, free)
	if wallet != null:
		wallet.horses_out += team

	var route := PackedVector3Array([storage.global_position, world.mine_dock(target)])
	var cart: Node = world.spawn_caravan(route, 0, faction, team)
	_guard_caravan(faction, cart)


## К какой шахте слать обоз: за тем, чего у стороны меньше всего.
##
## Железо, камень и золото — то, на что ИИ реально тратит (стройка, казармы,
## наём). Уголь пока ни на что не идёт, и возить его ИИ незачем. Равенство
## решается в пользу железа: без него нет казарм.
func _pick_mine(faction: int) -> Node3D:
	var world := get_parent()
	if not ("mines" in world):
		return null
	var wallet := _wallet(faction)
	var best: Node3D = null
	var best_have := INF
	for kind in [RES.Kind.IRON, RES.Kind.STONE, RES.Kind.GOLD]:
		var target: Node3D = world.mine_of(kind)
		if target == null:
			continue
		var have: float = float(wallet.get_amount(kind)) if wallet != null else 0.0
		if have < best_have:
			best_have = have
			best = target
	return best


## Купить лошадь, если есть конюшня и есть на что.
##
## Ставим ПОСЛЕ стройки и войска: лошадь ускоряет обоз, но не защищает базу, и
## сторона, потратившая золото на конюшню вместо казармы, проигрывает первому
## же набегу.
func _buy_horses(faction: int) -> void:
	var world := get_parent()
	if world.stable_of(faction) == null:
		return
	var wallet := _wallet(faction)
	if wallet == null or wallet.horses >= HORSES_WANTED:
		return
	if not wallet.spend(RES.HORSE_COST):
		return
	wallet.horses += 1
	print("[конюшня] %s: куплена лошадь, всего %d"
		% [FACTIONS.name_of(faction), wallet.horses])


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
	var guards: int = mini(GUARDS_PER_CARAVAN, crew.size() - WORKERS_KEPT)
	for worker in crew:
		if taken >= guards:
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
	# ВМЕСТИМОСТЬ ОТ ДОМОВ — и для ИИ тоже. Дом дружины я ввёл, ограничив им
	# только игрока, и ИИ продолжал набирать по своему SQUAD_WANTED, будто
	# домов не существует. Набор «хозяйство» это и поймал: «8 при потолке 6».
	var room: int = mini(SQUAD_WANTED, world.squad_capacity(faction))
	if world.warband._band(faction).size() >= room:
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
